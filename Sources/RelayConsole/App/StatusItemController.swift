import AppKit
import SwiftUI
import Combine

/// 메뉴바 항목 수명 관리 — **`NSStatusItem` 으로 구조를 바꿨다** (PLAN_menubar_nsstatusitem).
///
/// ## 왜 `MenuBarExtra` 가 아니라 수동 `NSStatusItem` 인가
/// 1. **정렬** — SwiftUI label 단일 `Text` 로는 셀을 필드 단위로 못박을 수 없다.
///    공백 문자열 정렬은 단위 글리프 pt 폭 차이로 어긋난다(A안 실측). 이 뷰는
///    `RelayMenuBarView` 의 고정폭 `NSTextField` + 우측 정렬로 DroidRelay와 같은 렌더를 쓴다.
/// 2. **생존** — macOS 26+ 에서 시스템 설정으로 아이템이 꺼지면 `MenuBarExtra` 씬은
///    **크래시 로그 없이 프로세스가 조용히 종료**된다 (DroidRelay 실측).
///    `NSStatusItem` 은 `isVisible = false` 가 될 뿐 프로세스가 살아 있다.
///
/// ## 참조 구현
/// DroidRelay `StatusItemController` / `MenuBarSpeedView` (같은 사용자 앱 · 검증된 기하).
/// `statusItem.view` 만 성공했다 — `button` 의 title·image·서브뷰는 전부 실패(DroidRelay 5회 실측).
///
/// ## 설치와 클로저 주입은 분리다
/// `openWindow`/`openSettings` Environment 값은 **SwiftUI body 평가 시점에만** 읽힌다.
/// 설치는 `AppDelegate.didFinishLaunching`, 주입은 App body — **둘 중 어느 쪽이 먼저 와도
/// 동작하도록** 단순 저장 구조로 둔다 (`install` 은 `actions` 없어도 갱신만 하면 된다).
@MainActor
final class StatusItemController: NSObject {

    static let shared = StatusItemController()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    /// **메뉴바에 붙는 뷰 — 강한 참조로 붙든다.** 풀리면 아이콘이 조용히 사라진다.
    private var speedView: RelayMenuBarView?
    private var cancellables = Set<AnyCancellable>()

    /// SwiftUI App body 가 넘겨주는 창 열기 클로저들 — body 평가 시점에 한 번 쓰인다.
    struct Actions {
        var openConsole: () -> Void = {}
        var openDebug: () -> Void = {}
        var openSettings: () -> Void = {}
        var openProcesses: () -> Void = {}
        var openLogs: () -> Void = {}
        var openAppNetwork: () -> Void = {}
        var openFiles: () -> Void = {}
    }

    private var actions = Actions()

    private override init() { super.init() }

    // MARK: - 설치 (AppDelegate.didFinishLaunching)

    func install() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let v = RelayMenuBarView(
            onClick: { [weak self] in self?.togglePopover() },
            onRightClick: { [weak self] in self?.showContextMenu() }
        )
        item.view = v
        statusItem = item
        speedView = v

