import Foundation

struct DeviceSnapshot: Sendable, Equatable {
    var serial: String = ""
    var model: String = ""
    var isOnline: Bool = false
    var batteryLevel: Int?
    var batteryTempC: Double?
    var isCharging: Bool?
    var thermalStatus: Int?
    var cpuUsePercent: Double?
    var deviceTempC: Double?
    var memoryUsedGB: Double?
    var memoryTotalGB: Double?
    var storageUsedGB: Double?
    var storageTotalGB: Double?
    var networkInfo: String?
    var netUpMBps: Double?
    var netDownMBps: Double?
    /// Wi-Fi / LTE / NR / … — dumpsys connectivity Active default
    var networkType: String?
    var voltageMV: Int?
    var batteryHealthPct: Int?
    var isProtectionMode: Bool?
    var protectionThresholdPct: Int?
    var cycleEstimate: Int?
    var load1: Double?
    var androidVersion: String?
    var sdkInt: Int?
    var lastError: String?

    /// ≥40°C or thermal Status≥2 (V0-2 Surface A)
    var isThermalAlert: Bool {
        if let t = deviceTempC ?? batteryTempC, t >= 40 { return true }
        if let s = thermalStatus, s >= 2 { return true }
        return false
    }
}

/// UI 유일 read 모델 (값 타입 — ConsoleStore가 @Published로 보유)
struct DeviceInventory: Equatable {
    var devices: [DeviceSnapshot] = []

    /// 부분 스냅샷 병합 — nil optional은 이전 값 유지 (5s 틱이 15s 필드를 덮지 않음)
    mutating func merge(_ snapshot: DeviceSnapshot) {
        guard !snapshot.serial.isEmpty else { return }
        if let idx = devices.firstIndex(where: { $0.serial == snapshot.serial }) {
            var merged = snapshot
            let prev = devices[idx]
            if merged.isOnline {
                merged.batteryLevel = merged.batteryLevel ?? prev.batteryLevel
                merged.batteryTempC = merged.batteryTempC ?? prev.batteryTempC
                merged.isCharging = merged.isCharging ?? prev.isCharging
                merged.thermalStatus = merged.thermalStatus ?? prev.thermalStatus
                merged.cpuUsePercent = merged.cpuUsePercent ?? prev.cpuUsePercent
                merged.deviceTempC = merged.deviceTempC ?? prev.deviceTempC
                merged.memoryUsedGB = merged.memoryUsedGB ?? prev.memoryUsedGB
                merged.memoryTotalGB = merged.memoryTotalGB ?? prev.memoryTotalGB
                merged.storageUsedGB = merged.storageUsedGB ?? prev.storageUsedGB
                merged.storageTotalGB = merged.storageTotalGB ?? prev.storageTotalGB
                merged.networkInfo = merged.networkInfo ?? prev.networkInfo
                merged.netUpMBps = merged.netUpMBps ?? prev.netUpMBps
                merged.netDownMBps = merged.netDownMBps ?? prev.netDownMBps
                merged.networkType = merged.networkType ?? prev.networkType
                merged.voltageMV = merged.voltageMV ?? prev.voltageMV
                merged.batteryHealthPct = merged.batteryHealthPct ?? prev.batteryHealthPct
                merged.isProtectionMode = merged.isProtectionMode ?? prev.isProtectionMode
                merged.protectionThresholdPct = merged.protectionThresholdPct ?? prev.protectionThresholdPct
                merged.cycleEstimate = merged.cycleEstimate ?? prev.cycleEstimate
                merged.load1 = merged.load1 ?? prev.load1
                merged.androidVersion = merged.androidVersion ?? prev.androidVersion
                merged.sdkInt = merged.sdkInt ?? prev.sdkInt
                if merged.model.isEmpty { merged.model = prev.model }
            }
            devices[idx] = merged
        } else {
            devices.append(snapshot)
        }
    }

    mutating func markOffline(serial: String) {
        guard let idx = devices.firstIndex(where: { $0.serial == serial }) else { return }
        devices[idx].isOnline = false
    }
}
