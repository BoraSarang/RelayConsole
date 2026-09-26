import AppKit
import SwiftUI
import Combine

/// 순수 플로팅 그래프 로직 — 단위 테스트 대상
enum FloatingGraphLogic {
    /// 창이 표시하는 지표 단위 (한 창 = 한 지표)
    enum Metric: String, CaseIterable, Codable, Equatable, Sendable {
        case network, cpu, gpu, memory

        var l10nKey: String { "float.card.\(rawValue)" }
    }

    /// 플로팅 창 인스턴스 — (지표, 기기, 위치)
    /// `id`는 생성 시 고정이라 기기/지표를 바꿔도 위치가 보존됨
    struct FloatWin: Identifiable, Codable, Equatable, Sendable {
        let id: UUID
        var metric: Metric
        var serial: String
        var frame: String
    }

    /// 동시에 띄울 수 있는 최대 창 수
    static let maxWindows = 6
    static let windowsKey = "relay.float.windows"

    // MARK: - 창 리스트 저장

    static func decodeWins(_ raw: String?) -> [FloatWin] {
        guard let raw, let data = raw.data(using: .utf8),
              let list = try? JSONDecoder().decode([FloatWin].self, from: data) else { return [] }
        return Array(list.prefix(maxWindows))
    }

    static func encodeWins(_ wins: [FloatWin]) -> String {
        guard let data = try? JSONEncoder().encode(Array(wins.prefix(maxWindows))),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }

    /// 구버전(단일 창 `relay.float.origin` + 카드 토글 4키) → 창 리스트 1회 마이그레이션
    /// 카드 전부 off였으면 network 강제 — 기존 `resolve`와 동일한 불변식
    static func migrateWins(
        origin: String?,
        network: Bool,
        cpu: Bool,
        gpu: Bool,
        memory: Bool,
        serial: String
    ) -> [FloatWin] {
        var on: [Metric] = []
        if network { on.append(.network) }
        if cpu { on.append(.cpu) }
        if gpu { on.append(.gpu) }
        if memory { on.append(.memory) }
        if on.isEmpty { on = [.network] }
        let frame = origin ?? ""
        return on.prefix(maxWindows).map {
            FloatWin(id: UUID(), metric: $0, serial: serial, frame: frame)
        }
    }

    // MARK: - 창 조작 (순수)

    static func indexOf(id: UUID, wins: [FloatWin]) -> Int? {
        wins.firstIndex { $0.id == id }
    }

    static func isOpen(_ metric: Metric, wins: [FloatWin]) -> Bool {
        wins.contains { $0.metric == metric }
    }

    /// 창 추가 — cap 초과 시 거부(반환 false)
    @discardableResult
    static func openWindow(metric: Metric, serial: String, wins: inout [FloatWin]) -> Bool {
        guard wins.count < maxWindows else { return false }
        wins.append(FloatWin(id: UUID(), metric: metric, serial: serial, frame: ""))
        return true
    }

    /// Settings 토글 — 해당 지표 창이 있으면 전부 닫고, 없으면 1개만 생성
    @discardableResult
    static func toggleMetric(_ metric: Metric, serial: String, wins: inout [FloatWin]) -> Bool {
        if isOpen(metric, wins: wins) {
            wins.removeAll { $0.metric == metric }
            return false
        }
        return openWindow(metric: metric, serial: serial, wins: &wins)
    }

    static func closeWindow(id: UUID, wins: inout [FloatWin]) {
        wins.removeAll { $0.id == id }
    }

    /// 지표 전환 — id·frame 유지
    static func setMetric(id: UUID, metric: Metric, wins: inout [FloatWin]) {
        guard let i = indexOf(id: id, wins: wins) else { return }
        wins[i].metric = metric
    }

    /// 기기 전환(창 전용) — 전역 선택은 건드리지 않음
    static func setSerial(id: UUID, serial: String, wins: inout [FloatWin]) {
        guard let i = indexOf(id: id, wins: wins) else { return }
        wins[i].serial = serial
    }

