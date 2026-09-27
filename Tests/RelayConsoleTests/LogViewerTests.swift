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

    @Test func caseInsensitiveExpandsToCharacterClasses() {
        // libutils RegExp 는 inline 플래그를 못 읽는다 — `(?i)` 는 쓰지 않는다 (2026-09-28 실측)
        #expect(LogcatFilter.pattern(for: "anr", caseInsensitive: true) == "[aA][nN][rR]")
        #expect(LogcatFilter.pattern(for: "ANR", caseInsensitive: false) == "ANR")
    }

    /// 회귀 고정 — `(?i)` 로 되돌려 놓으면 **이 기기에서 adb 가 죽어 검색이 항상 0건** 이 된다
    @Test func caseInsensitiveNeverUsesInlineFlags() {
        for q in ["anr", "FATAL EXCEPTION", "has died", "dropbox", "a.b"] {
            let p = LogcatFilter.pattern(for: q, caseInsensitive: true) ?? ""
            #expect(!p.contains("(?i"), "inline 플래그는 이 기기의 logcat 이 못 읽는다: \(q) → \(p)")
            #expect(!p.contains("(?s"), "inline 플래그는 이 기기의 logcat 이 못 읽는다: \(q) → \(p)")
        }
    }

    /// 문자클래스 패턴이 **양쪽 대소문자를 실제로 찾는다** — ICU 로 확인(기기와 같은 의미인지는 별도 실측)
    @Test func caseInsensitivePatternMatchesBothCases() throws {
        let p = try #require(LogcatFilter.pattern(for: "anr in", caseInsensitive: true))
        for line in [
            "09-27 19:30:04.962  1235  1235 E ActivityManager: ANR in com.example.app",
            "09-27 19:30:04.962  1235  1235 E ActivityManager: anr in com.example.app",
        ] {
            let hit = try NSRegularExpression(pattern: p)
                .firstMatch(in: line, range: NSRange(line.startIndex..., in: line))
            #expect(hit != nil, "\(p) 가 '\(line)' 를 찾아야 한다")
        }
        let miss = "09-27 19:30:04.962  1235  1235 E ActivityManager: nothing here"
        let none = try NSRegularExpression(pattern: p)
            .firstMatch(in: miss, range: NSRange(miss.startIndex..., in: miss))
        #expect(none == nil, "일치하지 않을 때는 걸러야 한다")
    }

    /// 대소문자가 같은 글자는 리터럴로 남는다 (한글 검색이 깨지지 않아야 한다)
    @Test func caselessScriptsStayLiteral() {
        #expect(LogcatFilter.pattern(for: "가나다", caseInsensitive: true) == "가나다")
        #expect(LogcatFilter.pattern(for: "안녕 123", caseInsensitive: true) == "안녕 123")
    }

    /// 글자별로 나눠 이스케이프해도 **메타문자는 그대로 이스케이프된다**
    @Test func caseInsensitiveStillEscapesMetacharacters() {
        #expect(LogcatFilter.pattern(for: "a.b", caseInsensitive: true) == #"[aA]\.[bB]"#)
        #expect(LogcatFilter.pattern(for: "FATAL (Exception)", caseInsensitive: true)
                == #"[fF][aA][tT][aA][lL] \([eE][xX][cC][eE][pP][tT][iI][oO][nN]\)"#)
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

/// 소음 태그 기기 측 제외 — 2026-09-28 · PLAN_log_cpu_noise_filter
///
/// 이 테스트의 존재 이유: 제외는 **adb 인자 한 칸**(`'<tag>:S'`)이라 앱 안에서 흐려진다.
/// 인자가 잘못되면 **앱이 조용히 아무것도 안 보여주는** 상태가 된다 — [표시②] 위반이자 최악의 실패.
struct LogcatNoiseFilterTests {
    // MARK: - 필터식 조립

    @Test func levelFilterComesFirstAndExclusionsFollow() {
        let specs = LogcatFilter.filterSpecs(minLevel: "*:W", excludedTags: LogcatFilter.defaultExcludedTags)
        #expect(specs.first == "*:W", "레벨 필터가 첫 칸이어야 인자가 한 줄로 읽힌다")
        #expect(specs == [
            "*:W",
            "SemApTrafficData:S",
            "HeatmapThread:S",
            "ThermalManagerService$ThermalHalWrapper:S",
        ])
    }

    @Test func noExclusionLeavesLevelFilterAlone() {
        // 토글을 끈 상태 = 종전 동작 그 자체 (회귀 0)
        #expect(LogcatFilter.filterSpecs(minLevel: "*:D", excludedTags: []) == ["*:D"])
    }

    /// 실측으로 확인된 값을 코드에 고정한다 — 목록이 조용히 바뀌면 효과도 조용히 사라진다
    @Test func noisyTagsMatchTheMeasuredOffenders() {
        #expect(LogcatFilter.defaultExcludedTags == [
            "SemApTrafficData",
            "HeatmapThread",
            "ThermalManagerService$ThermalHalWrapper",
        ])
        // 20초 전수 스캔: 282,655줄 중 SemAp 261,521(92.5%) · 서로 다른 메시지는 1종류
        // ThermalHalWrapper 는 버퍼 2,874줄 (PLAN_log_cpu_noise_filter §1)
    }

    /// **`$` 가 들어간 태그는 실기에서 검증했다** (2026-09-28 · 버퍼 2,874 → 0줄, 과잉 제외 없음).
    /// 안전 필터가 `$` 를 걸러내면 **검증된 제외가 조용히 사라진다** — 효과가 아니라 실패처럼 보인다
    @Test func dollarSignTagSurvivesTheSafetyFilter() {
        #expect(LogcatFilter.safeTags(["ThermalManagerService$ThermalHalWrapper"])
                == ["ThermalManagerService$ThermalHalWrapper"])
    }

    // MARK: - 명령을 망가뜨리는 값 방어

    /// `*` 를 제외하면 **모든 로그가 사라진다.** 전부 조용히 — 체감상으로는 "기기 로그가 없네" 가 된다
    @Test func wildcardTagIsNeverExcluded() {
        #expect(LogcatFilter.safeTags(["*"]) == [])
        #expect(LogcatFilter.filterSpecs(minLevel: "*:W", excludedTags: ["*"]) == ["*:W"])
    }

    /// 공백·콜론이 섞이면 필터식이 깨진다 — 조용히 버린다 (표시를 잃는 게 명령이 깨지는 것보다 낫다)
    @Test func malformedTagsAreDropped() {
        let bad = ["Sem Ap", "Tag:Extra", "a*b", "c,d", "  ", "  OK_tag  "]
        #expect(LogcatFilter.safeTags(bad) == ["OK_tag"])
    }

    /// 비-ASCII 태그는 필터식 문법의 전제 밖이다 — **제외가 안 되는 것**이 실패 방향이다
    @Test func nonAsciiTagsAreDropped() {
        #expect(LogcatFilter.safeTags(["세미엽트래픽", "Tag_"]) == ["Tag_"])
    }

    /// 태그 이름이 필터식 문법과 충돌하지 않는다는 **가정** 자체를 고정한다
    @Test func noisyTagsAreFilterSafe() {
        #expect(LogcatFilter.safeTags(LogcatFilter.defaultExcludedTags) == LogcatFilter.defaultExcludedTags)
    }

    // MARK: - 제외가 무엇을 건드리지 않는가

    /// 제외는 **로그 창의 실시간 스트림에만** 적용된다.
    /// incident 덤프(`logcat -d`)와 키워드 스캔까지 얇아지면
    /// "증거를 뽑아 보면 저게 보인다" 가 거짓말이 된다
    @Test func incidentCaptureIsNotFiltered() {
        let text = (try? String(contentsOf: Self.incidentURL, encoding: .utf8)) ?? ""
        #expect(!text.isEmpty, "IncidentBundle.swift 를 못 읽었다 — 테스트가 조용히 통과하면 안 된다")
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            // 주석은 건너뛴다 — `logcat -T` 형식 설명(`HH:MM:SS.mmm`)에 `:S` 가 우연히 있다
            guard !line.hasPrefix("//"), line.contains("logcat") else { continue }
            #expect(!line.contains(":S"), "incident 캡처에 소음 제외가 새어 들어갔다: \(line)")
        }
    }

    private static var incidentURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // RelayConsoleTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // 저장소 루트
            .appendingPathComponent("Sources/RelayConsole/Incident/IncidentBundle.swift")
    }
}

