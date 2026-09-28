import SwiftUI
import AppKit
import Combine

/// logcat 실시간 스트림 — 창 id:"logs" (PLAN_v0.7)
///
/// ## 왜 이렇게 생겼나 (2026-09-27)
///
/// 종전 구현은 "초록 LIVE 인디케이터만 켜지고 줄이 영영 나오지 않는" 상태로 고착돼 있었다.
/// 근본 원인은 **stderr 미배출**이었다.
///
/// 1. **stderr 교착** — `proc.standardError = Pipe()` 만 해놓고 읽지 않았다. 파이프 버퍼(64KB)가
///    차면 adb 가 `write()` 에서 블로킹되고 **stdout 생산이 멈춘다**. 프로세스는 종료도 하지
///    않으니 `terminationHandler` 도 안 불린다. = 초록 점 + 빈 화면이 영구 지속.
///    (`ProcessRunner.swift` 가 같은 함정을 이미 문서화했다 — 스트리밍 경로만 빠진 상태였다)
/// 2. **LIVE 거짓말** — `isRunning` 이 `proc.run()` 성공에서만 켜졌다. "프로세스 기동됨"과
///    "데이터가 흐르는 중"을 구분하지 않았다. [AGENTS.local §4 표시②] 위반.
/// 3. **볼륨** — 이 기기는 6초에 20MB(약 3만 줄/초)를 뱉는다. 200줄 링은 **약 7ms 분량**이라
///    사람이 읽을 수 있는 정보가 전혀 없었다. 기본을 `W 이상`으로 좁히고 필터를 제공한다.
///
/// 배수는 `readabilityHandler`(전용 백그라운드 스레드)로 통일했다. 종전의
/// `NSFileHandleDataAvailable` 알림 펌프는 알림 등록/재무장 사이의 경쟁이 있었고,
/// 알림 기반이므로 런루프 상태에 예민했다.
/// 로그 검색 — 판단 로직을 **순수 함수**로 분리한다 (2026-09-27 · PLAN_log_search)
///
/// 왜 분리했나: `LogcatStreamer` 는 싱글턴이고 `start()` 가 실제 adb 를 필요로 해서
/// "검색 중인데 0줄" 상태를 단위 테스트로 고정할 방법이 없다. 판단만 떼어 내면 고정된다.
enum LogcatFilter {
    /// 검색에 자주 쓰이는 신호 — 실패만, 상태 변화는 넣지 않는다
    /// (2026-09-27: `thermal`·`accelerometer_rotation` 같은 상태 변화는 실패 신호가 아니다)
    static let presets: [String] = ["ANR", "FATAL EXCEPTION", "has died", "dropbox"]

    // MARK: - 소음 태그 기기 측 제외 (2026-09-28 · PLAN_log_cpu_noise_filter)

    /// 같은 메시지를 반복해 사람이 읽을 수 없게 만드는 태그.
    ///
    /// ## 왜 이 목록이 있는가 (2026-09-28 실측 · SM-S901N Android 15)
    ///
    /// `logcat -v time '*:W'` 20초 채집 = **282,655줄** 중:
    ///
    /// | 태그 | 건수 | 비중 | 서로 다른 메시지 |
    /// |---|---:|---:|---:|
    /// | `SemApTrafficData` | 261,521 | **92.5%** | **1** (`Empty traffic data`) |
    /// | `HeatmapThread` | 1,178 | 0.4% | 3 (모두 `/efs/FactoryApp` 공장 EFS 접근 실패) |
    /// | `ThermalManagerService$ThermalHalWrapper` | 2,874 | 1.5% | 2 (HAL 조회 실패 — 냉각기·임계값 없음) |
    ///
    /// 로그 창을 열면 **CPU 99%** 로 올라간다(부하가 100배 변하므로 "40%" 라는 수치는 믿지 않는다).
    /// 1종류 메시지를 초당 1.3만 번 파싱·렌더하는 것이 비용의 대부분이다.
    /// 더구나 원인은 **개방 순간의 링 버퍼 덤프**였다(231,982줄 → 16,763줄, 7.2%).
    ///
    /// ## 왜 `ActivityManager` 는 넣지 않았나 (판단을 넘기는 이유를 남긴다)
    ///
    /// 3종 제외 후 잔여 13,811줄 중 `ActivityManager` 가 **40.4%** 이고 그중 5,247줄(94%)이
    /// **하나의 동일 메시지**다:
    /// `Foreground service started from background … : service com.nisargjhaveri.netspeed/.IndicatorService`
    /// 반복도로 보면 소음이지만, **이 줄은 범인 앱 이름을 담고 있다**(버퍼에 앱 7종).
    /// `Empty traffic data` 와 달리 "무엇이 이 기기를 망가뜨리고 있는가" 를 말해주는 신호이므로
    /// **기본 제외하지 않는다.** 사용자가 원하면 고를 수 있게 하는 것이 정답이며 — 태그 선택 UI 는 별도 과목.
    /// `PermissionService`(590줄·1종류) · `DeviceStorageMonitorService`(332줄·2종류) 도
    /// 순수 반복이지만, 이미 7% 로 줄인 잔여량에서 **6.7%** 뿐이라 뺄 이유가 부족하다
    /// (숨기는 `E` 줄이 늘면 배지가 아니라 **침묵** 이 된다).
    ///
    /// ## 왜 `--regex` 로 안 됐나 (실측 3-way 비교)
    ///
    /// | 방법 | 결과 |
    /// |---|---|
    /// | `--regex='^(?!.*Tag)'` (부정 순방위) | ❌ **제외 안 됨** — SemAp 3,918건 잔존 |
    /// | 기기 측 `logcat … \| grep -v -E 'Tag'` | ✅ 되지만 quoting·추가 프로세스 위험 |
    /// | **필터식 `'<tag>:S'`** | ✅ **제외됨 0건** — adb 인자 한 칸, 위험 0 |
    ///
    /// `--regex` 는 ECMAScript 엔진이 아니라 libutils `RegExp` 라 **부정 순방위를 지원하지 않고
    /// 컴파일 실패도 오류 없이 통과시킨다.** "수가 줄었다" 는 계측이 아니라 allowlist(검색어) 효과였고,
    /// 검색이 잘 먹는 이유도 "`--regex` 가 강력해서" 가 아니라 **양의 일치만 쓰기 때문**이다.
    ///
    /// ## 이 목록이 정직한 이유
    ///
    /// - 제외 대상은 **"비율이 아니라 반복도"** 로 골랐다. `ActivityManager`(2.1%, 44종류)처럼
    ///   사람이 읽을 정보가 있는 것은 남긴다
    /// - **숨기지 않는다** — 푸터 배지로 항상 개수를, tooltip 으로 태그명을 밝힌다. 1클릭으로 해제 가능
    /// - **범위가 좁다** — 로그 창의 실시간 스트림에만 적용된다.
    ///   `IncidentBundle` 캡처(`logcat -d`)와 `logcatKeywords` 스캔은 **전량 그대로**다.
    ///   "incident 를 뽑아 보면 저게 보인다" 는 사실이 유지된다
    /// 기본 시드 — 계측으로 고른 3종 (사용자가 지우고 더할 수 있다)
    ///
    /// 2026-09-28 실측 (SM-S901N) 근거는 위 표와 같다. 이 목록은 **시드일 뿐이고,
    /// 사용자가 푸터 배지를 눌러 태그마다 바꾼다** (PLAN_log_tag_picker §0).
    static let defaultExcludedTags: [String] = [
        "SemApTrafficData",
        "HeatmapThread",
        "ThermalManagerService$ThermalHalWrapper",
    ]

    /// 사용자 선택 목록 저장 키
    static let excludedTagsKey = "relay.logs.excludedTags"
    /// 종전 `Bool` 키 — 마이그레이션에서만 읽는다 (PLAN_log_tag_picker §2)
    static let legacyExcludeNoisyKey = "relay.logs.excludeNoisyTags"

