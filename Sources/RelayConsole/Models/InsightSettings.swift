import Foundation

// MARK: - retention / pattern 임계값 (설정화 — 테스트기↔안정기 모드 전환)

enum RetentionDays: Int, CaseIterable, Identifiable, Sendable {
    case d30 = 30
    case d60 = 60
    case d90 = 90
    case unlimited = 0

    var id: Int { rawValue }

    /// 0 = 무제한
    static let defaultDays = 30

    var labelKey: String {
        switch self {
        case .d30: return "settings.retention.30"
        case .d60: return "settings.retention.60"
        case .d90: return "settings.retention.90"
        case .unlimited: return "settings.retention.unlimited"
        }
    }
}

/// 반복/해소 판정 임계값 — 개발 테스트기/안정기에 맞춰 변경
struct PatternThresholds: Equatable, Sendable, Codable {
    /// 최근 N일 내 이 횟수 이상 = repeating
    var repeatingDays: Int
    var repeatingCount: Int
    /// clear 후 N일 무재발 = resolved
    var resolvedQuietDays: Int
    /// 과거 반복했으나 N일 침묵 = dormant
    var dormantQuietDays: Int

    static let `default` = PatternThresholds(
        repeatingDays: 7,
        repeatingCount: 3,
        resolvedQuietDays: 3,
        dormantQuietDays: 7
    )

    /// UserDefaults 키
    static let keys = (
        repeatingDays: "relay.pattern.repeatingDays",
        repeatingCount: "relay.pattern.repeatingCount",
        resolvedQuietDays: "relay.pattern.resolvedQuietDays",
        dormantQuietDays: "relay.pattern.dormantQuietDays"
    )

    static func fromDefaults(_ defaults: UserDefaults = .standard) -> PatternThresholds {
        PatternThresholds(
            repeatingDays: max(1, defaults.integer(forKey: keys.repeatingDays)),
            repeatingCount: max(1, defaults.integer(forKey: keys.repeatingCount)),
            resolvedQuietDays: max(1, defaults.integer(forKey: keys.resolvedQuietDays)),
            dormantQuietDays: max(1, defaults.integer(forKey: keys.dormantQuietDays))
        )
        // integer = 0 이면 기본값 미설정 → default 사용
        .normalized(defaults: defaults)
    }

    private func normalized(defaults: UserDefaults) -> PatternThresholds {
        var t = self
        if defaults.object(forKey: Self.keys.repeatingDays) == nil {
            t.repeatingDays = Self.default.repeatingDays
        }
        if defaults.object(forKey: Self.keys.repeatingCount) == nil {
            t.repeatingCount = Self.default.repeatingCount
        }
        if defaults.object(forKey: Self.keys.resolvedQuietDays) == nil {
            t.resolvedQuietDays = Self.default.resolvedQuietDays
        }
        if defaults.object(forKey: Self.keys.dormantQuietDays) == nil {
            t.dormantQuietDays = Self.default.dormantQuietDays
        }
        return t
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(repeatingDays, forKey: Self.keys.repeatingDays)
        defaults.set(repeatingCount, forKey: Self.keys.repeatingCount)
        defaults.set(resolvedQuietDays, forKey: Self.keys.resolvedQuietDays)
        defaults.set(dormantQuietDays, forKey: Self.keys.dormantQuietDays)
    }
}

/// 보관 + 패턴 + 알림 설정 키 모음 (ConsoleStore 공유용)
enum InsightSettings {
    static let retentionKey = "relay.retention.days"
    static let defaultRetentionDays = RetentionDays.defaultDays

    static func retentionDays(_ defaults: UserDefaults = .standard) -> Int {
        let v = defaults.integer(forKey: retentionKey)
        // 미설정(0)이면 기본 30 — unlimited는 명시적 0 저장이므로 object 유무로 구분
        if defaults.object(forKey: retentionKey) == nil {
            return defaultRetentionDays
        }
        return v
    }
}