        // 갱신 트리거 — 팝오버와 무관하게 메뉴바를 갱신한다 (DroidRelay 교훈:
        // 갱신을 팝오버에 묶으면 앱 시작 시점에 `—` 로 고착된다).
        ConsoleStore.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)
        // 설정 토글(`relay.menubarSpeed/All`) — AppStorage 은 UserDefaults 에 기록
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)

        update()
    }

    /// SwiftUI App body 가 부르는 주입 — `actions` 저장 + 딥링크/플로팅 라우팅 실행.
    /// (기존 `MenuBarExtra` label `onAppear` 에 있던 클로저 주입을 그대로 옮겼다)
    func adopt(actions: Actions, bootstrap: @escaping () -> Void = {}) {
        self.actions = actions
        bootstrap()
    }

    /// 팝오버를 정상 경로(`NSPopover.close()`)로 닫는다 — `isShown` 갱신 보장.
    /// `WindowFocus.dismissMenuBarPanels()`는 팝오버 창을 건드리지 않으므로(의도적 제외),
    /// 다른 창을 열기 전에는 반드시 여기로 닫는다. 이미 닫혀 있으면 no-op.
    func closePopover() {
        if popover?.isShown == true {
            DebugLogger.shared.action("MenuBar", "팝오버 닫음 (open* 진입)")
        }
        popover?.close()
    }

    /// 팝오버에서 다른 창을 열 때 — 팝오버를 먼저 정상 close한 뒤 액션 실행.
    /// footer/deviceRow/배너의 `open*`가 전부 이 경로를 탄다.
    private func dismissAndOpen(_ action: (Actions) -> Void) {
        popover?.close()
        action(actions)
    }

    // MARK: - 갱신

    func update() {
        guard let v = speedView else { return }
        let store = ConsoleStore.shared
        let d = UserDefaults.standard
        let speedOn = d.object(forKey: "relay.menubarSpeed") as? Bool ?? true
        let showAll = d.object(forKey: "relay.menubarAll") as? Bool ?? true

        let cells = BriefingLogic.menuSpeedCells(
            devices: store.inventory.devices,
            selectedSerial: store.selectedDevice?.serial,
            showAll: showAll
        )
        let severity = BriefingLogic.maxUnresolvedSeverity(store.recentWatchEvents)
        let dot: NSColor?
        switch severity {
        case .critical: dot = NSColor(OPColor.thermal)
        case .warning: dot = NSColor(OPColor.warn)
        default: dot = nil
        }
        v.apply(
            icon: statusIcon,
            dotColor: dot,
            up: cells?.up ?? [],
            down: cells?.down ?? [],
            showSpeed: speedOn
        )
    }

    /// 기기 0대 → Off(흰 안테나) · 1대+ → Online(흰 Android + 초록점)
    /// 다크 메뉴바용 흰색 리소스 — template 금지(색 유지) [기존 로직 그대로]
    private var statusIcon: NSImage {
        // [표시②] "한 번이라도 본 기기"가 아니라 **현재 온라인인 기기**로 판정
        let online = ConsoleStore.shared.inventory.devices.contains { $0.isOnline }
        let name = online ? "MenuBar-Online" : "MenuBar-Off"
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

    // MARK: - 팝오버

    private func ensurePopover() -> NSPopover {
        if let p = popover { return p }
        let p = NSPopover()
        p.behavior = .transient          // 바깥 클릭 시 닫힘
        p.animates = true
        p.contentSize = NSSize(width: 360, height: 560)
        // 호스팅은 1회만 만든다 — 매 열기마다 교체하면 닫힌 뒤에도 이전
        // NSHostingController 가 해제되지 않고 쌓인다 (DroidRelay 동일식).
        // 내용은 공유 싱글턴(ConsoleStore 등)이므로 재생성 없이도 최신이다.
        p.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView(
                store: ConsoleStore.shared,
                openConsole: { [weak self] in self?.dismissAndOpen { $0.openConsole() } },
                openDebug: { [weak self] in self?.dismissAndOpen { $0.openDebug() } },
                openSettings: { [weak self] in self?.dismissAndOpen { $0.openSettings() } },
                openProcesses: { [weak self] in self?.dismissAndOpen { $0.openProcesses() } },
                openLogs: { [weak self] in self?.dismissAndOpen { $0.openLogs() } },
                openAppNetwork: { [weak self] in self?.dismissAndOpen { $0.openAppNetwork() } },
                openFiles: { [weak self] in self?.dismissAndOpen { $0.openFiles() } },
                onClose: { [weak self] in self?.popover?.performClose(nil) }
            )
        )
        popover = p
        return p
    }

    private func togglePopover() {
        let p = ensurePopover()
        if p.isShown {
            // stale 복구 포함 — close()는 숨겨진 유령 상태에서도 isShown을 false로 되돌린다.
            // (performClose는 이미 숨은 창에 무반응일 수 있어 영구 먹통으로 이어진다)
            p.close()
            DebugLogger.shared.action("MenuBar", "팝오버 닫음 (토글)")
            return
        }
        guard let v = speedView else { return }
        p.show(relativeTo: v.bounds, of: v, preferredEdge: .minY)
        DebugLogger.shared.action("MenuBar", "팝오버 열음")
        // 팝오버 안 컨트롤이 키보드를 받을 수 있게 활성화 (LSUIElement)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - 우클릭 메뉴

    /// `statusItem.view` 로 전환하면 `button` 은 nil — 메뉴도 뷰에서 직접 연다 (DroidRelay 동일).
    private func showContextMenu() {
        let m = NSMenu()
        m.addItem(
            withTitle: L10n.string("menubar.button.openConsole"),
            action: #selector(openConsole), keyEquivalent: ""
        ).target = self
        m.addItem(.separator())
        m.addItem(
            withTitle: L10n.string("menubar.button.quit"),
            action: #selector(quit), keyEquivalent: "q"
        ).target = self
        guard let v = speedView else { return }
        m.popUp(positioning: nil, at: NSPoint(x: 0, y: v.bounds.maxY + 4), in: v)
    }

    @objc private func openConsole() { actions.openConsole() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - 검증 (디버그)

    /// 메뉴바 뷰의 실제 기하 — 잘림 여부를 숫자로 본다.
    var debugFrames: [String] {
        guard let v = speedView else { return ["speedView: **nil — install() 이 안 돌았다**"] }
        return ["speedView ok: true"] + v.debugGeometry
    }
}