    /// 제외 태그 목록이 adb 인자로 안전하게 변환되는지 — **명령을 망가뜨릴 값은 조용히 버린다.**
    ///
    /// 두 가지 실수를 막는다:
    /// - `*` 를 넣으면 **모든 로그가 사라진다**(전부 조용히 — [표시②] 위반)
    /// - 공백·`:` 등이 섞이면 필터식이 깨진다
    ///
    /// **비-ASCII 와 `$` 를 빼는 이유가 다르다.**
    /// 비-ASCII 태그는 필터식 문법의 전제 밖이라 애초에 검증되지 않았다.
    /// `$` 는 **검증된** 태그에 실제로 들어 있다(`ThermalManagerService$ThermalHalWrapper`).
    /// 2026-09-28 실기 — 버퍼 2,874줄이 이 태그였고 `'<tag>:S'` 를 걸었더니 **0줄**,
    /// 다른 태그는 194,910 → 185,309(딱 2,874줄만 감소)로 과잉 제외도 없었다.
    /// 즉 `$` 는 필터식 문법에서 특별하지 않다. **검증된 걸로 막으면 된다가 아니라,
    /// 검증된 예외는 예외로 들여다보다** — 이 성질이 문서에 없었다면 이 태그가 조용히 사라졌다.
    static func safeTags(_ tags: [String]) -> [String] {
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_$")
        var out: [String] = []
        for tag in tags {
            let t = tag.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, t != "*" else { continue }
            guard t.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { continue }
            out.append(t)
        }
        return out
    }

    /// adb `logcat` 에 넘길 필터식 목록 — **레벨 필터가 항상 첫 칸**, 그 뒤에 `<tag>:S` 를 붙인다.
    ///
    /// 순서는 logd 필터 평가에 영향을 주지 않지만, 인자를 사람이 읽을 때
    /// "무엇이 걸린 것" 이 한 줄로 보여야 해서 고정한다.
    static func filterSpecs(minLevel: String, excludedTags: [String]) -> [String] {
        [minLevel] + safeTags(excludedTags).map { "\($0):S" }
    }

    // MARK: - 태그 집계 (2026-09-28 · PLAN_log_tag_picker)

    /// `adb logcat -v time` 한 줄 — `09-28 02:03:02.326 W/dumpsys( 25283): 메시지`
    struct ParsedLine: Equatable {
        let level: String   // W · E · I · D …
        let tag: String
        let pid: Int?
        let message: String
    }

    /// 한 줄에서 태그를 뽑는다 — **정규식 없이** 인덱스로 찾는다.
    ///
    /// 왜 정규식을 안 쓰나: 이 함수는 **들어오는 모든 줄**에서 호출된다
    /// (최악 2.2만 줄/초). 정규식 컴파일·매칭 비용을 볼륨에 곱하면
    /// **측정 대상인 CPU 를 늘리는 방향**이 된다.
    ///
    /// 구획선(`--------- beginning of main`)은 태그가 없으므로 `nil`.
    ///
    /// ## 모든 인덱스 이동은 경계를 먼저 본다 (2026-09-28 크래시)
    ///
    /// 첫 구현은 `line.index(after: close)` 를 무조건 불렀다 → **메시지가 빈 줄**
    /// (`E/Tag( 1):` 처럼 `)` 가 마지막 글자)에서 트랩이 났다.
    /// ```
    /// RelayConsole-2026-09-28-024513.ips
    ///   exception : EXC_BREAKPOINT · SIGTRAP
    ///   frames    : _StringGuts.validateCharacterIndex ← String.index(after:)
    ///               ← LogcatFilter.LineParser.parse ← LogcatStreamer.append
    /// ```
    /// 로그 줄은 **기기에서 오는 데이터**다 — 내 문법이 맞다고 가정할 수 없다.
    /// 단위 테스트는 **내가 만든 정상 형식만** 넣어 이 결함을 통과시켰다.
    enum LineParser {
        /// 접두부만 본다 — 태그는 시각 필드 다음에 온다. 뒤를 볼 필요가 없다
        static let scanLimit = 48

        static func parse(_ line: String) -> ParsedLine? {
            // ① `/` 앞에는 **반드시 한 글자**가 있어야 한다(레벨). 맨 앞 `/` 면 뒤로 갈 수 없다
            guard let slash = line.firstIndex(of: "/"),
                  slash > line.startIndex,
                  slash < line.index(line.startIndex, offsetBy: min(scanLimit, line.count)),
                  let open = line[slash...].firstIndex(of: "("),
                  let close = line[line.index(after: open)...].firstIndex(of: ")"),
                  open > line.index(after: slash)
            else { return nil }

            // ② 태그 앞의 마지막 글자가 레벨이다 (` W/` → W). 붙어 있지 않으면 형식이 아니다
            let levelStart = line.index(before: slash)
            let level = String(line[levelStart])
            guard level.rangeOfCharacter(from: .uppercaseLetters) != nil else { return nil }

            let tag = String(line[line.index(after: slash)..<open])
            guard !tag.isEmpty, !tag.contains(" ") else { return nil }

            let pidText = String(line[line.index(after: open)..<close])
                .trimmingCharacters(in: .whitespaces)
            return ParsedLine(
                level: level,
                tag: tag,
                pid: Int(pidText),
                message: message(of: line, after: close)
            )
        }

        /// `)` 다음의 `": "` 를 건너뛴다 — **경계를 넘지 않는다**
        ///
        /// `)` 가 줄의 마지막 글자일 수 있다(`E/Tag( 1):`). 이때 메시지는 빈 문자열이고,
        /// 무조건 `index(after:)` 를 부르면 트랩이다(위 크래시).
        private static func message(of line: String, after close: String.Index) -> String {
            var i = line.index(after: close)
            var skipped = 0
            while i < line.endIndex, skipped < 2, line[i] == ":" || line[i] == " " {
                i = line.index(after: i)
                skipped += 1
            }
            return i < line.endIndex ? String(line[i...]) : ""
        }
    }

    /// 태그별 반복 집계 — "이 태그를 숨겨라" 의 입력이 되는 표
    ///
    /// ## 왜 순수 자료구조인가
    ///
    /// 스트리머·뷰·저장소를 한데 엮으면 **집계가 고장 났을 때 UI 탓인지 계산 탓인지 구분되지 않는다.**
    /// 판단만 여기서 끝내고(`record` · `snapshot` · `setExcluded`) 나머지는 배선만 한다.
    ///
    /// ## 왜 "얼어붙음" 이 핵심인가 (PLAN_log_tag_picker §1-②)
    ///
    /// 제외는 **기기에서** 일어나므로 제외한 태그의 줄은 더 이상 도착하지 않는다.
    /// 값을 버리면 사용자는 **자기가 뭘 숨겼는지 기억으로 되돌려야 한다.**
    /// → 제외해도 **마지막 집계값을 유지**한다. 되돌리기가 정보가 된다.
    struct TagStats {
        /// 태그 1개의 집계
        struct Entry: Equatable {
            var count: Int = 0
            /// 서로 다른 메시지 표본 (상한 `messageSampleLimit`)
            var messages: Set<String> = []
            /// 표본이 상한에 닿았는지 — 이때 "N종" 이 아니라 "N종 이상" 으로 말해야 한다
            var messagesSaturated = false
            /// 제외 중인가 — **집계값은 유지한 채 상태만 다르다**
            var excluded = false
            /// ★ 이 값을 **실제로 셌는가** (2026-09-28 추가)
            ///
            /// 앱을 다시 띄우면 집계를 비우고, 제외된 태그는 기기에서 안 오므로
            /// **집계 항목이 아예 생기지 않는다.** 그때 합성한 행의 `count` 는 0 이지만
            /// "0 줄 이다" 는 **거짓말**이다 — "몰라" 를 0 으로 말하면 안 된다.
            var counted = true
        }

