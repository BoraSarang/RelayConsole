import Foundation

/// S2 Device Health Score — 배터리·발열·스로틀 가중 0–100 (읽기 전용 파생 지표)
struct HealthBreakdown: Sendable, Equatable {
    var total: Int
    var battery: Int
    var thermal: Int
    var throttle: Int
    /// `health.band.good` | `health.band.fair` | `health.band.poor`
    var bandKey: String
}

enum HealthScoreLogic {
    static let batteryWeight = 0.4
    static let thermalWeight = 0.4
    static let throttleWeight = 0.2

    static func bandKey(total: Int) -> String {
        if total >= 80 { return "health.band.good" }
        if total >= 50 { return "health.band.fair" }
        return "health.band.poor"
    }

    /// 오프라인·필수 신호 전무 시 nil
    static func score(from snapshot: DeviceSnapshot) -> HealthBreakdown? {
        guard snapshot.isOnline else { return nil }

        let battery = batteryScore(snapshot)
        let thermal = thermalScore(snapshot)
        let throttle = throttleScore(snapshot)

        guard battery != nil || thermal != nil || throttle != nil else { return nil }

        let b = battery ?? 50
        let t = thermal ?? 50
        let c = throttle ?? 50
        let total = clamp(Int(
            (Double(b) * batteryWeight + Double(t) * thermalWeight + Double(c) * throttleWeight)
                .rounded()
        ))
        return HealthBreakdown(
            total: total,
            battery: b,
            thermal: t,
            throttle: c,
            bandKey: bandKey(total: total)
        )
    }

    /// 레벨 + SOH 평균. 충전 중 레벨 하한 40. 데이터 없으면 nil.
    static func batteryScore(_ d: DeviceSnapshot) -> Int? {
        guard let level = d.batteryLevel else {
            guard let soh = d.batteryHealthPct else { return nil }
            return clamp(soh)
        }
        var levelScore = clamp(level)
        if d.isCharging == true { levelScore = max(levelScore, 40) }
        guard let soh = d.batteryHealthPct else {
            return levelScore
        }
        return clamp(Int(((Double(levelScore) + Double(clamp(soh))) / 2).rounded()))
    }

    /// thermalStatus 등급 vs 온도 — 둘 중 더 좋은 쪽. 데이터 없으면 nil.
    static func thermalScore(_ d: DeviceSnapshot) -> Int? {
        let fromStatus = d.thermalStatus.map { statusScore($0) }
        let fromTemp = (d.deviceTempC ?? d.batteryTempC).map { tempScore($0) }
        switch (fromStatus, fromTemp) {
        case let (s?, t?): return max(s, t)
        case let (s?, nil): return s
        case let (nil, t?): return t
        case (nil, nil): return nil
        }
    }

    /// 0(NONE)…6(MUTDOWN) — 낮을수록 건강
    static func statusScore(_ status: Int) -> Int {
        switch status {
        case ...0: return 100
        case 1: return 90
        case 2: return 70
        case 3: return 50
        case 4: return 30
        case 5: return 15
        default: return 0
        }
    }

    /// ≤35°C 100 · 45°C 70 · 50°C 40 · ≥55°C 0
    static func tempScore(_ celsius: Double) -> Int {
        if celsius <= 35 { return 100 }
        if celsius >= 55 { return 0 }
        if celsius <= 45 {
            let t = (celsius - 35) / 10
            return Int((100 - 30 * t).rounded())
        }
        let t = (celsius - 45) / 10
        return Int((70 - 30 * t).rounded())
    }

    /// CPU%·load1 중 존재하는 것의 min (보수적). 없으면 nil.
    static func throttleScore(_ d: DeviceSnapshot) -> Int? {
        var parts: [Int] = []
        if let cpu = d.cpuUsePercent {
            parts.append(cpuLoadScore(cpu))
        }
        if let load = d.load1 {
            parts.append(loadScore(load))
        }
        return parts.min()
    }

    /// 0%→100 · 50%→70 · ≥100%→20
    static func cpuLoadScore(_ percent: Double) -> Int {
        if percent <= 0 { return 100 }
        if percent >= 100 { return 20 }
        if percent <= 50 {
            let t = percent / 50
            return Int((100 - 30 * t).rounded())
        }
        let t = (percent - 50) / 50
        return Int((70 - 50 * t).rounded())
    }

    /// load1 대비 코어×2 기준 — 초과 시 급락. (cores 미상 시 8 가정)
    static func loadScore(_ load1: Double, cores: Int = 8) -> Int {
        let limit = Double(max(cores, 1) * 2)
        let ratio = max(0, load1) / limit
        if ratio <= 0.5 { return 100 }
        if ratio >= 1.5 { return 10 }
        let t = (ratio - 0.5) / 1.0
        return Int((100 - 90 * t).rounded())
    }

    static func clamp(_ v: Int) -> Int {
        min(100, max(0, v))
    }
}
