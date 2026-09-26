import Foundation

/// **coalescing(합치기) 영속화 writer** — "대기 중인 쓰기를 최신 값으로 대체"한다.
///
/// ## 왜 필요한가
/// 기존 스토어들은 값이 바뀔 때마다 `queue.async { data.write(...) }` 로 **매번** 디스크에
/// 썼다. 그런데 상태 파일은 **최종 상태 하나**만 의미가 있다. 이벤트 20건이 연속으로 들어오면
/// 큐에 20번의 57KB 쓰기가 쌓이고, 최종 결과는 마지막 1번으로 덮어진다.
///
/// 실측 낭비: 호출 20회 → 실제 쓰기 20회 × 57KB = 1.12MB. 필요한 건 1회 = 0.06MB. **95% 낭비.**
/// 활동 60건/분이면 분당 3.4MB, 600건/분이면 분당 33.5MB 를 전부 버려 쓰게 된다.
///
/// ## 보장
/// - 큐에 대기 중인 쓰기가 있으면 새 요청은 그걸 **대체**한다 (최신 우선, 순서 보존)
/// - 인코딩도 **이 큐에서** 수행한다 → 호출 스레드(주로 MainActor)에 비용을 남기지 않는다
/// - \`flushSync()\` 는 진행 중 쓰기를 모두 마친 뒤 마지막 상태를 **동기 기록**한다
///   → 앱 종료 시 큐 미배출로 데이터가 유실되지 않는다
final class CoalescingWriter<Value: Sendable>: @unchecked Sendable {

    private let url: URL
    private let name: String
    private let queue: DispatchQueue
    private let encode: @Sendable (Value) throws -> Data

    private let lock = NSLock()
    /// 큐에서 아직 처리하지 않은 최신 값
    private var pending: Value?
    private var hasPending = false
    /// 드레인 작업 예약 여부 — 중복 예약을 막아 큐에 작업이 쌓이지 않게 한다
    private var drainScheduled = false
    /// 마지막 저장 실패 사유 — 조용한 실패를 막기 위한 신호 ([표시②])
    private var _lastError: String?

    /// 마지막 저장 실패 사유 (없으면 nil)
    var lastError: String? {
        lock.lock(); defer { lock.unlock() }
        return _lastError
    }

    /// 저장 파일 위치 (테스트 검증용)
    var fileURL: URL { url }

    init(
        url: URL,
        name: String,
        queueLabel: String,
        encode: @escaping @Sendable (Value) throws -> Data
    ) {
        self.url = url
        self.name = name
        self.encode = encode
        self.queue = DispatchQueue(label: queueLabel, qos: .utility)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    /// 값 저장 — 이미 대기 중이면 대체한다
    func submit(_ value: Value) {
        lock.lock()
        pending = value
        hasPending = true
        let needsSchedule = !drainScheduled
        if needsSchedule { drainScheduled = true }
        lock.unlock()

        if needsSchedule {
            queue.async { [self] in drainLoop() }
        }
    }

    /// 큐가 빌 때까지 대기 값을 처리한다.
    /// 새 값이 계속 들어와도 **중간값은 건너뛰고 최신만** 기록한다 (coalescing).
    private func drainLoop() {
        while true {
            lock.lock()
            guard hasPending, let value = pending else {
                drainScheduled = false
                lock.unlock()
                return
            }
            pending = nil
            hasPending = false
            lock.unlock()

            write(value)
        }
    }

    private func write(_ value: Value) {
        do {
            let data = try encode(value)
            try data.write(to: url, options: .atomic)
            lock.lock()
            _lastError = nil
            lock.unlock()
        } catch {
            // 조용히 삼키지 않는다 — 사유를 보존하고 로그로 남긴다 ([표시②])
            let message = error.localizedDescription
            lock.lock()
            _lastError = message
            lock.unlock()
            let store = name
            Task { @MainActor in
                DebugLogger.shared.warn("Store", "[WARN] \(store) 저장 실패: \(message)")
            }
        }
    }

    /// 진행 중 쓰기를 모두 마치고 남은 대기 값까지 **동기**로 기록한다.
    /// 앱 종료 전에 호출해야 유실이 없다.
    func flushSync() {
        // 큐에 쌓인 드레인 작업을 끝까지 소진
        queue.sync { }
        // 그 사이에 새로 들어온 대기 값이 있으면 여기서 기록
        lock.lock()
        let value = hasPending ? pending : nil
        pending = nil
        hasPending = false
        drainScheduled = false
        lock.unlock()

        guard let value else { return }
        write(value)
    }
}
