import AppKit

/// LSUIElement(메뉴바) 앱 — 창을 뒤로 숨기지 않고 앞으로 가져오는 유틸
@MainActor
enum WindowFocus {
    /// 알림 배너 패널 ID — 메뉴 팝오버 닫기 대상에서 제외
    static let alertBannerWindowID = "RelayAlertBanner"
    /// 기기 그래프 플로팅 ID — 메뉴 팝오버 닫기 대상에서 제외
    static let floatingGraphWindowID = "RelayFloatingGraph"

    private static var savedFrontOrder: [ObjectIdentifier] = []
    private static var popoverWasOpen = false

    /// 메뉴바 팝오버 패널(상태바 레벨) 닫기 — 알림 배너·플로팅 그래프는 제외
    static func dismissMenuBarPanels() {
        for window in NSApp.windows {
            guard let panel = window as? NSPanel else { continue }
            if panel.identifier?.rawValue == alertBannerWindowID { continue }
            if panel.identifier?.rawValue == floatingGraphWindowID { continue }
            if panel.level == .statusBar || panel.level == .popUpMenu {
                panel.perform(#selector(NSWindow.orderOut(_:)), with: nil)
            }
        }
    }

    /// 메뉴바 팝오버 열림 — LSUIElement는 activate가 자주 누락되어
    /// 일반 창이 다른 앱 뒤로 내려감. 앱을 활성화하고 앱 내 창 순서 복원.
    static func menuBarPopoverDidOpen() {
        let regular: [NSWindow] = NSApp.windows.filter { w in
            w.isVisible && !(w is NSPanel) && w.canBecomeKey
        }
        savedFrontOrder = regular
            .sorted(by: { (a: NSWindow, b: NSWindow) in a.windowNumber < b.windowNumber })
            .map { (w: NSWindow) -> ObjectIdentifier in ObjectIdentifier(w) }

        NSApp.activate(ignoringOtherApps: true)
        popoverWasOpen = true

        for id in savedFrontOrder {
            guard let w = NSApp.windows.first(where: { ObjectIdentifier($0) == id }) else { continue }
            w.orderFrontRegardless()
        }
    }

    /// 팝오버가 닫힌 뒤 — 앱이 아직 active면 창을 다시 앞으로
    /// (다른 앱으로 포커스 이동 시에는 개입하지 않음)
    static func menuBarPopoverDidClose() {
        guard popoverWasOpen else { return }
        popoverWasOpen = false
        // 패널 사라진 뒤 한 틱 대기 — SwiftUI panel orderOut 타이밍
        DispatchQueue.main.async {
            guard NSApp.isActive else { return }
            for id in savedFrontOrder {
                guard let w = NSApp.windows.first(where: { ObjectIdentifier($0) == id }),
                      w.isVisible, !(w is NSPanel) else { continue }
                w.orderFrontRegardless()
            }
            savedFrontOrder = []
        }
    }

    /// 앱 활성화 + 메뉴바 패널 닫기 + 지정 조건 창 앞으로
    static func present(matching predicate: @escaping (NSWindow) -> Bool) {
        NSApp.activate(ignoringOtherApps: true)
        dismissMenuBarPanels()
        DispatchQueue.main.async {
            if Self.front(matching: predicate) { return }
            // 씬 생성 지연 — 한 번 재시도
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                if Self.front(matching: predicate) { return }
                let candidates = NSApp.windows.filter {
                    $0.canBecomeKey && !($0 is NSPanel) && $0.isVisible
                }
                candidates.last?.makeKeyAndOrderFront(nil)
                candidates.last?.orderFrontRegardless()
            }
        }
    }

    @discardableResult
    private static func front(matching predicate: (NSWindow) -> Bool) -> Bool {
        guard let window = NSApp.windows.first(where: predicate) else { return false }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        return true
    }

    /// SwiftUI Window(id:) — identifier/rawValue에 id 포함
    static func present(sceneID: String) {
        present { window in
            let id = window.identifier?.rawValue ?? ""
            if id.contains(sceneID) { return true }
            if sceneID == "settings" {
                return id.localizedCaseInsensitiveContains("settings")
                    || window.title.localizedCaseInsensitiveContains("settings")
                    || window.title.contains("설정")
            }
            return false
        }
    }

    static func presentSettings() {
        present { window in
            let id = window.identifier?.rawValue ?? ""
            if id.localizedCaseInsensitiveContains("settings") { return true }
            if id.contains("Settings") { return true }
            if window.title.localizedCaseInsensitiveContains("settings") { return true }
            if window.title.contains("설정") { return true }
            // SwiftUI Settings — 제목 숨김, 크기 대략 설정 창
            if window.frame.width > 380 && window.frame.width < 700
                && window.frame.height > 250 && window.frame.height < 520
                && window.canBecomeKey && !(window is NSPanel) {
                return true
            }
            return false
        }
    }
}
