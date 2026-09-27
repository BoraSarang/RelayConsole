import Foundation
import AppKit

/// 종료 정리 — **정상 종료와 강제 종료(SIGTERM)가 같은 경로를 탄다**
///
/// ## 왜 이 클래스가 있나 (2026-09-28 실측)
///
/// `pkill RelayConsole` 로 죽이면 AppKit 은 `applicationWillTerminate` 를 **부르지 않는다.**
/// 프로세스가 시그널에 의해 그대로 끝나기 때문이다. 그래서 두 가지가 함께 잃힌다:
///
/// ① **로그 창의 `adb logcat` 이 고아가 된다** — PPID 1 로 남고 계속 스트리밍한다
/// ② **저장 대기분이 버려진다** — `CoalescingWriter` 는 최대 2분 분량을 모아 쓰므로
///    `flushSync()` (`R4`) 가 지켜야 할 마지막 상태가 유실된다
///
/// 실측 (2026-09-28 · SM-S901N):
/// ```
/// 경로 A  정상 종료(⌘Q)  → 앱의 adb 자식 사라짐 (onDisappear → stop())
/// 경로 B  pkill(SIGTERM) → adb 자식 PPID=1 로 잔존, 13초 후에도 살아 있음
///        └─ 고아를 죽이면 **기기 쪽 logcat 도 함께 사라진다** (기기 PID → 0건)
///            즉 **맥 쪽만 막으면 된다.** 기기 쪽 별도 정리는 필요 없다
/// ```
///
/// ## 막을 수 없는 것 — SIGKILL 과 크래시
///
/// 시그널 핸들러는 `SIGKILL` 과 크래시에는 불리지 않는다. 남는 고아는 **사용자가 정리해야 한다.**
/// 앱이 죽은 뒤 스스로를 정리하는 것은 불가능하다. 이 한계를 코드에 적어 둔다
/// (숨기면 다음 사람이 "왜 또 남아 있지?" 하고 또 Investigate 한다).
@MainActor
enum TerminationGuard {
    /// 처리하는 시그널 — **`SIGKILL` 은 넣을 수 없다** (막을 수 없다)
    ///
    /// `nonisolated` — 불변 상수이므로 어디서든 읽어도 안전하다. (메인 액터에 묶으면
    /// 테스트와 로그가 MainActor 밖에서 못 읽는다)
    nonisolated static let handledSignals: [Int32] = [SIGTERM, SIGINT]

    /// 정리 경로 — 정상 종료와 시그널이 **똑같은 함수**를 탄다 (두 벌로 두면 벌써 갈라진다)
    ///
    /// 반환값은 "실제로 돌았는가" 다. 이미 시그널 쪽에서 정리했다면 두 번째 호출은 막히고 `false`.
    @discardableResult
    static func runShutdown() -> Bool {
        once.run {
            // 창이 닫히길 기다리지 않는다 — 창이 그대로 열린 채 강제 종료돼도 자식은 죽어야 한다
            LogcatStreamer.shared.stop()
            AppDelegate.terminateWork()
        }
    }

    /// 시그널 소스 — **디스패치 큐에서 delivered** 되므로 여기서 아무 코드나 불러도 된다
    ///
    /// 왜 `signal()` 핸들러가 아닌가: C 시그널 핸들러 안에서는 할당·락·Objective-C 호출이 금지된다.
    /// 자식 PID 를 전역에 저장해 두고 `kill()` 하는 방법도 가능하지만,
    /// **PID 가 재사용되면 엉뚱한 프로세스를 죽인다.** `Process.terminate()` 는 살아 있는
    /// 객체만 다루므로 그 위험이 없다.
    static func install() {
        for sig in handledSignals {
            // 소스가 살아 있는 동안 시그널이 "무시" 되도록 막아 둔다 (없으면 경쟁이 생긴다)
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler {
                // 큐가 `.main` 이므로 여기선 메인 액터다. 이 가정이 틀리면 즉시 크래시하므로
                // 컴파일러가 아니라 런타임이 지켜 주는 지점이다.
                MainActor.assumeIsolated {
                    let ran = TerminationGuard.runShutdown()
                    DebugLogger.shared.info(
                        "App",
                        "[INFO] [TERM] 시그널 \(sig) 수신 — 정리 \(ran ? "실행" : "스킵(이미 정리됨)") 후 종료"
                    )
                }
                // AppKit 종료 흐름으로는 들어가지 않는다 — 정리를 마친 뒤 스스로 끝낸다
                exit(0)
            }
            src.resume()
            sources.append(src)   // 지역 변수로 두면 즉시 해제된다 — 반드시 유지한다
        }
    }

    private static var once = Once()
    /// 소스 보관 — 해제되면 시그널이 다시 기본 처리로 돌아간다
    private static var sources: [DispatchSourceSignal] = []

    /// **한 번만** 돌리는 가드 — 순수 값 타입이라 정리를 실행하지 않고 검증할 수 있다
    struct Once {
        private var fired = false
        /// 실행했으면 `true`, 이미 실행돼 있으면 `false` (본체는 두 번째에 실행하지 않는다)
        mutating func run(_ body: () -> Void) -> Bool {
            if fired { return false }
            fired = true
            body()
            return true
        }
        var hasFired: Bool { fired }
    }
}