        var entries: [String: Entry] = [:]
        /// 집계한 총 줄 수 — 상한 도달 여부를 정직하게 알리기 위해 남긴다
        private(set) var totalRecorded = 0
        private(set) var capped = false

        /// 상한은 **인스턴스 값**이다 — 테스트에서 수십만 줄을 채울 수는 없으므로
        /// 스텁으로 줄인다. 상한이 상수가 되면 상한 동작을 검증할 방법이 사라진다.
        var messageSampleLimit = TagStats.defaultMessageSampleLimit
        var totalLimit = TagStats.defaultTotalLimit
        var tagLimit = TagStats.defaultTagLimit

        /// 표본 상한 — 넘으면 "N종" 이 아니라 "N종 이상" 으로 표기한다
        static let defaultMessageSampleLimit = 5
        /// 집계 총 줄 상한 — 제외를 꺼 둔 2.2만 줄/초 환경에서 집계가 비용이 되지 않도록
        static let defaultTotalLimit = 200_000
        /// 표에 남길 태그 수 — 버퍼가 수천 개로 불어나지 않게
        static let defaultTagLimit = 60

        mutating func record(_ line: ParsedLine) {
            guard !capped else { return }
            var e = entries[line.tag] ?? Entry()
            e.count += 1
            if e.messages.count < messageSampleLimit {
                e.messages.insert(line.message)
            } else if !e.messages.contains(line.message) {
                e.messagesSaturated = true
            }
            entries[line.tag] = e
            totalRecorded += 1
            if totalRecorded >= totalLimit { capped = true }
            // **매 줄마다 자르지 않는다.** 표가 가득 찬 순간부터 정렬·축출을 반복하면
            // (실측: 태그가 수백 개 섞이는 구간에서) 줄마다 O(n log n) 이 붙고,
            // 건수가 1인 새 태그가 동률에서 즉시 밀려나 **"조용해졌다가 다시 시끄러워지는"
            // 태그를 영영 못 잡는다.** 상한의 2배까지 쌓였다 한 번만 자른다.
            if entries.count > tagLimit * 2 { trimRareTags() }
        }

        /// 개수가 적은 태그를 지운다 — 표의 크기를 상한에 묶는다
        private mutating func trimRareTags() {
            let keep = entries
                .sorted { $0.value.count > $1.value.count }
                .prefix(tagLimit)
                .map(\.key)
            entries = entries.filter { keep.contains($0.key) }
        }

        /// 제외 상태를 반영한다 — **값은 그대로 두고 상태만 바꾼다**
        mutating func setExcluded(_ tags: [String]) {
            let set = Set(tags)
            for (tag, var e) in entries {
                e.excluded = set.contains(tag)
                entries[tag] = e
            }
        }

        /// 건수 내림차순 상위 N — **제외된 태그는 집계가 없어도 반드시 포함한다.**
        ///
        /// ## 왜 이게 버그였나 (2026-09-28 실측)
        /// 이 주석은 "제외된 태그도 그대로 둔다" 고 **문서화되어 있었다.**
        /// 그런데 제외된 태그는 기기에서 걸러져 **더 이상 도착하지 않으므로**
        /// 앱을 다시 띄운 뒤에는 **집계 항목 자체가 없다.**
        /// → 목록에서 사라져 체크를 해제할 수단이 없어졌다.
        /// 실측: 앱 재시작 후 사용자가 추가한 `Watchdog` 가 목록에서 사라졌고,
        /// `기본값 복원` 을 눌러도 **돌아오지 않았다** (기본 3종으로만 복귀).
        /// 되돌릴 수 없는 상태였다.
        ///
        /// 집계는 창을 *연* 시점에 비워지는데(`resetStats: true`),
        /// 제외 태그는 **재시작 후 영원히 집계가 안 쌓인다** — 그래서 이 처리가 필수다.
        func snapshot(limit: Int = 8, excluding: [String] = []) -> [(tag: String, entry: Entry)] {
            var rows = entries
                .map { (tag: $0.key, entry: $0.value) }
                .sorted { $0.entry.count > $1.entry.count }
                .prefix(limit)
                .map { $0 }
            let listed = Set(rows.map(\.tag))
            // 집계에 없는 제외 태그를 **뒤에** 붙인다 — 건수가 0 으로 "상위" 가 된다면
            // 정직하지 않다. "모른다" 를 0 으로 말하지 않는다 (count 0 · counted=false)
            for tag in excluding where !listed.contains(tag) {
                rows.append((tag: tag, entry: Entry(count: 0, messages: [], excluded: true, counted: false)))
            }
            return rows
        }

        /// 태그가 몇 개나 집계됐나 (빈 상태와 "데이터 없음" 을 구분하기 위해)
        var isEmpty: Bool { entries.isEmpty }
    }

    /// 팝오버가 태그 한 줄에 보여줄 문구 — **뷰는 이 함수만 호출한다**
    ///
    /// 문자열을 뷰 안에 두면 "N종" 과 "N종 이상" 의 구분 규칙이 테스트 밖에 놓인다.
    /// 구분 규칙은 **정직성 규칙**이라(표본이 5개를 넘으면 "N" 이 아니라 "N 이상" 이다)
    /// 반드시 테스트가 있어야 한다.
    static func messageSummary(_ e: TagStats.Entry) -> (key: String, args: [CVarArg]) {
        // ★ 셌지 않은 값은 개수를 말하지 않는다 (2026-09-28)
        //   "0종" 은 "한 번도 안 봤다" 와 "0종 이다" 를 구분하지 못한다
        guard e.counted else { return ("droid.logs.picker.unknown", []) }
        return e.messagesSaturated
            ? ("droid.logs.picker.msgs.more", [e.messages.count])
            : ("droid.logs.picker.msgs", [e.messages.count])
    }

    /// 행의 건수 문구 — 셌지 않은 값은 **"몰라"** 를 말한다
    static func countSummary(_ e: TagStats.Entry) -> (key: String, args: [CVarArg]) {
        e.counted
            ? ("droid.logs.picker.countN", [e.count])
            : ("droid.logs.picker.countUnknown", [])
    }

