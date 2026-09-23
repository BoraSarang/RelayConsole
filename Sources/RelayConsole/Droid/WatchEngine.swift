import Foundation

/// serial·지표별 게이트 보관 + WatchEvent emit — DeviceMonitor에서 delta 주입만 받음
/// MainActor: ConsoleStore/히스토리와 경합 없이 단일 스레드
@MainActor
final class WatchEngine {
    static let shared = WatchEngine()

    /// 스로틀링: enter≥3 SEVERE, clear≤1 LIGHT, 60s 쿨다운
    private var thermalGates: [String: ThresholdGate] = [:]
    private var chargeGates: [String: TransitionGate] = [:]
    private var protectionGates: [String: TransitionGate] = [:]
    private var lowPowerGates: [String: TransitionGate] = [:]
    /// 배터리 임계 ( discharge 하강 시 1회, 충전 재상승 시 재무장 )
    private var batteryArmed: [String: Set<Int>] = [:]
    private let batteryThresholds = [20, 10, 5]

    /// Phase2 (수집 연결 전까지 미사용 — Gate만 선 구성)
    private var psiGates: [String: ThresholdGate] = [:]
    private var loadGates: [String: ThresholdGate] = [:]
    private var memGates: [String: ThresholdGate] = [:]

    private init() {}

    func thermalGate(for serial: String) -> ThresholdGate {
        if let g = thermalGates[serial] { return g }
        let g = ThresholdGate(enter: 3, clear: 1, cooldown: 60)
        thermalGates[serial] = g
        return g
    }

    // MARK: - Feed (DeviceMonitor 호출)

    /// thermalStatus 0~6
    func feedThermal(serial: String, status: Int, now: Date = .now) -> WatchEvent? {
        var gate = thermalGates[serial] ?? ThresholdGate(enter: 3, clear: 1, cooldown: 60)
        let action = gate.evaluate(value: Double(status), now: now)
        thermalGates[serial] = gate
        guard action != .none else { return nil }

        let short = AdbClient.shortId(serial)
        if action == .enter {
            let sev: WatchSeverity = status >= 3 ? .critical : .warning
            return WatchEvent(
                kind: .throttling,
                severity: sev,
                serial: serial,
                title: L10n.string("event.throttling.enter"),
                detail: "\(short) · Status \(status)",
                at: now
            )
        }
        return WatchEvent(
            kind: .throttling,
            severity: .info,
            serial: serial,
            title: L10n.string("event.throttling.clear"),
            detail: "\(short) · Status \(status)",
            at: now,
            isClear: true
        )
    }

    /// 충전 전이 (true/false 변경)
    func feedCharging(serial: String, charging: Bool, now: Date = .now) -> WatchEvent? {
        var gate = chargeGates[serial] ?? TransitionGate(cooldown: 5)
        let action = gate.evaluate(current: charging, now: now)
        chargeGates[serial] = gate
        guard action == .enter else { return nil }

        let short = AdbClient.shortId(serial)
        let title = charging
            ? L10n.string("event.charge.start")
            : L10n.string("event.charge.stop")
        return WatchEvent(
            kind: .chargeChanged,
            severity: .info,
            serial: serial,
            title: title,
            detail: short,
            at: now
        )
    }

    /// 보호모드 0→1 / 1→0
    func feedProtection(serial: String, enabled: Bool, now: Date = .now) -> WatchEvent? {
        var gate = protectionGates[serial] ?? TransitionGate(cooldown: 10)
        let action = gate.evaluate(current: enabled, now: now)
        protectionGates[serial] = gate
        guard action == .enter else { return nil }

        let short = AdbClient.shortId(serial)
        let title = enabled
            ? L10n.string("event.protection.on")
            : L10n.string("event.protection.off")
        return WatchEvent(
            kind: .protectionChanged,
            severity: enabled ? .warning : .info,
            serial: serial,
            title: title,
            detail: short,
            at: now,
            isClear: !enabled
        )
    }

    /// 저전력/절전 모드 0↔1
    func feedLowPower(serial: String, enabled: Bool, now: Date = .now) -> WatchEvent? {
        var gate = lowPowerGates[serial] ?? TransitionGate(cooldown: 10)
        let action = gate.evaluate(current: enabled, now: now)
        lowPowerGates[serial] = gate
        guard action == .enter else { return nil }

        let short = AdbClient.shortId(serial)
        let title = enabled
            ? L10n.string("event.lowPower.on")
            : L10n.string("event.lowPower.off")
        return WatchEvent(
            kind: .lowPowerChanged,
            severity: enabled ? .info : .info,
            serial: serial,
            title: title,
            detail: short,
            at: now,
            isClear: !enabled
        )
    }

    /// 배터리 하강 임계 (20/10/5%) — 충전 중 재충전 시 재무장
    func feedBatteryLevel(serial: String, level: Int, charging: Bool, now: Date = .now) -> WatchEvent? {
        var armed = batteryArmed[serial] ?? Set(batteryThresholds)
        if charging {
            // 충전 시작 시 이미 지나간 임계 재무장 (다음 방전 사이클 준비)
            for t in batteryThresholds where level > t {
                armed.insert(t)
            }
            batteryArmed[serial] = armed
            return nil
        }
        guard armed.contains(where: { level <= $0 }) else {
            batteryArmed[serial] = armed
            return nil
        }
        // 가장 높은 미충족 임계 하나만 발화
        let hit = batteryThresholds.filter { level <= $0 && armed.contains($0) }.max()
        guard let threshold = hit else { return nil }
        armed.remove(threshold)
        batteryArmed[serial] = armed

        let short = AdbClient.shortId(serial)
        let sev: WatchSeverity = threshold <= 10 ? .warning : .info
        return WatchEvent(
            kind: .batteryThreshold,
            severity: sev,
            serial: serial,
            title: L10n.format("event.battery.low", "\(threshold)"),
            detail: "\(short) · \(level)%",
            at: now
        )
    }

    /// 기기 분리 시 상태 정리
    func forget(serial: String) {
        thermalGates.removeValue(forKey: serial)
        chargeGates.removeValue(forKey: serial)
        protectionGates.removeValue(forKey: serial)
        lowPowerGates.removeValue(forKey: serial)
        batteryArmed.removeValue(forKey: serial)
        psiGates.removeValue(forKey: serial)
        loadGates.removeValue(forKey: serial)
        memGates.removeValue(forKey: serial)
    }

    func resetAll() {
        thermalGates.removeAll()
        chargeGates.removeAll()
        protectionGates.removeAll()
        lowPowerGates.removeAll()
        batteryArmed.removeAll()
        psiGates.removeAll()
        loadGates.removeAll()
        memGates.removeAll()
    }
}
