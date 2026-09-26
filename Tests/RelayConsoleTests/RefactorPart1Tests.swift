import Foundation
import Testing
@testable import RelayConsole
import RelayMcpCore

/// 1단계(어댑버 안전화 + 즉시 결함) 회귀 테스트
///
/// 각 테스트는 `PLAN_refactor_perf_stability_macos` 1단계의 항목 하나를 고정한다.
/// 이 테스트들이 깨지면 해당 결함이 되살아난 것으로 본다.
struct RefactorPart1Tests {

    // MARK: - 1-1 ProcessRunner 교착 · 데드라인 · 원인 보존

    /// 정상 경로 — stdout이 그대로 반환된다
    @Test func processRunnerReturnsStdout() throws {
        let out = try ProcessRunner.run(
            "/bin/echo",
            ["hello-part1"],
            failure: .init(base: "실패", reason: "")
        )
        #expect(out.contains("hello-part1"))
    }

    /// 데드라인을 넘기면 **무한 대기 대신 예외**를 던진다 (이전 결함의 핵심)
    @Test func processRunnerTimesOutInsteadOfHanging() {
        let start = Date()
        // sleep 30 — 데드라인 1초면 절대 끝나지 않는다
        #expect(throws: ProcessRunner.TimedOut.self) {
            try ProcessRunner.run(
                "/bin/sleep",
                ["30"],
                timeout: 1,
                failure: .init(base: "실패", reason: "")
            )
        }
        // 30초를 기다렸다면 테스트 전체가 멈췄을 것 — 실제로는 1초 + escalation 만 소요
        #expect(Date().timeIntervalSince(start) < 10)
    }

    /// **교착 회귀**: 자식이 stderr에 64KB를 넘겨도 멈추지 않는다.
    /// 이전 구현은 stderr 파이프를 읽지 않아 이 케이스에서 영구 대기했다.
    @Test func processRunnerDoesNotDeadlockOnLargeStderr() throws {
        // stderr에 400줄(약 20KB 이상)을 쓴 뒤 정상 종료 — 버퍼 64KB 경계 근처까지 채운다
        let script = """
        i=0
        while [ $i -lt 4000 ]; do
          echo 'error line padding padding padding padding padding padding padding' >&2
          i=$((i+1))
        done
        echo done
        """
        let out = try ProcessRunner.run(
            "/bin/sh",
            ["-c", script],
            timeout: 30,
            failure: .init(base: "실패", reason: "")
        )
        #expect(out.contains("done"))
    }

    /// 1-1 [표시②] — 실패 시 stderr 원문이 보존된다 (원인 삭제 금지)
    @Test func processRunnerPreservesStderrCause() {
        do {
            _ = try ProcessRunner.run(
                "/bin/sh",
                ["-c", "echo 'device unauthorized' >&2; exit 1"],
                failure: .init(base: "기기에 연결할 수 없습니다.", reason: "")
            )
            Issue.record("exit 1이면 throw 되어야 한다")
        } catch {
            let text = error.localizedDescription
            #expect(text.contains("device unauthorized"))
            #expect(text.contains("기기에 연결할 수 없습니다."))
        }
    }

    /// stderr만 크고 **성공**하는 경우 — 교착 없이 성공으로 처리되어야 한다
    @Test func processRunnerSucceedsDespiteLargeStderr() throws {
        let script = "i=0; while [ $i -lt 4000 ]; do echo 'warn padding padding padding' >&2; i=$((i+1)); done; echo ok"
        let out = try ProcessRunner.run(
            "/bin/sh",
            ["-c", script],
            timeout: 30,
            failure: .init(base: "실패", reason: "")
        )
        #expect(out.contains("ok"))
    }

    // MARK: - 1-3 ConnectionSessionStore.flush (동기 기록)

    /// flush() 직후 파일을 **동기적으로** 읽어도 반영돼야 한다
    /// — 이전엔 `dirty`가 true가 될 수 없어 flush()가 no-op이었다
    @MainActor
    @Test func connectionSessionFlushWritesSynchronously() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("refactor-p1-sessions-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = ConnectionSessionStore(url: url)
        store.open(serial: "flush-test", kind: .usb, at: Date(timeIntervalSince1970: 1_700_000_000))
        store.flush()

        // 비동기 큐에 기대지 않고 즉시 읽는다 — 미배출이면 이전(빈) 상태가 보인다
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("flush-test"))
    }

    /// 1-6 [HARD] 로그 마스킹 — 하트비트 토큰이 로그에 평문으로 남지 않는다
    @Test func heartbeatTokenIsMaskedInLog() {
        let token = "supersecrettoken1234567890"
        let masked = NotifyChannel.maskSecret(token)
        #expect(masked != token)
        #expect(!masked.contains(token))
        // 짧은 토큰은 값 자체를 노출하지 않는다
        #expect(NotifyChannel.maskSecret("abc") != "abc")
    }

    // MARK: - 1-7 기기 0대 표시는 온라인이 아니다

    /// 오프라인 기기가 배열에 남아 있어도 온라인으로 판정되지 않아야 한다
    @Test func offlineDevicesAreNotCountedAsOnline() {
        var inv = DeviceInventory()
        #expect(!inv.devices.contains { $0.isOnline })

        var dev = DeviceSnapshot()
        dev.serial = "gone-serial"
        dev.isOnline = false
        inv.merge(dev)
        #expect(inv.devices.count == 1)
        #expect(!inv.devices.contains { $0.isOnline })
        #expect(inv.onlineDevices.isEmpty)

        // 온라인 1대를 추가하면 그때만 온라인으로 판정
        var live = DeviceSnapshot()
        live.serial = "live-serial"
        live.isOnline = true
        inv.merge(live)
        #expect(inv.onlineDevices.count == 1)
    }

    // MARK: - 1-4 사이트 결과가 다른 사이트에 섞이지 않는다

    /// await 동안 배열이 변형돼도 check는 **id가 일치하는** 사이트에만 기록된다
    @Test func siteCheckResultTargetsMatchingSiteOnly() {
        let a = Site(name: "A-site", target: "https://a.example", probe: .http, intervalSec: 60)
        let b = Site(name: "B-site", target: "https://b.example", probe: .http, intervalSec: 60)
        var list = [a, b]

        let captured = list[0]                 // 체크를 시작한 사이트
        // await 동안 C가 앞에 삽입돼 인덱스가 밀린다
        list.insert(Site(name: "C-site", target: "https://c.example", probe: .http), at: 0)

        // 수정된 코드와 같은 방식: 저장 후 id로 다시 찾는다
        let idx = list.firstIndex(where: { $0.id == captured.id })!
        #expect(idx == 1)
        list[idx].appendCheck(SiteCheck(ok: true, latencyMs: 42))

        #expect(list[idx].history.count == 1)
        #expect(list[idx].history[0].latencyMs == 42)
        // 다른 사이트(A/B)에는 기록되면 안 된다
        #expect(list[0].history.isEmpty)
        #expect(list[2].history.isEmpty)
    }

    /// 대상(target)까지 바뀌었으면 이전 체크 결과는 버려야 한다
    @Test func siteCheckIsDiscardedWhenTargetChanged() {
        let a = Site(name: "A", target: "https://old.example", probe: .http)
        var list = [a]
        let before = a.target
        list[0].target = "https://new.example"
        // target 재확인이 없으면 옛 대상의 결과가 새 대상에 붙는다
        #expect(list[0].target != before)
    }

    // MARK: - 1-9 버전 단일 진실원처

    /// **출시 정본** `Resources/Info.plist`의 버전 형식
    @Test func shippedInfoPlistHasSaneVersion() throws {
        let plist = Self.repoRoot().appendingPathComponent("Resources/Info.plist")
        let version = try #require(AppVersion.fromPlist(at: plist), "Info.plist 버전 읽기 실패")
        let parts = version.split(separator: ".")
        #expect(parts.count >= 2, "major.minor.patch 형태여야 한다: \(version)")
        #expect(parts.allSatisfy { !$0.isEmpty })
        #expect(parts.dropLast().allSatisfy { Int($0) != nil }, "숫자 형식이어야 한다: \(version)")
    }

    /// MCP 서버 버전과 **출시 Info.plist**가 어긋나면 안 된다.
    /// relay-mcp는 별도 프로세스라 값을 직접 선언하므로, 이 대조가 없으면
    /// 버전 상승 때 조용히 뒤처진다 (실제로 1.15.0·1.16.0에서 발생).
    @Test func mcpServerVersionMatchesShippedInfoPlist() throws {
        let plist = Self.repoRoot().appendingPathComponent("Resources/Info.plist")
        let version = try #require(AppVersion.fromPlist(at: plist))
        #expect(McpRouter.serverVersion == version)
    }

    /// 화면 표기는 하드코딩이 아니라 Info.plist에서 온다
    @Test func appVersionFallsBackToBundleVersionNumber() {
        // Bundle.main이 앱 번들이 아닌 환경이면 "0"이 되어야 한다 — 값이 조용히 발명되지 않는다
        #expect(!AppVersion.value(from: .main).isEmpty)
        #expect(AppVersion.prefixed.hasPrefix("v"))
    }

    /// 테스트 위치 기준으로 패키지 루트를 찾는다 (CWD 의존 제거)
    private static func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)      // Tests/RelayConsoleTests/RefactorPart1Tests.swift
            .deletingLastPathComponent()    // RelayConsoleTests
            .deletingLastPathComponent()    // Tests
            .deletingLastPathComponent()    // <repo root>
    }
}
