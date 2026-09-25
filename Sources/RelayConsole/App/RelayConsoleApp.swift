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
        MenuBarExtra {
            MenuBarPopoverView(store: store, openConsole: {
                openConsole()
            }, openDebug: {
                openDebug()
            }, openSettings: {
                openSettingsWindow()
            }, openProcesses: {
                openProcesses()
            }, openLogs: {
                openLogs()
            }, openAppNetwork: {
                openAppNetwork()
            })
            .frame(width: 360, height: 560)
            .preferredColorScheme(theme.mode.preferred)
            .background(OPColor.popBG) // SOLID — V0-2: no material/glass
        }
        label: {
            // 아이콘만 — 텍스트 없음. 0대: 흰 안테나 · 1대+: 흰 Android + 초록점 · critical 미해결: 주황 배지
            ZStack(alignment: .topTrailing) {
                Image(nsImage: statusIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 18)
                    .onAppear {
                        // 플로팅에서 각 창 열기 — openWindow Environment 주입 (항상 메뉴바에 존재)
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
                if store.hasActiveCritical {
                    Circle()
                        .fill(OPColor.thermal)
                        .frame(width: 7, height: 7)
                        .offset(x: 3, y: -1)
                }
            }
        }
        .menuBarExtraStyle(.window)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button(L10n.string("menubar.button.quit")) {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }

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

        Settings {
            SettingsView(store: store)
                .frame(minWidth: 560, maxWidth: 640, minHeight: 400, maxHeight: 720)
                .preferredColorScheme(theme.mode.preferred)
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

    /// 기기 0대 → Off(흰 안테나) · 1대+ → Online(흰 Android + 초록점)
    /// 다크 메뉴바용 흰색 리소스 — template 금지(색 유지)
    private var statusIcon: NSImage {
        let empty = store.inventory.devices.isEmpty
        let name = empty ? "MenuBar-Off" : "MenuBar-Online"
        guard let img = Bundle.main.image(forResource: name) else {
            return Self.fallbackIcon
        }
        img.isTemplate = false
        let displayH: CGFloat = 18
        if let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           rep.pixelsHigh > 0 {
            let displayW = max(1, displayH * CGFloat(rep.pixelsWide) / CGFloat(rep.pixelsHigh))
            img.size = NSSize(width: displayW, height: displayH)
        } else {
            img.size = NSSize(width: displayH, height: displayH)
        }
        return img
    }

    private static let fallbackIcon: NSImage = {
        guard let img = Bundle.main.image(forResource: "MenuBarTemplate") else {
            return NSImage(size: NSSize(width: 18, height: 18))
        }
        img.isTemplate = true
        img.size = NSSize(width: 18, height: 18)
        return img
    }()
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
