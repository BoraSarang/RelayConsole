import Foundation

// MARK: - Sites (업타임)

enum SiteProbe: String, Codable, Sendable, CaseIterable {
    case http
    case tcp
    case ping
}

/// 개별 체크 결과 (히스토리 1건)
struct SiteCheck: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let at: Date
    let ok: Bool
    /// 응답/RTT ms — ping fail 등은 nil
    var latencyMs: Int?
    /// 오류 한 줄 (URL 마스킹 후)
    var detail: String?
    /// HTTPS 인증서 만료일 (A5 — 해당 체크에서 수집 시)
    var sslExpiresAt: Date?

    init(
        id: UUID = UUID(),
        at: Date = .now,
        ok: Bool,
        latencyMs: Int? = nil,
        detail: String? = nil,
        sslExpiresAt: Date? = nil
    ) {
        self.id = id
        self.at = at
        self.ok = ok
        self.latencyMs = latencyMs
        self.detail = detail
        self.sslExpiresAt = sslExpiresAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, at, ok, latencyMs, detail, sslExpiresAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        at = try c.decode(Date.self, forKey: .at)
        ok = try c.decode(Bool.self, forKey: .ok)
        latencyMs = try c.decodeIfPresent(Int.self, forKey: .latencyMs)
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
        sslExpiresAt = try c.decodeIfPresent(Date.self, forKey: .sslExpiresAt)
    }
}

/// 외부 서비스 업타임 모니터 대상
struct Site: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    var name: String
    /// URL(http) | host:port(tcp) | host(ping)
    var target: String
    var probe: SiteProbe
    var intervalSec: Int
    var enabled: Bool
    /// 연속 실패 N회째에만 down (UptimeRobot delay 유사) — 1...5, 기본 2
    var failThreshold: Int
    /// HTTPS 인증서 만료일 (최근 체크 갱신 · A5)
    var sslExpiresAt: Date?
    /// HTTP 본문 assertion — body에 포함해야 ok (nil = 검사 안 함)
    var assertBody: String?
    /// 최근 체크 (최신 last) — 90일 / 300건 cap
    var history: [SiteCheck]
    /// 그룹/태그 (A6) — 공백·쉼표 없이 소문자 키로 정규화하지 않고 원문 유지
    var tags: [String]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        target: String,
        probe: SiteProbe,
        intervalSec: Int = 60,
        enabled: Bool = true,
        failThreshold: Int = 2,
        sslExpiresAt: Date? = nil,
        assertBody: String? = nil,
        history: [SiteCheck] = [],
        tags: [String] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.target = target
        self.probe = probe
        self.intervalSec = max(10, intervalSec)
        self.enabled = enabled
        self.failThreshold = min(5, max(1, failThreshold))
        self.sslExpiresAt = sslExpiresAt
        self.assertBody = assertBody
        self.history = history
        self.tags = tags
        self.createdAt = createdAt
    }

    /// 하위호환: failThreshold·sslExpiresAt·assertBody·tags 키 없던 기존 JSON → 기본
    private enum CodingKeys: String, CodingKey {
        case id, name, target, probe, intervalSec, enabled, failThreshold, sslExpiresAt, assertBody, history, tags, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        target = try c.decode(String.self, forKey: .target)
        probe = try c.decode(SiteProbe.self, forKey: .probe)
        intervalSec = try c.decode(Int.self, forKey: .intervalSec)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        failThreshold = min(5, max(1, try c.decodeIfPresent(Int.self, forKey: .failThreshold) ?? 2))
        sslExpiresAt = try c.decodeIfPresent(Date.self, forKey: .sslExpiresAt)
        assertBody = try c.decodeIfPresent(String.self, forKey: .assertBody)
        history = try c.decode([SiteCheck].self, forKey: .history)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }

    /// Alerts serial 그룹 키
    var serialKey: String { "site:\(id.uuidString)" }

    /// raw 최신 체크 기준 up — 이력 없으면 nil (기존 API 유지)
    func isUp() -> Bool? {
        history.last?.ok
    }

    /// 임계값 적용 현재 상태 — 연속 fail ≥ failThreshold 전까지 up
    func effectiveUp() -> Bool? {
        guard !history.isEmpty else { return nil }
        var consecutiveFails = 0
        for check in history.reversed() {
            if check.ok { return true }
            consecutiveFails += 1
            if consecutiveFails >= failThreshold { return false }
        }
        // 실패했으나 임계 미달 → 아직 up (flapping 보호)
        return true
    }

    /// 현재 effective 상태가 시작된 시각 — nil = 이력 없음
    func stateSince() -> Date? {
        guard !history.isEmpty else { return nil }
        var fails = 0
        var state: Bool?
        var stateStart: Date?
        for check in history {
            if check.ok {
                fails = 0
                if state != true {
                    state = true
                    stateStart = check.at
                }
            } else {
                fails += 1
                if fails >= failThreshold, state != false {
                    state = false
                    stateStart = check.at
                }
            }
        }
        return stateStart
    }

    /// 창 가동률 % (0...100) — 체크 0건이면 nil
    func uptimePercent(since: Date) -> Double? {
        let checks = history.filter { $0.at >= since }
        guard !checks.isEmpty else { return nil }
        let ok = checks.filter(\.ok).count
        return Double(ok) / Double(checks.count) * 100
    }

    /// 일 단위 집계 (과거 → 최신) — Google식 행 바
    func dayBars(days: Int, now: Date = .now, calendar: Calendar = .current) -> [(date: Date, status: DayBarStatus)] {
        let startOfToday = calendar.startOfDay(for: now)
        var result: [(date: Date, status: DayBarStatus)] = []
        result.reserveCapacity(days)
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let dayStart = calendar.date(byAdding: .day, value: -offset, to: startOfToday),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
            else { continue }
            let checks = history.filter { $0.at >= dayStart && $0.at < dayEnd }
            let status: DayBarStatus
            if checks.isEmpty {
                status = .unknown
            } else {
                let okCount = checks.filter(\.ok).count
                if okCount == checks.count {
                    status = .up
                } else if okCount == 0 {
                    status = .down
                } else {
                    status = .partial
                }
            }
            result.append((dayStart, status))
        }
        return result
    }

    /// 체크 결과 append + cap (300건 / 90일)
    mutating func appendCheck(_ check: SiteCheck, now: Date = .now) {
        history.append(check)
        let cutoff = now.addingTimeInterval(-90 * 86400)
        history.removeAll { $0.at < cutoff }
        if history.count > 300 {
            history.removeFirst(history.count - 300)
        }
    }

    /// 상태 바용 최근 N건 ok 플래그 (최신 → 과거)
    func recentBars(limit: Int = 90) -> [Bool] {
        Array(history.suffix(limit).reversed().map(\.ok))
    }

    /// 스파크라인용 latency samples (ok only, 과거→최신)
    func latencySpark(limit: Int = 60) -> [Int] {
        history.suffix(limit).compactMap { $0.ok ? $0.latencyMs : nil }
    }
}

