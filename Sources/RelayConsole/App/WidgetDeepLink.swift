import Foundation

/// 위젯 탭 딥링크 — `relayconsole://<target>` (PLAN_widget)
/// 앱 미실행으로 openWindow 클로저가 아직 미주입이면 보류했다가 `flush()`에서 실행
@MainActor
final class WidgetDeepLink {
    static let shared = WidgetDeepLink()
    static let scheme = "relayconsole"

    var openConsole: (() -> Void)?
    var openProcesses: (() -> Void)?
    var openLogs: (() -> Void)?
    var openAppNetwork: (() -> Void)?
    var openSettings: (() -> Void)?

    private var pendingTarget: String?

    static func url(_ target: String) -> URL? {
        URL(string: "\(scheme)://\(target)")
    }

    func handle(_ urls: [URL]) {
        for url in urls where url.scheme?.lowercased() == Self.scheme {
            route(url.host ?? "console")
        }
    }

    /// App 쪽 openWindow 클로저 주입 직후 호출 — 보류 중이던 라우팅 실행
    func flush() {
        guard let target = pendingTarget else { return }
        pendingTarget = nil
        route(target)
    }

    private func route(_ target: String) {
        // 사이드바 섹션 대상(alerts/sites/jobs/insights/devices) → 콘솔 열고 해당 탭으로
        if let section = ConsoleSection(rawValue: target) {
            ConsoleStore.shared.pendingConsoleSection = section
        }
        let action: (() -> Void)? = {
            switch target {
            case "processes": return openProcesses
            case "logs": return openLogs
            case "appnetwork": return openAppNetwork
            case "settings": return openSettings
            default: return openConsole
            }
        }()
        if let action {
            action()
            pendingTarget = nil
        } else {
            // 라우팅 준비 안 됨 (앱 기동 직후) — 클로저 주입 시 재시도
            pendingTarget = target
        }
    }
}
