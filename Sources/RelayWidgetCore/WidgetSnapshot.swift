import Foundation

/// 위젯 스냅샷 — 앱이 App Group에 기록하고 위젯은 읽기만 함 (PLAN_widget)
/// 표시용 라벨(ident)은 앱이 이미 `identLabel`로 확정해 담는다 — 위젯은 원문 그대로 출력만 ([표시①])
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public static let currentSchema = 2

    public var schema: Int
    /// 기록 시각 — "마지막 업데이트" 표시·신선도 판단 ([표시②])
    public var updatedAt: Date
    /// 아침 브리핑 한 줄 — 앱이 현지화해 저장, nil = 브리핑 OFF
    public var briefing: String?
    /// critical 미해결 수 — 메뉴바 배지와 동일 산식
    public var critical: Int
    /// 기기 (선택 기기 1대 우선 · 최대 4)
    public var devices: [WidgetDevice]
    /// 최근 감시 이벤트 최대 3건 (최신 우선)
    public var events: [WidgetEvent]

    public init(
        schema: Int = WidgetSnapshot.currentSchema,
        updatedAt: Date = .now,
        briefing: String? = nil,
        critical: Int = 0,
        devices: [WidgetDevice] = [],
        events: [WidgetEvent] = []
    ) {
        self.schema = schema
        self.updatedAt = updatedAt
        self.briefing = briefing
        self.critical = critical
        self.devices = devices
        self.events = events
    }

    /// 아무 데이터도 없음 — 위젯 빈 상태(가이드 문구) 노출용
    public var isEmpty: Bool {
        critical == 0 && devices.isEmpty && events.isEmpty
    }

    /// 톤 — 팝오버 브리핑과 동일 규칙 (critical > 정상)
    public var tone: Tone {
        if critical > 0 { return .bad }
        return .ok
    }

    public enum Tone: String, Sendable {
        case ok, warn, bad
    }
}

/// 기기 한 줄 — ident는 화면에 그대로 노출하는 원문 ([표시①] 마스킹 금지)
public struct WidgetDevice: Codable, Equatable, Sendable {
    /// `identLabel` 결과 — 네트워크 `IP:PORT` · USB `기기명 · 시리얼 원문`
    public var ident: String
    public var online: Bool
    public var batteryPct: Int?
    public var charging: Bool?
    /// 발열 경보 (Android thermalStatus/온도 · Apple serious 이상)
    public var thermalAlert: Bool
    /// 선택된 기기 (widget 첫 줄 노출)
    public var selected: Bool

    public init(
        ident: String,
        online: Bool,
        batteryPct: Int? = nil,
        charging: Bool? = nil,
        thermalAlert: Bool = false,
        selected: Bool = false
    ) {
        self.ident = ident
        self.online = online
        self.batteryPct = batteryPct
        self.charging = charging
        self.thermalAlert = thermalAlert
        self.selected = selected
    }
}

public struct WidgetEvent: Codable, Equatable, Sendable {
    public var at: Date
    /// WatchSeverity rawValue — info | warning | critical
    public var severity: String
    /// 이벤트 제목 (생성 시점에 이미 현지화된 문자열)
    public var title: String
    /// 기기 식별 라벨 — `identLabel` ([표시①])
    public var ident: String

    public init(at: Date, severity: String, title: String, ident: String) {
        self.at = at
        self.severity = severity
        self.title = title
        self.ident = ident
    }
}

extension WidgetSnapshot {
    /// placeholder/미리보기용 샘플 — 실제 데이터 아님
    public static var preview: WidgetSnapshot {
        WidgetSnapshot(
            updatedAt: .now,
            briefing: nil,
            critical: 1,
            devices: [
                WidgetDevice(ident: "S22 · R5CT30XXXXX", online: true, batteryPct: 82, charging: false, thermalAlert: false, selected: true)
            ],
            events: []
        )
    }
}
