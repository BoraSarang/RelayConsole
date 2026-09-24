import Foundation

/// serial·지표별 게이트 보관 + WatchEvent emit — DeviceMonitor에서 delta 주입만 받음
/// MainActor: ConsoleStore/히스토리와 경합 없이 단일 스레드
@MainActor
final class WatchEngine {
    static let shared = WatchEngine()

    /// 스로틀링: enter≥3 SEVERE, clear≤2 (SEVERE 이탈), 60s 쿨다운
    private var thermalGates: [String: ThresholdGate] = [:]
    private var chargeGates: [String: TransitionGate] = [:]
    private var protectionGates: [String: TransitionGate] = [:]
    private var lowPowerGates: [String: TransitionGate] = [:]
    /// 배터리 임계 ( discharge 하강 시 1회, 충전 재상승 시 재무장 )
    private var batteryArmed: [String: Set<Int>] = [:]
    private let batteryThresholds = [20, 10, 5]

    /// Phase2 A5 — PSI / load / MemAvailable
    private var psiGates: [String: ThresholdGate] = [:]
    private var loadGates: [String: ThresholdGate] = [:]
    private var memGates: [String: ThresholdGate] = [:]

    /// Phase v0.7 — Bsoh 급락 / RSRP 급락
    private var bsohBaseline: [String: Int] = [:]
    private var bsohPreDrop: [String: Int] = [:]
    private var bsohAlertActive: [String: Bool] = [:]
    private var batteryAlertActive: [String: Bool] = [:]
    private var rsrpLast: [String: Int] = [:]
    private var rsrpAlertActive: [String: Bool] = [:]
    private var rsrpEnterAt: [String: Date] = [:]
    private let rsrpCooldown: TimeInterval = 60

    /// Phase v0.8 — ANR / 크래시 (logcat 1회성, 5분 쿨다운, clear 자동 없음)
    private var anrLastAt: [String: Date] = [:]
    private var crashLastAt: [String: Date] = [:]
    private let logcatFatalCooldown: TimeInterval = 300

    private init() {}

    func thermalGate(for serial: String) -> ThresholdGate {
        if let g = thermalGates[serial] { return g }
        // clear ≤2 (SEVERE 이탈) — Status 2 구간에서 후속조치 잔류 방지, 60s 쿨다운 유지
        let g = ThresholdGate(enter: 3, clear: 2, cooldown: 60)
        thermalGates[serial] = g
        return g
    }

    // MARK: - Feed (DeviceMonitor 호출)