// MARK: - Jobs (하트비트)

/// 크론/스크립트 하트비트 수신 대상
struct Job: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    var name: String
    /// 하트비트 경로 토큰 (UUID 앞 8)
    var token: String
    /// 예정 주기 (초) — 기본 1시간
    var expectEverySec: Int
    var lastBeatAt: Date?
    var lastBeatOk: Bool?
    var enabled: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        token: String = String(UUID().uuidString.prefix(8)).lowercased(),
        expectEverySec: Int = 3600,
        lastBeatAt: Date? = nil,
        lastBeatOk: Bool? = nil,
        enabled: Bool = true,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.token = token
        self.expectEverySec = max(30, expectEverySec)
        self.lastBeatAt = lastBeatAt
        self.lastBeatOk = lastBeatOk
        self.enabled = enabled
        self.createdAt = createdAt
    }

    /// Alerts serial 그룹 키
    var serialKey: String { "job:\(id.uuidString)" }

    /// overdue: 미수신 또는 expectEverySec × 1.5 초과
    /// grace 미만이면 nil(판정 유보 — 방금 시작/주기 미도래)
    func isOverdue(now: Date = .now) -> Bool? {
        guard enabled else { return false }
        guard let last = lastBeatAt else {
            // 미수신: 생성 후 grace(=expect) 동안은 유보
            return now.timeIntervalSince(createdAt) > TimeInterval(expectEverySec) ? true : nil
        }
        let elapsed = now.timeIntervalSince(last)
        if elapsed > TimeInterval(expectEverySec) * 1.5 { return true }
        if elapsed <= TimeInterval(expectEverySec) { return false }
        return nil
    }

    /// 하트비트 수신 반영
    mutating func beat(at: Date = .now, ok: Bool = true) {
        lastBeatAt = at
        lastBeatOk = ok
    }
}