/// 태그 선택 UI 의 판단 로직 — 2026-09-28 · PLAN_log_tag_picker
///
/// 이 테스트들이 지키는 것: **"사용자가 고른 것"이 기기 명령에 정확히 반영되고,
/// 숨긴 태그의 기록이 사라지지 않는 것.** 후자가 없으면 사용자는 기억으로 되돌린다.
struct LogTagPickerTests {
    // MARK: - 한 줄 파싱

    @Test func parsesTimeFormatLine() throws {
        let line = "09-28 02:03:02.326 W/dumpsys( 25283): Thread Pool max thread count is 0."
        let p = try #require(LogcatFilter.LineParser.parse(line))
        #expect(p.level == "W")
        #expect(p.tag == "dumpsys")
        #expect(p.pid == 25283)
        #expect(p.message == "Thread Pool max thread count is 0.")
    }

    @Test func parsesTagWithDollarAndLongName() throws {
        let line = "09-28 02:03:02.326 E/ThermalManagerService$ThermalHalWrapper( 2395): no cooling device"
        let p = try #require(LogcatFilter.LineParser.parse(line))
        #expect(p.tag == "ThermalManagerService$ThermalHalWrapper")
        #expect(p.level == "E")
    }

    /// 파싱 실패는 `nil` — **집계에서 조용히 빠진다.** 구획선·형식 외 줄이 여기 걸린다
    @Test func nonLogLinesAreNotCounted() {
        for line in [
            "--------- beginning of main",
            "",
            "메시지 처럼 생긴 줄",
            "09-28 02:03:02.326 W/ ( 1): 태그가 비었다",
        ] {
            #expect(LogcatFilter.LineParser.parse(line) == nil, "집계되면 안 되는 줄: \(line)")
        }
    }

