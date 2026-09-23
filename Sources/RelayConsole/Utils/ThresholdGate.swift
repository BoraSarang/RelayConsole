import Foundation

/// ThresholdGate 판정 결과
enum GateAction: Equatable, Sendable {
    case none
    case enter
    case clear
}

/// enter/clear hysteresis + cooldown — 플래핑·중복 발화 방지
/// 상태: normal →(value≥enter, cooldown만료)→ active →(value≤clear)→ cooldown → normal
struct ThresholdGate: Sendable {
    let enter: Double
    /// enter > clear 필수 (hysteresis). clear ≥ enter면 플래핑 방지 실패.
    let clear: Double
    let cooldown: TimeInterval

    private var isActive = false
    private var cooldownUntil: Date?

    init(enter: Double, clear: Double, cooldown: TimeInterval) {
        precondition(enter > clear, "ThresholdGate: enter must be > clear (hysteresis)")
        self.enter = enter
        self.clear = clear
        self.cooldown = cooldown
    }

    /// 스로틀링 등 discrete 레벨 게이트 (enter/clear는 정수 레벨 해석 아님 — 임계값 비교)
    mutating func evaluate(value: Double, now: Date = .now) -> GateAction {
        if isActive {
            if value <= clear {
                isActive = false
                cooldownUntil = now.addingTimeInterval(cooldown)
                return .clear
            }
            return .none
        }

        // normal 상태: cooldown 중이면 enter 불가
        if let until = cooldownUntil, now < until {
            return .none
        }

        if value >= enter {
            isActive = true
            cooldownUntil = nil
            return .enter
        }
        return .none
    }

    var active: Bool { isActive }

    /// 기기 분리 시 상태 초기화용
    mutating func reset() {
        isActive = false
        cooldownUntil = nil
    }
}

/// 충전/보호모드 등 bool 전이 게이트 — 빠른 토글에도 전이당 1회 fire
struct TransitionGate: Sendable {
    let cooldown: TimeInterval
    private var lastValue: Bool?
    private var lastFiredAt: Date?

    init(cooldown: TimeInterval) {
        self.cooldown = cooldown
    }

    /// nil 첫 틱은 baseline만 기록 (이벤트 없음). 이후 bool 변경 시 true 1회.
    mutating func evaluate(current: Bool, now: Date = .now) -> GateAction {
        defer { lastValue = current }
        guard let prev = lastValue, prev != current else { return .none }
        if let at = lastFiredAt, now.timeIntervalSince(at) < cooldown {
            return .none
        }
        lastFiredAt = now
        return .enter
    }

    mutating func reset() {
        lastValue = nil
        lastFiredAt = nil
    }
}
