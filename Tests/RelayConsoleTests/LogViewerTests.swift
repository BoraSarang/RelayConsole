import Foundation
import Testing
@testable import RelayConsole

/// 로그 창 스트림 수명 주기 — 2026-09-27
///
/// ## 계측으로 발견한 것
/// 로그 창에서 레벨 필터(D/I/W/E)를 바꿀 때마다 `adb logcat` 이 **하나씩 새로 살아남았다.**
/// 실측: 필터 4회 전환 → 자식 adb 4개 동시 생존. 규칙상 최대 1개다.
/// ```
/// stop()   → 이전 프로세스 terminate() → 죽음 → 슬롯 비움
///                                          └─ terminationHandler 가 Task 로 **큐잉**
/// start()  → 새 프로세스 run() → 슬롯에 새 프로세스 adopt
///                    ... 잠시 후 ...
///            이전 프로세스 알림 도착 → 슬롯을 통째로 비워버림  ← ★
/// ```
/// 그 다음 필터 전환에서 `stop()` 은 "현재 프로세스" 가 없어 아무것도 죽이지 못한다.
/// 셸에서 `kill -TERM` 은 즉시 죽는 것을 확인했으므로 **adb 가 아니라 참조 소실이 원인**이었다.
struct LogViewerTests {
    /// 이전 프로세스의 종료 알림이 살아 있는 새 프로세스의 자리를 지우지 않는다
    @Test func replacedProcessTerminationDoesNotClearSlot() {
        let slot = LogcatProcessSlot()
        let first = Process()
        let second = Process()

        slot.adopt(first)
        slot.adopt(second)  // stop() → terminate() → start() 로 교체

        #expect(slot.release(first) == false, "이전 프로세스 알림은 자리를 건드리지 않는다")
        #expect(slot.current === second, "살아 있는 새 프로세스 참조가 남아 있어야 한다")

        #expect(slot.release(second) == true, "현재 프로세스 알림은 정리한다")
        #expect(slot.current == nil)
    }

    /// 방어선 — 자리가 비었을 때 들어온 알림은 무시된다(조기 종료·중복 알림 대비)
    @Test func terminationOnEmptySlotIsIgnored() {
        let slot = LogcatProcessSlot()
        #expect(slot.release(Process()) == false)
        #expect(slot.current == nil)
    }

    /// 자리가 비었다면 `stop()` 은 죽일 대상이 없다 — 이전 구현이 놓친 바로 그 상태
    @Test func stopWithoutCurrentProcessHasNothingToTerminate() {
        let slot = LogcatProcessSlot()
        #expect(slot.current == nil)
        slot.adopt(nil)
        #expect(slot.current == nil)
    }
}
