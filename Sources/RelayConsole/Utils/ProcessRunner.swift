import Foundation

/// 외부 프로세스 실행기 — 교착 · 무제한 대기 · 원인 유실을 한곳에서 막는다.
///
/// ## 왜 필요한가
/// `Process`를 직접 띄우던 패턴에는 두 가지 치명적인 결함이 있었다.
///
/// 1. **stderr 미배출** — `proc.standardError = Pipe()`만 해놓고 끝내면 파이프 버퍼(64KB)가
///    차는 순간 자식 프로세스가 `write`에서 블로킹된다. 그러면 stdout의 EOF가 오지 않아
///    `readDataToEndOfFile()`가 **영구 대기**한다. 타임아웃도 없으니 복구 수단이 없다.
/// 2. **무제한 대기** — 네트워크 ADB(`IP:PORT`)는 half-open TCP가 되면 응답 없이 남는다.
///    `waitUntilExit()`가 끝나지 않으면 이를 호출한 actor가 통째로 정지해
///    `stop()`·`shutdown()`조차 처리할 수 없다(앱 재시작 외 복구 불가).
///
/// ## 보장
/// - stdout·stderr를 **별도 큐에서 동시에** 소진 → 어느 한쪽이 먼저 끝나도 교착하지 않는다
/// - 데드라인 초과 시 `terminate()` → `interrupt()` → 강제 종료로 단계적으로 escalation
/// - 대기도 **유한**하다 (escalation 후에도 남은 시간을 기다리지 않는다)
/// - 실패 시 **stderr 원문을 보존**한다 (AGENTS.local §4 [표시②] — 원인 삭제 금지)
enum ProcessRunner {

    /// 실행 결과
    struct Output: Sendable {
        let stdout: String
        let stderr: String
        let exitCode: Int32
        /// 데드라인을 넘어 강제 종료했는지
        let timedOut: Bool

        /// 실패 원인을 사람이 읽을 수 있는 한 줄로 — 비어 있지 않으면 유효.
        /// stderr를 우선하고, 비어 있으면 stdout에서 가져온다.
        var cause: String {
            ProcessRunner.lastMeaningfulLine(stderr)
                ?? ProcessRunner.lastMeaningfulLine(stdout)
                ?? ""
        }
    }

    /// 외부 명령 실패 — 실제 원인을 보존한다 ([표시②])
    struct Failure: LocalizedError, Sendable {
        /// 기본 문구 (ErrorCode.koMessage 등)
        let base: String
        /// 실제 stderr 등 원인 (없으면 빈 문자열)
        let reason: String

        var errorDescription: String? {
            reason.isEmpty ? base : "\(base) — \(reason)"
        }
    }

    /// 데드라인을 넘겼을 때 던지는 오류 — 실패와 구분되게 한다
    struct TimedOut: LocalizedError, Sendable {
        let seconds: TimeInterval
        var errorDescription: String? {
            "명령이 \(Int(seconds))초 안에 끝나지 않아 중단했습니다. 기기 연결 상태를 확인해 주세요."
        }
    }

    /// 폴링 경로 기본 기한 — 정상 adb 응답은 100ms 내외, 기기 doze 시 수백 ms.
    /// 20초는 정상 지연과 실제 정지를 구분하기 위한 충분한 여유다.
    static let pollTimeout: TimeInterval = 20

    // escalate 간격 · 폴링 간격
    private static let pollInterval: TimeInterval = 0.01
    private static let graceAfterTerminate: TimeInterval = 1.0

    /// 마지막으로 나온 비어 있지 않은 줄 — 에러 원인은 보통 마지막 줄에 있다
    static func lastMeaningfulLine(_ text: String) -> String? {
        var result: String?
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { result = String(trimmed) }
        }
        return result
    }

    /// stdout 문자열만 필요할 때 (대부분의 adb 폴링 경로)
    @discardableResult
    static func run(
        _ path: String,
        _ args: [String],
        timeout: TimeInterval = pollTimeout,
        failure: Failure
    ) throws -> String {
        let out = try capture(path, args, timeout: timeout)
        if out.timedOut { throw TimedOut(seconds: timeout) }
        guard out.exitCode == 0 else {
            throw Failure(base: failure.base, reason: out.cause)
        }
        return out.stdout
    }

    /// 결과 전체(종료 코드·stderr) 필요할 때
    static func capture(
        _ path: String,
        _ args: [String],
        timeout: TimeInterval = pollTimeout
    ) throws -> Output {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        do {
            try proc.run()
        } catch {
            // 실행 자체가 실패 (경로 없음·권한) — stderr는 아직 없다
            return Output(stdout: "", stderr: "", exitCode: -1, timedOut: false)
        }

        // 두 파이프를 **동시에** 읽는다. 순차로 읽으면 먼저 읽는 쪽이 끝날 때까지
        // 다른 쪽이 채워져 교착할 수 있다.
        let group = DispatchGroup()
        let lock = NSLock()
        var outData = Data()
        var errData = Data()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            let d = out.fileHandleForReading.readDataToEndOfFile()
            lock.lock(); outData = d; lock.unlock()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            let d = err.fileHandleForReading.readDataToEndOfFile()
            lock.lock(); errData = d; lock.unlock()
            group.leave()
        }

        // 데드라인까지 대기
        let deadline = Date().addingTimeInterval(timeout)
        while proc.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: pollInterval)
        }

        var timedOut = false
        if proc.isRunning {
            timedOut = true
            // SIGTERM → (유지되면) SIGINT 로 단계적 escalation
            proc.terminate()
            let graceDeadline = Date().addingTimeInterval(graceAfterTerminate)
            while proc.isRunning && Date() < graceDeadline {
                Thread.sleep(forTimeInterval: pollInterval)
            }
            if proc.isRunning {
                proc.interrupt()
            }
        }

        // 프로세스가 끝났다면 두 읽기는 이미 완료됐고(EOF), 이 짧은 대기는 즉시 반환된다.
        // 끝나지 않은 경우에도 **무한정 기다리지 않는다** — 남은 읽기는 백그라운드 큐가 회수한다.
        _ = group.wait(timeout: .now() + graceAfterTerminate)

        lock.lock()
        let finalOut = outData
        let finalErr = errData
        lock.unlock()

        return Output(
            stdout: String(decoding: finalOut, as: UTF8.self),
            stderr: String(decoding: finalErr, as: UTF8.self),
            exitCode: proc.terminationStatus,
            timedOut: timedOut
        )
    }
}
