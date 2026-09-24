import Foundation

/// Trust-only Apple 기기 스냅샷 — Phase 1 (libimobiledevice)
struct AppleSnapshot: Sendable, Equatable, Identifiable {
    var udid: String = ""
    var isOnline: Bool = false
    var deviceName: String?
    var productType: String?
    var productVersion: String?
    var batteryLevel: Int?
    var isCharging: Bool?
    /// 헬스 프록시(0–100) — lockdown/ioreg 제공 시
    var batteryHealthPct: Int?
    var cycleCount: Int?
    var storageUsedGB: Double?
    var storageTotalGB: Double?
    /// nominal / fair / serious / critical — lockdown 미제공 시 nil
    var thermalState: String?
    var at: Date = .now

    var id: String { udid }

    var displayName: String {
        if let n = deviceName, !n.isEmpty { return n }
        if let m = productType, !m.isEmpty { return m }
        return IdeviceClient.shortUdid(udid)
    }
}

/// libimobiledevice 순수 파서 — IO 없음 (테스트 대상)
enum IdeviceClient {
    // MARK: - Paths

    /// `idevice_id` 탐지 — PATH 우선과 동일 패턴 (자동 설치 없음)
    static func locateIdeviceId() -> String? {
        locate(tool: "idevice_id")
    }

    static func locateIdeviceInfo() -> String? {
        locate(tool: "ideviceinfo")
    }

    static func locate(tool: String) -> String? {
        let candidates = [
            "/opt/homebrew/bin/\(tool)",
            "/usr/local/bin/\(tool)",
            "/usr/bin/\(tool)"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in pathEnv.split(separator: ":") {
            let p = "\(dir)/\(tool)"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    static var toolsAvailable: Bool {
        locateIdeviceId() != nil && locateIdeviceInfo() != nil
    }

    // MARK: - Parsers

    /// `idevice_id -l` — UDID 한 줄씩, 빈 줄·에러 문구 제외
    static func parseDeviceIds(_ text: String) -> [String] {
        var ids: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty else { continue }
            // 최소 16자 hex/uuid류 — 명시적 에러 문구 스킵
            guard s.count >= 16, !s.lowercased().hasPrefix("error") else { continue }
            guard s.allSatisfy({ $0.isHexDigit || $0 == "-" }) else { continue }
            ids.append(s)
        }
        return ids
    }

    /// `ideviceinfo` — `Key: value` (콜론 1회 분리, 앞 공백 trim)
    static func parseInfo(_ text: String) -> [String: String] {
        var map: [String: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let idx = line.firstIndex(of: ":") else { continue }
            let key = line[..<idx].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: idx)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            map[key] = value
        }
        return map
    }

    /// BOOL 텍스트 → Bool? ("true"/"YES"/"1")
    static func parseBool(_ raw: String?) -> Bool? {
        guard let raw else { return nil }
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "true", "yes", "1": return true
        case "false", "no", "0": return false
        default: return nil
        }
    }

    /// bytes → GB (소수 1자리 반올림 없이 double)
    static func bytesToGB(_ bytes: Double) -> Double {
        bytes / 1_000_000_000
    }

    /// 표시용 UDID — 뒤 4자리만 (로그 마스킹)
    static func shortUdid(_ udid: String) -> String {
        guard udid.count > 4 else { return udid }
        return "…" + udid.suffix(4)
    }

    /// lockdown info 딕셔너리 → AppleSnapshot (disk_usage 병합 가능)
    static func snapshot(
        udid: String,
        info: [String: String],
        disk: [String: String] = [:],
        now: Date = .now
    ) -> AppleSnapshot {
        var snap = AppleSnapshot(udid: udid, isOnline: true, at: now)
        snap.deviceName = info["DeviceName"]
        snap.productType = info["ProductType"]
        snap.productVersion = info["ProductVersion"]
        if let cap = Int(info["BatteryCurrentCapacity"] ?? "") {
            snap.batteryLevel = min(100, max(0, cap))
        }
        snap.isCharging = parseBool(info["BatteryIsCharging"])
        if let health = Int(info["BatteryHealthPercent"] ?? info["BatteryHealth"] ?? "") {
            snap.batteryHealthPct = health
        }
        if let cycle = Int(info["BatteryCycleCount"] ?? "") {
            snap.cycleCount = cycle
        }
        if let thermal = info["ThermalState"] ?? info["thermalState"], !thermal.isEmpty {
            snap.thermalState = thermal.lowercased()
        }

        // com.apple.disk_usage — bytes
        let capacityKeys = ["TotalDataCapacity", "TotalCapacity", "TotalDiskCapacity"]
        let freeKeys = ["TotalDataAvailable", "TotalAvailableCapacity", "AmountDataAvailable", "AvailableCapacity"]
        var totalBytes: Double?
        var freeBytes: Double?
        for k in capacityKeys {
            if let v = disk[k] ?? info[k], let d = Double(v) { totalBytes = d; break }
        }
        for k in freeKeys {
            if let v = disk[k] ?? info[k], let d = Double(v) { freeBytes = d; break }
        }
        if let total = totalBytes, total > 0 {
            snap.storageTotalGB = bytesToGB(total)
            if let free = freeBytes, free >= 0 {
                snap.storageUsedGB = bytesToGB(total - free)
            }
        }
        return snap
    }
}
