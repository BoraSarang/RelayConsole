import Foundation

/// ADB 순수 파서 — 단위 테스트 대상 (static, IO 없음)
enum AdbClient {
    // MARK: - Battery

    static func parseBattery(_ text: String) -> DeviceSnapshot {
        parseBatteryEx(text)
    }

    /// dumpsys battery — core + Samsung extended (Bsoh/Asoc/Usage/Protect)
    static func parseBatteryEx(_ text: String) -> DeviceSnapshot {
        var snap = DeviceSnapshot()
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2 else { continue }
            let key = parts[0]
            let value = parts[1]
            switch key {
            case "level":
                snap.batteryLevel = Int(value)
            case "temperature":
                // 0.1°C 단위
                if let raw = Double(value) { snap.batteryTempC = raw / 10.0 }
            case "status":
                // 2=charging, 5=full — nil이면 UI가 "—" (P0-b)
                snap.isCharging = (value == "2" || value == "5")
            case "voltage":
                snap.voltageMV = Int(value)
            case "mSavedBatteryBsoh":
                snap.batteryHealthPct = Int(value)
            case "mProtectBatteryMode":
                snap.isProtectionMode = (Int(value) ?? 0) != 0
            case "mProtectionThreshold":
                snap.protectionThresholdPct = Int(value)
            case "mSavedBatteryUsage":
                // [80739] → 앞 3자리 cycle 추정 (비공식)
                let digits = value.filter(\.isNumber)
                if digits.count >= 3 {
                    snap.cycleEstimate = Int(digits.prefix(3))
                }
            default:
                break
            }
        }
        return snap
    }

    // MARK: - Thermal

    struct ThermalSample: Equatable, Sendable {
        var status: Int?
        var apTempC: Double?
        var skinTempC: Double?
        var batTempC: Double?
    }

    /// dumpsys thermalservice — Thermal Status 0~6 + AP/SKIN/BAT
    static func parseThermal(_ text: String) -> ThermalSample {
        var sample = ThermalSample()
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Thermal Status:") {
                let raw = trimmed.replacingOccurrences(of: "Thermal Status:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                sample.status = Int(raw)
                continue
            }
            guard trimmed.hasPrefix("Temperature{") else { continue }
            guard let valueStr = matchField(trimmed, "mValue"),
                  let value = Double(valueStr),
                  let name = matchField(trimmed, "mName") else { continue }
            switch name {
            case "AP":
                sample.apTempC = value
            case "SKIN":
                sample.skinTempC = value
            case "BAT":
                sample.batTempC = value
            default:
                break
            }
        }
        return sample
    }

    // MARK: - Load average

    struct LoadSample: Equatable, Sendable {
        var load1: Double?
        var load5: Double?
        var load15: Double?
    }

    /// /proc/loadavg — `4.49 5.13 4.45 14/4457 3975`
    static func parseLoadAvg(_ text: String) -> LoadSample {
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var sample = LoadSample()
        if tokens.count > 0 { sample.load1 = Double(tokens[0]) }
        if tokens.count > 1 { sample.load5 = Double(tokens[1]) }
        if tokens.count > 2 { sample.load15 = Double(tokens[2]) }
        return sample
    }

    // MARK: - Memory

    struct MemSample: Equatable, Sendable {
        var totalGB: Double?
        var availableGB: Double?
        var usedGB: Double?
        var swapTotalGB: Double?
    }

    /// /proc/meminfo — MemTotal/MemAvailable kB → GB; used = total − available
    static func parseMemInfo(_ text: String) -> MemSample {
        var totalKB: Double?
        var availKB: Double?
        var swapKB: Double?
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2 else { continue }
            let kb = parts[1].split(whereSeparator: \.isWhitespace).first
                .flatMap { Double($0) }
            switch parts[0] {
            case "MemTotal": totalKB = kb
            case "MemAvailable": availKB = kb
            case "SwapTotal": swapKB = kb
            default: break
            }
        }
        let totalGB = totalKB.map { $0 / (1024 * 1024) }
        let availGB = availKB.map { $0 / (1024 * 1024) }
        let usedGB: Double?
        if let t = totalGB, let a = availGB {
            usedGB = max(0, t - a)
        } else {
            usedGB = nil
        }
        return MemSample(
            totalGB: totalGB,
            availableGB: availGB,
            usedGB: usedGB,
            swapTotalGB: swapKB.map { $0 / (1024 * 1024) }
        )
    }

    // MARK: - CPU (/proc/stat delta)

    struct ProcStatSample: Equatable, Sendable {
        var total: UInt64?
        var idle: UInt64?
    }

    /// /proc/stat aggregate `cpu ` line — totals for delta use%
    static func parseProcStat(_ text: String) -> ProcStatSample {
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("cpu ") || trimmed.hasPrefix("cpu\t") else { continue }
            let fields = trimmed.split(whereSeparator: \.isWhitespace).dropFirst().compactMap {
                UInt64($0)
            }
            // user nice system idle iowait irq softirq steal ...
            guard fields.count >= 4 else { continue }
            let idle = fields[3] + (fields.count > 4 ? fields[4] : 0)
            let total = fields.reduce(0, +)
            return ProcStatSample(total: total, idle: idle)
        }
        return ProcStatSample()
    }

    /// 사용률 % from consecutive samples. nil if no delta (first tick).
    static func cpuUsePercent(prev: ProcStatSample, curr: ProcStatSample) -> Double? {
        guard let pt = prev.total, let pi = prev.idle,
              let ct = curr.total, let ci = curr.idle,
              ct > pt else { return nil }
        let totalD = ct - pt
        let idleD = ci > pi ? ci - pi : 0
        if totalD == 0 { return nil }
        let busy = totalD > idleD ? totalD - idleD : 0
        return Double(busy) / Double(totalD) * 100.0
    }

    // MARK: - Storage (df -h /data)

    struct DfSample: Equatable, Sendable {
        var usedGB: Double?
        var totalGB: Double?
        var usePercent: Int?
    }

    static func parseDf(_ text: String) -> DfSample {
        for line in text.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            // Filesystem Size Used Avail Use% Mounted
            guard fields.count >= 6 else { continue }
            guard fields[0] != "Filesystem" else { continue }
            let mount = fields[5]
            // df -h /data → /data 또는 /storage/emulated/... (One UI)
            let isData = mount == "/data"
                || mount.hasSuffix("/data")
                || mount.hasPrefix("/storage/emulated")
                || fields[0].hasPrefix("/dev/block")
            guard isData else { continue }
            return DfSample(
                usedGB: parseSizeToGB(fields[2]),
                totalGB: parseSizeToGB(fields[1]),
                usePercent: Int(fields[4].trimmingCharacters(in: CharacterSet(charactersIn: "%")))
            )
        }
        return DfSample()
    }

    // MARK: - Network (/proc/net/dev)

    struct NetSample: Equatable, Sendable {
        var rxBytes: UInt64?
        var txBytes: UInt64?
    }

    /// Sum all non-lo interfaces — delta for MB/s
    static func parseNetDev(_ text: String) -> NetSample {
        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var saw = false
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let ifName = String(trimmed[trimmed.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            guard ifName != "lo" else { continue }
            let rest = trimmed[trimmed.index(after: colon)...]
                .split(whereSeparator: \.isWhitespace).compactMap { UInt64($0) }
            // rx: bytes packets errs drop fifo frame compressed multicast
            // tx: bytes ...
            guard rest.count >= 10 else { continue }
            rx += rest[0]
            tx += rest[8]
            saw = true
        }
        guard saw else { return NetSample() }
        return NetSample(rxBytes: rx, txBytes: tx)
    }

    /// MB/s from consecutive net samples over interval seconds. nil if first tick.
    static func netRatesMBps(
        prev: NetSample,
        curr: NetSample,
        seconds: Double
    ) -> (up: Double, down: Double)? {
        guard seconds > 0,
              let pr = prev.rxBytes, let pt = prev.txBytes,
              let cr = curr.rxBytes, let ct = curr.txBytes,
              cr >= pr, ct >= pt else { return nil }
        let down = Double(cr - pr) / seconds / (1024 * 1024)
        let up = Double(ct - pt) / seconds / (1024 * 1024)
        return (up: up, down: down)
    }

    // MARK: - Network type (dumpsys connectivity)

    /// Active default network transport — "Wi-Fi" | "LTE" | "NR" | "CELLULAR" | …
    /// `Active default network: 116` + matching `NetworkAgentInfo{network{116} … Transports:`
    static func parseNetworkType(_ text: String) -> String? {
        var activeId: String?
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Active default network:") {
                activeId = trimmed.replacingOccurrences(of: "Active default network:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                break
            }
        }
        guard let activeId else { return nil }
        let needle = "network{\(activeId)}"
        for line in text.split(separator: "\n") {
            let s = String(line)
            guard s.contains(needle) else { continue }
            if s.contains("Transports: WIFI") { return "Wi-Fi" }
            if s.contains("MOBILE[NR]") || s.contains("Transports: CELLULAR") && s.contains("[NR]") {
                return "NR"
            }
            if let range = s.range(of: "MOBILE[") {
                let after = s[range.upperBound...]
                if let end = after.firstIndex(of: "]") {
                    return String(after[after.startIndex..<end])
                }
            }
            if s.contains("Transports: CELLULAR") { return "CELLULAR" }
            if s.contains("Transports: ETHERNET") { return "Ethernet" }
        }
        return nil
    }

    // MARK: - Helpers

    static func shortId(_ serial: String) -> String {
        guard serial.count > 4 else { return serial }
        return "…" + serial.suffix(4)
    }

    static func missingBinaryError() -> (ErrorCode, String) {
        (.adbBinaryMissing, ErrorCode.adbBinaryMissing.koMessage)
    }

    /// `mValue=53.0` / `mName=AP` field extract from Temperature{...}
    private static func matchField(_ line: String, _ key: String) -> String? {
        guard let range = line.range(of: "\(key)=") else { return nil }
        let after = line[range.upperBound...]
        if let end = after.firstIndex(where: { $0 == "," || $0 == "}" }) {
            return String(after[after.startIndex..<end])
        }
        return String(after)
    }

    /// "23G" / "223G" / "1.5T" / "512M" → GB
    private static func parseSizeToGB(_ raw: String) -> Double? {
        let s = raw.uppercased()
        guard let last = s.last, let num = Double(s.dropLast()) else {
            return Double(s)
        }
        switch last {
        case "T": return num * 1024
        case "G": return num
        case "M": return num / 1024
        case "K": return num / (1024 * 1024)
        case "B": return num / (1024 * 1024 * 1024)
        default: return nil
        }
    }
}
