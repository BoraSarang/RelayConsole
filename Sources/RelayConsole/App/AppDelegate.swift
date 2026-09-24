import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // V0-2: appearance는 NSApp 준비 후 세팅 — 테마(시스템/다크/화이트) 연동
        ThemeManager.shared.applyAppearance()
        DebugLogger.shared.info("App", "[INFO] [FEATURE] Relay Console 1.13.0 시작")
        HeadlessLaunch.apply()
        LoginItemController.shared.refreshStatus()
        ConsoleStore.shared.start()
        // 플로팅 창 enabled 복원 — 재기동 후 설정 ON이면 즉시 표시 (이슈 5)
        if UserDefaults.standard.bool(forKey: "relay.float.enabled") {
            FloatingGraphController.shared.show()
        }
        // 감시 알림 권한 (PLAN_v0.5) — 최초 1회
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 종료 시 플로팅 좌상단 저장 — didMove 없이 끝나도 재시작 시 동일 위치
        FloatingGraphController.shared.persistPosition()
        ConsoleStore.shared.shutdown()
    }
}
