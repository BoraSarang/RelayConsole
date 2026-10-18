import Foundation

/// `dumpsys dropbox` 파싱·회수 선별 — 순수 (테스트 대상)
///
/// ## 왜 dropbox 인가
///
/// logcat 은 **링 버퍼**다. 폴링(5초)·상한(50KB) 사이로 밀려나면 ANR·크래시가 통째로 사라진다
/// (실측 2026-09-27: 초당 3만 줄 기기에서 500줄 ≈ 2초분).
/// dropbox 는 시스템이 남기는 **영속 큐**(기본 1000건·재부팅 생존)라
/// **로그가 롤아웃된 뒤에도 원문이 남는다.** 이 파일은 그 원문을 구조화 이벤트로 되살린다.
///
/// ## 두 가지 출력 형식 (실측 2026-10-18 · SM-A908N Android 12 / SM-S901N Android 16)
///
/// 목록 — `dumpsys dropbox`
///
/// ```
/// Drop box contents: 75 entries
/// Max entries: 1000
/// …(헤더 4줄)…
///
/// 2026-10-18 04:50:23 data_app_crash (text, 1871 bytes)
///     Process: com.borasarang.zenfreeproxy
/// ```
///
/// 33~75건 = **3.8~8KB**. 저렴해서 매 스캔에 쓴다.
///
/// 본문 — `dumpsys dropbox --print '<정확한 시각>'`
///
/// ```
/// Searching for: 2026-10-18 04:50:23
///
/// ========================================
/// 2026-10-18 04:50:23 data_app_crash (text, 1871 bytes)
/// Process: com.borasarang.zenfreeproxy
/// Package: com.borasarang.zenfreeproxy v1 (0.1.0)
/// …
/// java.util.IllegalFormatConversionException: d != java.lang.String
/// ```
///
/// **시각 인자는 "정확 일치" 필터다**(이후 시각이 아니다 — 실측: `--print '2026-10-18 00:00:00'`
/// 은 0건). 그래서 "새 항목"을 찾으려면 목록을 먼저 읽고 시각별로 본문을 받아야 한다.
///
/// **시각은 반드시 `'…'` 로 인용한다** — `adb shell` 은 argv 를 공백으로 이어 붙여
/// 기기 셸에 넘기므로, 인용하지 않으면 `2026-10-18` 과 `04:50:23` 이 **두 인자로 쪼개진다**
/// (폰 찾기에서 배운 함정과 동일 — `AdbClient.shellQuoted`).
enum DropboxLogLogic {
    /// 목록 한 줄 — 시각·태그·크기
    struct Entry: Equatable, Sendable {
        /// `2026-10-18 04:50:23` — **기기 로컬 시각**. 같은 형식이라 문자열 비교 = 시간 비교
        let stamp: String
        let tag: String
        let bytes: Int
    }

    /// `--print` 블록 하나 — 헤더(시각·태그) + 본문
    struct Block: Equatable, Sendable {
        let stamp: String
        let tag: String
        let body: String
    }

    /// 회수 계획 — 발행할 시각(최신 우선)과 다음 기준선
    struct RecoveryPlan: Equatable, Sendable {
        let stamps: [String]
        let watermark: String?
    }

    /// `yyyy-MM-dd HH:mm:ss` 길이
    static let stampLength = 19
    static let stampFormat = "yyyy-MM-dd HH:mm:ss"

    /// 본문 상한 (bytes)
    ///
    /// ANR 트레이스는 수십~수백 KB 다. **앞을 남긴다** — `Process`·`Package`·`Subject`·
    /// 트레이스 머리가 전부 앞에 있다. (logcat 덤프가 `-T <이벤트 시각>` 이라 **뒤를 남기는** 것과
    /// 반대 방향인 이유: 거기는 끝이 사건에 가깝고, 여기는 머리가 사건의 정체다)
    static let printMaxBytes = 200_000

    /// 스캔 1회당 발행할 최대 항목 — 폭주 방지 (WatchEngine 이 다시 5분 쿨다운을 건다)
    static let recoveryLimit = 3

    // MARK: - 시각

    static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = stampFormat
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    static func date(fromStamp stamp: String) -> Date? {
        stampFormatter.date(from: stamp)
    }

    static func stamp(from date: Date) -> String {
        stampFormatter.string(from: date)
    }