    /// pid 를 못 읽어도 **태그가 유효하면 집계한다** — 줄은 실제로 존재하므로 세는 게 맞다.
    /// 조용히 버리면 "이 기기가 뱉는 태그 목록" 이 틀어진다
    @Test func unknownPidStillCounts() throws {
        let p = try #require(LogcatFilter.LineParser.parse("09-28 02:03:02.326 E/SomeTag(  ): 메시지"))
        #expect(p.tag == "SomeTag")
        #expect(p.pid == nil)
    }

    /// 태그에 공백이 들어갈 수는 없다(형식이 깨진다) — 그런 줄은 세지 않는다
    @Test func tagWithSpaceIsRejected() {
        #expect(LogcatFilter.LineParser.parse("09-28 02:03:02.326 E/Bad Tag( 1): x") == nil)
    }

    // MARK: - 집계

    @Test func countsLinesPerTag() {
        var s = LogcatFilter.TagStats()
        for _ in 0..<3 {
            s.record(.init(level: "E", tag: "Noisy", pid: 1, message: "Empty traffic data"))
        }
        s.record(.init(level: "W", tag: "Other", pid: 2, message: "hello"))
        #expect(s.entries["Noisy"]?.count == 3)
        #expect(s.entries["Other"]?.count == 1)
        #expect(s.entries["Noisy"]?.messages == ["Empty traffic data"])
        #expect(s.entries["Noisy"]?.messagesSaturated == false, "1종류일 뿐인데 '이상' 이면 거짓말이다")
        #expect(s.isEmpty == false)
    }

    /// 표본 상한에 닿으면 **"N종" 이 아니라 "N종 이상"** 이다
    @Test func messageSaturationIsMarked() {
        var s = LogcatFilter.TagStats()
        s.messageSampleLimit = 2
        for i in 0..<4 {
            s.record(.init(level: "E", tag: "T", pid: 1, message: "m\(i)"))
        }
        #expect(s.entries["T"]?.messages.count == 2)
        #expect(s.entries["T"]?.messagesSaturated == true)
    }

