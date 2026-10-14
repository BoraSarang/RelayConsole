import SwiftUI
import AppKit

/// 실행 시 자동 열린 대시보드와 사용자 요청 구분 — SwiftUI는 첫 Window 씬을 자동 표시하므로,
/// 설정이 꺼져 있으면 진입 직후 닫는다. 위젯 딥링크·사용자 클릭은 전부 `openConsole()`을
/// 경유하므로 플래그로 보호한다 (딥링크로 열린 창을 닫는 사고 방지).
enum ConsoleLaunchGate {
    /// 가변 전역(Swift 6 금지) 대신 불변 박스 + 잠금 — 메인 스레드에서만 접근
    private static let box = LaunchFlagBox()
    static var userOpened: Bool {
        get { box.get() }
        set { box.set(newValue) }
    }
}

private final class LaunchFlagBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func get() -> Bool { lock.withLock { value } }
    func set(_ v: Bool) { lock.withLock { value = v } }
}

@main
struct RelayConsoleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ConsoleStore.shared
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some Scene {
        // **SwiftUI 는 body 평가 시점에만 Environment(openWindow/openSettings)를 읽는다.**
        // 메뉴바는 AppKit NSStatusItem(StatusItemController)으로 그린다 (PLAN_menubar_nsstatusitem)
        // — 여기서 창 열기 클로저를 넘긴다. 설치 자체는 AppDelegate.didFinishLaunching.
        let _ = StatusItemController.shared.adopt(
            actions: StatusItemController.Actions(
                openConsole: { openConsole() },
                openDebug: { openDebug() },
                openSettings: { openSettingsWindow() },
                openProcesses: { openProcesses() },
                openLogs: { openLogs() },
                openAppNetwork: { openAppNetwork() },
                openFiles: { openFiles() }
            ),
            bootstrap: {
                // 플로팅에서 각 창 열기 — openWindow Environment 주입 (구 MenuBarExtra label onAppear)
                FloatingGraphController.shared.openProcesses = { openProcesses() }
                FloatingGraphController.shared.openAppNetwork = { openAppNetwork() }
                FloatingGraphController.shared.openConsole = { openConsole() }
                // 위젯 딥링크 라우팅 — 클로저 주입 완료 후 보류 URL 플러시
                WidgetDeepLink.shared.openProcesses = { openProcesses() }
                WidgetDeepLink.shared.openLogs = { openLogs() }
                WidgetDeepLink.shared.openAppNetwork = { openAppNetwork() }
                WidgetDeepLink.shared.openSettings = { openSettingsWindow() }
                WidgetDeepLink.shared.openConsole = { openConsole() }
                WidgetDeepLink.shared.flush()
            }
        )

        // 창 크롬 통일: 전부 시스템 타이틀바 (Settings scene과 동일 — DESIGN §4 native)
        Window(L10n.string("droid.header.title"), id: "console") {
            ConsoleView(store: store)
                .frame(minWidth: 760, minHeight: 520)
                .preferredColorScheme(theme.mode.preferred)
                .background(OPColor.popBG)
        }
        .defaultSize(width: 900, height: 700)

        Window(L10n.string("droid.process.titleShort"), id: "processes") {
            ProcessListWindowView(store: store)
                .frame(minWidth: 640, minHeight: 480)
                .preferredColorScheme(theme.mode.preferred)
                .background(OPColor.popBG)
        }
        .defaultSize(width: 720, height: 560)

        Window(L10n.string("droid.logs.titleShort"), id: "logs") {
            LogViewerWindowView(store: store)
                .frame(minWidth: 640, minHeight: 420)
                .preferredColorScheme(theme.mode.preferred)
                .background(OPColor.popBG)
        }
        .defaultSize(width: 720, height: 480)

        Window(L10n.string("droid.appnet.titleShort"), id: "appnetwork") {
            AppNetworkWindowView(store: store)
                .frame(minWidth: 520, minHeight: 420)
                .preferredColorScheme(theme.mode.preferred)
                .background(OPColor.popBG)
        }
        .defaultSize(width: 620, height: 460)

        Window(L10n.string("files.title"), id: "files") {
            FileBrowserWindowView(store: store)
                .frame(minWidth: 760, minHeight: 480)
                .preferredColorScheme(theme.mode.preferred)
                .background(OPColor.popBG)
        }
        .defaultSize(width: 960, height: 640)

        Settings {
            SettingsView(store: store)
                .frame(minWidth: 560, maxWidth: 640, minHeight: 400, maxHeight: 720)
                .preferredColorScheme(theme.mode.preferred)
        }
        // ⌘Q 종료 커맨드 — 구 MenuBarExtra scene 제거로 여기로 이동
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button(L10n.string("menubar.button.quit")) {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }

#if DEBUG
        debugScenes
#endif
    }

#if DEBUG
    @SceneBuilder
    private var debugScenes: some Scene {
        Window(L10n.string("ui.debug.title"), id: "debug") {
            DebugPanelView()
                .frame(minWidth: 560, minHeight: 400)
                .preferredColorScheme(theme.mode.preferred)
                .background(OPColor.popBG)
        }
        .defaultSize(width: 640, height: 480)
        .commands {
            CommandGroup(after: .sidebar) {
                Button(L10n.string("menubar.button.debug")) { openDebug() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }
    }
#endif

    /// 창 열기 공통 — 팝오버 정상 close → 활성화 → 메뉴 패널 정리 → open → 전면화.
    /// 7개 open*의 반복 패턴을 한 곳으로 묶는다 (호출 순서·동작 동일 유지).
    private func openScene(setup: () -> Void, present: () -> Void) {
        StatusItemController.shared.closePopover()
        NSApp.activate(ignoringOtherApps: true)
        WindowFocus.dismissMenuBarPanels()
        setup()
        present()
    }

    private func openConsole() {
        ConsoleLaunchGate.userOpened = true
        openScene(setup: { openWindow(id: "console") }) {
            WindowFocus.present(sceneID: "console")
        }
    }

    private func openDebug() {
#if DEBUG
        openScene(setup: { openWindow(id: "debug") }) {
            WindowFocus.present(sceneID: "debug")
        }
#endif
    }

    private func openSettingsWindow() {
        openScene(setup: { openSettings() }) {
            WindowFocus.presentSettings()
        }
    }

    private func openProcesses() {
        openScene(setup: { openWindow(id: "processes") }) {
            WindowFocus.present(sceneID: "processes")
        }
    }

    private func openLogs() {
        openScene(setup: { openWindow(id: "logs") }) {
            WindowFocus.present(sceneID: "logs")
        }
    }

    private func openAppNetwork() {
        openScene(setup: { openWindow(id: "appnetwork") }) {
            WindowFocus.present(sceneID: "appnetwork")
        }
    }

    private func openFiles() {
        openScene(setup: {
            if let serial = store.selectedSerial {
                FileBrowserController.shared.open(serial: serial)
            }
            openWindow(id: "files")
        }) {
            WindowFocus.present(sceneID: "files")
        }
    }
}
