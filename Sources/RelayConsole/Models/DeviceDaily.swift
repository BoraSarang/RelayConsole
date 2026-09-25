import Foundation

/// 기기별 일자 메트릭 롤업 — 1분 디바운스로 day bucket 병합
struct DeviceDaily: Codable, Equatable, Sendable {
    let serial: String
    let dayKey: String

    // CPU
    var cpuAvg: Double?
    var cpuMax: Double?
    // 온도 (°C) — device/battery 중 최우선
    var tempAvg: Double?
    var tempMax: Double?
    // 배터리
    var batteryMin: Int?
    var batteryMax: Int?
    var batteryStartLevel: Int?
    var batteryEndLevel: Int?
    var chargeMinutes: Double?
    // 네트워크 (MB, 해당 틱에서 수집된 값 합)
    var netUpMB: Double?
    var netDownMB: Double?
    // 디스크 (MB/s 평균 기반 누적 추정 없음 — 평균 유지)
    var diskReadAvgMBps: Double?
    var diskWriteAvgMBps: Double?
    // GPU / 메모리 / PSI
    var gpuAvg: Double?
    var memUsedPctAvg: Double?
    var psiAvg: Double?
    var psiMax: Double?
    // 신호
    var rsrpMin: Int?
    // 온라인 시간 (분) — 샘플 수 기반 추정
    var onlineMinutes: Double?
    /// 샘플 수 (1분 롤업 유닛)
    var samples: Int
    /// 스로틀링/PSI/메모리 등 경고 횟수 (이벤트 카운트 보조)
    var warnEvents: Int
    var criticalEvents: Int
    var crashEvents: Int
    var anrEvents: Int
    var firstAt: Date?
    var lastAt: Date?

    init(
        serial: String,
        dayKey: String,
        samples: Int = 0,
        warnEvents: Int = 0,
        criticalEvents: Int = 0,
        crashEvents: Int = 0,
        anrEvents: Int = 0
    ) {
        self.serial = serial
        self.dayKey = dayKey
        self.samples = samples
        self.warnEvents = warnEvents
        self.criticalEvents = criticalEvents
        self.crashEvents = crashEvents
        self.anrEvents = anrEvents
    }
}

// MARK: - 샘플 주입 (순수 — 테스트 대상)

struct DeviceDailySample: Equatable, Sendable {
    var cpu: Double?
    var temp: Double?
    var batteryLevel: Int?
    var isCharging: Bool?
    var netUpMB: Double?
    var netDownMB: Double?
    var diskReadMBps: Double?
    var diskWriteMBps: Double?
    var gpu: Double?
    var memUsedPct: Double?
    var psi: Double?
    var rsrp: Int?
    var at: Date = .now
}

enum DeviceDailyLogic {
    /// dayKey 정규화
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    /// 샘플 1건 병합 — running average via samples count
    static func merge(
        into daily: inout DeviceDaily,
        sample: DeviceDailySample
    ) {
        daily.samples += 1
        let n = Double(daily.samples)

        func avg(_ old: Double?, _ v: Double?) -> Double? {
            guard let v else { return old }
            guard let old else { return v }
            return old + (v - old) / n
        }
        func maxOf(_ old: Double?, _ v: Double?) -> Double? {
            guard let v else { return old }
            guard let old else { return v }
            return max(old, v)
        }
        func minOf(_ old: Double?, _ v: Double?) -> Double? {
            guard let v else { return old }
            guard let old else { return v }
            return min(old, v)
        }

        daily.cpuAvg = avg(daily.cpuAvg, sample.cpu)
        daily.cpuMax = maxOf(daily.cpuMax, sample.cpu)
        daily.tempAvg = avg(daily.tempAvg, sample.temp)
        daily.tempMax = maxOf(daily.tempMax, sample.temp)

        if let lvl = sample.batteryLevel {
            daily.batteryMin = min(daily.batteryMin ?? lvl, lvl)
            daily.batteryMax = max(daily.batteryMax ?? lvl, lvl)
            if daily.batteryStartLevel == nil { daily.batteryStartLevel = lvl }
            daily.batteryEndLevel = lvl
        }
        if sample.isCharging == true {
            // 1분 단위 샘플 → chargeMinutes += 1
            daily.chargeMinutes = (daily.chargeMinutes ?? 0) + 1
        }

        if let up = sample.netUpMB {
            daily.netUpMB = (daily.netUpMB ?? 0) + up
        }
        if let down = sample.netDownMB {
            daily.netDownMB = (daily.netDownMB ?? 0) + down
        }

        daily.diskReadAvgMBps = avg(daily.diskReadAvgMBps, sample.diskReadMBps)
        daily.diskWriteAvgMBps = avg(daily.diskWriteAvgMBps, sample.diskWriteMBps)
        daily.gpuAvg = avg(daily.gpuAvg, sample.gpu)
        daily.memUsedPctAvg = avg(daily.memUsedPctAvg, sample.memUsedPct)
        daily.psiAvg = avg(daily.psiAvg, sample.psi)
        daily.psiMax = maxOf(daily.psiMax, sample.psi)
        if let r = sample.rsrp {
            daily.rsrpMin = daily.rsrpMin.map { min($0, r) } ?? r
        }

        // 온라인 ≈ 샘플 수 (1분 유닛 기준)
        daily.onlineMinutes = Double(daily.samples)

        if daily.firstAt == nil { daily.firstAt = sample.at }
        daily.lastAt = sample.at
    }

    /// 이벤트 카운트 (WatchEvent ingest 시)
    static func countEvent(into daily: inout DeviceDaily, kind: WatchKind, isClear: Bool) {
        guard !isClear else { return }
        switch kind {
        case .crash: daily.crashEvents += 1
        case .anr: daily.anrEvents += 1
        case .throttling, .psiPressure, .loadSpike, .memoryLow, .signalDrop, .bsohDrop:
            daily.warnEvents += 1
        case .batteryThreshold:
            daily.warnEvents += 1
        default:
            break
        }
        if WatchSeverity.severity(for: kind) >= .critical {
            daily.criticalEvents += 1
        }
    }

    /// retention 경과분 제거 (days<=0 = 무제한)
    @discardableResult
    static func prune(
        _ map: inout [String: DeviceDaily],
        retentionDays: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        guard retentionDays > 0 else { return 0 }
        guard let cutoffDay = calendar.date(
            byAdding: .day,
            value: -retentionDays,
            to: calendar.startOfDay(for: now)
        ) else { return 0 }
        let cutoff = dayKey(for: cutoffDay, calendar: calendar)
        let before = map.count
        map = map.filter { $0.value.dayKey >= cutoff }
        return before - map.count
    }
}

private extension WatchSeverity {
    static func severity(for kind: WatchKind) -> WatchSeverity {
        switch kind {
        case .anr, .crash, .siteDown: return .critical
        case .sslExpiring: return .warning
        default: return .warning
        }
    }
}