    /// 총 줄 상한 — **조용히 멈추지 않는다** (`capped` 로 알린다)
    @Test func totalLimitStopsAndFlags() {
        var s = LogcatFilter.TagStats()
        s.totalLimit = 3
        for _ in 0..<5 { s.record(.init(level: "E", tag: "T", pid: 1, message: "m")) }
        #expect(s.capped == true)
        #expect(s.totalRecorded == 3, "상한 이후에는 더 세지 않는다")
    }

    /// 표 크기 상한 — 드문 태그가 밀어내되, **조용해졌다 다시 시끄러지는 태그는 살아남아야 한다**
    ///
    /// 이 테스트가 처음 실패했다: 상한을 "꽉 찼으면 매 줄 자르기"로 구현해서,
    /// 건수가 1인 새 태그가 동률에서 즉시 축출되며 `loud` 가 표에 **한 번도 남지 못했다.**
    /// → 자르는 시점을 상한의 2배로 옮기고, 자르는 순간의 비용도 줄였다
    @Test func loudTagSurvivesTagLimit() {
        var s = LogcatFilter.TagStats()
        s.tagLimit = 2
        for i in 0..<5 { s.record(.init(level: "E", tag: "rare\(i)", pid: 1, message: "m")) }
        for _ in 0..<10 { s.record(.init(level: "E", tag: "loud", pid: 1, message: "m")) }
        #expect(s.entries["loud"]?.count == 10, "제일 시끄러운 태그는 살아남아야 한다")
        #expect(s.entries.count <= 4, "상한의 2배까지만 쌓인다")
    }

    // MARK: - 제외 상태 = 얼어붙음 (핵심)

    /// 제외해도 **집계값을 버리지 않는다** — 기기에서 걸린 태그는 더 이상 안 오니까
    @Test func exclusionFreezesInsteadOfDropping() throws {
        var s = LogcatFilter.TagStats()
        for _ in 0..<7 {
            s.record(.init(level: "E", tag: "Noisy", pid: 1, message: "Empty traffic data"))
        }
        s.setExcluded(["Noisy"])
        let row = try #require(s.snapshot().first { $0.tag == "Noisy" })
        #expect(row.entry.excluded == true)
        #expect(row.entry.count == 7, "숨긴 태그의 건수는 마지막 값으로 남는다")
        #expect(s.snapshot().contains { $0.tag == "Noisy" }, "숨긴 태그를 목록에서 지우면 되돌릴 수 없다")

        s.setExcluded([])
        let back = try #require(s.snapshot().first { $0.tag == "Noisy" })
        #expect(back.entry.excluded == false)
        #expect(back.entry.count == 7, "해제해도 집계는 이어진다")
    }

    @Test func snapshotIsSortedByCountDesc() {
        var s = LogcatFilter.TagStats()
        for (tag, n) in [("a", 2), ("b", 9), ("c", 5)] {
            for _ in 0..<n { s.record(.init(level: "W", tag: tag, pid: 1, message: "m")) }
        }
        #expect(s.snapshot().map(\.tag) == ["b", "c", "a"])
        #expect(s.snapshot(limit: 2).map(\.tag) == ["b", "c"])
    }

    @Test func freshStatsAreEmptyNotZero() {
        // "0건" 과 "아직 모른다" 를 구분한다 — [표시②]
        #expect(LogcatFilter.TagStats().isEmpty == true)
    }
}

/// 팝오버가 **표시하는 문구**의 규칙 — 2026-09-28
///
/// 문자열이 뷰 안에 있으면 규칙이 테스트 밖에 놓인다. 표본이 5개를 넘었을 때
/// "N종" 이라고 말하면 **거짓말**이므로 — 표가 아니라 **규칙**을 고정한다.
struct LogTagPickerTextTests {
    @Test func underCapSaysExactCount() {
        var e = LogcatFilter.TagStats.Entry()
        e.messages = ["a", "b", "c"]
        let t = LogcatFilter.messageSummary(e)
        #expect(t.key == "droid.logs.picker.msgs")
        #expect(t.args.count == 1)
    }

    @Test func saturatedSaysAtLeast() {
        var e = LogcatFilter.TagStats.Entry()
        e.messages = ["a", "b", "c", "d", "e"]
        e.messagesSaturated = true
        let t = LogcatFilter.messageSummary(e)
        #expect(t.key == "droid.logs.picker.msgs.more", "5개를 다 봤으면 'N종' 이 아니라 'N종 이상'")
        #expect(t.args.count == 1)
    }

