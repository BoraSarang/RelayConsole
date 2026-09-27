import Foundation
import Testing
@testable import RelayConsole

/// 종료 정리 가드 — 2026-09-28
///
/// 실측 근거: `pkill` (SIGTERM) 경로에서 ① 로그 창의 `adb logcat` 이 **PPID 1 로 고아**가 되고
/// ② `CoalescingWriter` 대기분(최대 2분)이 유실됐다. `applicationWillTerminate` 는 부르지 않기 때문이다.
struct TerminationGuardTests {
    /// 한 번만 돌아야 한다 — 두 경로(⌘Q · SIGTERM)가 우연히 겹쳐도 정리는 한 번
    @Test func onceRunsBodyExactlyOnce() {
        var once = TerminationGuard.Once()
        var count = 0
        #expect(once.run { count += 1 } == true)
        #expect(once.run { count += 1 } == false, "두 번째는 실행하지 않고 거짓말을 해야 한다")
        #expect(once.run { count += 1 } == false)
        #expect(count == 1)
        #expect(once.hasFired == true)
    }

    /// 설치 전에는 아무것도 실행되지 않는다
    @Test func freshOnceHasNotFired() {
        #expect(TerminationGuard.Once().hasFired == false)
    }

    /// 처리 대상 시그널 — **`SIGKILL` 은 들어갈 수 없다** (막을 수 없다)
    @Test func handledSignalsExcludeUncatchable() {
        #expect(TerminationGuard.handledSignals.contains(SIGTERM))
        #expect(TerminationGuard.handledSignals.contains(SIGINT))
        #expect(!TerminationGuard.handledSignals.contains(SIGKILL),
                "SIGKILL 은 못 막는다 — 넣으면 '막았다'는 거짓말이 된다")
        #expect(!TerminationGuard.handledSignals.contains(SIGSTOP))
    }
}
