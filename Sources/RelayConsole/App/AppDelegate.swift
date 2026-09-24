import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // V0-2: NSApp.appearance = .darkAqua (App.init too early — NSApp nil crash)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        DebugLogger.shared.info("App", "[INFO] [FEATURE] Relay Console 1.6.0 시작")
        ConsoleStore.shared.start()
        // 감시 알림 권한 (PLAN_v0.5) — 최초 1회
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        ConsoleStore.shared.shutdown()
    }
}