    /// 두 키 모두 en/ko 에 있어야 하고, 변환자가 `%d` 여야 한다 (L10nFormatTests 가 1:1 을 보지만
    /// "두 키가 같은 형식인가" 는 여기서 고정한다)
    @Test func bothMessageKeysExistInBothLocales() throws {
        for key in ["droid.logs.picker.msgs", "droid.logs.picker.msgs.more"] {
            for loc in ["en", "ko"] {
                let text = try #require(
                    try L10nFormatTests.stringsTable(loc)[key],
                    "\(loc) 에 \(key) 없음")
                #expect(text.contains("%d"), "\(key) 는 건수를 넣어야 한다: \(text)")
            }
        }
    }
}

/// 파서의 **경계** — 2026-09-28 크래시 회귀 고정
///
/// `RelayConsole-2026-09-28-024513.ips` · `EXC_BREAKPOINT` / `SIGTRAP`
/// `_StringGuts.validateCharacterIndex` ← `String.index(after:)` ← `LineParser.parse`
/// 원인: **메시지가 빈 줄**에서 `)` 가 마지막 글자인데 무조건 `index(after:)` 를 불렀다.
///
/// 단위 테스트가 이 결함을 통과시킨 이유는 **내가 만든 정상 형식만** 넣었기 때문이다.
struct LogLineParserBoundaryTests {
    /// 실제로 크래시를 부른 형태
    @Test func emptyMessageAtEndOfLineDoesNotTrap() throws {
        for line in [
            "09-28 02:45:13.000 E/Tag( 1)",
            "09-28 02:45:13.000 E/Tag( 1):",
        ] {
            let p = try #require(LogcatFilter.LineParser.parse(line), "파싱되어야 한다: \(line)")
            #expect(p.tag == "Tag")
            #expect(p.message.isEmpty, "빈 메시지는 빈 문자열 — 트랩이 아니다: \(line)")
        }
    }

    /// `/` 로 시작하는 줄 — `index(before:)` 가 범위를 벗어난다
    @Test func leadingSlashDoesNotTrap() {
        for line in ["/", "//", "/(1)", "/Tag(1)"] {
            #expect(LogcatFilter.LineParser.parse(line) == nil, "세어지면 안 되는 줄: \(line)")
        }
    }

    /// 괄호가 닫히지 않은 줄, 아주 짧은 줄, 구분자만 있는 줄
    @Test func malformedShortLinesAreRejectedNotTrapped() {
        for line in [
            "W/Tag(", "W/Tag", "W/", "W", ")", "(", "E/Tag(1", "ㅏ/ㅓ(1): x", " ", "  ",
        ] {
            #expect(LogcatFilter.LineParser.parse(line) == nil, "세어지면 안 되는 줄: '\(line)'")
        }
    }

    /// 임의 문자열을 넣어도 **죽지 않는지** — 기기가 보낸 데이터는 내 문법을 지킨다는 보장이 없다
    @Test func arbitraryStringsNeverTrap() {
        let samples = [
            "", " ", "\n", "\t", "/", "()", ") (", "E/(1):", "E/Tag():", "E/Tag( ):x",
            "12345678", "ㅁㅂㅅ", "E/Tag(9999999999999999999999): x",
            "E/" + String(repeating: "T", count: 200) + "(1): x",
            "---------- beginning of kernel",
            "W/Tag(1):" + String(repeating: "가", count: 500),
        ]
        for line in samples {
            _ = LogcatFilter.LineParser.parse(line)   // 죽지 않으면 통과
        }
    }

    /// 구획선 처리를 죽이지 않았는지 — 실제 형식은 계속 잡힌다
    @Test func normalLinesStillParse() throws {
        let p = try #require(LogcatFilter.LineParser.parse(
            "09-28 02:03:02.326 W/dumpsys( 25283): Thread Pool max thread count is 0."))
        #expect(p.level == "W")
        #expect(p.tag == "dumpsys")
        #expect(p.pid == 25283)
        #expect(p.message == "Thread Pool max thread count is 0.")
}
}
