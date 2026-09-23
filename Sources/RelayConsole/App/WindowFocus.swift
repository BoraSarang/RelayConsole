import AppKit

/// LSUIElement(메뉴바) 앱 — 창을 뒤로 숨기지 않고 앞으로 가져오는 유틸
@MainActor
enum WindowFocus {
    /// 메뉴바 팝오버 패널(상태바 레벨) 닫기
    static func dismissMenuBarPanels() {
        for window in NSApp.windows {
            guard let panel = window as? NSPanel else { continue }
            if panel.level == .statusBar || panel.level == .popUpMenu {
                panel.perform(#selector(NSWindow.orderOut(_:)), with: nil)
            }
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
