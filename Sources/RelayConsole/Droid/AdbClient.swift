import Foundation

/// ADB 순수 파서 — 단위 테스트 대상 (static, IO 없음)
enum AdbClient {
    static func parseBattery(_ text: String) -> DeviceSnapshot {
        var snap = DeviceSnapshot()
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "level":
                snap.batteryLevel = Int(parts[1])
            case "temperature":
                // 0.1°C 단위
                if let raw = Double(parts[1]) { snap.batteryTempC = raw / 10.0 }
            case "status":
                // 2=charging, 5=full
                snap.isCharging = (parts[1] == "2" || parts[1] == "5")
            default:
                break
            }
        }
        return snap
    }

    static func shortId(_ serial: String) -> String {
        guard serial.count > 4 else { return serial }
        return "…" + serial.suffix(4)
    }

    static func missingBinaryError() -> (ErrorCode, String) {
        (.adbBinaryMissing, ErrorCode.adbBinaryMissing.koMessage)
    }
}
