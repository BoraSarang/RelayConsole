import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // V0-2: appearance는 NSApp 준비 후 세팅 — 테마(시스템/다크/화이트) 연동
        ThemeManager.shared.applyAppearance()
        DebugLogger.shared.info("App", "[INFO] [FEATURE] Relay Console \(AppVersion.display) 시작")
        HeadlessLaunch.apply()
        LoginItemController.shared.refreshStatus()
        ConsoleStore.shared.start()
        // 위젯 스냅샷 동기화 시작 — App Group 기록 + WidgetKit 리로드 (PLAN_widget)
        WidgetSnapshotSync.shared.attach(ConsoleStore.shared)
        // 플로팅 창 복원 — 재기동 후 설정 ON이면 저장된 창 리스트 전체 재생성 (이슈 5)
        FloatingGraphController.shared.restoreAll()
        // 감시 알림 권한 (PLAN_v0.5) — 최초 1회
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// 위젯/외부 URL — `relayconsole://<target>` (PLAN_widget 딥링크)
    func application(_ application: NSApplication, open urls: [URL]) {
        WidgetDeepLink.shared.handle(urls)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 종료 시 플로팅 좌상단 저장 — didMove 없이 끝나도 재시작 시 동일 위치
        FloatingGraphController.shared.persistPosition()
        WidgetSnapshotSync.shared.flush(ConsoleStore.shared)
        ConsoleStore.shared.shutdown()
    }
}
