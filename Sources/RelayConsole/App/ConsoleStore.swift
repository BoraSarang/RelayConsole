import Foundation
import Combine

/// UI 유일 read 모델 — `devices`만 읽도록 강제 (PLAN P0-a)
@MainActor
final class ConsoleStore: ObservableObject {
    static let shared = ConsoleStore()

    @Published var inventory = DeviceInventory()
    @Published var recentEvents: [String] = []
    @Published var lastError: String?

    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        DebugLogger.shared.info("Store", "[INFO] [FEATURE] ConsoleStore 시작 (relay.*)", meta: "keyPrefix=relay.")
        let handler: @Sendable (DeviceSnapshot) -> Void = { [weak self] snapshot in
            Task { @MainActor in
                self?.inventory.merge(snapshot)
            }
        }
        Task {
            await DeviceMonitor.shared.attach(handler)
            await DeviceMonitor.shared.start()
        }
    }

    func pushEvent(_ text: String) {
        recentEvents.insert(text, at: 0)
        if recentEvents.count > 20 { recentEvents.removeLast() }
    }
}
