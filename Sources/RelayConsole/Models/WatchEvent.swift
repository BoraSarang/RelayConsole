import Foundation

/// 감시 이벤트 종류 — kind는 소수 유지, 중복은 fingerprint로
enum WatchKind: String, Sendable, Equatable, CaseIterable {
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
}

/// 심각도 — 시스템 알림 interruptionLevel 매핑
enum WatchSeverity: String, Sendable, Equatable, Comparable {
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

/// 구조화 감시 이벤트 — ConsoleStore 파이프 진입점
struct WatchEvent: Identifiable, Sendable, Equatable {
    let id: UUID
    let kind: WatchKind
    let severity: WatchSeverity
    /// adb serial (raw) — shortId는 UI에서
    let serial: String
    let title: String
    let detail: String
    let at: Date
    /// true = 회복(clear) 이벤트
    let isClear: Bool

    var fingerprint: String { "\(serial):\(kind.rawValue)" }

    init(
        kind: WatchKind,
        severity: WatchSeverity,
        serial: String,
        title: String,
        detail: String,
        at: Date = .now,
        isClear: Bool = false
    ) {
        self.id = UUID()
        self.kind = kind
        self.severity = severity
        self.serial = serial
        self.title = title
        self.detail = detail
        self.at = at
        self.isClear = isClear
    }

    /// 팝오버/로그용 한 줄 요약 (기존 recentEvents: [String] 하위호환)
    var summary: String {
        isClear ? "\(title) — \(detail)" : "\(title): \(detail)"
    }
}
