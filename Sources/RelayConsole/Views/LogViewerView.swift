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
    ///
    /// 로그 창을 열면 **CPU 102%** 로 올라간다(부하가 100배 변하므로 "40%" 라는 수치는 믿지 않는다).
    /// 1종류 메시지를 초당 1.3만 번 파싱·렌더하는 것이 비용의 대부분이다.
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
    static let noisyTags: [String] = ["SemApTrafficData", "HeatmapThread"]

    /// 제외 토글 저장 키 — 기본 ON
    static let excludeNoisyKey = "relay.logs.excludeNoisyTags"

    /// 제외 태그 목록이 adb 인자로 안전하게 변환되는지 — **명령을 망가뜨릴 값은 조용히 버린다.**
    ///
    /// 두 가지 실수를 막는다:
    /// - `*` 를 넣으면 **모든 로그가 사라진다**(전부 조용히 — [표시②] 위반)
    /// - 공백·`:` 등이 섞이면 필터식이 깨진다
    ///
    /// 비-ASCII 태그도 여기서 떨어진다. 필터식 문법은 ASCII 를 전제로 하고,
    /// **제외가 안 되는 것(효과 없음)보다 명령이 깨지는 것(전부 안 보임)이 나쁘다.**
    /// 그러므로 이 함수는 "안전한 것만 남긴다" 로 정의한다.
    static func safeTags(_ tags: [String]) -> [String] {
        let asciiTag = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_")
        var out: [String] = []
        for tag in tags {
            let t = tag.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, t != "*" else { continue }
            guard t.unicodeScalars.allSatisfy({ asciiTag.contains($0) }) else { continue }
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
    /// 반복 소음 태그를 **기기에서** 제외 — 기본 ON (`E` 레벨 줄을 감추므로 배지로 항상 밝힌다)
    ///
    /// `bool(forKey:)` 로 읽으면 **저장 전 값이 false** 가 되어 기본 ON 이 깨진다.
    /// `WifiAdbLogic.autoModeKey` 와 같은 이유로 `object(forKey:)` + `?? true` 로 읽는다.
    @Published var excludeNoisyTags: Bool {
        didSet { UserDefaults.standard.set(excludeNoisyTags, forKey: LogcatFilter.excludeNoisyKey) }
    }

    /// 지금 adb 에 실제로 적용된 제외 태그 — 배지와 tooltip 의 진실원천
    @Published private(set) var appliedExcludedTags: [String] = []

    /// `isLive` 판정용 틱 — 시간이 지나면 스스로 갱신되어야 "정지"를 감지한다
    @Published private var tick = Date()

    /// 기동 중인 프로세스의 자리 — 종료 알림이 **이전 프로세스** 것인지 판별한다
    private let slot = LogcatProcessSlot()
    private var tickTask: Task<Void, Never>?
    /// adb 1차 필터 재기동 대기 — 입력 중 adb 를 새로 띄우지 않기 위한 디바운스
    private var searchTask: Task<Void, Never>?
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
        excludeNoisyTags = UserDefaults.standard.object(forKey: LogcatFilter.excludeNoisyKey) as? Bool ?? true
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

    func start(serial: String, adbPath: String?) {
        stop()
        guard let adb = adbPath, !serial.isEmpty else {
            lastError = ErrorCode.adbBinaryMissing.koMessage
            return
        }
        lastError = nil
        stderrTail.reset()
        lines.removeAll()
        nextID = 0
        totalLines = 0
        lastDataAt = nil
        tick = .now

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
        let tags = excludeNoisyTags ? LogcatFilter.noisyTags : []
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
        for text in batch {
            next.append(Line(id: nextID, text: text))
            nextID &+= 1
        }
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
        streamer.start(serial: s, adbPath: adbPath)
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

            // 소음 태그 제외 — `E` 레벨 줄을 기기에서 거르므로 **무엇이 걸렸는지 반드시 밝힌다** [표시②]
            // 이 기기는 `SemApTrafficData` 의 동일 줄이 초당 1.3만 회 → 로그 창 CPU 102%
            Toggle(L10n.string("droid.logs.exclude"), isOn: $streamer.excludeNoisyTags)
                .toggleStyle(.checkbox)
                .font(OPFont.body(11))
                .help(excludeTip)
                .onChange(of: streamer.excludeNoisyTags) { _, _ in
                    streamer.start(serial: serial, adbPath: adbPath)
                }

            Spacer()
            // "어디서 거르는가" 를 숨기지 않는다 — adb 측 필터는 **기기에서** 걸러온 결과다
            // (필터 중에는 그 이전 구간이 되돌아오지 않는다)
            Text(ringLabel)
                .font(OPFont.number(10))
                .foregroundStyle(streamer.appliedPattern == nil ? OPColor.inkDim : OPColor.cta)
                .lineLimit(1)
                .truncationMode(.middle)
            // 제외가 걸리고 있으면 **몇 개를 기기에서 뺐는지** — 개수만 말해도 "아무것도 안 보였구나" 와
            // "기기에서 걸렸다" 를 구분된다. 끈 상태(0개)에서는 배지를 내보내지 않는다 = 아무것도 안 숨겼다
            if !streamer.appliedExcludedTags.isEmpty {
                Text(L10n.format("droid.logs.excluded", streamer.appliedExcludedTags.count))
                    .font(OPFont.number(10))
                    .foregroundStyle(OPColor.cta)
                    .lineLimit(1)
                    .fixedSize()          // 옆 라벨이 줄어들어도 배지는 잘리지 않는다
                    .help(excludeTip)
            }
        }
        .padding(OPSpace.sm)
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
