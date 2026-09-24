import Foundation

/// ADB 순수 파서 — 단위 테스트 대상 (static, IO 없음)
enum AdbClient {
    // MARK: - Connection (USB vs network)

    /// serial에 `:` 포함 → network(`IP:PORT`), 아니면 USB
    static func parseConnection(_ serial: String) -> (kind: ConnectionKind, label: String) {
        if serial.contains(":") {
            return (.network, serial)
        }
        return (.usb, "USB")
    }

    /// `settings get global device_name` — null/empty → nil
    static func parseDeviceName(_ text: String) -> String? {
        parseSettingValue(text)
    }

    /// 표시용 기기 ID — deviceName 우선, 없으면 model, 그 외 shortId
    static func displayDeviceName(deviceName: String?, model: String?, serial: String) -> String {
        if let n = deviceName, !n.isEmpty { return n }
        if let m = model, !m.isEmpty { return m }
        return shortId(serial)
    }

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

    /// 네트워크 속도 표시 단위 — ≥1.0 MB/s → MB/s, 미만 → KB/s
    static func formatNetRate(_ mbps: Double) -> (value: String, unit: String) {
        guard mbps.isFinite, mbps >= 0 else { return ("—", "") }
        if mbps >= 1.0 {
            let fmt = mbps >= 100 ? "%.0f" : "%.1f"
            return (String(format: fmt, mbps), "MB/s")
        }
        let kbps = mbps * 1024.0
        let fmt = kbps >= 100 ? "%.0f" : "%.1f"
        return (String(format: fmt, kbps), "KB/s")
    }

    /// ↑↓ 한 줄 — 방향 단위가 다르면 각각 단위를 붙임
    static func formatNetRatePair(up: Double, down: Double) -> String {
        let u = formatNetRate(up)
        let d = formatNetRate(down)
        if u.unit == d.unit, !u.unit.isEmpty {
            return "↑\(u.value) ↓\(d.value) \(u.unit)"
        }
        return "↑\(u.value) \(u.unit) ↓\(d.value) \(d.unit)"
    }

    // MARK: - Settings watch (accelerometer_rotation / user_rotation)

    /// `settings get …` — "0"/"1"/"null" → trimmed value; null/empty → nil
    static func parseSettingValue(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t == "null" { return nil }
        return t
    }

    // MARK: - Logcat watch (fixed keywords)