// MARK: - 순수 연산 (테스트)

enum SitesJobsLogic {
    /// URL에서 쿼리·유저정보 제거 (간단 마스킹 — 시크릿 쿼리스트링 제거)
    static func sanitizeTarget(_ raw: String, probe: SiteProbe) -> String {
        switch probe {
        case .http:
            guard var c = URLComponents(string: raw) else { return raw }
            c.user = nil
            c.password = nil
            c.query = nil
            c.fragment = nil
            return c.string ?? raw
        case .tcp, .ping:
            return raw
        }
    }

    /// 대상 형식 검증 — nil이면 유효, 아니면 i18n 키
    static func validateTarget(_ raw: String, probe: SiteProbe) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "sites.error.target.empty" }
        switch probe {
        case .http:
            guard let u = URL(string: t),
                  let scheme = u.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  let host = u.host, !host.isEmpty
            else { return "sites.error.target.http" }
            return nil
        case .tcp:
            guard !t.contains(" "), !t.contains(";") else { return "sites.error.target.tcp" }
            if t.contains(":") {
                guard let (host, port) = strictHostPort(t), !host.isEmpty, (1...65535).contains(port) else {
                    return "sites.error.target.tcp"
                }
            }
            return nil
        case .ping:
            guard !t.contains(" "), !t.contains(";"), !t.hasPrefix("-") else {
                return "sites.error.target.ping"
            }
            return nil
        }
    }

    /// host:port 엄격 파싱 (숫자 포트 없으면 실패)
    static func strictHostPort(_ target: String) -> (String, Int)? {
        let t = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if t.hasPrefix("["), let close = t.firstIndex(of: "]") {
            let host = String(t[t.index(after: t.startIndex)..<close])
            let rest = t[t.index(after: close)...]
            guard rest.hasPrefix(":"), let p = Int(rest.dropFirst()), (1...65535).contains(p) else { return nil }
            return (host, p)
        }
        let parts = t.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, let p = Int(parts[1]), (1...65535).contains(p) else {
            return nil
        }
        return (String(parts[0]), p)
    }

    /// 붙여넣은 curl/텍스트에서 하트비트 토큰 추출 (/hb/{token})
    static func token(fromCurl text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: #"/hb/([A-Za-z0-9_-]+)"#) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = re.firstMatch(in: text, range: range),
              let r = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[r])
    }

    /// 체크 오류 한 줄 (요약)
    static func summarize(error: Error?, httpStatus: Int? = nil) -> String {
        if let code = httpStatus {
            return "HTTP \(code)"
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return "timeout"
            case .cannotFindHost, .dnsLookupFailed: return "dns"
            case .cannotConnectToHost, .networkConnectionLost: return "connect"
            case .notConnectedToInternet: return "offline"
            default: return urlError.code.rawValue.description
            }
        }
        return error?.localizedDescription ?? "unknown"
    }

    /// 토큰 경로 매칭: /hb/{token}
    static func token(fromPath path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[parts.count - 2] == "hb" else { return nil }
        return parts.last
    }

    /// 사이트 down 전이 감지 — before nil(첫 체크)은 전이 아님 · after는 effectiveUp()
    static func siteTransition(before: Bool?, after: Bool?) -> SiteTransition? {
        guard let before, let after else { return nil }
        if before, !after { return .down }
        if !before, after { return .up }
        return nil
    }

    /// Job overdue 전이
    static func jobTransition(before: Bool?, after: Bool?) -> JobTransition? {
        // nil = 유보 — 전이 없음
        guard let after else { return nil }
        guard let before else {
            // 첫 판정이 true면 overdue 진입
            return after ? .overdue : nil
        }
        if !before, after { return .overdue }
        if before, !after { return .recovered }
        return nil
    }
}

enum SiteTransition: Equatable, Sendable {
    case down
    case up
}

/// 일 단위 업타임 상태 (Google식 세그먼트)
enum DayBarStatus: Equatable, Sendable {
    case unknown
    case up
    case down
    case partial
}

enum JobTransition: Equatable, Sendable {
    case overdue
    case recovered
}

// MARK: - 태그 · 캘린더 (A6)

enum SitesCalendarLogic {
    static let calendarDays = 90

