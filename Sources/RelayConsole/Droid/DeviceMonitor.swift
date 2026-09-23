import Foundation

actor DeviceMonitor {
    static let shared = DeviceMonitor()

    private var timer: Task<Void, Never>?
    private var onSnapshot: (@Sendable (DeviceSnapshot) -> Void)?

    func attach(_ handler: @escaping @Sendable (DeviceSnapshot) -> Void) {
        onSnapshot = handler
    }

    func start() async {
        guard timer == nil else { return }
        await MainActor.run {
            DebugLogger.shared.info("Monitor", "[INFO] [FEATURE] DeviceMonitor 5s 틱 시작")
        }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self else { break }
                await self.tick()
            }
        }
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func tick() async {
        let snapshot = DeviceSnapshot()
        onSnapshot?(snapshot)
    }
}
