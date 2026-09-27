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

/// 로그 검색 로직 — 2026-09-27 · PLAN_log_search
///
/// 검색을 adb(기기) 쪽에서 거르는 근거: 이 기기는 `*:W` 가 **초당 1.4만 줄**이라
/// 링 2000행이 **0.14초분**이다. 클라이언트에서만 거르면 사실상 순간만 볼 수 있다.
struct LogcatFilterTests {
    private let anr = "09-27 19:30:04.962  1235  1235 E ActivityManager: ANR in com.example.app"

    // MARK: - adb 패턴 (단순 문자열 계약의 핵심)

    @Test func emptyQueryMeansNoDeviceFilter() {
        #expect(LogcatFilter.pattern(for: "", caseInsensitive: false) == nil)
        #expect(LogcatFilter.pattern(for: "   ", caseInsensitive: true) == nil)
    }

    @Test func plainQueryIsRegexEscaped() {
        // 계약이 "단순 문자열" 이므로 `a.b` 가 임의 문자로 해석돼선 안 된다
        #expect(LogcatFilter.pattern(for: "a.b", caseInsensitive: false) == #"a\.b"#)
        #expect(LogcatFilter.pattern(for: "FATAL (Exception)", caseInsensitive: false) == #"FATAL \(Exception\)"#)
        #expect(LogcatFilter.pattern(for: "a+b*c?", caseInsensitive: false) == #"a\+b\*c\?"#)
    }

    @Test func caseInsensitivePrefixesInlineFlag() {
        // logcat --regex 는 Java Pattern 이므로 (?i) 로 접두한다
        #expect(LogcatFilter.pattern(for: "anr", caseInsensitive: true) == #"(?i)anr"#)
        #expect(LogcatFilter.pattern(for: "ANR", caseInsensitive: false) == "ANR")
    }

    /// 공백이 들어간 검색어가 한 인자로 전달되어야 한다 (셸 인용은 Process 배열 인자가 담당)
    @Test func patternWithSpaceSurvivesAsOneToken() {
        let p = LogcatFilter.pattern(for: "FATAL EXCEPTION", caseInsensitive: false)
        #expect(p == "FATAL EXCEPTION")
        #expect(p?.contains(" ") == true)
    }

    // MARK: - 2차(로컬) 필터

    @Test func localFilterMatchesSubstring() {
        #expect(LogcatFilter.matches(anr, query: "ANR", caseInsensitive: false))
        #expect(LogcatFilter.matches(anr, query: "com.example", caseInsensitive: false))
        #expect(!LogcatFilter.matches(anr, query: "dropbox", caseInsensitive: false))
    }

    @Test func localFilterRespectsCaseToggle() {
        #expect(!LogcatFilter.matches(anr, query: "anr in", caseInsensitive: false))
        #expect(LogcatFilter.matches(anr, query: "anr in", caseInsensitive: true))
    }

    @Test func emptyQueryPassesEverything() {
        #expect(LogcatFilter.matches(anr, query: "", caseInsensitive: false))
        #expect(LogcatFilter.matches(anr, query: "  ", caseInsensitive: true))
    }

    // MARK: - 무데이터 상태 구분 [표시②]

    /// 검색 중인데 0줄 = "일치 없음" — "데이터 없음"(오류로 오해)이 아니다
    @Test func searchWithNoBytesIsNoMatchNotFailure() {
        let s = LogcatFilter.silence(query: "ANR", stderr: nil, isSilent: true, isStalled: false)
        #expect(s?.key == "droid.logs.search.none")
        #expect(s?.args.count == 1)
    }

    /// 잘못된 패턴은 adb 가 stderr 로 뱉는다 — "일치 없음" 으로 덮지 않고 원인을 그대로
    @Test func adbStderrWinsOverNoMatch() {
        let s = LogcatFilter.silence(
            query: "[oops", stderr: "regex_error", isSilent: true, isStalled: false
        )
        #expect(s?.key == "droid.logs.search.none.err")
    }

    @Test func withoutSearchSilenceKeepsOriginalKeys() {
        #expect(LogcatFilter.silence(query: "", stderr: nil, isSilent: true, isStalled: false)?.key
                == "droid.logs.silent")
        #expect(LogcatFilter.silence(query: "", stderr: "boom", isSilent: true, isStalled: false)?.key
                == "droid.logs.silent.err")
        #expect(LogcatFilter.silence(query: "", stderr: nil, isSilent: false, isStalled: true)?.key
                == "droid.logs.stalled")
        #expect(LogcatFilter.silence(query: "", stderr: "boom", isSilent: false, isStalled: true)?.key
                == "droid.logs.stalled.err")
    }

    @Test func healthyStreamHasNoSilenceMessage() {
        #expect(LogcatFilter.silence(query: "ANR", stderr: nil, isSilent: false, isStalled: false) == nil)
    }

    // MARK: - 프리셋

    /// 프리셋은 **실패 신호만** — 상태 변화 태그를 넣으면 "문제 N건" 이 장식이 된다 (2026-09-27 교훈)
    @Test func presetsAreFailureSignalsOnly() throws {
        #expect(LogcatFilter.presets == ["ANR", "FATAL EXCEPTION", "has died", "dropbox"])
        for banned in ["thermal", "accelerometer_rotation", "wm_user_rotation_changed"] {
            #expect(!LogcatFilter.presets.contains(banned), "상태 변화는 실패 신호가 아니다: \(banned)")
        }
        // 이스케이프가 제대로 됐는지 확인한다 — 프리셋 패턴이 자기 자신을 찾아야 한다
        // (기기는 Java Pattern, 여기는 ICU. ASCII 키워드에선 동일하게 동작한다)
        for p in LogcatFilter.presets {
            let pattern = try #require(LogcatFilter.pattern(for: p, caseInsensitive: false))
            let line = "09-27 19:30:04.962  1235  1235 E Tag: \(p) 뒤에 뭐가 더 있든"
            let hit = try NSRegularExpression(pattern: pattern)
                .firstMatch(in: line, range: NSRange(line.startIndex..., in: line))
            #expect(hit != nil, "프리셋 '\(p)' → 패턴 '\(pattern)' 이 자기 자신을 찾아야 한다")
        }
    }
}