    static func setFrame(id: UUID, frame: String, wins: inout [FloatWin]) {
        guard let i = indexOf(id: id, wins: wins) else { return }
        wins[i].frame = frame
    }

    // MARK: - 위치

    /// 세로 정렬 — 좌상단에서 시작해 열(column) 단위로 채우고 넘치면 옆 열로
    static func arrange(wins: inout [FloatWin], in area: NSRect, gap: CGFloat = 10) {
        guard !wins.isEmpty else { return }
        let inset: CGFloat = 16
        var x = area.minX + inset
        var y = area.maxY
        var columnWidth: CGFloat = 0
        for i in wins.indices {
            let size = parseFrame(wins[i].frame)?.size ?? NSSize(width: 300, height: 200)
            if y - size.height < area.minY + inset {
                // 현재 열이 꽉 참 → 다음 열
                x += columnWidth + gap
                y = area.maxY
                columnWidth = 0
            }
            y -= size.height
            let clamped = clampTopLeft(
                NSPoint(x: x, y: max(y, area.minY + size.height)),
                size: size,
                in: area
            )
            wins[i].frame = formatFrame(topLeft: clamped, size: size)
            y -= gap
            columnWidth = max(columnWidth, size.width)
        }
    }

    /// 새 창 위치 — 기존 창과 겹치면 아래로(불가하면 오른쪽으로) 밀어 배치
    static func cascadeTopLeft(
        _ p: NSPoint,
        size: NSSize,
        occupied: [NSRect],
        in area: NSRect
    ) -> NSPoint {
        var candidate = clampTopLeft(p, size: size, in: area)
        for _ in 0..<maxWindows {
            let rect = NSRect(origin: bottomLeft(fromTopLeft: candidate, height: size.height), size: size)
            if !occupied.contains(where: { $0.intersects(rect) }) { return candidate }
            var next = candidate
            next.y -= (size.height + 12)
            if clampTopLeft(next, size: size, in: area) == next {
                candidate = next
            } else {
                next = candidate
                next.x += 28
                candidate = clampTopLeft(next, size: size, in: area)
            }
        }
        return candidate
    }

    // MARK: - 기존 프레임 로직 (하위호환 유지)

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

    /// `"x,y"` (구버전) 또는 `"x,y,w,h"` → (좌상단, 크기). 실패 시 nil
    static func parseFrame(_ raw: String?) -> (topLeft: NSPoint, size: NSSize)? {
        guard let raw else { return nil }
        let parts = raw.split(separator: ",")
            .map { Double($0.trimmingCharacters(in: .whitespaces)) }
            .compactMap { $0 }
        guard parts.count >= 2, parts[0].isFinite, parts[1].isFinite else { return nil }
        let size = parts.count >= 4 && parts[2].isFinite && parts[3].isFinite
            && parts[2] > 0 && parts[3] > 0
            ? NSSize(width: parts[2], height: parts[3])
            : NSSize(width: 300, height: 200)
        return (NSPoint(x: parts[0], y: parts[1]), size)
    }

    /// 저장 포맷 = 왼쪽 위 꼭지점 + 크기 (스케일/해상도 변경 시 복원 정확도)
    static func formatFrame(topLeft: NSPoint, size: NSSize) -> String {
        "\(topLeft.x),\(topLeft.y),\(size.width),\(size.height)"
    }