    /// adb `logcat --regex=<패턴>` 에 넘길 값.
    ///
    /// - 빈 검색어 → `nil` (= 기기 필터 없음)
    /// - **메타문자는 반드시 이스케이프한다** — 계약은 "단순 문자열" 이므로 `a.b` 가 `a 임의 문자 b` 로
    ///   해석돼서는 안 된다. 잘못 이스케이프를 빼면 사용자가 검색을 못 하는 것보다 나쁘다.
    /// - 대소문자 무시 → **글자별 문자클래스**(`anr` → `[aA][nN][rR]`), `(?i)` 접두를 쓰지 않는다
    ///
    /// ## 왜 `(?i)` 를 쓰지 않는가 (2026-09-28 실측 — 주석이 틀렸던 것을 계측이 잡았다)
    ///
    /// 종전 주석은 "logcat `--regex` 는 Java `Pattern` 이므로 지원된다" 라 적었으나 **거짓**이었다.
    /// 이 기기(SM-S901N · Android 15) 실측:
    /// ```
    /// adb shell logcat -v time '*:W' 'SemApTrafficData:S' --regex=(?i)anr
    ///   → 0줄 · stderr: regex_error was thrown in -fno-exceptions mode
    /// ```
    /// logcat 의 정규식 엔진은 ECMAScript/Java 이 아니라 **libutils `RegExp`** 다
    /// (부정 순방위 미지원이 같은 근거로 증명됐다 — `noisyTags` 주석 참고).
    /// inline 플래그를 못 읽으면 **adb 가 곧 죽고** 대소문자 무시 검색은 항상 0건이 된다.
    ///
    /// 문자클래스 `[aA]` 는 **어떤 엔진에서도** 뜻이 통한다.
    /// 원인이 stderr 로 노출되므로 ([표시②] 덕분에 사용자는 "기기 오류" 라 이해했다) 이지만,
    /// **검색이 안 먹는다** 는 사실 자체가 그대로 남는다.
    static func pattern(for query: String, caseInsensitive: Bool) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard caseInsensitive else { return NSRegularExpression.escapedPattern(for: trimmed) }
        return trimmed.map(characterClass).joined()
    }

    /// 한 글자를 "자기 자신 + 대소문자 반대 형태" 문자클래스로 바꾼다.
    ///
    /// - 대소문자가 같은 글자(한글·숫자·기호) → 이스케이프한 리터럴 그대로
    /// - 대소문자가 다른 글자 → `[aA]`
    /// - 대소문자 변환이 **여러 글자**로 늘어나는 경우(`ß` → `SS`)는 그대로 넣는다 —
    ///   약간 넓게 잡는 것이 **좁게 잡는 것보다 안전하다**(기기가 더 많은 줄을 보내고
    ///   2차 로컬 필터가 줄인다. 반대면 사용자가 못 찾는다)
    static func characterClass(_ ch: Character) -> String {
        let lower = ch.lowercased()
        let escapedLower = NSRegularExpression.escapedPattern(for: lower)
        let upper = ch.uppercased()
        guard lower != upper else { return escapedLower }
        return "[\(escapedLower)\(NSRegularExpression.escapedPattern(for: upper))]"
    }

    /// 링 버퍼 2차 필터 — adb 가 아직 따라오기 전(디바운스 중)에도 즉시 반응한다.
    /// adb `--regex` 미지원 기기에서도 여기가 최종 방어선이 된다.
    static func matches(_ text: String, query: String, caseInsensitive: Bool) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        return caseInsensitive
            ? text.lowercased().contains(trimmed.lowercased())
            : text.contains(trimmed)
    }

    /// 무관한 값을 보여주는 이유 — [표시②] 실제 상태를 구분해 그대로 말한다.
    ///
    /// 핵심 구분: **검색 중인데 0줄** 과 **데이터가 안 옴** 은 다른 상태다.
    /// 검색 중인데 "데이터 없음" 이라 하면 기기가 멀쩡한데 사용자는 오류라고 읽는다.
    /// 반대로 adb 오류(stderr)가 있으면 "일치 없음" 으로 덮지 않고 **원인을 그대로** 보여준다.
    static func silence(
        query: String,
        stderr: String?,
        isSilent: Bool,
        isStalled: Bool
    ) -> (key: String, args: [CVarArg])? {
        let hasQuery = !query.trimmingCharacters(in: .whitespaces).isEmpty
        if isSilent {
            if hasQuery {
                if let stderr, !stderr.isEmpty { return ("droid.logs.search.none.err", [stderr]) }
                return ("droid.logs.search.none", [query])
            }
            if let stderr, !stderr.isEmpty { return ("droid.logs.silent.err", [stderr]) }
            return ("droid.logs.silent", [])
        }
        if isStalled {
            if let stderr, !stderr.isEmpty { return ("droid.logs.stalled.err", [stderr]) }
            return ("droid.logs.stalled", [])
        }
        return nil
    }
}

/// 기동 중인 프로세스 **한 개의 자리** — 종료 알림이 "이전 프로세스" 것인지 판별한다.
///
/// ## 왜 이 클래스가 있나 (2026-09-27 실측)
///
/// `Process.terminationHandler` 는 `Task { @MainActor }` 로 **나중에** 실행된다.
/// 필터를 바꿀 때마다 일어나는 실제 순서는 이렇다:
///
/// ```
/// stop()  → 이전 프로세스 terminate() → 이전 프로세스 죽음 → 슬롯 비움
///                                                          └─ 이 알림이 메인액터에 **큐잉**
/// start() → 새 프로세스 run() → 슬롯에 새 프로세스 adopt
///                       ... 잠시 후 ...
///                  이전 프로세스 알림 도착 → 슬롯을 비워버림
/// ```
///
/// 마지막 한 줄이 범인이다. **살아 있는 새 프로세스의 참조가 사라져** 다음 필터 전환 때
/// `stop()` 이 그 프로세스를 죽이지 못하고, adb logcat 가 전환 횟수만큼 **누적된다**.
/// 실측: 필터 4회 전환 → adb logcat 4개가 동시 생존(규칙은 최대 1개).
/// 셸에서 `kill -TERM` 은 즉시 죽으므로 adb 문제는 아니었다 — 참조가 사라진 것이 원인.
final class LogcatProcessSlot {
    /// 현재 기동 중(또는 기동 대상)인 프로세스
    private(set) var current: Process?

    func adopt(_ process: Process?) { current = process }

    /// 종료 알림을 반영한다 — **내가 지금 들고 있는 그 프로세스** 일 때만 정리하고 `true`.
    /// 이전 프로세스의 알림이면 아무것도 하지 않고 `false` (아래가 그 회귀 테스트의 대상).
    @discardableResult
    func release(_ dead: Process) -> Bool {
        guard current === dead else { return false }
        current = nil
        return true
    }
}

@MainActor
final class LogcatStreamer: ObservableObject {
    static let shared = LogcatStreamer()

    /// 링 버퍼 한 줄 — SwiftUI 가 `offset` 를 id 로 쓰면 플러시마다 전 줄이 재렌더된다.
    /// 안정 id 를 부여해 스크롤·색칠이 유지되게 한다.
    struct Line: Identifiable, Equatable {
        let id: UInt64
        let text: String
    }

    /// 최소 레벨 필터 — 관제 기본은 `W` (D/I 는 초당 수만 줄이라 사람이 못 본다)
    enum MinLevel: String, CaseIterable, Identifiable, Sendable {
        case debug = "D", info = "I", warning = "W", error = "E"
        var id: String { rawValue }
        /// adb logcat 필터식 — `*:W` 형태
        var filterSpec: String { "*:\(rawValue)" }
    }

    @Published private(set) var lines: [Line] = []
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?
    /// 마지막으로 **실제 바이트**가 들어온 시각 — LIVE 표시의 진실
    @Published private(set) var lastDataAt: Date?
    /// 프로세스 기동 이후 받은 총 줄 수 (링 잘려도 실측량으로 남는다)
    @Published private(set) var totalLines: Int = 0
    /// 필터 변경 시 스트림을 다시 튼다 (이 값을 바꾸면 `restartOnLevelChange` 참조)
    @Published var minLevel: MinLevel = .warning
    /// 검색어 — 로컬 2차 필터는 **즉시** 반영, adb 1차 필터는 디바운스 뒤 반영된다
    @Published var query: String = ""
    /// 대소문자 무시
    @Published var caseInsensitive: Bool = false
    /// 반복 소음 태그 — **사용자가 고른다** (기본 시드 3종)
    ///
    /// 종전에는 `Bool` 하나("소음 태그 제외" 켜기/끄기)였다. 목록을 고를 수 없었기 때문이다
    /// (PLAN_log_tag_picker §0). 이제 **배열**이며 푸터 배지를 눌러 태그마다 켜고 끈다.
    ///
    /// 읽을 때 `bool(forKey:)` 를 쓰면 **저장 전 값이 false** 가 되어 기본값이 깨진다.
    /// `object(forKey:) as? [String]` 로 읽고, `nil`(저장 전)일 때만 시드를 넣는다.
    @Published private(set) var excludedTags: [String] = []

    /// 지금 adb 에 실제로 적용된 제외 태그 — 배지와 tooltip 의 진실원천
    @Published private(set) var appliedExcludedTags: [String] = []
    /// 태그별 반복 집계 — 배지 클릭 시 표를 그린다
    @Published private(set) var tagStats = LogcatFilter.TagStats()

