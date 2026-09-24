import AppKit
import SwiftUI
import Combine

/// 순수 플로팅 그래프 로직 — 단위 테스트 대상
enum FloatingGraphLogic {
    struct Cards: Equatable {
        var network: Bool
        var cpu: Bool
        var gpu: Bool
        var memory: Bool
    }

    /// 카드 전부 off 방지 — Network 강제 유지 (TetherLens network always-on)
    static func resolve(
        network: Bool,
        cpu: Bool,
        gpu: Bool,
        memory: Bool
    ) -> Cards {
        let anyOn = network || cpu || gpu || memory
        if !anyOn {
            return Cards(network: true, cpu: false, gpu: false, memory: false)
        }
        return Cards(network: network, cpu: cpu, gpu: gpu, memory: memory)
    }

    /// `"x,y"` → NSPoint (실패 시 nil)
    static func parseOrigin(_ raw: String?) -> NSPoint? {
        guard let raw else { return nil }
        let parts = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2, parts[0].isFinite, parts[1].isFinite else { return nil }
        return NSPoint(x: parts[0], y: parts[1])
    }

    static func formatOrigin(_ p: NSPoint) -> String {
        "\(p.x),\(p.y)"
    }
}

/// 기기 그래프 플로팅 창 — TetherLens FloatingWindowController 패턴
/// borderless NSPanel · .nonactivatingPanel · .floating · 위치/카드 설정 유지
@MainActor
final class FloatingGraphController {
    static let shared = FloatingGraphController()

    static let windowID = WindowFocus.floatingGraphWindowID
    private static let originKey = "relay.float.origin"

    private var panel: NSPanel?
    private var moveObserver: NSObjectProtocol?
    private var dragMonitor: Any?
    private var dragPressScreen: NSPoint?
    private var dragOriginAtPress: NSPoint?
    private var dragSkippedControl = false
    private var isDragging = false

    private let store = ConsoleStore.shared
    private var storeCancellable: Any?

    var isVisible: Bool { panel?.isVisible == true }

    private init() {
        // 설정 카드 토글 변경 → 높이 재적합
        storeCancellable = store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.fitToContent()
            }
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        UserDefaults.standard.set(true, forKey: "relay.float.enabled")
        if let panel, panel.isVisible {
            panel.orderFront(nil)
            fitToContent()
            return
        }
        if panel == nil {
            createPanel()
        }
        panel?.orderFront(nil)
        fitToContent()
        DebugLogger.shared.action("FloatGraph", "플로팅 창 표시")
    }

    func hide() {
        UserDefaults.standard.set(false, forKey: "relay.float.enabled")
        guard isVisible else { return }
        panel?.orderOut(nil)
        DebugLogger.shared.action("FloatGraph", "플로팅 창 숨김")
    }

    private func createPanel() {
        let hosting = NSHostingController(
            rootView: FloatingGraphView(store: store)
        )
        let size = NSSize(width: 300, height: 200)
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var origin = FloatingGraphLogic.parseOrigin(
            UserDefaults.standard.string(forKey: Self.originKey)
        ) ?? NSPoint(
            x: screenFrame.maxX - size.width - 20,
            y: screenFrame.maxY - size.height - 48
        )
        origin.x = min(max(origin.x, screenFrame.minX), max(screenFrame.maxX - size.width, screenFrame.minX))
        origin.y = min(max(origin.y, screenFrame.minY), max(screenFrame.maxY - size.height, screenFrame.minY))

        let win = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        win.level = .floating
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.isReleasedWhenClosed = false
        win.identifier = NSUserInterfaceItemIdentifier(Self.windowID)
        win.contentViewController = hosting
        panel = win
        observeMove(win)
        installDragMonitor(for: win)
        DebugLogger.shared.action("FloatGraph", "창 생성 위치=\(origin)")
    }

    func fitToContent() {
        guard !isDragging, let panel, panel.isVisible,
              let hosting = panel.contentViewController else { return }
        hosting.view.layoutSubtreeIfNeeded()
        var h = hosting.view.fittingSize.height
        hosting.view.layoutSubtreeIfNeeded()
        h = hosting.view.fittingSize.height
        guard h > 0, h.isFinite else { return }
        h = min(max(h, 80), 480)
        guard abs(h - panel.frame.height) > 0.5 else { return }
        let screenFrame = NSScreen.main?.visibleFrame ?? panel.frame
        var origin = panel.frame.origin
        origin.y += panel.frame.height - h
        origin.x = min(max(origin.x, screenFrame.minX), max(screenFrame.maxX - panel.frame.width, screenFrame.minX))
        origin.y = min(max(origin.y, screenFrame.minY), max(screenFrame.maxY - h, screenFrame.minY))
        panel.setFrame(
            NSRect(origin: origin, size: NSSize(width: panel.frame.width, height: h)),
            display: true
        )
    }

    private func installDragMonitor(for panel: NSPanel) {
        guard dragMonitor == nil else { return }
        dragMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible else { return event }
            switch event.type {
            case .leftMouseDown:
                self.dragPressScreen = nil
                self.dragOriginAtPress = nil
                self.dragSkippedControl = false
                self.isDragging = false
                guard event.window === panel else { return event }
                if let hit = panel.contentView?.hitTest(event.locationInWindow), hit is NSControl {
                    self.dragSkippedControl = true
                } else {
                    self.dragPressScreen = NSEvent.mouseLocation
                    self.dragOriginAtPress = panel.frame.origin
                    self.isDragging = true
                }
            case .leftMouseDragged:
                guard !self.dragSkippedControl,
                      let press = self.dragPressScreen,
                      let origin = self.dragOriginAtPress else { return event }
                let cur = NSEvent.mouseLocation
                panel.setFrameOrigin(NSPoint(
                    x: origin.x + cur.x - press.x,
                    y: origin.y + cur.y - press.y
                ))
            case .leftMouseUp:
                if self.dragPressScreen != nil {
                    self.saveOrigin(panel.frame.origin)
                }
                self.dragPressScreen = nil
                self.dragOriginAtPress = nil
                self.dragSkippedControl = false
                self.isDragging = false
            default:
                break
            }
            return event
        }
    }

    private func observeMove(_ panel: NSPanel) {
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] note in
            guard let win = note.object as? NSWindow else { return }
            Task { @MainActor [weak self] in
                self?.saveOrigin(win.frame.origin)
            }
        }
    }

    private func saveOrigin(_ p: NSPoint) {
        UserDefaults.standard.set(FloatingGraphLogic.formatOrigin(p), forKey: Self.originKey)
    }

    /// Settings 토글 ↔ 패널 표시 동기화
    func setEnabled(_ enabled: Bool) {
        if enabled { show() } else { hide() }
    }
}