    /// `"api, prod, API"` → `["api", "prod"]` (소문자·중복 제거·빈 토큰 제외)
    static func parseTags(_ raw: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for part in raw.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" || $0 == "\t" }) {
            let t = part.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !t.isEmpty, !seen.contains(t) else { continue }
            seen.insert(t)
            out.append(t)
        }
        return out
    }

    static func formatTags(_ tags: [String]) -> String {
        tags.joined(separator: ", ")
    }

    /// 전체 사이트 태그 유니온 — 알파벳 정렬
    static func allTags(_ sites: [Site]) -> [String] {
        var seen = Set<String>()
        for s in sites {
            for t in s.tags { seen.insert(t) }
        }
        return seen.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// 선택 태그 AND 필터 — 빈 집합 = 전체
    static func filter(_ sites: [Site], selectedTags: Set<String>) -> [Site] {
        guard !selectedTags.isEmpty else { return sites }
        return sites.filter { site in
            let have = Set(site.tags)
            return selectedTags.isSubset(of: have)
        }
    }

    /// 90일 주 단위 격자용 날짜 (과거→오늘, startOfDay)
    static func calendarDays(
        days: Int = SitesCalendarLogic.calendarDays,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Date] {
        let startOfToday = calendar.startOfDay(for: now)
        var out: [Date] = []
        out.reserveCapacity(days)
        for offset in stride(from: days - 1, through: 0, by: -1) {
            if let d = calendar.date(byAdding: .day, value: -offset, to: startOfToday) {
                out.append(d)
            }
        }
        return out
    }

    /// 주 첫날 보정 패딩 (선행 빈 셀 수) — Locale startOfWeek
    static func leadingPad(now: Date = .now, calendar: Calendar = .current) -> Int {
        let startOfToday = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: startOfToday)
        let first = calendar.firstWeekday
        return (weekday - first + 7) % 7
    }

    /// 헤더 요일 7글자 (Locale)
    static func weekdayHeaders(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        guard (0..<7).contains(first) else { return symbols }
        return Array(symbols[first...] + symbols[..<first])
    }

    /// 사이트 dayBars → 단일 날짜 상태 합산 (하나라도 down → down)
    static func combinedStatus(site: Site, day: Date, calendar: Calendar = .current) -> DayBarStatus {
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) else { return .unknown }
        let checks = site.history.filter { $0.at >= day && $0.at < dayEnd }
        guard !checks.isEmpty else { return .unknown }
        let okCount = checks.filter(\.ok).count
        if okCount == checks.count { return .up }
        if okCount == 0 { return .down }
        return .partial
    }

    /// 여러 사이트 셀 합산 — down > partial > up > unknown
    static func aggregate(_ statuses: [DayBarStatus]) -> DayBarStatus {
        if statuses.isEmpty { return .unknown }
        if statuses.contains(.down) { return .down }
        if statuses.contains(.partial) { return .partial }
        if statuses.allSatisfy({ $0 == .up }) { return .up }
        if statuses.contains(.up) {
            return statuses.contains(.unknown) ? .partial : .up
        }
        return .unknown
    }
}

// MARK: - SSL · assertion (A5)

enum SslAssertLogic {
    /// 만료까지 남은 일수 — nil = 만료일 없음 · 음수 = 만료됨
    static func daysRemaining(expiresAt: Date?, now: Date = .now) -> Int? {
        guard let expiresAt else { return nil }
        let cal = Calendar.current
        let from = cal.startOfDay(for: now)
        let to = cal.startOfDay(for: expiresAt)
        return cal.dateComponents([.day], from: from, to: to).day
    }

    /// warnDays 이하(음수 포함)면 경고
    static func sslShouldWarn(expiresAt: Date?, now: Date = .now, warnDays: Int) -> Bool {
        guard let d = daysRemaining(expiresAt: expiresAt, now: now) else { return false }
        return d <= max(0, warnDays)
    }

    /// HTTP 본문 assertion — expected nil이면 항상 통과
    static func assertBody(_ body: String, expected: String?) -> Bool {
        guard let expected, !expected.isEmpty else { return true }
        return body.contains(expected)
    }

    /// D-day 라벨용 — nil = 표시 안 함
    static func sslBadge(days: Int?) -> String? {
        guard let days else { return nil }
        if days < 0 { return "SSL ✕" }
        return "SSL D-\(days)"
    }
}
