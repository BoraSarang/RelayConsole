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

    /// frame이 유한한 크기인지 (저장 전 가드)
    static func isSavableFrame(_ frame: NSRect) -> Bool {
        frame.height >= 80
            && frame.width > 0
            && frame.origin.x.isFinite
            && frame.origin.y.isFinite
            && frame.width.isFinite
            && frame.height.isFinite
    }

    /// 저장 기준 = 왼쪽 위 꼭지점 1점 (fitToContent 상단 고정과 동일 기준)
    static func topLeft(of frame: NSRect) -> NSPoint {
        NSPoint(x: frame.minX, y: frame.maxY)
    }

    static func bottomLeft(fromTopLeft topLeft: NSPoint, height: CGFloat) -> NSPoint {
        NSPoint(x: topLeft.x, y: topLeft.y - height)
    }

    /// 화면 visibleFrame 안에 상단-좌표 창이 완전히 들어오도록 clamp
    static func clampTopLeft(_ p: NSPoint, size: NSSize, in screen: NSRect) -> NSPoint {
        NSPoint(
            x: min(max(p.x, screen.minX), max(screen.maxX - size.width, screen.minX)),
            y: min(max(p.y, screen.minY + size.height), screen.maxY)
        )
    }

    static let opacityKey = "relay.float.opacity"
    static let minOpacity = 0.35
    static let maxOpacity = 1.0
    static let defaultOpacity = 1.0

    /// 패널 투명도 clamp — 비정상 값은 기본(1.0)
    static func clampOpacity(_ raw: Double) -> Double {
        guard raw.isFinite else { return defaultOpacity }
        return min(max(raw, minOpacity), maxOpacity)
    }

    static func storedOpacity(_ defaults: UserDefaults = .standard) -> Double {
        clampOpacity(defaults.object(forKey: opacityKey) as? Double ?? defaultOpacity)
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

    /// App 라벨 onAppear에서 주입 — 플로팅에서 프로세스 창 열기 (openWindow Environment 재사용)
    var openProcesses: (() -> Void)?

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
        guard let panel, panel.isVisible else { return }
        // 위치 저장 — 재오픈/재시작 시 복원 (이슈 4)
        saveOrigin(panel.frame)
        panel.orderOut(nil)
        DebugLogger.shared.action("FloatGraph", "플로팅 창 숨김")
    }

    /// 앱 종료 직전 현재 프레임 저장 (didMove 없이 종료해도 위치 유지)
    func persistPosition() {
        guard let panel else { return }
        saveOrigin(panel.frame)
    }

    func requestOpenProcesses() {
        openProcesses?()
    }

    private func createPanel() {
        let hosting = NSHostingController(
            rootView: FloatingGraphView(
                store: store,
                onOpenProcesses: { [weak self] in
                    self?.requestOpenProcesses()
                }
            )
        )
        let size = NSSize(width: 300, height: 200)
        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        // 저장값 = 왼쪽 위 꼭지점 1점 — 없으면 좌상단 고정 (오른쪽 기본값 금지)
        let savedTopLeft = FloatingGraphLogic.parseOrigin(
            UserDefaults.standard.string(forKey: Self.originKey)
        )
        let topLeft = FloatingGraphLogic.clampTopLeft(
            savedTopLeft ?? NSPoint(
                x: screenFrame.minX + 20,
                y: screenFrame.maxY - 48
            ),
            size: size,
            in: screenFrame
        )
        let origin = FloatingGraphLogic.bottomLeft(fromTopLeft: topLeft, height: size.height)

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
        // 투명 배경 + 그림자 이슈 방지 (TetherLens 동일)
        win.hasShadow = false
        win.isReleasedWhenClosed = false
        win.identifier = NSUserInterfaceItemIdentifier(Self.windowID)
        win.contentViewController = hosting
        panel = win
        // 생성 직후 content 크기 반영 전 frame을 못 맞추면 maxY가 깨져 저장됨 — 의도한 좌상단으로 고정
        win.setFrame(NSRect(origin: origin, size: size), display: false)
        observeMove(win)
        installDragMonitor(for: win)
        DebugLogger.shared.action("FloatGraph", "창 생성 위치=\(origin)")
    }

    /// Settings 슬라이더 / AppStorage → clamp 후 defaults 기록 (뷰 배경 fill이 투명도 반영)
    func setOpacity(_ raw: Double) {
        let v = FloatingGraphLogic.clampOpacity(raw)
        UserDefaults.standard.set(v, forKey: FloatingGraphLogic.opacityKey)
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
        let screenFrame = (panel.screen ?? NSScreen.main)?.visibleFrame ?? panel.frame
        var origin = panel.frame.origin
        origin.y += panel.frame.height - h
        origin.x = min(max(origin.x, screenFrame.minX), max(screenFrame.maxX - panel.frame.width, screenFrame.minX))
        origin.y = min(max(origin.y, screenFrame.minY), max(screenFrame.maxY - h, screenFrame.minY))
        panel.setFrame(
            NSRect(origin: origin, size: NSSize(width: panel.frame.width, height: h)),
            display: true
        )
        saveOrigin(panel.frame)
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
                    self.saveOrigin(panel.frame)
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
                self?.saveOrigin(win.frame)
            }
        }
    }

    private func saveOrigin(_ frame: NSRect) {
        guard FloatingGraphLogic.isSavableFrame(frame) else { return }
        let topLeft = FloatingGraphLogic.topLeft(of: frame)
        UserDefaults.standard.set(FloatingGraphLogic.formatOrigin(topLeft), forKey: Self.originKey)
    }

    /// Settings 토글 ↔ 패널 표시 동기화
    func setEnabled(_ enabled: Bool) {
        if enabled { show() } else { hide() }
    }
}