    /// 점을 포함하는 화면 visibleFrame — 해당 없으면 메인(없으면 1440×900)
    static func screenFrame(
        containing point: NSPoint,
        screens: [NSScreen] = NSScreen.screens
    ) -> NSRect {
        for s in screens {
            let f = s.visibleFrame
            if point.x >= f.minX && point.x <= f.maxX
                && point.y >= f.minY && point.y <= f.maxY {
                return f
            }
        }
        return NSScreen.main?.visibleFrame
            ?? screens.first?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// 전체 화면 frame 합집합 — 드래그 시 창이 소실 영역으로 벗어나지 않도록
    static func unionFrame(screens: [NSScreen] = NSScreen.screens) -> NSRect {
        guard let first = screens.first else {
            return NSRect(x: 0, y: 0, width: 1440, height: 900)
        }
        var r = first.frame
        for s in screens.dropFirst() { r = r.union(s.frame) }
        return r
    }

    /// 드래그 원점 clamp — 창 전체가 합집합 화면 안에 들어오도록
    static func clampOrigin(_ p: NSPoint, size: NSSize, in screen: NSRect) -> NSPoint {
        NSPoint(
            x: min(max(p.x, screen.minX), max(screen.maxX - size.width, screen.minX)),
            y: min(max(p.y, screen.minY), max(screen.maxY - size.height, screen.minY))
        )
    }

    static func originKey() -> String { "relay.float.origin" }

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
/// borderless NSPanel · .nonactivatingPanel · .floating
/// 한 창 = 한 지표, (지표 × 기기) 인스턴스를 여러 개 동시에 띄울 수 있음
@MainActor
final class FloatingGraphController: ObservableObject {
    static let shared = FloatingGraphController()

    static let windowID = WindowFocus.floatingGraphWindowID
    private static let originKey = "relay.float.origin"
    static let enabledKey = "relay.float.enabled"

    typealias Metric = FloatingGraphLogic.Metric
    typealias FloatWin = FloatingGraphLogic.FloatWin

    /// 창 id → 패널
    private var panels: [UUID: NSPanel] = [:]
    /// 창 id → 마지막으로 호스팅한 콘텐츠 (metric/serial 비교용)
    private var hosted: [UUID: FloatWin] = [:]
    private var moveObservers: [UUID: NSObjectProtocol] = [:]
    private var dragMonitor: Any?
    private var dragPressScreen: NSPoint?
    private var dragOriginAtPress: NSPoint?
    private var dragSkippedControl = false
    private var isDragging = false

    private let store = ConsoleStore.shared
    private var storeCancellable: Any?

    /// On/Off 단일 진실원천 — Settings 토글·메뉴바 버튼·창 X 모두 이 값으로 동기화
    @Published private(set) var isEnabled: Bool =
        UserDefaults.standard.bool(forKey: FloatingGraphController.enabledKey)

    /// 열려 있는 창 리스트 — 단일 진실원처 (Settings 토글·창 UI 공통)
    @Published private(set) var wins: [FloatWin] = []

    /// App 라벨 onAppear에서 주입 — 플로팅에서 프로세스 창 열기 (openWindow Environment 재사용)
    var openProcesses: (() -> Void)?
    /// 플로팅에서 앱 네트워크 창 열기
    var openAppNetwork: (() -> Void)?
    /// 플로팅에서 대시보드(콘솔) 창 열기
    var openConsole: (() -> Void)?

    /// 하나라도 보이면 On으로 간주
    var isVisible: Bool { panels.values.contains { $0.isVisible } }

    var isAtCapacity: Bool { wins.count >= FloatingGraphLogic.maxWindows }

    private init() {
        wins = Self.loadWins()
        installDragMonitor()
        // 콘텐츠 높이 변화(수집 직후 카드 늘어남 등) → 디바운스 재적합
        // (구버전: store 변경마다 즉시 fit 2회 layout → 레이아웃 폭주)
        // 카드(FloatingGraphView) 가 실제로 읽는 값은 `inventory` 와 `metricsHistory` 뿐이다.
        // 종전엔 `store.objectWillChange`(관측 가능 프로퍼티 57개 전부)를 구독해서
        // 5초 폴링마다 fitAll() 이 돌았다. 알림 테스트 결과나 선택 기기 변경처럼
        // 카드와 무관한 변경에도 강제 레이아웃이 발생했다 → 필요한 신호만 구독한다.
        storeCancellable = Publishers.Merge(
            store.$inventory.map { _ in () },
            store.$metricsHistory.map { _ in () }
        )
        .receive(on: DispatchQueue.main)
        .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.fitAll()
        }
    }

    // MARK: - 저장/마이그레이션

    private static func boolDefault(_ key: String, _ fallback: Bool) -> Bool {
        let d = UserDefaults.standard
        return d.object(forKey: key) == nil ? fallback : d.bool(forKey: key)
    }

    private static func loadWins() -> [FloatWin] {
        let d = UserDefaults.standard
        let key = FloatingGraphLogic.windowsKey
        if d.object(forKey: key) != nil {
            return FloatingGraphLogic.decodeWins(d.string(forKey: key))
        }
        // 1회 마이그레이션 — 기존 단일 창 프레임 + 카드 토글 4키
        let migrated = FloatingGraphLogic.migrateWins(
            origin: d.string(forKey: originKey),
            network: boolDefault("relay.float.showNetwork", true),
            cpu: boolDefault("relay.float.showCPU", true),
            gpu: boolDefault("relay.float.showGPU", false),
            memory: boolDefault("relay.float.showMemory", false),
            serial: d.string(forKey: "relay.selectedSerial") ?? ""
        )
        d.set(FloatingGraphLogic.encodeWins(migrated), forKey: key)
        return migrated
    }

    private func persistWins() {
        UserDefaults.standard.set(FloatingGraphLogic.encodeWins(wins), forKey: FloatingGraphLogic.windowsKey)
    }

    // MARK: - 표시/숨김

    func toggle() {
        if isVisible { hide() } else { show() }
        // 토글 직후 메뉴바 팝오버가 플로팅을 가림 — 팝오버 닫기(플로팅은 제외 대상)
        WindowFocus.dismissMenuBarPanels()
    }

    func show() {
        setEnabledFlag(true)
        if wins.isEmpty {
            FloatingGraphLogic.openWindow(metric: .network, serial: defaultSerial(), wins: &wins)
            persistWins()
        }
        syncPanels()
        DebugLogger.shared.action("FloatGraph", "플로팅 창 표시 (\(wins.count)개)")
    }

    func hide() {
        setEnabledFlag(false)
        for (id, panel) in panels where panel.isVisible {
            persistFrame(id: id, frame: panel.frame)
            panel.orderOut(nil)
        }
        DebugLogger.shared.action("FloatGraph", "플로팅 창 숨김")
    }

    /// 재기동 복원 — enabled가 true일 때만 패널 재생성
    func restoreAll() {
        guard isEnabled else { return }
        if wins.isEmpty {
            FloatingGraphLogic.openWindow(metric: .network, serial: defaultSerial(), wins: &wins)
            persistWins()
        }
        syncPanels()
    }

    /// 단일 진실원천 갱신 — 플리시 값과 UserDefaults를 한 곳에서만 기록
    private func setEnabledFlag(_ value: Bool) {
        if isEnabled != value { isEnabled = value }
        UserDefaults.standard.set(value, forKey: Self.enabledKey)
    }

    /// 앱 종료 직전 전 창 프레임 저장 (didMove 없이 종료해도 위치 유지)
    func persistPosition() {
        for (id, panel) in panels {
            persistFrame(id: id, frame: panel.frame)
        }
    }

    // MARK: - 창 조작

    /// 새 창 추가 (cap 초과 시 거부)
    func openWindow(metric: Metric, serial: String? = nil) {
        guard FloatingGraphLogic.openWindow(
            metric: metric,
            serial: serial ?? defaultSerial(),
            wins: &wins
        ) else {
            DebugLogger.shared.warn("FloatGraph", "[WARN] 창 최대 \(FloatingGraphLogic.maxWindows)개 도달")
            return
        }
        persistWins()
        if !isEnabled { setEnabledFlag(true) }
        syncPanels()
    }

    /// 창 닫기 — 마지막 창이 닫히면 On/Off도 off로
    func closeWindow(id: UUID) {
        var list = wins
        FloatingGraphLogic.closeWindow(id: id, wins: &list)
        guard list.count != wins.count else { return }
        wins = list
        persistWins()
        syncPanels()
        if wins.isEmpty { setEnabledFlag(false) }
    }

    /// Settings 카드 토글 ↔ 창 열림/닫힘
    func setMetricOpen(_ metric: Metric, _ open: Bool) {
        var list = wins
        if open {
            guard !FloatingGraphLogic.isOpen(metric, wins: list) else { return }
            guard FloatingGraphLogic.openWindow(
                metric: metric, serial: defaultSerial(), wins: &list
            ) else {
                DebugLogger.shared.warn("FloatGraph", "[WARN] 창 최대 \(FloatingGraphLogic.maxWindows)개 도달")
                return
            }
        } else {
            list.removeAll { $0.metric == metric }
        }
        wins = list
        persistWins()
        if open, !isEnabled { setEnabledFlag(true) }
        if list.isEmpty { setEnabledFlag(false); return }
        syncPanels()
    }

    func setMetric(id: UUID, metric: Metric) {
        var list = wins
        FloatingGraphLogic.setMetric(id: id, metric: metric, wins: &list)
        guard list != wins else { return }
        wins = list
        persistWins()
        syncPanels()
    }

    func setSerial(id: UUID, serial: String) {
        var list = wins
        FloatingGraphLogic.setSerial(id: id, serial: serial, wins: &list)
        guard list != wins else { return }
        wins = list
        persistWins()
        syncPanels()
    }

    /// 세로 정렬 — wins 프레임 갱신 후 패널에 반영
    func arrange() {
        var list = wins
        FloatingGraphLogic.arrange(wins: &list, in: Self.visibleUnion())
        guard list != wins else { return }
        wins = list
        persistWins()
        applyFrames()
    }

    private static func visibleUnion() -> NSRect {
        let frames = NSScreen.screens.map(\.visibleFrame)
        guard let first = frames.first else {
            return NSRect(x: 0, y: 0, width: 1440, height: 900)
        }
        return frames.dropFirst().reduce(first) { $0.union($1) }
    }

    private func defaultSerial() -> String {
        store.selectedDevice?.serial ?? ""
    }

    // MARK: - 외부 창 열기

    func requestOpenProcesses() {
        guard let openProcesses else {
            DebugLogger.shared.warn("FloatGraph", "[WARN] openProcesses 미주입 — App 라벨 onAppear 미호출")
            return
        }
        // LSUIElement + .nonactivatingPanel — 미활성 상태에선 openWindow가 조용히 무시됨
        NSApp.activate(ignoringOtherApps: true)
        openProcesses()
    }

    func requestOpenAppNetwork() {
        guard let openAppNetwork else {
            requestOpenProcesses()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        openAppNetwork()
    }

    func requestOpenConsole() {
        guard let openConsole else {
            DebugLogger.shared.warn("FloatGraph", "[WARN] openConsole 미주입 — App 라벨 onAppear 미호출")
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        openConsole()
    }

    /// Settings 슬라이더 / AppStorage → clamp 후 defaults 기록 (뷰 배경 fill이 투명도 반영)
    func setOpacity(_ raw: Double) {
        let v = FloatingGraphLogic.clampOpacity(raw)
        UserDefaults.standard.set(v, forKey: FloatingGraphLogic.opacityKey)
    }

    // MARK: - 패널 동기화

    private func syncPanels() {
        for win in wins {
            if let panel = panels[win.id] {
                let contentChanged = hosted[win.id].map {
                    $0.metric != win.metric || $0.serial != win.serial
                } ?? true
                if contentChanged {
                    // 지표/기기 전환 — 호스팅만 교체(위치·패널 유지)
                    panel.contentViewController = makeHosting(for: win)
                    hosted[win.id] = win
                    if isEnabled, !panel.isVisible { panel.orderFront(nil) }
                    fitToContent(id: win.id)
                } else if isEnabled, !panel.isVisible {
                    panel.orderFront(nil)
                }
            } else {
                createPanel(for: win)
            }
        }
        for (id, panel) in panels where !wins.contains(where: { $0.id == id }) {
            panel.orderOut(nil)
            teardown(id: id)
        }
    }

    private func makeHosting(for win: FloatWin) -> NSHostingController<FloatingGraphView> {
        NSHostingController(
            rootView: FloatingGraphView(
                store: store,
                win: win,
                onOpenProcesses: { [weak self] in
                    self?.requestOpenProcesses()
                },
                onOpenAppNetwork: { [weak self] in
                    self?.requestOpenAppNetwork()
                },
                onOpenConsole: { [weak self] in
                    self?.requestOpenConsole()
                }
            )
        )
    }

    private func createPanel(for win: FloatWin) {
        let hosting = makeHosting(for: win)
        let defaultSize = NSSize(width: 300, height: 200)
        // 저장값 = (좌상단, 크기) — 구버전 "x,y"도 하위호환. 화면 역조회로 소실 방지
        let stored = FloatingGraphLogic.parseFrame(win.frame)
        let savedTopLeft = stored?.topLeft
        let savedSize = stored?.size ?? defaultSize
        let screenFrame = FloatingGraphLogic.screenFrame(
            containing: savedTopLeft ?? NSPoint(x: 0, y: CGFloat.greatestFiniteMagnitude)
        )
        let desiredTopLeft = savedTopLeft ?? NSPoint(
            x: screenFrame.minX + 20,
            y: screenFrame.maxY - 48
        )
        // 이미 떠 있는 창과 겹치지 않도록 캐스케이드
        let topLeft = FloatingGraphLogic.cascadeTopLeft(
            desiredTopLeft,
            size: savedSize,
            occupied: panels.values.map(\.frame),
            in: screenFrame
        )
        let origin = FloatingGraphLogic.bottomLeft(fromTopLeft: topLeft, height: savedSize.height)

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: savedSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // 투명 배경 + 그림자 이슈 방지 (TetherLens 동일)
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        // 식별자에 창 id 접미 — WindowFocus가 접두로 전체를 팝오버 닫힘 대상에서 제외
        panel.identifier = NSUserInterfaceItemIdentifier("\(Self.windowID).\(win.id.uuidString)")
        panel.contentViewController = hosting
        panels[win.id] = panel
        hosted[win.id] = win
        // 생성 직후 content 크기 반영 전 frame을 못 맞추면 maxY가 깨져 저장됨 — 의도한 좌상단으로 고정
        panel.setFrame(NSRect(origin: origin, size: savedSize), display: false)
        observeMove(id: win.id, panel: panel)
        DebugLogger.shared.action("FloatGraph", "창 생성 metric=\(win.metric.rawValue) 위치=\(origin)")
        fitToContent(id: win.id)
    }

    private func teardown(id: UUID) {
        if let token = moveObservers.removeValue(forKey: id) {
            NotificationCenter.default.removeObserver(token)
        }
        panels.removeValue(forKey: id)
        hosted.removeValue(forKey: id)
    }

    // MARK: - 높이 재적합

    private func fitAll() {
        guard !isDragging else { return }
        for id in panels.keys { fitToContent(id: id) }
    }

    func fitToContent(id: UUID) {
        guard !isDragging, let panel = panels[id], panel.isVisible,
              let hosting = panel.contentViewController else { return }
        hosting.view.layoutSubtreeIfNeeded()
        var h = hosting.view.fittingSize.height
        hosting.view.layoutSubtreeIfNeeded()
        h = hosting.view.fittingSize.height
        guard h > 0, h.isFinite else { return }
        // 한 창 = 한 카드 — 상한은 카드 1장 + 여유로 설정
        h = min(max(h, 80), 560)
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
        persistFrame(id: id, frame: panel.frame)
    }

    // MARK: - 드래그

    private func installDragMonitor() {
        guard dragMonitor == nil else { return }
        dragMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            guard let self else { return event }
            let panel = event.window as? NSPanel
            switch event.type {
            case .leftMouseDown:
                self.dragPressScreen = nil
                self.dragOriginAtPress = nil
                self.dragSkippedControl = false
                self.isDragging = false
                guard let panel, self.isFloatPanel(panel) else { return event }
                if let hit = panel.contentView?.hitTest(event.locationInWindow), hit is NSControl {
                    self.dragSkippedControl = true
                } else {
                    self.dragPressScreen = NSEvent.mouseLocation
                    self.dragOriginAtPress = panel.frame.origin
                    self.isDragging = true
                }
            case .leftMouseDragged:
                guard !self.dragSkippedControl,
                      let panel, self.isFloatPanel(panel),
                      let press = self.dragPressScreen,
                      let origin = self.dragOriginAtPress else { return event }
                let cur = NSEvent.mouseLocation
                let raw = NSPoint(
                    x: origin.x + cur.x - press.x,
                    y: origin.y + cur.y - press.y
                )
                // 화면 밖으로 빠져 위치 소실 방지 — 전체 화면 합집합 안에서 clamp
                let clamped = FloatingGraphLogic.clampOrigin(
                    raw,
                    size: panel.frame.size,
                    in: FloatingGraphLogic.unionFrame()
                )
                panel.setFrameOrigin(clamped)
            case .leftMouseUp:
                // 실제 드래그를 시도했는지를 먼저 기록한다
                let didDragOnPanel = self.dragPressScreen != nil
                if self.dragPressScreen != nil, let panel, self.isFloatPanel(panel),
                   let dragID = self.id(of: panel) {
                    self.persistFrame(id: dragID, frame: panel.frame)
                }
                self.dragPressScreen = nil
                self.dragOriginAtPress = nil
                self.dragSkippedControl = false
                self.isDragging = false
                // [표시②]/성능 — 종전엔 **앱 내 모든 마우스 클릭**에서 무조건 fitAll() 이 돌았다.
                // fitAll 은 창마다 layoutSubtreeIfNeeded 2회 + fittingSize 2회 + setFrame(display:true)
                // → 플로팅 그래프를 켜둔 사용자는 클릭 1회당 최대 6창 × 4회 강제 레이아웃을 치른다.
                // 실제로 플로팅 패널을 드래그한 경우에만 높이를 다시 재적합한다.
                if didDragOnPanel {
                    self.fitAll()
                }
            default:
                break
            }
            return event
        }
    }

    private func isFloatPanel(_ panel: NSPanel) -> Bool {
        panels.values.contains { $0 === panel }
    }

    private func id(of panel: NSPanel) -> UUID? {
        panels.first { $0.value === panel }?.key
    }

    private func observeMove(id: UUID, panel: NSPanel) {
        let token = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] note in
            guard let win = note.object as? NSWindow else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                // 드래그 중에는 매 프레임 갱신하지 않음 — mouseUp에서 1회 기록
                guard !self.isDragging else { return }
                self.persistFrame(id: id, frame: win.frame)
            }
        }
        moveObservers[id] = token
    }

    private func persistFrame(id: UUID, frame: NSRect) {
        guard FloatingGraphLogic.isSavableFrame(frame) else { return }
        let str = FloatingGraphLogic.formatFrame(
            topLeft: FloatingGraphLogic.topLeft(of: frame),
            size: frame.size
        )
        guard let i = FloatingGraphLogic.indexOf(id: id, wins: wins), wins[i].frame != str else { return }
        wins[i].frame = str
        persistWins()
    }

    /// 기존 프레임 그대로 패널에 적용 (arrange 직후)
    private func applyFrames() {
        for win in wins {
            guard let panel = panels[win.id],
                  let stored = FloatingGraphLogic.parseFrame(win.frame) else { continue }
            let screenFrame = FloatingGraphLogic.screenFrame(containing: stored.topLeft)
            let tl = FloatingGraphLogic.clampTopLeft(stored.topLeft, size: stored.size, in: screenFrame)
            let origin = FloatingGraphLogic.bottomLeft(fromTopLeft: tl, height: stored.size.height)
            panel.setFrame(NSRect(origin: origin, size: stored.size), display: true)
        }
    }

    /// Settings 토글 ↔ 패널 표시 동기화 — isEnabled가 단일 진실원천
    func setEnabled(_ enabled: Bool) {
        if enabled { show() } else { hide() }
    }
}
