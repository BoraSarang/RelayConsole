import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // V0-2: NSApp.appearance = .darkAqua (App.init too early — NSApp nil crash)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        DebugLogger.shared.info("App", "[INFO] [FEATURE] Relay Console 0.3.0 시작")
        ConsoleStore.shared.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
