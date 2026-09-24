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

    init(
        id: UUID = UUID(),
        at: Date = .now,
        ok: Bool,
        latencyMs: Int? = nil,
        detail: String? = nil
    ) {
        self.id = id
        self.at = at
        self.ok = ok
        self.latencyMs = latencyMs
        self.detail = detail
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
    /// 최근 체크 (최신 last) — 90일 / 300건 cap
    var history: [SiteCheck]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        target: String,
        probe: SiteProbe,
        intervalSec: Int = 60,
        enabled: Bool = true,
        history: [SiteCheck] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.target = target
        self.probe = probe
        self.intervalSec = max(10, intervalSec)
        self.enabled = enabled
        self.history = history
        self.createdAt = createdAt
    }

    /// Alerts serial 그룹 키
    var serialKey: String { "site:\(id.uuidString)" }

    /// 최신 유효 체크 기준 up 여부 — 이력 없으면 nil(모름)
    func isUp() -> Bool? {
        history.last?.ok
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

    /// 사이트 down 전이 감지 — before nil(첫 체크)은 전이 아님
    static func siteTransition(before: Bool?, after: Bool) -> SiteTransition? {
        guard let before else { return nil }
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

enum JobTransition: Equatable, Sendable {
    case overdue
    case recovered
}