    /// 태그 하나를 켜고 끈다 — **스트림 재기동은 디바운스 뒤** (2026-09-28 실측)
    ///
    /// ## 왜 즉시 재기동하지 않는가
    ///
    /// 태그를 켜자마자 `start()` 하면 두 가지가 동시에 잃는다:
    /// ① **팝오버가 닫힌다** — `@Published` 변경 → 부모 body 재평가 → `.popover` 콘텐츠가
    ///    새로 만들어지며 SwiftUI 가 닫아 버린다. 여러 개를 연속으로 고를 수 없는 상태가 된다
    ///    (실측: 태그 1개 켜고 팝오버 사라짐 — 고치지 않으면 기능이 반만 된다)
    /// ② **adb 를 매 클릭마다 다시 띄운다** — 개방할 때마다 링 버퍼를 다시 받는다
    ///    (이 기기에서 1.6만 줄). 태그 3개를 고르면 3번 받는 셈
    ///
    /// 체크박스 표시는 `setExcluded` 로 **즉시** 바뀌고(`tagStats` 갱신),
    /// 배지는 **실제로 적용된 뒤**의 값(`appliedExcludedTags`)을 말하므로
    /// 0.6초 동안 배지가 옛 값인 것은 "아직 적용 안 됨" 이라는 **참이다**.
    func toggleTag(_ tag: String) {
        var next = excludedTags
        if let idx = next.firstIndex(of: tag) {
            next.remove(at: idx)
        } else {
            next.append(tag)
        }
        setExcludedTags(next)
        scheduleRestart()
    }

    /// 기본 시드로 되돌린다 (사용자가 지운 기본 태그를 되살린다)
    func restoreDefaultExcludedTags() {
        setExcludedTags(LogcatFilter.defaultExcludedTags)
        scheduleRestart()
    }

