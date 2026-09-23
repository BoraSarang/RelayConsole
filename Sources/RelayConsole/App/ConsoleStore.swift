import Foundation
import Combine

/// UI 유일 read 모델 — `devices`만 읽도록 강제 (PLAN P0-a)
@MainActor
final class ConsoleStore: ObservableObject {
    static let shared = ConsoleStore()

    @Published var inventory = DeviceInventory()
    @Published var recentEvents: [String] = []
    @Published var lastError: String?
    /// serial → DroidMetrics 링 60점 (5s × 60 = 5분)
    @Published private(set) var metricsHistory: [String: DroidMetrics] = [:]
    /// 현재 선택 기기 (팝오버/대시보드 기준) — PLAN_v0.3
    @Published var selectedSerial: String?

    private let selectedKey = "relay.selectedSerial"
    private var started = false
    private var lastNetPushAt: [String: Date] = [:]

    private init() {
        selectedSerial = UserDefaults.standard.string(forKey: selectedKey)
    }

    func start() {
        guard !started else { return }
        started = true
        DebugLogger.shared.info("Store", "[INFO] [FEATURE] ConsoleStore 시작 (relay.*)", meta: "keyPrefix=relay.")
        let handler: @Sendable (DeviceSnapshot) -> Void = { [weak self] snapshot in
            Task { @MainActor in
                self?.ingest(snapshot)
            }
        }
        let eventHandler: @Sendable (String) -> Void = { [weak self] text in
            Task { @MainActor in
                self?.pushEvent(text)
            }
        }
        Task {
            await DeviceMonitor.shared.attach(handler)
            await DeviceMonitor.shared.attachEvent(eventHandler)
            await DeviceMonitor.shared.start()
        }
    }

    private func ingest(_ snapshot: DeviceSnapshot) {
        inventory.merge(snapshot)
        guard snapshot.isOnline else { return }

        // 선택 기기 없으면 첫 온라인 자동 선택
        if selectedSerial == nil || inventory.device(serial: selectedSerial ?? "") == nil {
            selectedSerial = snapshot.serial
            UserDefaults.standard.set(snapshot.serial, forKey: selectedKey)
        }

        var m = metricsHistory[snapshot.serial] ?? DroidMetrics()
        let temp = snapshot.deviceTempC ?? snapshot.batteryTempC
        let level = snapshot.batteryLevel.map(Double.init)
        let cpu = snapshot.cpuUsePercent

        var netPush: Double?
        if let up = snapshot.netUpMBps, let down = snapshot.netDownMBps {
            let key = snapshot.serial
            if lastNetPushAt[key] == nil || Date().timeIntervalSince(lastNetPushAt[key]!) >= 10 {
                netPush = up + down
                lastNetPushAt[key] = Date()
            }
        }

        var diskRead: Double?
        var diskWrite: Double?
        if snapshot.diskReadMBps != nil || snapshot.diskWriteMBps != nil {
            diskRead = snapshot.diskReadMBps
            diskWrite = snapshot.diskWriteMBps
        }

        let gpu = snapshot.gpuUtilPercent

        if cpu != nil || temp != nil || level != nil || netPush != nil || diskRead != nil || diskWrite != nil || gpu != nil {
            m.push(cpu: cpu, temp: temp, level: level, net: netPush, diskRead: diskRead, diskWrite: diskWrite, gpu: gpu)
            metricsHistory[snapshot.serial] = m
        }
    }

    // MARK: - Selection (PLAN_v0.3)

    /// 기기 선택 + persist (`relay.selectedSerial`)
    func select(_ serial: String) {
        guard !serial.isEmpty else { return }
        selectedSerial = serial
        UserDefaults.standard.set(serial, forKey: selectedKey)
    }

    /// 선택 기기 스냅샷 — nil이면 첫 장치 폴백
    var selectedDevice: DeviceSnapshot? {
        if let s = selectedSerial, let d = inventory.device(serial: s) {
            return d
        }
        return inventory.devices.first
    }

    func device(for serial: String) -> DeviceSnapshot? {
        inventory.device(serial: serial)
    }

    /// 기기 선택 후 콘솔 열기 — openConsole 콜백이 App 측 주입
    func openConsoleAfterSelect(serial: String, open: () -> Void) {
        select(serial)
        open()
    }

    func metrics(for serial: String) -> DroidMetrics {
        metricsHistory[serial] ?? DroidMetrics()
    }

    func metricsForSelected() -> DroidMetrics? {
        selectedDevice.map { metrics(for: $0.serial) }
    }

    func pushEvent(_ text: String) {
        recentEvents.insert(text, at: 0)
        if recentEvents.count > 20 { recentEvents.removeLast() }
    }

    func markDeviceOffline(_ serial: String) {
        inventory.markOffline(serial: serial)
    }
}
