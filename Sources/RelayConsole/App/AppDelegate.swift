import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 강제 종료(SIGTERM) 정리 — **install 을 launch 맨 처음에** 해야 한다.
        // 늦으면 그 사이의 SIGTERM 이 기본 처리로 빠져 고아 adb 와 저장 유실이 그대로 난다
        TerminationGuard.install()
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

    /// ⌘Q · 메뉴 종료 — 정리 후 **일반 종료**
    ///
    /// 정리 본체는 `TerminationGuard.runShutdown()` 이고, 시그널 경로와 **같은 함수**를 탄다.
    /// 반환값(실제로 돌았는가)은 여기서 쓰지 않는다 — 이미 시그널 쪽에서 정리했다면
    /// `runShutdown` 안에서 막히고, 그때는 두 번째 정리가 일어나지 않는다.
    func applicationWillTerminate(_ notification: Notification) {
        TerminationGuard.runShutdown()
    }

    /// 실제 정리 작업 — **정상 종료와 SIGTERM 이 공유한다**
    ///
    /// 두 곳에 복제하면 반드시 갈라진다. 2026-09-27 에 이미 그랬다:
    /// `flushSync()` 를 `shutdown()` 에만 넣어 두고, `pkill` 경로에는 없었던 것이
    /// **저장 유실**로 이어질 뻔했다.
    @MainActor
    static func terminateWork() {
        // 종료 시 플로팅 좌상단 저장 — didMove 없이 끝나도 재시작 시 동일 위치
        FloatingGraphController.shared.persistPosition()
        WidgetSnapshotSync.shared.flush(ConsoleStore.shared)
        ConsoleStore.shared.shutdown()
    }
}