    /// `2026-10-18 04:50:23` 형식인가 — 헤더·미리보기 줄을 걸러내는 1차 관문
    static func isValidStamp(_ s: String) -> Bool {
        let chars = Array(s)
        guard chars.count == stampLength else { return false }
        func digit(_ i: Int) -> Bool { chars[i] >= "0" && chars[i] <= "9" }
        return digit(0) && digit(1) && digit(2) && digit(3)
            && chars[4] == "-" && digit(5) && digit(6)
            && chars[7] == "-" && digit(8) && digit(9)
            && chars[10] == " " && digit(11) && digit(12)
            && chars[13] == ":" && digit(14) && digit(15)
            && chars[16] == ":" && digit(17) && digit(18)
    }

    // MARK: - 파싱

    /// 목록 파싱 — 헤더 4줄과 들여쓴 미리보기 줄은 버린다
    static func parseList(_ text: String) -> [Entry] {
        var out: [Entry] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let entry = parseHeaderLine(String(raw)) else { continue }
            out.append(entry)
        }
        return out
    }

    /// `2026-10-18 04:50:23 data_app_crash (text, 1871 bytes)` → (시각, 태그, 바이트)
    ///
    /// 미리보기 줄(`    Process: com.foo`)은 시각으로 시작하지 않으므로 자연히 탈락한다.
    static func parseHeaderLine(_ line: String) -> Entry? {
        let s = line.trimmingCharacters(in: .whitespaces)
        guard s.count > stampLength else { return nil }
        let head = String(s.prefix(stampLength))
        guard isValidStamp(head) else { return nil }
        let rest = s.dropFirst(stampLength).trimmingCharacters(in: .whitespaces)
        guard let open = rest.range(of: " ("),
              let close = rest.range(of: " bytes)")
        else { return nil }
        let tag = String(rest[rest.startIndex..<open.lowerBound])
        guard !tag.isEmpty else { return nil }
        let sizePart = rest[rest.index(after: open.lowerBound)..<close.lowerBound]
        let digits = String(sizePart.reversed().prefix { $0 >= "0" && $0 <= "9" }.reversed())
        guard let bytes = Int(digits) else { return nil }
        return Entry(stamp: head, tag: tag, bytes: bytes)
    }

    /// `--print` 파싱 — `====` 구분선 단위로 블록을 나눈다
    ///
    /// 구분선 이전(헤더·`Searching for:`)은 블록이 아니므로 버린다.
    /// 구분선이 없는 출력(단일 항목을 그대로 붙여넣은 경우)도 헤더 줄에서 블록을 연다.
    static func parseBlocks(_ text: String) -> [Block] {
        var out: [Block] = []
        var current: Entry?
        var body: [String] = []
        func flush() {
            if let c = current {
                out.append(Block(stamp: c.stamp, tag: c.tag, body: body.joined(separator: "\n")))
            }
            current = nil
            body = []
        }
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("====") { flush(); continue }
            if let meta = parseHeaderLine(line) {
                if current != nil { flush() }
                current = meta
                continue
            }
            if current != nil { body.append(line) }
        }
        flush()
        return out
    }

    // MARK: - 태그 해석

    /// 회수 대상 태그인가 — `data_app_anr`·`system_app_anr`·`<pkg>.anr` 계열
    ///
    /// 범위 밖(의도적): `SYSTEM_TOMBSTONE`(네이티브), `data_app_wtf`·`storage_trim` 등 잡음 태그.
    static func kind(forTag tag: String) -> WatchKind? {
        let t = tag.lowercased()
        if t.hasSuffix("_anr") || t.hasSuffix(".anr") { return .anr }
        if t.hasSuffix("_crash") || t.hasSuffix(".crash") { return .crash }
        return nil
    }

    static func kindMatches(_ tag: String, kind: WatchKind) -> Bool {
        DropboxLogLogic.kind(forTag: tag) == kind
    }

    /// 태그에서 패키지명 — 레거시 `<pkg>.crash`·`<pkg>@123.anr` 형식만
    /// (`data_app_anr` 은 패키지명이 아니라 종류 이름이다)
    static func packageName(forTag tag: String) -> String? {
        let t = tag.lowercased()
        guard let kind = kind(forTag: t) else { return nil }
        let suffix = ".\(kind.rawValue)"
        guard t.hasSuffix(suffix) else { return nil }
        var name = String(t.dropLast(suffix.count))
        if let at = name.firstIndex(of: "@") { name = String(name[..<at]) }
        return name.contains(".") ? name : nil
    }

    /// 본문에서 `Package: com.foo v1 (0.1.0)` → `com.foo`, 없으면 `Process: com.foo`
    static func packageName(inBlock body: String) -> String? {
        let lines = body.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        for prefix in ["Package: ", "Process: "] {
            guard let hit = lines.first(where: { $0.hasPrefix(prefix) }) else { continue }
            let value = String(hit.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            let token = value.split(separator: " ").first.map(String.init) ?? value
            if token.contains(".") { return token }
        }
        return nil
    }

    /// 본문에서 사유 — ANR 은 `Subject:`, 크래시는 메타 블록 뒤 첫 줄(예외 머리)
    static func reason(inBlock body: String) -> String? {
        let lines = body
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if let subject = lines.first(where: { $0.hasPrefix("Subject: ") }) {
            return trim(String(subject.dropFirst("Subject: ".count)))
        }
        var i = 0
        while i < lines.count, lines[i].isEmpty { i += 1 }
        while i < lines.count, isMetaLine(lines[i]) { i += 1 }
        while i < lines.count, lines[i].isEmpty { i += 1 }
        guard i < lines.count else { return nil }
        return trim(lines[i])
    }

    /// `Process: com.foo`·`Loading-Progress: 1.0` 같은 메타 줄 (`Key: value`)
    static func isMetaLine(_ s: String) -> Bool {
        guard let colon = s.firstIndex(of: ":") else { return false }
        let key = s[s.startIndex..<colon]
        guard !key.isEmpty, key.count <= 24 else { return false }
        guard key.allSatisfy({ $0.isLetter || $0 == "-" || $0 == "_" }) else { return false }
        let after = s[s.index(after: colon)...]
        return after.hasPrefix(" ")
    }

    static func trim(_ s: String, limit: Int = 200) -> String {
        s.count <= limit ? s : String(s.prefix(limit)) + "…"
    }

    // MARK: - 회수 선별

    /// 새로 생긴 ANR/크래시 항목 선별 — **첫 스캔은 기준선만 잡고 발행하지 않는다**
    ///
    /// 첫 스캔에서 발행하면 dropbox 에 남아 있던 과거 전건이 쏟아진다(기본 1000건).
    /// 기준선은 **해당 태그 항목의 최신 시각**이라, 잡음 태그가 쌓여도 밀리지 않는다.
    static func recoveryPlan(
        entries: [Entry],
        since: String?,
        limit: Int = recoveryLimit
    ) -> RecoveryPlan {
        let matching = entries.filter { kind(forTag: $0.tag) != nil }
        guard let newest = matching.map(\.stamp).max() else {
            return RecoveryPlan(stamps: [], watermark: since)
        }
        guard let since else {
            return RecoveryPlan(stamps: [], watermark: newest)
        }
        // 같은 초에 두 항목이 있을 수 있다 — 시각 단위로 묶어 1회 본문 조회로 처리한다
        let fresh = Set(matching.filter { $0.stamp > since }.map(\.stamp))
        let stamps = Array(fresh.sorted(by: >).prefix(max(0, limit)))
        return RecoveryPlan(stamps: stamps, watermark: max(newest, since))
    }

    /// 번들 첨부용 선별 — 이벤트 시각 앞뒤 창에 든 같은 종류 항목 (최신 우선)
    static func selectEntries(
        _ entries: [Entry],
        kind: WatchKind,
        eventAt: Date,
        lead: TimeInterval = 600,
        trail: TimeInterval = 300,
        limit: Int = 2
    ) -> [Entry] {
        entries
            .filter { entry in
                guard kindMatches(entry.tag, kind: kind) else { return false }
                guard let at = date(fromStamp: entry.stamp) else { return false }
                let delta = at.timeIntervalSince(eventAt)
                return delta >= -lead && delta <= trail
            }
            .sorted { $0.stamp > $1.stamp }
            .prefix(max(0, limit))
            .map { $0 }
    }

    /// 번들에 넣을 dropbox 원문 — 같은 종류 블록만 남긴다 (없으면 nil = 첨부 생략)
    static func captureText(blocks: [Block], kind: WatchKind) -> String? {
        let picked = blocks.filter { kindMatches($0.tag, kind: kind) }
        guard !picked.isEmpty else { return nil }
        var out = ["===== RelayConsole: dumpsys dropbox 발췌 \(picked.count)건 (logcat 롤아웃 보강) ====="]
        for block in picked {
            out.append("===== \(block.stamp) \(block.tag) =====")
            out.append(block.body.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return out.joined(separator: "\n") + "\n"
    }

    /// 본문 조회 커맨드 — 시각 인용 필수 + 앞부분만 보존
    static func dropboxPrintCommand(stamp: String, maxBytes: Int = printMaxBytes) -> String {
        "dumpsys dropbox --print \(AdbClient.shellQuoted(stamp)) 2>/dev/null | head -c \(maxBytes)"
    }

    /// 목록 조회 커맨드 — 전건 본문(`--print` 단독)보다 훨씬 싸다
    static let dropboxListCommand = "dumpsys dropbox"
}
