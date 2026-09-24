import Foundation
import AppKit

/// screencap 썸네일 — 수동/연결 시 1회 (상시 폴링 금지, PLAN_v0.7)
@MainActor
final class ScreenshotService: ObservableObject {
    static let shared = ScreenshotService()

    @Published private(set) var images: [String: NSImage] = [:]
    @Published private(set) var updatedAt: [String: Date] = [:]
    @Published private(set) var loadingSerials: Set<String> = []

    private init() {}

    func refresh(serial: String, adbPath: String?) {
        guard !serial.isEmpty, let adb = adbPath, !loadingSerials.contains(serial) else { return }
        loadingSerials.insert(serial)
        Task.detached(priority: .utility) { [weak self] in
            let data = Self.capture(adb: adb, serial: serial)
            await MainActor.run {
                guard let self else { return }
                self.loadingSerials.remove(serial)
                if let data, let img = NSImage(data: data) {
                    self.images[serial] = img
                    self.updatedAt[serial] = Date()
                }
            }
        }
    }

    func clear(serial: String) {
        images[serial] = nil
        updatedAt[serial] = nil
    }

    nonisolated private static func capture(adb: String, serial: String) -> Data? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: adb)
        proc.arguments = ["-s", serial, "exec-out", "screencap", "-p"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0, !data.isEmpty else { return nil }
        return data
    }
}
