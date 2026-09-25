import Foundation

/// 감시 이벤트 종류 — kind는 소수 유지, 중복은 fingerprint로
enum WatchKind: String, Sendable, Equatable, CaseIterable, Codable {
    case throttling
    case chargeChanged
    case protectionChanged
    case lowPowerChanged
    case batteryThreshold
    case psiPressure
    case loadSpike
    case memoryLow
    case bsohDrop
    case signalDrop
    case anr
    case crash
    /// Apple 기기 연결 (PLAN_alerts)
    case appleConnected
    /// Apple 기기 해제
    case appleDisconnected
    /// Android USB/network 연결
    case androidConnected
    /// Android 연결 해제
    case androidDisconnected
    /// 사이트 다운 (PLAN_sites_jobs)
    case siteDown
    /// 사이트 복구
    case siteUp
    /// 작업 하트비트 overdue
    case jobOverdue
    /// 작업 하트비트 복구
    case jobRecovered
    /// HTTPS 인증서 만료 임박 (A5)
    case sslExpiring
}

/// 심각도 — 시스템 알림 interruptionLevel 매핑
enum WatchSeverity: String, Sendable, Equatable, Comparable, Codable, CaseIterable {
    case info
    case warning
    case critical

    static func < (lhs: WatchSeverity, rhs: WatchSeverity) -> Bool {
        let order: [WatchSeverity] = [.info, .warning, .critical]
        guard let li = order.firstIndex(of: lhs), let ri = order.firstIndex(of: rhs) else {
            return false
        }
        return li < ri
    }
}

/// 이벤트 소스 플랫폼 — nil(기존 JSON)은 android 취급
enum WatchSource: String, Sendable, Equatable, Codable {
    case android
    case apple
}

/// Alerts 탭 상태 — 저장하지 않고 파생
enum AlertsState: String, Sendable, Equatable, CaseIterable, Codable {
    case active
    case muted
    case cleared
}

/// 구조화 감시 이벤트 — ConsoleStore 파이프 진입점 (EventStore JSON 직렬화용)
struct WatchEvent: Identifiable, Sendable, Equatable, Codable {
    let id: UUID
    let kind: WatchKind
    let severity: WatchSeverity
    /// adb serial (raw) 또는 Apple udid — shortId는 UI에서
    let serial: String
    let title: String
    let detail: String
    let at: Date
    /// true = 회복(clear) 이벤트
    let isClear: Bool
    /// nil → android (기존 JSON 하위호환)
    var source: WatchSource?
    /// 확인 시각 — nil = 미확인
    var ackAt: Date?
    /// 운영 메모
    var note: String?
    /// 무음 만료 — nil = mute 안됨
    var mutedUntil: Date?
    /// 문제 앱 패키지명 (crash/ANR 구조화) — 기존 JSON nil 허용
    var packageName: String?
    /// 예외 클래스 (java.lang.XxxException 등)
    var exceptionClass: String?
    /// 반복 이슈 키 — serial:kind:pkg:exception (nil이면 errorFingerprintComputed 미사용)
    var errorFingerprint: String?
    /// crash 시점 앱 버전 (dumpsys package, 선택)
    var appVersion: String?

    var fingerprint: String { "\(serial):\(kind.rawValue)" }

    /// 반복 패턴용 fingerprint — errorFingerprint 없으면 기존 serial:kind
    var patternFingerprint: String {
        errorFingerprint ?? fingerprint
    }

    /// 플랫폼 (nil은 android)
    var sourceOrDefault: WatchSource { source ?? .android }

    init(
        kind: WatchKind,
        severity: WatchSeverity,
        serial: String,
        title: String,
        detail: String,
        at: Date = .now,
        isClear: Bool = false,
        source: WatchSource? = nil,
        ackAt: Date? = nil,
        note: String? = nil,
        mutedUntil: Date? = nil,
        packageName: String? = nil,
        exceptionClass: String? = nil,
        errorFingerprint: String? = nil,
        appVersion: String? = nil
    ) {
        self.id = UUID()
        self.kind = kind
        self.severity = severity
        self.serial = serial
        self.title = title
        self.detail = detail
        self.at = at
        self.isClear = isClear
        self.source = source
        self.ackAt = ackAt
        self.note = note
        self.mutedUntil = mutedUntil
        self.packageName = packageName
        self.exceptionClass = exceptionClass
        self.errorFingerprint = errorFingerprint
        self.appVersion = appVersion
    }

    /// 팝오버/로그용 한 줄 요약 (기존 recentEvents: [String] 하위호환)
    var summary: String {
        isClear ? "\(title) — \(detail)" : "\(title): \(detail)"
    }

    /// Alerts 탭 분류 — mute 만료 후 자동 active 복귀
    func state(now: Date = .now) -> AlertsState {
        if isClear { return .cleared }
        if let until = mutedUntil, until > now { return .muted }
        return .active
    }

    /// ack/note/mute 갱신 (불변 복사)
    func updating(
        ackAt: Date? = nil,
        setAck: Bool = false,
        note: String? = nil,
        setNote: Bool = false,
        mutedUntil: Date? = nil,
        setMute: Bool = false
    ) -> WatchEvent {
        var copy = self
        if setAck { copy.ackAt = ackAt }
        if setNote { copy.note = note }
        if setMute { copy.mutedUntil = mutedUntil }
        return copy
    }