    /// logcat 한 줄 타임스탬프 — `09-23 19:30:04.962 …` → `09-23 19:30:04.962`
    static func logcatLineTimestamp(_ line: String) -> String? {
        let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return nil }
        let date = parts[0]
        let time = parts[1]
        // time must look like HH:mm:ss.mmm
        guard time.contains(":") else { return nil }
        return "\(date) \(time)"
    }

    /// 첫 유효 라인의 타임스탬프 (디버그용)
    static func firstLogcatTimestamp(_ text: String) -> String? {
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if let ts = logcatLineTimestamp(String(line)) { return ts }
        }
        return nil
    }

    /// 마지막 유효 라인의 타임스탬프 — 다음 `-T` 커서 (중복 재카운트 방지)
    static func lastLogcatTimestamp(_ text: String) -> String? {
        var last: String?
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if let ts = logcatLineTimestamp(String(line)) { last = ts }
        }
        return last
    }

    /// 키워드 적중 수 — 대소문자 무시, 부분 문자열 매칭
    /// `afterTimestamp`가 있으면 그 타임스탬프와 같거나 이전인 라인은 제외 (`-T`는 inclusive)
    static func countLogcatHits(
        _ text: String,
        keywords: [String] = DeviceMonitor.logcatKeywords,
        afterTimestamp: String? = nil
    ) -> Int {
        guard !keywords.isEmpty else { return 0 }
        var n = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let s = String(line)
            if let cutoff = afterTimestamp, let ts = logcatLineTimestamp(s), ts <= cutoff {
                continue
            }
            let lower = s.lowercased()
            if keywords.contains(where: { lower.contains($0.lowercased()) }) {
                n += 1
            }
        }
        return n
    }

    // MARK: - CPU cores (cpufreq sysfs + /proc/stat per-core)

    struct CoreFreqSample: Equatable, Sendable {
        var curMHz: [Double] = []
        var maxMHz: [Double] = []
        var governor: String?
    }

    /// `cat` multi-line kHz values → MHz (cpufreq sysfs)
    static func parseCpuCores(curText: String, maxText: String, governorText: String? = nil) -> CoreFreqSample {
        var sample = CoreFreqSample()
        sample.curMHz = curText.split(separator: "\n").compactMap { line in
            Double(line.trimmingCharacters(in: .whitespacesAndNewlines)).map { $0 / 1000.0 }
        }
        sample.maxMHz = maxText.split(separator: "\n").compactMap { line in
            Double(line.trimmingCharacters(in: .whitespacesAndNewlines)).map { $0 / 1000.0 }
        }
        if let g = governorText {
            let first = g.split(separator: "\n").first
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let first, !first.isEmpty { sample.governor = first }
        }
        return sample
    }

    struct CoreStatSample: Equatable, Sendable {
        /// index → (total, idle)
        var cores: [(total: UInt64, idle: UInt64)] = []

        static func == (lhs: CoreStatSample, rhs: CoreStatSample) -> Bool {
            guard lhs.cores.count == rhs.cores.count else { return false }
            for i in 0..<lhs.cores.count
            where lhs.cores[i].total != rhs.cores[i].total || lhs.cores[i].idle != rhs.cores[i].idle {
                return false
            }
            return true
        }
    }

    /// /proc/stat `cpu0`..`cpuN` lines
    static func parseProcStatCores(_ text: String) -> CoreStatSample {
        var sample = CoreStatSample()
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("cpu"), trimmed.count > 3,
                  trimmed[trimmed.index(trimmed.startIndex, offsetBy: 3)].isNumber else { continue }
            let fields = trimmed.split(whereSeparator: \.isWhitespace).dropFirst().compactMap { UInt64($0) }
            guard fields.count >= 4 else { continue }
            let idle = fields[3] + (fields.count > 4 ? fields[4] : 0)
            let total = fields.reduce(0, +)
            sample.cores.append((total: total, idle: idle))
        }
        return sample
    }

    /// 코어별 use% delta — count 맞춰 nil 유지
    static func coreUsePercents(prev: CoreStatSample, curr: CoreStatSample) -> [Double]? {
        guard !curr.cores.isEmpty, prev.cores.count == curr.cores.count else { return nil }
        var out: [Double] = []
        for i in 0..<curr.cores.count {
            let pt = prev.cores[i].total, pi = prev.cores[i].idle
            let ct = curr.cores[i].total, ci = curr.cores[i].idle
            guard ct > pt else { out.append(0); continue }
            let totalD = ct - pt
            let idleD = ci > pi ? ci - pi : 0
            let busy = totalD > idleD ? totalD - idleD : 0
            out.append(Double(busy) / Double(totalD) * 100.0)
        }
        return out
    }

    // MARK: - Memory pressure (PSI)

    /// /proc/pressure/memory — `some avg10=1.23 avg60=… avg300=… total=…`
    static func parsePressure(_ text: String) -> (pct: Double?, label: String?) {
        for line in text.split(separator: "\n") {
            let s = String(line)
            guard s.hasPrefix("some") else { continue }
            guard let range = s.range(of: "avg10=") else { continue }
            let after = s[range.upperBound...]
            let numStr = after.prefix { $0.isNumber || $0 == "." }
            guard let pct = Double(numStr) else { continue }
            let label: String
            switch pct {
            case ..<1: label = "none"
            case 1..<10: label = "low"
            case 10..<50: label = "moderate"
            default: label = "full"
            }
            return (pct, label)
        }
        return (nil, nil)
    }

    // MARK: - Top RSS processes

    struct TopProcess: Equatable, Sendable {
        var name: String
        var rssMB: Double
    }

    /// `ps -A -o RSS,NAME --sort=-rss` head — RSS is KB
    static func parseTopRss(_ text: String, limit: Int = 3) -> [ProcessRSS] {
        var out: [ProcessRSS] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 2 else { continue }
            if parts[0].uppercased() == "RSS" { continue }
            guard let kb = Double(parts[0]) else { continue }
            let name = parts[1...].joined(separator: " ")
            guard !name.isEmpty else { continue }
            out.append(ProcessRSS(name: name, rssMB: kb / 1024.0))
            if out.count >= limit { break }
        }
        return out
    }

    /// `dumpsys cpuinfo` — `  12.3% 4567/com.app: 8% user + 4% kernel` → name/cpu/pid
    static func parseCpuInfoProcs(_ text: String, limit: Int = 30) -> [ProcessRow] {
        var out: [ProcessRow] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.contains("%"), trimmed.contains("/") else { continue }
            // "12.3% 4567/com.app: ..."
            let parts = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 2 else { continue }
            var pctStr = parts[0]
            if pctStr.hasSuffix("%") { pctStr.removeLast() }
            guard let cpu = Double(pctStr) else { continue }
            // "4567/com.app:" → pid + name
            let pidName = parts[1]
            guard let slash = pidName.firstIndex(of: "/") else { continue }
            let pidStr = String(pidName[..<slash])
            var name = String(pidName[pidName.index(after: slash)...])
            if name.hasSuffix(":") { name.removeLast() }
            guard !name.isEmpty else { continue }
            out.append(ProcessRow(
                name: name,
                cpuPercent: cpu,
                rssMB: nil,
                pid: Int(pidStr),
                path: nil
            ))
            if out.count >= limit { break }
        }
        return out
    }

    /// `ps -A -o PID,RSS,NAME,ARGS --sort=-rss` — ARGS는 실행 경로(공백 포함 나머지 줄)
    static func parsePsProcRows(_ text: String, limit: Int = 30) -> [ProcessRow] {
        var out: [ProcessRow] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 4 else { continue }
            if parts[0].uppercased() == "PID" { continue }
            guard let pid = Int(parts[0]), let kb = Double(parts[1]) else { continue }
            let name = parts[2]
            guard !name.isEmpty, name != "NAME" else { continue }
            let path = parts[3...].joined(separator: " ")
            out.append(ProcessRow(
                name: name,
                cpuPercent: nil,
                rssMB: kb / 1024.0,
                pid: pid,
                path: path.isEmpty ? nil : path
            ))
            if out.count >= limit { break }
        }
        return out
    }

    /// RSS/ARGS 목록 + CPU 목록 이름 기준 병합
    static func mergeProcessRows(rss: [ProcessRow], cpu: [ProcessRow]) -> [ProcessRow] {
        var map: [String: ProcessRow] = [:]
        var order: [String] = []
        for r in rss {
            let key = r.name
            if map[key] == nil { order.append(key) }
            map[key] = r
        }
        for c in cpu {
            let key = c.name
            if var existing = map[key] {
                existing.cpuPercent = c.cpuPercent
                if existing.pid == nil { existing.pid = c.pid }
                map[key] = existing
            } else {
                map[key] = c
                order.append(key)
            }
        }
        return order.compactMap { map[$0] }
    }

    /// 구버전 호환 — [ProcessRSS] → [ProcessRow]
    static func mergeProcessRows(rss: [ProcessRSS], cpu: [ProcessRow]) -> [ProcessRow] {
        let asRows = rss.map {
            ProcessRow(name: $0.name, cpuPercent: nil, rssMB: $0.rssMB, pid: nil, path: nil)
        }
        return mergeProcessRows(rss: asRows, cpu: cpu)
    }

    // MARK: - Thermal zones (all Temperature{...})

    struct ThermalZoneSample: Equatable, Sendable {
        var zones: [ThermalZone] = []
    }

    static func parseThermalZones(_ text: String) -> ThermalZoneSample {
        var sample = ThermalZoneSample()
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("Temperature{") else { continue }
            guard let valueStr = matchField(trimmed, "mValue"),
                  let value = Double(valueStr),
                  let name = matchField(trimmed, "mName") else { continue }
            sample.zones.append(ThermalZone(name: name, tempC: value))
        }
        return sample
    }

    // MARK: - Signal (telephony.registry)

    struct SignalSample: Equatable, Sendable {
        var rsrp: Int?
        var carrier: String?
        var rat: String?
    }

    /// `CellSignalStrengthLte: … rsrp=-100 …` + `mOperatorAlphaLong=KT`
    static func parseSignal(_ text: String) -> SignalSample {
        var sample = SignalSample()
        for line in text.split(separator: "\n") {
            let s = String(line)
            if sample.rsrp == nil, let range = s.range(of: "rsrp=") {
                let after = s[range.upperBound...]
                let digits = after.prefix { $0.isNumber || $0 == "-" }
                sample.rsrp = Int(digits)
            }
            if sample.carrier == nil, let range = s.range(of: "mOperatorAlphaLong=") {
                let after = s[range.upperBound...]
                let val = after.prefix { $0 != "," && $0 != " " && $0 != "}" }
                if !val.isEmpty { sample.carrier = String(val) }
            }
            if sample.rat == nil {
                if s.contains(" CellSignalStrengthLte") || s.contains("mServiceState=0") {
                    sample.rat = "LTE"
                }
                if s.contains("CellSignalStrengthNr") { sample.rat = "NR" }
            }
        }
        return sample
    }

    // MARK: - Wi-Fi status (cmd wifi status)

    struct WifiSample: Equatable, Sendable {
        var enabled: Bool?
        var ssid: String?
        var rssi: Int?
    }

    static func parseWifiStatus(_ text: String) -> WifiSample {
        var sample = WifiSample()
        let lower = text.lowercased()
        if lower.contains("wi-fi is enabled") || lower.contains("wifi is enabled") || lower.contains("wifi is turned on") {
            sample.enabled = true
        }
        if lower.contains("wi-fi is disabled") || lower.contains("wifi is disabled") || lower.contains("wifi is turned off") {
            sample.enabled = false
        }
        for line in text.split(separator: "\n") {
            let s = String(line)
            if sample.ssid == nil, let range = s.range(of: "SSID:") {
                let after = s[range.upperBound...].trimmingCharacters(in: .whitespaces)
                var ssid = after.prefix { $0 != "," && !$0.isNewline }
                if ssid.hasPrefix("\"") { ssid = ssid.dropFirst() }
                if ssid.hasSuffix("\"") { ssid = ssid.dropLast() }
                if !ssid.isEmpty && ssid != "<unknown ssid>" { sample.ssid = String(ssid) }
            }
            if sample.rssi == nil, let range = s.range(of: "rssi=") {
                let after = s[range.upperBound...]
                let digits = after.prefix { $0.isNumber || $0 == "-" }
                sample.rssi = Int(digits)
            }
            if sample.rssi == nil, let range = s.range(of: "RSSI: ") {
                let after = s[range.upperBound...]
                let digits = after.prefix { $0.isNumber || $0 == "-" }
                sample.rssi = Int(digits)
            }
        }
        return sample
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

    // MARK: - P2: GPU (SurfaceFlinger GLES + kgsl sysfs only)

    struct GpuGlesSample: Equatable, Sendable {
        var renderer: String?
        var esVersion: String?
    }

    /// `GLES: Qualcomm, Adreno (TM) 730, OpenGL ES 3.2 V@0615.98 …`
    static func parseGpuGles(_ text: String) -> GpuGlesSample {
        var sample = GpuGlesSample()
        for line in text.split(separator: "\n") {
            let s = String(line)
            guard s.contains("GLES:") || s.contains("OpenGL ES") else { continue }
            // renderer: after GLES: up to ", OpenGL" or end
            if let range = s.range(of: "GLES:") {
                let rest = String(s[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if let esIdx = rest.range(of: ", OpenGL ES") {
                    sample.renderer = String(rest[..<esIdx.lowerBound]).trimmingCharacters(in: .whitespaces)
                } else if let comma = rest.firstIndex(of: ",") {
                    sample.renderer = String(rest[..<comma]).trimmingCharacters(in: .whitespaces)
                } else {
                    sample.renderer = rest.isEmpty ? nil : rest
                }
            }
            if let esRange = s.range(of: "OpenGL ES") {
                let after = s[esRange.upperBound...]
                // " 3.2 V@…" → "3.2"
                let digits = after.drop(while: { $0 == " " })
                    .prefix { $0.isNumber || $0 == "." }
                if !digits.isEmpty { sample.esVersion = String(digits) }
            }
            if sample.renderer != nil || sample.esVersion != nil { break }
        }
        return sample
    }

    /// kgsl `gpu_busy_percentage` → e.g. "12 %" / "12"; `gpubusy` → "busy idle"
    static func parseGpuBusyPercent(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let parts = t.split(whereSeparator: \.isWhitespace)
        if parts.count >= 2, let busy = Double(parts[0]), let idle = Double(parts[1]) {
            let total = busy + idle
            if total > 0 { return min(max(busy / total * 100.0, 0), 100) }
        }
        if parts.count >= 1, let v = Double(parts[0]) {
            return min(max(v, 0), 100)
        }
        return nil
    }

    /// kgsl `gpuclk` (Hz) → MHz
    static func parseGpuClkMHz(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hz = Double(t.split(whereSeparator: \.isWhitespace).first ?? "") else { return nil }
        // 이미 MHz면 범위 가드 (보통 1e8~3e9 Hz)
        if hz >= 1_000_000 { return hz / 1_000_000.0 }
        if hz > 0 && hz < 10_000 { return hz } // already MHz
        return nil
    }

    // MARK: - P2: Sensors summary

    struct SensorsSummary: Equatable, Sendable {
        var total: Int?
        var activeCount: Int?
        var activeNames: [String] = []
        /// active 센서별 샘플 주기(ms) — activeNames와 같은 순서 (없으면 생략)
        var activePeriodsMs: [Double?] = []
    }

    /// sensorservice — Samsung(AOSP 접두) + AOSP 형식
    /// Samsung: `Total 39 h/w … clients:` + `Name … (handle=0x…)  active-count = N; … selected = 20.00 ms`
    /// AOSP: `active connections:` + `0x…) type 0x… (accelerometer)`
    static func parseSensorsSummary(_ text: String, nameLimit: Int = 8) -> SensorsSummary {
        var sample = SensorsSummary()
        for line in text.split(separator: "\n") {
            let s = String(line)

            if sample.total == nil, s.contains("Total"), s.contains("h/w sensors") {
                let tokens = s.split(separator: " ")
                for (i, tok) in tokens.enumerated() where tok == "Total" {
                    if i + 1 < tokens.count, let n = Int(tokens[i + 1]) {
                        sample.total = n
                        break
                    }
                }
            }

            // ── 활성 센서 라인 (active-count 포함)
            if s.contains("active-count") {
                sample.activeCount = (sample.activeCount ?? 0) + 1
                if sample.activeNames.count < nameLimit,
                   let name = activeSensorName(s) {
                    if !sample.activeNames.contains(name) {
                        sample.activeNames.append(name)
                        sample.activePeriodsMs.append(activeSensorPeriodMs(s))
                    } else if let idx = sample.activeNames.firstIndex(of: name),
                              sample.activePeriodsMs.indices.contains(idx),
                              sample.activePeriodsMs[idx] == nil {
                        sample.activePeriodsMs[idx] = activeSensorPeriodMs(s)
                    }
                }
                continue
            }

            // ── AOSP 레거시: `0x…) type 0x… (accelerometer)`
            if s.contains(") type 0x"), let typeRange = s.range(of: ") type 0x") {
                let afterType = s[typeRange.upperBound...]
                if let open = afterType.firstIndex(of: "("),
                   let close = afterType.firstIndex(of: ")"),
                   open < close {
                    var name = String(afterType[afterType.index(after: open)..<close])
                        .trimmingCharacters(in: .whitespaces)
                    if let w = name.range(of: " Non-wakeup") { name = String(name[..<w.lowerBound]) }
                    if let w = name.range(of: " Wakeup") { name = String(name[..<w.lowerBound]) }
                    if !name.isEmpty, !sample.activeNames.contains(name),
                       sample.activeNames.count < nameLimit {
                        sample.activeNames.append(name)
                        sample.activePeriodsMs.append(nil)
                    }
                }
            }
        }
        return sample
    }

    /// `lsm6dso … Accelerometer Non-wakeup(handle=0x…)` → display name
    /// `smd  Wakeup                        (handle=0x…)` → `smd`
    private static func activeSensorName(_ line: String) -> String? {
        guard let hRange = line.range(of: "(handle=") else { return nil }
        var name = String(line[line.startIndex..<hRange.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        // trailing Non-wakeup / Wakeup (optional space variants)
        for suffix in [" Non-wakeup", "Wakeup", " Non-wakeup ", " Wakeup "] {
            if name.hasSuffix(suffix.trimmingCharacters(in: .whitespaces)) ||
                name.hasSuffix(suffix) {
                name = String(name.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        // 더 안전: 정규로 끝 wakeup 표기 제거
        if let r = name.range(of: "\\s*Non-wakeup\\s*$", options: .regularExpression) {
            name = String(name[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        if let r = name.range(of: "\\s+Wakeup\\s*$", options: .regularExpression) {
            name = String(name[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return name.isEmpty ? nil : name
    }

    /// `selected = 20.00 ms` 또는 `sampling_period(ms) = {20.0}` → ms
    private static func activeSensorPeriodMs(_ line: String) -> Double? {
        if let r = line.range(of: #"selected\s*=\s*([0-9.]+)\s*ms"#, options: .regularExpression) {
            let s = line[r]
            if let numRange = s.range(of: #"[0-9.]+"#, options: .regularExpression),
               let v = Double(s[numRange]) {
                return v
            }
        }
        if let r = line.range(of: #"sampling_period\(ms\)\s*=\s*\{([0-9.]+)"#, options: .regularExpression) {
            let s = line[r]
            if let numRange = s.range(of: #"[0-9.]+$"#, options: .regularExpression),
               let v = Double(s[numRange]) {
                return v
            }
        }
        return nil
    }

    // MARK: - P2: diskstats R/W (sda만 — 파티션/loop/dm/zram 제외)

    struct DiskSample: Equatable, Sendable {
        var readSectors: UInt64?
        var writeSectors: UInt64?
    }

    /// `/proc/diskstats` — whole-disk `sda` only (partitions like sda1 excluded)
    static func parseDiskStats(_ text: String) -> DiskSample {
        for line in text.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 10, fields[2] == "sda" else { continue }
            // [0]=major [1]=minor [2]=name [3]=reads [4]=merged [5]=sectors_read
            // [6]=ms [7]=writes [8]=merged_w [9]=sectors_written
            guard let rs = UInt64(fields[5]), let ws = UInt64(fields[9]) else { continue }
            return DiskSample(readSectors: rs, writeSectors: ws)
        }
        return DiskSample()
    }

    /// sector delta → MB/s. nil on first tick.
    static func diskRatesMBps(
        prev: DiskSample,
        curr: DiskSample,
        seconds: Double
    ) -> (read: Double, write: Double)? {
        guard seconds > 0,
              let pr = prev.readSectors, let pw = prev.writeSectors,
              let cr = curr.readSectors, let cw = curr.writeSectors,
              cr >= pr, cw >= pw else { return nil }
        // 1 sector = 512 bytes
        let read = Double(cr - pr) * 512.0 / seconds / (1024 * 1024)
        let write = Double(cw - pw) * 512.0 / seconds / (1024 * 1024)
        return (read: read, write: write)
    }

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
