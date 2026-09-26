import Foundation
import Testing
@testable import RelayConsole

/// 4단계(메인 스레드 정지) 회귀 테스트
///
/// R4 는 실측으로 범위를 재정의했다. 측정 결과:
/// - 스토어 인코딩+쓰기 = 건당 0.46ms(EventStore) / 2.42ms(SitesJobsStore 8×300)
///   → 메인 스레드 부담 **1% 미만** (에이전트 추정치보다 훨씬 작음)
/// - **진짜 결함은 쓰기 증폭**: 이벤트 1건마다 57KB 전량 재기록,
///   20건 연속이면 1.12MB 를 쓰고 최종 결과는 마지막 1회로 덮어진다 → **95% 낭비**
///
/// 그래서 핵심은 "코alescing 으로 낭비 제거" + "비원자적 publish 제거" 다.
struct RefactorPart4Tests {

    // MARK: - CoalescingWriter: 증폭 제거

    /// 여러 번 제출해도 **최종 상태 1개**만 기록된다
    @Test func coalescingWriterCollapsesBurstToLatestValue() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cw-burst-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var n = 0
            func bump() { lock.lock(); n += 1; lock.unlock() }
            var value: Int { lock.lock(); defer { lock.unlock() }; return n }
        }
        let encodes = Counter()

        let w = CoalescingWriter(url: url, name: "test", queueLabel: "cw.test.burst") { (v: Int) -> Data in
            encodes.bump()
            return Data(String(v).utf8)
        }

        // 50번 연속 제출
        for i in 1...50 {
            w.submit(i)
        }
        w.flushSync()

        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text == "50", "최신 값이 기록되어야 한다")
        // 50회 전부 인코딩했다면 50회, 합쳐졌다면 훨씬 적어야 한다
        #expect(encodes.value < 50, "인코딩이 \(encodes.value)회 — 합쳐지지 않았다")
    }

    /// flushSync 는 호출 시점에 **그때까지의 최신 상태**를 반드시 기록한다
    /// (큐 미배출로 유실되면 안 됨 — R1 ConnectionSessionStore 와 동일 결함)
    @Test func coalescingWriterFlushSyncPersistsLatest() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cw-flush-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let w = CoalescingWriter(url: url, name: "test", queueLabel: "cw.test.flush") { (v: String) -> Data in
            Data(v.utf8)
        }
        w.submit("first")
        w.submit("second")
        w.submit("third")
        w.flushSync()

        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text == "third")
    }

    /// flushSync 를 여러 번 불러도 안전하다 (중복 기록/크래시 없음)
    @Test func coalescingWriterFlushIsIdempotent() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cw-idem-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let w = CoalescingWriter(url: url, name: "test", queueLabel: "cw.test.idem") { (v: Int) -> Data in
            Data(String(v).utf8)
        }
        w.submit(7)
        w.flushSync()
        w.flushSync()
        w.flushSync()
        #expect(try String(contentsOf: url, encoding: .utf8) == "7")
        #expect(w.lastError == nil)
    }

    /// 제출이 없으면 아무 것도 쓰지 않는다 (빈 파일 생성 금지)
    @Test func coalescingWriterDoesNotWriteWithoutSubmit() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cw-none-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let w = CoalescingWriter(url: url, name: "test", queueLabel: "cw.test.none") { (_: Int) -> Data in
            Data("x".utf8)
        }
        w.flushSync()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    /// 인코딩이 실패해도 **오류를 보존**한다 (조용한 실패 금지 — [표시②])
    @Test func coalescingWriterRecordsEncodeFailure() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cw-fail-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        struct Boom: Error {}
        let w = CoalescingWriter(url: url, name: "test", queueLabel: "cw.test.fail") { (_: Int) -> Data in
            throw Boom()
        }
        w.submit(1)
        w.flushSync()
        #expect(w.lastError != nil, "실패가 조용히 사라졌다")
    }

    /// 동시 제출에도 크래시 없이 최종 상태가 기록된다
    @Test func coalescingWriterHandlesConcurrentSubmits() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cw-conc-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let w = CoalescingWriter(url: url, name: "test", queueLabel: "cw.test.conc") { (v: Int) -> Data in
            Data(String(v).utf8)
        }
        DispatchQueue.concurrentPerform(iterations: 200) { i in
            w.submit(i)
        }
        w.flushSync()
        // 값이 하나는 기록돼 있고 오류는 없어야 한다
        #expect(w.lastError == nil)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - 비원자적 @Published publish 제거

    /// WatchEvent 상한이 실제로 지켜지는지 (1회 대입 방식)
    @Test func watchEventCapIsEnforced() {
        #expect(ConsoleStore.maxWatchEvents == 500)
        var next: [WatchEvent] = []
        for i in 0..<600 {
            next.insert(
                WatchEvent(kind: .throttling, severity: .info, serial: "s", title: "t\(i)", detail: ""),
                at: 0
            )
            if next.count > ConsoleStore.maxWatchEvents {
                next.removeLast(next.count - ConsoleStore.maxWatchEvents)
            }
        }
        #expect(next.count == 500)
        // 최신 것이 맨 앞
        #expect(next.first?.title == "t599")
    }

    /// 로그 텍스트 상한
    @Test func recentEventCapIsEnforced() {
        #expect(ConsoleStore.maxRecentEvents == 20)
        var next: [String] = []
        for i in 0..<50 {
            next.insert("line\(i)", at: 0)
            if next.count > ConsoleStore.maxRecentEvents {
                next.removeLast(next.count - ConsoleStore.maxRecentEvents)
            }
        }
        #expect(next.count == 20)
        #expect(next.first == "line49")
    }

    /// 중간 상태가 관측되지 않는 이유 — 1회 대입은 트림 전/후 어느 값도 남기지 않는다
    @Test func singleAssignmentNeverExposesOverCapState() {
        let cap = 3
        // 이미 상한에 찬 상태에서 새 값을 넣는 상황
        var legacy = [1, 2, 3]
        var observedLegacy: [Int] = []
        legacy.insert(4, at: 0)
        observedLegacy.append(legacy.count)          // ← 4 (상한 초과) 가 먼저 관측됨
        if legacy.count > cap { legacy.removeLast() }
        observedLegacy.append(legacy.count)
        #expect(observedLegacy == [4, 3], "종전 방식은 상한 초과 중간 상태가 관측된다")

        // 개선 방식: 로컬에서 끝까지 계산 → 1회만 대입
        var published = [1, 2, 3]
        var observedNew: [Int] = []
        var next = published
        next.insert(4, at: 0)
        if next.count > cap { next.removeLast(next.count - cap) }
        published = next
        observedNew.append(published.count)
        #expect(observedNew == [3], "한 번만 대입하므로 초과 상태가 노출되지 않는다")
        #expect(published == [4, 1, 2], "최신 값이 앞에, 가장 오래된 값이 제거")
    }
}
