import SwiftUI
import AppKit

@main
struct RelayConsoleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ConsoleStore.shared
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
            })
            .frame(width: 360, height: 560)
            .preferredColorScheme(.dark)
            .background(Color(hex: 0x0F111A)) // SOLID — V0-2: no material/glass
        }         label: {
            // 아이콘만 — 텍스트 없음. 0대: 흰 안테나 · 1대+: 흰 Android + 초록점 · critical 미해결: 주황 배지
            ZStack(alignment: .topTrailing) {
                Image(nsImage: statusIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 18)
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

        Window(L10n.string("droid.header.title"), id: "console") {
            ZStack {
                Color(hex: 0x0F111A).ignoresSafeArea()
                ConsoleView(store: store)
            }
            .frame(minWidth: 760, minHeight: 520)
            .preferredColorScheme(.dark)
            .background(Color(hex: 0x0F111A))
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 700)

        Window(L10n.string("droid.process.titleShort"), id: "processes") {
            ZStack {
                Color(hex: 0x0F111A).ignoresSafeArea()
                ProcessListWindowView(store: store)
            }
            .frame(minWidth: 560, minHeight: 480)
            .preferredColorScheme(.dark)
            .background(Color(hex: 0x0F111A))
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 640, height: 520)

        Settings {
            ZStack {
                Color(hex: 0x0F111A).ignoresSafeArea()
                SettingsView(store: store)
            }
            .frame(minWidth: 420, minHeight: 280)
            .preferredColorScheme(.dark)
            .background(Color(hex: 0x0F111A))
        }

        debugScenes
    }

    @SceneBuilder
    private var debugScenes: some Scene {
#if DEBUG
        Window(L10n.string("ui.debug.title"), id: "debug") {
            ZStack {
                Color(hex: 0x0F111A).ignoresSafeArea()
                DebugPanelView()
            }
            .frame(minWidth: 560, minHeight: 400)
            .preferredColorScheme(.dark)
            .background(Color(hex: 0x0F111A))
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
        WindowFocus.dismissMenuBarPanels()
        openWindow(id: "console")
        WindowFocus.present(sceneID: "console")
    }

    private func openDebug() {
#if DEBUG
        WindowFocus.dismissMenuBarPanels()
        openWindow(id: "debug")
        WindowFocus.present(sceneID: "debug")
#endif
    }

    private func openSettingsWindow() {
        WindowFocus.dismissMenuBarPanels()
        openSettings()
        WindowFocus.presentSettings()
    }

    private func openProcesses() {
        WindowFocus.dismissMenuBarPanels()
        openWindow(id: "processes")
        WindowFocus.present(sceneID: "processes")
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