    /// 재기동 예약 — 사람 속도(연속 클릭)에서 1회로 합쳐진다
    private func scheduleRestart() {
        restartTask?.cancel()
        let (serial, adb) = (currentSerial, currentAdbPath)
        guard !serial.isEmpty else { return }
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.tagToggleDebounce))
            guard let self, !Task.isCancelled else { return }
            self.start(serial: serial, adbPath: adb)
        }
    }

    /// 태그 토글 → 재기동 대기 — 검색 디바운스와 같은 목적(0.3s)지만 조금 길다.
    /// 스트림 재기동이 버퍼 재수신을 포함하므로 "깜빡임" 이 눈에 보여야 한다
    static let tagToggleDebounce: TimeInterval = 0.6

    /// 제외 목록을 저장한다 — **안전 필터를 통과한 것만** (명령을 망가뜨리는 값이 여기서 막힌다)
    func setExcludedTags(_ tags: [String]) {
        let safe = LogcatFilter.safeTags(tags)
        UserDefaults.standard.set(safe, forKey: LogcatFilter.excludedTagsKey)
        excludedTags = safe
        tagStats.setExcluded(safe)
    }

    /// `isLive` 판정용 틱 — 시간이 지나면 스스로 갱신되어야 "정지"를 감지한다
    @Published private var tick = Date()

    /// 기동 중인 프로세스의 자리 — 종료 알림이 **이전 프로세스** 것인지 판별한다
    private let slot = LogcatProcessSlot()
    private var tickTask: Task<Void, Never>?
    /// adb 1차 필터 재기동 대기 — 입력 중 adb 를 새로 띄우지 않기 위한 디바운스
    private var searchTask: Task<Void, Never>?
    /// 태그 토글 디바운스 예약
    private var restartTask: Task<Void, Never>?
    /// 마지막으로 기동한 대상 — 태그 토글 뒤 재기동에 쓴다
    private var currentSerial: String = ""
    private var currentAdbPath: String?
    private let stderrTail = StderrTail()
    private var nextID: UInt64 = 0
    /// 링 버퍼 상한
    private let maxLines = 2000
    /// 2차 필터 메모 키 — 링이 같은 상태 + 같은 검색 조건일 때만 재계산한다
    private struct FilterKey: Equatable {
        let count: Int
        let first: UInt64?
        let last: UInt64?
        let query: String
        let caseInsensitive: Bool
    }
    private var filterCache: (key: FilterKey, value: [Line])?
    /// 이만큼 넘게 바이트가 없으면 "살아 있지만 멈춤" 으로 본다
    static let staleAfter: TimeInterval = 3
    /// 검색어 입력 → adb 재기동 대기 — 사람 속도(초당 3~5자)면 한 번만 재기동된다
    static let searchDebounce: TimeInterval = 0.3

    private init() {
        let defaults = UserDefaults.standard
        if let stored = defaults.object(forKey: LogcatFilter.excludedTagsKey) as? [String] {
            // 저장된 배열이 비어 있으면 그것이 **사용자의 선택**(아무것도 숨기지 않기)이다
            excludedTags = LogcatFilter.safeTags(stored)
        } else {
            // 마이그레이션 (PLAN_log_tag_picker §2) — 종전 Bool 키를 존중한다.
            // `false` 로 껐던 사용자는 "기본 시드도 원하지 않다" 고 말한 것이므로 빈 배열.
            let legacyOff = (defaults.object(forKey: LogcatFilter.legacyExcludeNoisyKey) as? Bool) == false
            excludedTags = legacyOff ? [] : LogcatFilter.defaultExcludedTags
            defaults.set(excludedTags, forKey: LogcatFilter.excludedTagsKey)
        }
        tagStats.setExcluded(excludedTags)
    }

    // MARK: - 상태 판정 (LIVE 표시의 정직한 정의)

    /// 프로세스도 살아 있고 데이터도 흐르는 중
    var isLive: Bool {
        guard isRunning, let at = lastDataAt else { return false }
        return Date().timeIntervalSince(at) < Self.staleAfter
    }

    /// 기동은 됐지만 아직 한 줄도 오지 않음 — 교착·오류 후보
    var isSilent: Bool { isRunning && lastDataAt == nil }

    /// 기동됐지만 데이터가 멈춤
    var isStalled: Bool {
        guard isRunning, let at = lastDataAt else { return false }
        return Date().timeIntervalSince(at) >= Self.staleAfter
    }

    /// 왜 안 나오는지 — [표시②] 실제 원인을 그대로 노출한다
    var silenceReason: String? {
        guard let s = LogcatFilter.silence(
            query: query,
            stderr: stderrTail.lastMeaningful,
            isSilent: isSilent,
            isStalled: isStalled
        ) else { return nil }
        return L10n.format(s.key, s.args)
    }

    /// 지금 adb 에 실제로 적용된 검색 패턴 — "기기 필터" 배지에 쓴다
    private(set) var appliedPattern: String?

    // MARK: - 수명 주기

    /// 스트림을 다시 띄운다
    ///
    /// - Parameter resetStats: **true 면 태그 집계를 비운다** — 창을 *연* 시점에만 true.
    ///   필터 변경(레벨·검색·제외 토글)으로 재기동할 때는 false 다.
    ///   팝오버를 열어 태그를 켜는 순간 목록이 비어버리면 **사용자는 무엇을 고르는지 볼 수 없다.**
    func start(serial: String, adbPath: String?, resetStats: Bool = false) {
        stop()
        guard let adb = adbPath, !serial.isEmpty else {
            lastError = ErrorCode.adbBinaryMissing.koMessage
            return
        }
        lastError = nil
        currentSerial = serial
        currentAdbPath = adb
        stderrTail.reset()
        lines.removeAll()
        nextID = 0
        totalLines = 0
        lastDataAt = nil
        tick = .now
        if resetStats { tagStats = LogcatFilter.TagStats() }
        tagStats.setExcluded(excludedTags)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: adb)
        // 레벨 필터를 adb 쪽에서 적용 — 이 기기는 무필터 시 초당 3만 줄이라
        // 파이프가 살아 있어도 사람이 못 본다.
        //
        // 검색도 **adb(기기) 쪽**에서 거른다. 이 기기는 초당 1.4만 줄이라 클라이언트에서만
        // 거르면 0.14초분밖에 볼 수 없다 — 볼륨 자체를 줄여야 검색이 산다.
        // Process 배열 인자라 셸 인용 위험이 없다(패턴에 공백이 있어도 한 인자로 전달된다).
        let pattern = LogcatFilter.pattern(for: query, caseInsensitive: caseInsensitive)
        appliedPattern = pattern
        // 반복 소음 태그는 **기기에서** 제외한다 (2026-09-28 실측).
        // 이 기기는 초당 1.3만 줄의 92.5% 가 `SemApTrafficData` 의 **동일한 한 줄**이었다.
        // 클라이언트에서 걸러도 파싱·디코드 비용은 이미 incurred 라 **전송량부터 줄여야 한다.**
        let tags = LogcatFilter.safeTags(excludedTags)
        appliedExcludedTags = tags
        var args = ["-s", serial, "logcat", "-v", "time"]
        args.append(contentsOf: LogcatFilter.filterSpecs(minLevel: minLevel.filterSpec, excludedTags: tags))
        if let pattern { args.append("--regex=\(pattern)") }
        proc.arguments = args
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        proc.terminationHandler = { [weak self] proc in
            let reason = Self.terminationReason(proc)
            Task { @MainActor in
                guard let self else { return }
                // 알림은 `Task { @MainActor }` 로 **나중에** 도착한다. 그 사이에 필터를 바꿔
                // 새 프로세스가 이미 자리를 잡았을 수 있다 — 이때 이전 프로세스 알림이
                // 자리를 비우면 **살아 있는 새 프로세스의 참조가 사라져** adb 가 누적된다.
                // `release` 는 내가 아직 들고 있는 그 프로세스일 때만 정리한다 (2026-09-27 실측).
                guard self.slot.release(proc) else { return }
                self.isRunning = false
                // 프로세스가 죽은 것은 실패다 — 원인을 남긴다 ([표시②])
                if proc.terminationStatus != 0 || proc.terminationReason == .uncaughtSignal {
                    self.lastError = reason
                }
            }
        }

        do {
            try proc.run()
        } catch {
            lastError = ErrorCode.adbConnectFailed.koMessage
            return
        }
        slot.adopt(proc)
        isRunning = true

        // ① stderr **배수** — 이것이 교착의 근본 해법이다. 64KB 버퍼가 차면
        //    adb 가 stdout 생산까지 멈춘다. 읽지 않으면 초록 점 + 빈 화면이 고착된다.
        let errHandle = err.fileHandleForReading
        errHandle.readabilityHandler = { [self] h in
            let data = h.availableData
            if data.isEmpty {
                h.readabilityHandler = nil
                return
            }
            stderrTail.append(String(decoding: data, as: UTF8.self))
        }

        // ② stdout 배수 — 알림 펌프 대신 전용 스레드 핸들러 (경합 없음).
        //    핸들러는 파일 핸들 전용 스레드에서 **직렬** 호출되므로 공유 버퍼가 필요 없다.
        let outHandle = out.fileHandleForReading
        outHandle.readabilityHandler = { [self] h in
            let data = h.availableData
            if data.isEmpty {
                h.readabilityHandler = nil
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            let batch = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard !batch.isEmpty else { return }
            Task { @MainActor in
                self.append(batch)
            }
        }

        // ③ 틱 — isLive/isStalled 는 시간 경과에 따라 스스로 갱신되어야 한다.
        //    값이 바뀌면 objectWillChange 가 울려 바디가 재평가되므로
        //    "3초 넘게 데이터 없음" 이 화면에도 반영된다.
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(700))
                guard let self else { return }
                self.tick = .now
            }
        }
    }

    func stop() {
        tickTask?.cancel()
        tickTask = nil
        searchTask?.cancel()
        searchTask = nil
        restartTask?.cancel()
        restartTask = nil
        if let p = slot.current, p.isRunning {
            p.terminate()
        }
        slot.adopt(nil)
        isRunning = false
        lastDataAt = nil
        appliedPattern = nil
        appliedExcludedTags = []
        filterCache = nil
    }

    /// 검색어 변경 — **로컬 필터는 즉시**(2차), **adb 재기동은 디바운스 뒤**(1차)
    ///
    /// 디바운스가 없으면 한 단어마다 adb 를 새로 띄우게 되고, 게다가 재기동 사이에는
    /// 이전 스트림이 살아 있으므로 **"일치 없음" 문구가 깜빡인다.** 기다리는 동안은
    /// 이전 스트림이 계속 채우므로 사용자는 즉시 결과를 본다.
    func searchChanged(serial: String, adbPath: String?) {
        filterCache = nil
        guard !serial.isEmpty else { return }
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(Self.searchDebounce))
            guard !Task.isCancelled else { return }
            self.searchTask = nil
            self.start(serial: serial, adbPath: adbPath)
        }
    }

    // MARK: - 내부

    /// 화면에 **보여줄** 줄 — 링 버퍼에서 검색어를 2차로 거른 것
    ///
    /// adb 필터가 아직 따라오지 않은 **디바운스 사이**에도 즉시 반응해야 하므로 로컬에서도 거른다.
    /// `body` 는 초당 수십 번 평가되므로 **여기서 다시 계산하면 안 된다** — 키가 같으면 메모를 돌려준다.
    var visibleLines: [Line] {
        let key = FilterKey(
            count: lines.count,
            first: lines.first?.id,
            last: lines.last?.id,
            query: query,
            caseInsensitive: caseInsensitive
        )
        if let cache = filterCache, cache.key == key { return cache.value }
        let value: [Line]
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            value = lines
        } else {
            value = lines.filter { LogcatFilter.matches($0.text, query: query, caseInsensitive: caseInsensitive) }
        }
        filterCache = (key, value)
        return value
    }

    private func append(_ batch: [String]) {
        var next = lines
        var stats = tagStats
        for text in batch {
            next.append(Line(id: nextID, text: text))
            nextID &+= 1
            // 태그 집계는 **들어온 모든 줄**에서 — 로컬 검색 필터보다 앞에서 센다.
            // (검색 중에도 "무엇이 시끄러운가" 는 변하지 않는다)
            if let parsed = LogcatFilter.LineParser.parse(text) {
                stats.record(parsed)
            }
        }
        if stats.entries != tagStats.entries { tagStats = stats }
        totalLines &+= batch.count
        lastDataAt = .now
        if next.count > maxLines {
            next.removeFirst(next.count - maxLines)
        }
        lines = next
    }

    /// 종료 사유 — `%@` 에 숫자를 넣으면 크래시한다 (2026-09-27 `EXC_BAD_ACCESS` 0x8ad).
    /// 키는 `%d` 다 — 기기 뽑으면 adb 가 0 으로 끝나므로 **정상 경로에서도 이 문구가 나온다.**
    nonisolated private static func terminationReason(_ proc: Process) -> String {
        let status = proc.terminationStatus
        if proc.terminationReason == .uncaughtSignal {
            return L10n.format("droid.logs.term.signal", status)
        }
        return L10n.format("droid.logs.term.exit", status)
    }
}

/// stderr 스니펫 — 교착이 원인이면 **그 원인이 stderr 에 있다.**
/// 전체를 보관하지 않고 의미 있는 마지막 줄만 유지한다 (AGENTS.local §4 [표시②]).
private final class StderrTail: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    private var latest: String?

    func append(_ text: String) {
        lock.lock()
        buffer.append(text)
        // 상한 — adb 가 폭주해도 무한히 쌓지 않는다
        if buffer.count > 8192 { buffer = String(buffer.suffix(4096)) }
        if let line = ProcessRunner.lastMeaningfulLine(buffer) { latest = line }
        lock.unlock()
    }

    var lastMeaningful: String? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    func reset() {
        lock.lock()
        buffer = ""
        latest = nil
        lock.unlock()
    }
}