    /// 구조화 필드 주입 (crash context 승격용)
    func structured(
        packageName: String? = nil,
        exceptionClass: String? = nil,
        errorFingerprint: String? = nil,
        appVersion: String? = nil
    ) -> WatchEvent {
        var copy = self
        if let packageName { copy.packageName = packageName }
        if let exceptionClass { copy.exceptionClass = exceptionClass }
        if let errorFingerprint { copy.errorFingerprint = errorFingerprint }
        if let appVersion { copy.appVersion = appVersion }
        return copy
    }

    /// errorFingerprint 자동 생성 (pkg + exception)
    static func makeErrorFingerprint(
        serial: String,
        kind: WatchKind,
        packageName: String?,
        exceptionClass: String?
    ) -> String? {
        guard let pkg = packageName, !pkg.isEmpty else { return nil }
        let exc = (exceptionClass ?? "unknown").trimmingCharacters(in: .whitespaces)
        return "\(serial):\(kind.rawValue):\(pkg):\(exc)"
    }
}

/// Alerts 조회 필터 — 순수 (배서 메모리 500건 기준)
struct AlertsFilter: Sendable, Equatable {
    var state: AlertsState?
    var severities: Set<WatchSeverity>?
    var sources: Set<WatchSource>?
    /// 이벤트 종류 필터 — nil/빈 set = 전체
    var kinds: Set<WatchKind>?
    var serial: String?
    var since: Date?
    var until: Date?
    var search: String?

    init(
        state: AlertsState? = nil,
        severities: Set<WatchSeverity>? = nil,
        sources: Set<WatchSource>? = nil,
        kinds: Set<WatchKind>? = nil,
        serial: String? = nil,
        since: Date? = nil,
        until: Date? = nil,
        search: String? = nil
    ) {
        self.state = state
        self.severities = severities
        self.sources = sources
        self.kinds = kinds
        self.serial = serial
        self.since = since
        self.until = until
        self.search = search
    }
}

/// 필터·export 순수 연산 (테스트 대상)
enum WatchEventAlerts {
    static func filter(
        _ events: [WatchEvent],
        by f: AlertsFilter,
        now: Date = .now
    ) -> [WatchEvent] {
        events.filter { e in
            if let s = f.state, e.state(now: now) != s { return false }
            if let sev = f.severities, !sev.isEmpty, !sev.contains(e.severity) { return false }
            if let src = f.sources, !src.isEmpty, !src.contains(e.sourceOrDefault) { return false }
            if let kinds = f.kinds, !kinds.isEmpty, !kinds.contains(e.kind) { return false }
            if let serial = f.serial, e.serial != serial { return false }
            if let since = f.since, e.at < since { return false }
            if let until = f.until, e.at > until { return false }
            if let q = f.search?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty {
                let hay = "\(e.title) \(e.detail) \(e.serial) \(e.packageName ?? "") \(e.exceptionClass ?? "")"
                if !hay.localizedCaseInsensitiveContains(q) { return false }
            }
            return true
        }
    }

    static func counts(
        _ events: [WatchEvent],
        filteredBy base: AlertsFilter,
        now: Date = .now
    ) -> [AlertsState: Int] {
        var f = base
        f.state = nil
        var out: [AlertsState: Int] = [:]
        for s in AlertsState.allCases {
            var sf = f
            sf.state = s
            out[s] = filter(events, by: sf, now: now).count
        }
        return out
    }

    static func groupByDevice(_ events: [WatchEvent]) -> [(key: String, source: WatchSource, events: [WatchEvent])] {
        var order: [String] = []
        var buckets: [String: [WatchEvent]] = [:]
        for e in events {
            let key = e.serial
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = []
            }
            buckets[key]?.append(e)
        }
        return order.map { key in
            let list = buckets[key] ?? []
            return (key, list.first?.sourceOrDefault ?? .android, list)
        }
    }

    static func exportJSON(_ events: [WatchEvent]) -> Data? {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? enc.encode(events)
    }

    static func exportCSV(_ events: [WatchEvent], now: Date = .now) -> String {
        let header = "at,source,serial,kind,severity,state,title,detail,package,exception,ackAt,note,mutedUntil"
        let iso = ISO8601DateFormatter()
        var lines = [header]
        for e in events {
            let cells: [String] = [
                iso.string(from: e.at),
                e.sourceOrDefault.rawValue,
                csvEscape(e.serial),
                e.kind.rawValue,
                e.severity.rawValue,
                e.state(now: now).rawValue,
                csvEscape(e.title),
                csvEscape(e.detail),
                csvEscape(e.packageName ?? ""),
                csvEscape(e.exceptionClass ?? ""),
                e.ackAt.map { iso.string(from: $0) } ?? "",
                csvEscape(e.note ?? ""),
                e.mutedUntil.map { iso.string(from: $0) } ?? ""
            ]
            lines.append(cells.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func csvEscape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }
}