    /// thermalStatus 0~6 — enter ≥3, clear ≤2 (SEVERE 이탈), 60s
    func feedThermal(serial: String, status: Int, now: Date = .now) -> WatchEvent? {
        var gate = thermalGates[serial] ?? ThresholdGate(enter: 3, clear: 2, cooldown: 60)
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
            severity: enabled ? .warning : .info,
            serial: serial,
            title: title,
            detail: short,
            at: now,
            isClear: !enabled
        )
    }

    /// 배터리 하강 임계 (20/10/5%) — 충전 중 재충전 시 재무장 + 미해결 warning clear
    func feedBatteryLevel(serial: String, level: Int, charging: Bool, now: Date = .now) -> WatchEvent? {
        var armed = batteryArmed[serial] ?? Set(batteryThresholds)
        if charging {
            // 충전 시작 시 이미 지나간 임계 재무장 (다음 방전 사이클 준비)
            for t in batteryThresholds where level > t {
                armed.insert(t)
            }
            batteryArmed[serial] = armed
            if batteryAlertActive[serial] == true {
                batteryAlertActive[serial] = false
                let short = AdbClient.shortId(serial)
                return WatchEvent(
                    kind: .batteryThreshold,
                    severity: .info,
                    serial: serial,
                    title: L10n.string("event.battery.clear"),
                    detail: "\(short) · \(level)% charging",
                    at: now,
                    isClear: true
                )
            }
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
        if sev >= .warning {
            batteryAlertActive[serial] = true
        }
        return WatchEvent(
            kind: .batteryThreshold,
            severity: sev,
            serial: serial,
            title: L10n.format("event.battery.low", "\(threshold)"),
            detail: "\(short) · \(level)%",
            at: now
        )
    }

    /// PSI memory some avg10 — enter ≥5.0, clear ≤3.0, 120s
    func feedPsi(serial: String, avg10: Double, now: Date = .now) -> WatchEvent? {
        var gate = psiGates[serial] ?? ThresholdGate(enter: 5.0, clear: 3.0, cooldown: 120)
        let action = gate.evaluate(value: avg10, now: now)
        psiGates[serial] = gate
        guard action != .none else { return nil }

        let short = AdbClient.shortId(serial)
        if action == .enter {
            return WatchEvent(
                kind: .psiPressure,
                severity: .warning,
                serial: serial,
                title: L10n.string("event.psi.enter"),
                detail: String(format: "%@ · avg10=%.1f", short, avg10),
                at: now
            )
        }
        return WatchEvent(
            kind: .psiPressure,
            severity: .info,
            serial: serial,
            title: L10n.string("event.psi.clear"),
            detail: String(format: "%@ · avg10=%.1f", short, avg10),
            at: now,
            isClear: true
        )
    }

    /// load1 급증 — enter ≥ cores×2, clear ≤ cores×1, 60s
    func feedLoad(serial: String, load1: Double, cores: Int, now: Date = .now) -> WatchEvent? {
        guard cores > 0 else { return nil }
        var gate = loadGates[serial]
            ?? ThresholdGate(enter: Double(cores) * 2, clear: Double(cores), cooldown: 60)
        let action = gate.evaluate(value: load1, now: now)
        loadGates[serial] = gate
        guard action != .none else { return nil }

        let short = AdbClient.shortId(serial)
        if action == .enter {
            return WatchEvent(
                kind: .loadSpike,
                severity: load1 >= Double(cores) * 3 ? .critical : .warning,
                serial: serial,
                title: L10n.string("event.load.enter"),
                detail: String(format: "%@ · load1=%.1f/%d", short, load1, cores),
                at: now
            )
        }
        return WatchEvent(
            kind: .loadSpike,
            severity: .info,
            serial: serial,
            title: L10n.string("event.load.clear"),
            detail: String(format: "%@ · load1=%.1f/%d", short, load1, cores),
            at: now,
            isClear: true
        )
    }

    /// MemAvailable 부족 — usedPct = 100−avail% · enter ≥90 (avail<10%), clear ≤80 (avail>20%), 60s
    func feedMemory(serial: String, usedPct: Double, now: Date = .now) -> WatchEvent? {
        var gate = memGates[serial] ?? ThresholdGate(enter: 90, clear: 80, cooldown: 60)
        let action = gate.evaluate(value: usedPct, now: now)
        memGates[serial] = gate
        guard action != .none else { return nil }

        let short = AdbClient.shortId(serial)
        if action == .enter {
            return WatchEvent(
                kind: .memoryLow,
                severity: usedPct >= 95 ? .critical : .warning,
                serial: serial,
                title: L10n.string("event.memory.enter"),
                detail: String(format: "%@ · %.0f%%", short, usedPct),
                at: now
            )
        }
        return WatchEvent(
            kind: .memoryLow,
            severity: .info,
            serial: serial,
            title: L10n.string("event.memory.clear"),
            detail: String(format: "%@ · %.0f%%", short, usedPct),
            at: now,
            isClear: true
        )
    }

    /// Bsoh 건강 급락 — 하락 Δ≥5pt 1회성 · pre-drop 이상 회복 시 clear
    func feedBsoh(serial: String, bsoh: Int, now: Date = .now) -> WatchEvent? {
        if bsohAlertActive[serial] == true, let pre = bsohPreDrop[serial], bsoh >= pre {
            bsohAlertActive[serial] = false
            bsohPreDrop[serial] = nil
            bsohBaseline[serial] = bsoh
            let short = AdbClient.shortId(serial)
            return WatchEvent(
                kind: .bsohDrop,
                severity: .info,
                serial: serial,
                title: L10n.string("event.bsoh.clear"),
                detail: String(format: "%@ · %d%%", short, bsoh),
                at: now,
                isClear: true
            )
        }
        if let base = bsohBaseline[serial] {
            guard bsoh <= base - 5 else { return nil }
            bsohPreDrop[serial] = base
            bsohAlertActive[serial] = true
            bsohBaseline[serial] = bsoh
            let short = AdbClient.shortId(serial)
            return WatchEvent(
                kind: .bsohDrop,
                severity: .warning,
                serial: serial,
                title: L10n.string("event.bsoh.drop"),
                detail: String(format: "%@ · %d%% → %d%%", short, base, bsoh),
                at: now
            )
        }
        bsohBaseline[serial] = bsoh
        return nil
    }

    /// RSRP 급락 — 악화 Δ≤−6 enter · 회복 Δ≥+6 clear · 60s enter 쿨다운
    func feedRsrp(serial: String, rsrp: Int, now: Date = .now) -> WatchEvent? {
        let short = AdbClient.shortId(serial)
        if let last = rsrpLast[serial] {
            let delta = rsrp - last
            let active = rsrpAlertActive[serial] ?? false
            if !active, delta <= -6 {
                if let at = rsrpEnterAt[serial], now.timeIntervalSince(at) < rsrpCooldown {
                    rsrpLast[serial] = rsrp
                    return nil
                }
                rsrpAlertActive[serial] = true
                rsrpEnterAt[serial] = now
                rsrpLast[serial] = rsrp
                return WatchEvent(
                    kind: .signalDrop,
                    severity: .warning,
                    serial: serial,
                    title: L10n.string("event.signal.drop"),
                    detail: String(format: "%@ · %d → %d dBm", short, last, rsrp),
                    at: now
                )
            }
            if active, delta >= 6 {
                rsrpAlertActive[serial] = false
                rsrpLast[serial] = rsrp
                return WatchEvent(
                    kind: .signalDrop,
                    severity: .info,
                    serial: serial,
                    title: L10n.string("event.signal.clear"),
                    detail: String(format: "%@ · %d dBm", short, rsrp),
                    at: now,
                    isClear: true
                )
            }
        }
        rsrpLast[serial] = rsrp
        return nil
    }

    /// ANR logcat 적중 — 1회성, 5분 쿨다운, clear 자동 없음 (가이드 TTL 의존)
    func feedAnr(serial: String, detail: String = "", now: Date = .now) -> WatchEvent? {
        if let last = anrLastAt[serial], now.timeIntervalSince(last) < logcatFatalCooldown {
            return nil
        }
        anrLastAt[serial] = now
        let short = AdbClient.shortId(serial)
        return WatchEvent(
            kind: .anr,
            severity: .critical,
            serial: serial,
            title: L10n.string("event.anr.enter"),
            detail: detail.isEmpty ? short : "\(short) · \(detail)",
            at: now
        )
    }

    /// 크래시 logcat 적중 — 1회성, 5분 쿨다운, clear 자동 없음 (가이드 TTL 의존)
    func feedCrash(serial: String, detail: String = "", now: Date = .now) -> WatchEvent? {
        if let last = crashLastAt[serial], now.timeIntervalSince(last) < logcatFatalCooldown {
            return nil
        }
        crashLastAt[serial] = now
        let short = AdbClient.shortId(serial)
        return WatchEvent(
            kind: .crash,
            severity: .critical,
            serial: serial,
            title: L10n.string("event.crash.enter"),
            detail: detail.isEmpty ? short : "\(short) · \(detail)",
            at: now
        )
    }

    /// 기기 분리 시 상태 정리 + 미해결 활성 gate의 synthetic clear 반환
    @discardableResult
    func forget(serial: String) -> [WatchEvent] {
        let short = AdbClient.shortId(serial)
        let now = Date()
        var clears: [WatchEvent] = []

        if let g = thermalGates[serial], g.active {
            clears.append(.init(
                kind: .throttling, severity: .info, serial: serial,
                title: L10n.string("event.throttling.clear"),
                detail: "\(short) · disconnect", at: now, isClear: true
            ))
        }
        if let g = protectionGates[serial], g.problemActive {
            clears.append(.init(
                kind: .protectionChanged, severity: .info, serial: serial,
                title: L10n.string("event.protection.off"),
                detail: "\(short) · disconnect", at: now, isClear: true
            ))
        }
        if let g = lowPowerGates[serial], g.problemActive {
            clears.append(.init(
                kind: .lowPowerChanged, severity: .info, serial: serial,
                title: L10n.string("event.lowPower.off"),
                detail: "\(short) · disconnect", at: now, isClear: true
            ))
        }
        if let g = psiGates[serial], g.active {
            clears.append(.init(
                kind: .psiPressure, severity: .info, serial: serial,
                title: L10n.string("event.psi.clear"),
                detail: "\(short) · disconnect", at: now, isClear: true
            ))
        }
        if let g = loadGates[serial], g.active {
            clears.append(.init(
                kind: .loadSpike, severity: .info, serial: serial,
                title: L10n.string("event.load.clear"),
                detail: "\(short) · disconnect", at: now, isClear: true
            ))
        }
        if let g = memGates[serial], g.active {
            clears.append(.init(
                kind: .memoryLow, severity: .info, serial: serial,
                title: L10n.string("event.memory.clear"),
                detail: "\(short) · disconnect", at: now, isClear: true
            ))
        }
        if rsrpAlertActive[serial] == true {
            clears.append(.init(
                kind: .signalDrop, severity: .info, serial: serial,
                title: L10n.string("event.signal.clear"),
                detail: "\(short) · disconnect", at: now, isClear: true
            ))
        }
        if batteryAlertActive[serial] == true {
            clears.append(.init(
                kind: .batteryThreshold, severity: .info, serial: serial,
                title: L10n.string("event.battery.clear"),
                detail: "\(short) · disconnect", at: now, isClear: true
            ))
        }
        if bsohAlertActive[serial] == true {
            clears.append(.init(
                kind: .bsohDrop, severity: .info, serial: serial,
                title: L10n.string("event.bsoh.clear"),
                detail: "\(short) · disconnect", at: now, isClear: true
            ))
        }

        thermalGates.removeValue(forKey: serial)
        chargeGates.removeValue(forKey: serial)
        protectionGates.removeValue(forKey: serial)
        lowPowerGates.removeValue(forKey: serial)
        batteryArmed.removeValue(forKey: serial)
        batteryAlertActive[serial] = nil
        psiGates.removeValue(forKey: serial)
        loadGates.removeValue(forKey: serial)
        memGates.removeValue(forKey: serial)
        bsohBaseline.removeValue(forKey: serial)
        bsohPreDrop[serial] = nil
        bsohAlertActive[serial] = nil
        rsrpLast.removeValue(forKey: serial)
        rsrpAlertActive[serial] = nil
        rsrpEnterAt[serial] = nil
        // ANR/크래시 — clear는 자동 없음, 쿨다운만 재무장
        anrLastAt[serial] = nil
        crashLastAt[serial] = nil
        return clears
    }

    func resetAll() {
        thermalGates.removeAll()
        chargeGates.removeAll()
        protectionGates.removeAll()
        lowPowerGates.removeAll()
        batteryArmed.removeAll()
        batteryAlertActive.removeAll()
        psiGates.removeAll()
        loadGates.removeAll()
        memGates.removeAll()
        bsohBaseline.removeAll()
        bsohPreDrop.removeAll()
        bsohAlertActive.removeAll()
        rsrpLast.removeAll()
        rsrpAlertActive.removeAll()
        rsrpEnterAt.removeAll()
        anrLastAt.removeAll()
        crashLastAt.removeAll()
    }
}