/// 로그 뷰어 콘텐츠 — 시트/윈도우 공용
struct LogViewerContent: View {
    @ObservedObject private var streamer = LogcatStreamer.shared
    @ObservedObject var store: ConsoleStore
    var onClose: (() -> Void)?
    /// true: 독립 창 — 시스템 타이틀바가 제목/닫기를 담당
    var windowMode: Bool = false

    @State private var follow = true
    /// 태그 선택 팝오버 — 배지를 눌러 연다
    @State private var showingTagPicker = false

    private var serial: String { store.selectedSerial ?? "" }
    private var adbPath: String? { DeviceMonitor.adbPathNow() }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(OPColor.border)
            searchBar

            if streamer.lastError != nil || serial.isEmpty {
                notice(
                    streamer.lastError ?? L10n.string("droid.logs.noDevice"),
                    icon: "exclamationmark.triangle",
                    tint: OPColor.warn
                )
            } else if let reason = streamer.silenceReason {
                notice(reason, icon: "pause.circle", tint: OPColor.warn)
            } else if streamer.visibleLines.isEmpty {
                notice(L10n.string("droid.logs.empty"), icon: "clock", tint: OPColor.inkDim)
            } else {
                stream
            }

            Divider().overlay(OPColor.border)
            footer
        }
        .frame(minWidth: 640, minHeight: 420)
        .background(OPColor.popBG)
        .preferredColorScheme(ThemeManager.shared.mode.preferred)
        .onAppear { restart(serial) }
        .onDisappear { streamer.stop() }
    }

    private var stream: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(streamer.visibleLines) { line in
                        Text(line.text)
                            .font(OPFont.number(11))
                            .foregroundStyle(color(for: line.text))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .id(line.id)
                    }
                }
                .padding(OPSpace.sm)
            }
            .onChange(of: streamer.visibleLines.last?.id) { _, _ in
                guard follow, let last = streamer.visibleLines.last else { return }
                proxy.scrollTo(last.id, anchor: .bottom)
            }
            .onChange(of: serial) { _, s in
                restart(s)
            }
        }
    }

    private func notice(_ text: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(tint)
            Text(text)
                .font(OPFont.body(12))
                .foregroundStyle(OPColor.inkDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func restart(_ s: String) {
        guard !s.isEmpty else { streamer.stop(); return }
        // 창을 **열었을 때만** 집계를 초기화한다 (필터 변경 재기동은 유지 — PLAN_log_tag_picker §1-③)
        streamer.start(serial: s, adbPath: adbPath, resetStats: true)
    }

    // MARK: - 검색 (PLAN_log_search)

    /// 검색바 — 로컬 필터는 즉시, adb 재기동은 디바운스 뒤.
    /// "기기 필터" 배지로 **어디서 거르는지** 밝힌다: 필터 중에는 이전 구간이 되돌아오지 않는다.
    private var searchBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(OPColor.inkDim)
                TextField(L10n.string("droid.logs.search.placeholder"), text: $streamer.query)
                    .textFieldStyle(.plain)
                    .font(OPFont.body(12))
                    .foregroundStyle(OPColor.ink)
                    .onSubmit { streamer.searchChanged(serial: serial, adbPath: adbPath) }
                if !streamer.query.isEmpty {
                    Button {
                        streamer.query = ""
                        streamer.searchChanged(serial: serial, adbPath: adbPath)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(OPColor.inkDim)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.string("droid.logs.search.clear"))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(OPColor.card, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(OPColor.border, lineWidth: 1))
            .onChange(of: streamer.query) { _, _ in
                streamer.searchChanged(serial: serial, adbPath: adbPath)
            }
            .onChange(of: streamer.caseInsensitive) { _, _ in
                streamer.searchChanged(serial: serial, adbPath: adbPath)
            }

            HStack(spacing: 6) {
                ForEach(LogcatFilter.presets, id: \.self) { preset in
                    presetChip(preset)
                }
                Toggle(isOn: $streamer.caseInsensitive) {
                    Text("Aa")
                        .font(OPFont.number(11))
                }
                .toggleStyle(.checkbox)
                .help(L10n.string("droid.logs.search.ci"))
            }
        }
        .padding(.horizontal, OPSpace.md)
        .padding(.vertical, 6)
    }

    /// 프리셋 칩 — 실패 신호만 넣었다 (상태 변화 태그는 실패가 아니다 · 2026-09-27 교훈)
    private func presetChip(_ preset: String) -> some View {
        let active = streamer.query == preset
        return Button {
            streamer.query = active ? "" : preset
            streamer.searchChanged(serial: serial, adbPath: adbPath)
        } label: {
            Text(preset)
                .font(OPFont.number(10))
                .foregroundStyle(active ? OPColor.ink : OPColor.inkDim)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(OPColor.card, in: Capsule())
                .overlay(Capsule().stroke(active ? OPColor.cta : OPColor.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func color(for line: String) -> Color {
        if line.contains(" E/") || line.contains(" E ") { return OPColor.bad }
        if line.contains(" W/") || line.contains(" W ") { return OPColor.warn }
        return OPColor.inkDim
    }

    private var header: some View {
        HStack {
            if windowMode {
                if let name = store.selectedDevice?.displayName {
                    Text(name)
                        .font(OPFont.number(12))
                        .foregroundStyle(OPColor.inkDim)
                        .lineLimit(1)
                }
            } else {
                Text(L10n.format("droid.logs.title", store.selectedDevice?.displayName ?? L10n.na))
                    .font(OPFont.title(14))
                    .foregroundStyle(OPColor.ink)
                    .lineLimit(1)
            }
            Spacer()
            // LIVE 는 **데이터가 흐르는 중** 일 때만 — 프로세스 기동이 아니고
            let live = streamer.isLive
            Circle().fill(live ? OPColor.ok : (streamer.isRunning ? OPColor.warn : OPColor.inkDim))
                .frame(width: 6, height: 6)
            Text(live
                 ? L10n.string("droid.logs.live")
                 : L10n.string("droid.logs.connecting"))
                .font(OPFont.number(10))
                .foregroundStyle(live ? OPColor.ok : OPColor.inkDim)
            if streamer.totalLines > 0 {
                // 줄 수는 숫자다 — 키는 `%d`. `%@` 에 Int 를 넣으면 이 자리에서 SIGSEGV 났다
                // (2026-09-27 · `RelayConsole-2026-09-27-170630.ips` far=0x8ad=2221줄)
                Text(L10n.format("droid.logs.count", streamer.totalLines))
                    .font(OPFont.number(10))
                    .foregroundStyle(OPColor.inkDim)
            }
            // 검색 중이면 "무엇이 몇 줄 남았는지" 를 함께 보여준다 (링은 잘리므로 실측 아님)
            if !streamer.query.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(L10n.format("droid.logs.matched", streamer.visibleLines.count))
                    .font(OPFont.number(10))
                    .foregroundStyle(OPColor.cta)
            }
            if onClose != nil {
                Button(L10n.string("droid.logs.close")) { onClose?() }
                    .buttonStyle(.plain)
                    .foregroundStyle(OPColor.inkDim)
            }
        }
        .padding(OPSpace.md)
    }

    /// 링 설명 — 검색 중이면 "기기가 얼마나 걸렀다" 를 함께 밝힌다
    private var ringLabel: String {
        guard streamer.appliedPattern != nil else { return L10n.string("droid.logs.ring") }
        return L10n.format("droid.logs.ring.filtered", streamer.query)
    }

    /// 반복 소음 태그 tooltip — **제외하는 대상의 이름까지 밝힌다** (개수만 말하면 무엇이 사라졌는지 모른다)
    private var excludeTip: String {
        let base = L10n.string("droid.logs.exclude.tip")
        let tags = streamer.appliedExcludedTags
        guard !tags.isEmpty else { return base }
        return base + "  ·  " + tags.joined(separator: ", ")
    }

    private var footer: some View {        HStack(spacing: 12) {
            Button {
                if streamer.isRunning {
                    streamer.stop()
                } else {
                    restart(serial)
                }
            } label: {
                Text(streamer.isRunning
                     ? L10n.string("droid.logs.stop")
                     : L10n.string("droid.logs.start"))
                    .font(OPFont.body(11))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(OPColor.card, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(OPColor.border, lineWidth: 1))
            }
            .buttonStyle(.plain)

            // 레벨 필터 — 무필터는 초당 3만 줄이라 사람이 볼 수 없다
            Picker("", selection: $streamer.minLevel) {
                ForEach(LogcatStreamer.MinLevel.allCases) { lv in
                    Text(lv.rawValue).tag(lv)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 132)
            .onChange(of: streamer.minLevel) { _, _ in
                streamer.start(serial: serial, adbPath: adbPath)
            }

            Toggle(L10n.string("droid.logs.follow"), isOn: $follow)
                .toggleStyle(.checkbox)
                .font(OPFont.body(11))

            Spacer()
            // "어디서 거르는가" 를 숨기지 않는다 — adb 측 필터는 **기기에서** 걸러온 결과다
            // (필터 중에는 그 이전 구간이 되돌아오지 않는다)
            Text(ringLabel)
                .font(OPFont.number(10))
                .foregroundStyle(streamer.appliedPattern == nil ? OPColor.inkDim : OPColor.cta)
                .lineLimit(1)
                .truncationMode(.middle)

            // **배지를 버튼으로** — "몇 개를 뺐는가" 를 넘어 **무엇을 뺄지 고르게** 한다.
            // 제외는 기기에서 일어나므로 태그를 켜도 이 자리(배지)가 유일한 안내가 된다 [표시②]
            Button {
                showingTagPicker = true
            } label: {
                HStack(spacing: 4) {
                    Text(L10n.format("droid.logs.excluded", streamer.appliedExcludedTags.count))
                        .font(OPFont.number(10))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 7, weight: .semibold))
                }
                .foregroundStyle(streamer.appliedExcludedTags.isEmpty ? OPColor.inkDim : OPColor.cta)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(OPColor.card, in: Capsule())
                .overlay(Capsule().stroke(
                    streamer.appliedExcludedTags.isEmpty ? OPColor.border : OPColor.cta.opacity(0.5),
                    lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help(excludeTip)
            .accessibilityLabel(L10n.format("droid.logs.excluded", streamer.appliedExcludedTags.count))
            .popover(isPresented: $showingTagPicker, arrowEdge: .bottom) {
                LogTagPickerView(
                    stats: streamer.tagStats,
                    excluded: streamer.excludedTags,
                    // 재기동은 streamer 가 디바운스한다 — 여기서 부르면 팝오버가 닫힌다
                    onToggle: { streamer.toggleTag($0) },
                    onRestoreDefaults: { streamer.restoreDefaultExcludedTags() }
                )
            }
        }
        .padding(OPSpace.sm)
    }
}

/// 태그 선택 팝오버 — "이 태그를 숨겨라" 를 **사용자에게** 돌려준다
///
/// 종전에는 목록을 코드가 정했다. 계측 근거는 문서에 남겼지만 **선택은 없었고**,
/// 그만큼 [표시②] 는 AI 의 판단에 의존했다 (PLAN_log_tag_picker §0).
///
/// **제외된 태그도 목록에 남긴다** — 집계는 얼어붙은 채로 보여준다.
/// 기기에서 걸러 버린 태그는 더 이상 도착하지 않으므로, 표시하지 않으면
/// 사용자는 **자기가 뭘 숨겼는지 기억으로 되돌려야 한다.**
struct LogTagPickerView: View {
    let stats: LogcatFilter.TagStats
    let excluded: [String]
    let onToggle: (String) -> Void
    let onRestoreDefaults: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.string("droid.logs.picker.title"))
                    .font(OPFont.body(11))
                    .foregroundStyle(OPColor.ink)
                Spacer()
                // 집계의 기준을 밝힌다 — "전체" 가 아니라 **이 창을 연 뒤**다 [표시②]
                Text(L10n.string("droid.logs.picker.scope"))
                    .font(OPFont.number(9))
                    .foregroundStyle(OPColor.inkDim)
            }

            if stats.isEmpty {
                // 0건이라고 쓰지 않는다 — "아직 모른다" 와 "없다" 는 다르다
                Text(L10n.string("droid.logs.picker.empty"))
                    .font(OPFont.body(11))
                    .foregroundStyle(OPColor.inkDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(stats.snapshot(excluding: excluded), id: \.tag) { row in
                        rowView(row)
                    }
                }
                if stats.capped {
                    // 상한에 닿으면 조용히 멈추지 않는다
                    Text(L10n.format("droid.logs.picker.capped", stats.totalRecorded))
                        .font(OPFont.number(9))
                        .foregroundStyle(OPColor.warn)
                }
            }

            Divider().overlay(OPColor.border)
            HStack {
                Button(L10n.string("droid.logs.picker.restore")) { onRestoreDefaults() }
                    .buttonStyle(.plain)
                    .font(OPFont.body(10))
                    .foregroundStyle(OPColor.cta)
                Spacer()
                Text(L10n.format("droid.logs.picker.count", excluded.count))
                    .font(OPFont.number(9))
                    .foregroundStyle(OPColor.inkDim)
            }
        }
        .padding(12)
        .frame(width: 296)
        .background(OPColor.popBG)
        .preferredColorScheme(ThemeManager.shared.mode.preferred)
    }

    private func rowView(_ row: (tag: String, entry: LogcatFilter.TagStats.Entry)) -> some View {
        let isExcluded = row.entry.excluded
        return Button {
            onToggle(row.tag)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isExcluded ? "checkmark.square.fill" : "square")
                    .font(.system(size: 11))
                    .foregroundStyle(isExcluded ? OPColor.cta : OPColor.inkDim)
                Text(row.tag)
                    .font(OPFont.number(11))
                    .foregroundStyle(isExcluded ? OPColor.inkDim : OPColor.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                // 몇 종류의 메시지가 있었는지 — 반복도 판단의 근거를 사용자에게 준다
                Text(L10n.format(LogcatFilter.messageSummary(row.entry).key,
                                 LogcatFilter.messageSummary(row.entry).args))
                    .font(OPFont.number(9))
                    .foregroundStyle(OPColor.inkDim)
                Text(L10n.format(LogcatFilter.countSummary(row.entry).key,
                                 LogcatFilter.countSummary(row.entry).args))
                    .font(OPFont.number(10))
                    .foregroundStyle(OPColor.inkDim)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isExcluded
              ? (row.entry.counted
                  ? L10n.format("droid.logs.picker.row.excluded", row.entry.count)
                  : L10n.string("droid.logs.picker.row.excludedUnknown"))
              : L10n.format("droid.logs.picker.row.visible", row.entry.count))
    }
}

struct LogViewerSheet: View {
    @ObservedObject var store: ConsoleStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        LogViewerContent(store: store) { dismiss() }
    }
}

struct LogViewerWindowView: View {
    @ObservedObject var store: ConsoleStore
    var body: some View {
        LogViewerContent(store: store, windowMode: true)
            .background(WindowAccessorLogs { w in
                w.identifier = NSUserInterfaceItemIdentifier("logs")
            })
    }
}

private struct WindowAccessorLogs: NSViewRepresentable {
    var configure: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            if let w = v.window { configure(w) }
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let w = nsView.window { configure(w) }
        }
    }
}
