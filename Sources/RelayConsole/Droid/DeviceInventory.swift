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
    var lastError: String?
}

/// UI 유일 read 모델 (값 타입 — ConsoleStore가 @Published로 보유)
struct DeviceInventory: Equatable {
    var devices: [DeviceSnapshot] = []

    mutating func merge(_ snapshot: DeviceSnapshot) {
        guard !snapshot.serial.isEmpty else { return }
        if let idx = devices.firstIndex(where: { $0.serial == snapshot.serial }) {
            devices[idx] = snapshot
        } else {
            devices.append(snapshot)
        }
    }
}
