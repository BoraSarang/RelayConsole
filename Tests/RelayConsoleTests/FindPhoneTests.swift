import Foundation
import Testing
@testable import RelayConsole

/// 폰 찾기 인자 조립 — 실측으로 검증된 adb 표면만 쓰는지·밝기를 원복하는지 고정
/// (`docs/plans/PLAN_find_phone_relayconsole.md` — 지속 벨소리·진동·손전등은 미채택)
struct FindPhoneTests {
    @Test func wakeUsesKeycodeWakeup() {
        #expect(FindPhoneLogic.wakeArgs() == ["shell", "input", "keyevent", "224"])
    }

    @Test func applyOrderIsManualModeThenBrightnessThenWake() {
        let steps = FindPhoneLogic.applyArgs()
        #expect(steps.count == 3)
        #expect(steps[0] == ["shell", "settings", "put", "system", "screen_brightness_mode", "0"])
        #expect(steps[1] == ["shell", "settings", "put", "system", "screen_brightness", "255"])
        #expect(steps[2] == FindPhoneLogic.wakeArgs())
        // 값은 1~255 로 자른다(0 은 화면을 어둡게 만든다)
        #expect(FindPhoneLogic.brightnessArgs(level: 0).last == "1")
        #expect(FindPhoneLogic.brightnessArgs(level: 9999).last == "255")
        #expect(FindPhoneLogic.brightnessArgs(level: 120).last == "120")
    }

    @Test func parseSettingRejectsNullAndOutOfRange() {
        #expect(FindPhoneLogic.parseSetting("255") == 255)
        #expect(FindPhoneLogic.parseSetting(" 120 \n") == 120)
        #expect(FindPhoneLogic.parseSetting("0") == 0)
        #expect(FindPhoneLogic.parseSetting("null") == nil)
        #expect(FindPhoneLogic.parseSetting("") == nil)
        #expect(FindPhoneLogic.parseSetting("-1") == nil)
        #expect(FindPhoneLogic.parseSetting("999") == nil)
        #expect(FindPhoneLogic.parseSetting("error") == nil)
    }

    @Test func restoreOnlyTouchesReadValues() {
        let both = FindPhoneLogic.restoreArgs(mode: 1, level: 88)
        #expect(both == [
            ["shell", "settings", "put", "system", "screen_brightness_mode", "1"],
            ["shell", "settings", "put", "system", "screen_brightness", "88"],
        ])
        // 읽기 실패(null)면 그 키는 건드리지 않는다
        #expect(FindPhoneLogic.restoreArgs(mode: nil, level: nil).isEmpty)
        #expect(FindPhoneLogic.restoreArgs(mode: 1, level: nil).count == 1)
        #expect(FindPhoneLogic.restoreArgs(mode: nil, level: 88).first?.contains("screen_brightness") == true)
        // 모드는 0/1 로만 되돌린다
        #expect(FindPhoneLogic.restoreArgs(mode: 7, level: nil).first?.last == "1")
    }

    @Test func notifyArgsMatchShellCommandPost() {
        let args = FindPhoneLogic.notifyArgs(title: "RelayConsole", text: "폰 찾기 (1/3)")
        // 제목·본문은 기기 셸 재파싱을 견디도록 단일 인용으로 감싼다
        #expect(args == [
            "shell", "cmd", "notification", "post",
            "-t", "'RelayConsole'", "relay-find", "'폰 찾기 (1/3)'",
        ])
    }

    @Test func shellQuotingSurvivesMetacharacters() {
        // 괄호·공백·세미콜론 — 인용이 없으면 기기 셸이 `syntax error` 를 낸다(실측 재현)
        #expect(FindPhoneLogic.shellQuoted("찾기 (1/3)") == "'찾기 (1/3)'")
        #expect(FindPhoneLogic.shellQuoted("a;b|c") == "'a;b|c'")
        // 내부 단일 인용은 이어 붙여 이스케이프한다
        #expect(FindPhoneLogic.shellQuoted("it's") == "'it'\\''s'")
        // 알림 단계도 실제로 인용된 값을 담는다
        let step = FindPhoneLogic.notifySteps(title: "T", text: "찾기", repeats: 2).first
        #expect(step?.last == "'찾기 (1/2)'")
        #expect(step?.contains("'T'") == true)
    }

    @Test func notifyTagIsSanitizedAndNeverEmpty() {
        #expect(FindPhoneLogic.safeTag("relay find!") == "relayfind")
        #expect(FindPhoneLogic.safeTag("   ") == FindPhoneLogic.defaultTag)
        #expect(FindPhoneLogic.safeTag(String(repeating: "a", count: 200)).count == 64)
    }

    @Test func notifyTextDropsControlCharactersAndFallsBack() {
        #expect(FindPhoneLogic.safe("폰\n찾기", fallback: "x") == "폰찾기")
        #expect(FindPhoneLogic.safe("   ", fallback: "fallback") == "fallback")
        #expect(FindPhoneLogic.safe(String(repeating: "가", count: 300), fallback: "x").count == 120)
    }

    @Test func notifyStepsKeepOneTagAndChangeBody() {
        let steps = FindPhoneLogic.notifySteps(title: "T", text: "찾기", repeats: 3)
        #expect(steps.count == 3)
        #expect(steps.first?.last == "'찾기 (1/3)'")
        #expect(steps.last?.last == "'찾기 (3/3)'")
        // 같은 tag 라 알림은 한 건만 남고, 본문이 달라 다시 울린다
        #expect(Set(steps.map { $0[$0.count - 2] }) == [FindPhoneLogic.defaultTag])
    }

    @Test func repeatCountIsClampedToOneThroughFive() {
        #expect(FindPhoneLogic.notifySteps(title: "T", text: "찾기", repeats: 0).count == 1)
        #expect(FindPhoneLogic.notifySteps(title: "T", text: "찾기", repeats: 99).count == 5)
        // 1회만 보낼 때는 진행 표기를 붙이지 않는다
        #expect(FindPhoneLogic.notifySteps(title: "T", text: "찾기", repeats: 1).first?.last == "'찾기'")
    }

    @Test func notificationStepDetection() {
        #expect(FindPhoneLogic.isNotificationStep(FindPhoneLogic.notifyArgs(title: "T", text: "x")))
        #expect(!FindPhoneLogic.isNotificationStep(FindPhoneLogic.wakeArgs()))
        #expect(!FindPhoneLogic.isNotificationStep(FindPhoneLogic.brightnessArgs()))
        #expect(!FindPhoneLogic.isNotificationStep(FindPhoneLogic.brightnessModeReadArgs()))
        #expect(!FindPhoneLogic.isNotificationStep([]))
    }
}
