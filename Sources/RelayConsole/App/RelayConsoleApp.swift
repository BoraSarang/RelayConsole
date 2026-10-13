import SwiftUI
import AppKit

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
                openSettings: { openSettings() },
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

        debugScenes
    }

    @SceneBuilder
    private var debugScenes: some Scene {
#if DEBUG
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
#else
        EmptyScene()
#endif
    }

    private func openConsole() {
        NSApp.activate(ignoringOtherApps: true)
        WindowFocus.dismissMenuBarPanels()
        openWindow(id: "console")
        WindowFocus.present(sceneID: "console")
    }

    private func openDebug() {
#if DEBUG
        NSApp.activate(ignoringOtherApps: true)
        WindowFocus.dismissMenuBarPanels()
        openWindow(id: "debug")
        WindowFocus.present(sceneID: "debug")
#endif
    }

    private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        WindowFocus.dismissMenuBarPanels()
        openSettings()
        WindowFocus.presentSettings()
    }

    private func openProcesses() {
        NSApp.activate(ignoringOtherApps: true)
        WindowFocus.dismissMenuBarPanels()
        openWindow(id: "processes")
        WindowFocus.present(sceneID: "processes")
    }

    private func openLogs() {
        NSApp.activate(ignoringOtherApps: true)
        WindowFocus.dismissMenuBarPanels()
        openWindow(id: "logs")
        WindowFocus.present(sceneID: "logs")
    }

    private func openAppNetwork() {
        NSApp.activate(ignoringOtherApps: true)
        WindowFocus.dismissMenuBarPanels()
        openWindow(id: "appnetwork")
        WindowFocus.present(sceneID: "appnetwork")
    }

    private func openFiles() {
        NSApp.activate(ignoringOtherApps: true)
        WindowFocus.dismissMenuBarPanels()
        if let serial = store.selectedSerial {
            FileBrowserController.shared.open(serial: serial)
        }
        openWindow(id: "files")
        WindowFocus.present(sceneID: "files")
    }
}

struct EmptyScene: Scene {
    var body: some Scene {
        WindowGroup {
            EmptyView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1, height: 1)
        .windowResizability(.contentMinSize)
    }
}
