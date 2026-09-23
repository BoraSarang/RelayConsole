import SwiftUI
import AppKit

@main
struct RelayConsoleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ConsoleStore.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView(store: store, openConsole: {
                openConsole()
            }, openDebug: {
                openDebug()
            })
            .frame(width: 360, height: 560)
            .preferredColorScheme(.dark)
            .background(Color(hex: 0x0F111A)) // SOLID — V0-2: no material/glass
        } label: {
            HStack(spacing: 4) {
                Image(nsImage: Self.menuBarIcon)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 16)
                Text(menuTitle)
                    .font(OPFont.number(12))
            }
        }
        .menuBarExtraStyle(.window)
        .windowResizability(.contentSize)

        Window("Relay Console · 외부 관제 콘솔", id: "console") {
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
        Window("디버그", id: "debug") {
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
                Button("디버그") { openWindow(id: "debug") }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }
#else
        EmptyScene()
#endif
    }

    private func openConsole() {
        openWindow(id: "console")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openDebug() {
#if DEBUG
        openWindow(id: "debug")
        NSApp.activate(ignoringOtherApps: true)
#endif
    }

    private var menuTitle: String {
        let online = store.inventory.devices.filter(\.isOnline).count
        if store.inventory.devices.isEmpty { return "Relay" }
        return "Relay \(online)/\(store.inventory.devices.count)"
    }

    /// Black_Template_22 — must be template (not White preview)
    private static let menuBarIcon: NSImage = {
        guard let img = Bundle.main.image(forResource: "MenuBarTemplate") else {
            return NSImage(size: NSSize(width: 16, height: 16))
        }
        img.isTemplate = true
        img.size = NSSize(width: 44, height: 16)
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
