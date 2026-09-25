import AppKit
import Foundation
import ServiceManagement

/// 로그인 항목·헤드리스 순수 로직 (테스트 대상)
enum LoginItemLogic {
    static let launchAtLoginKey = "relay.login.launchAtLogin"
    static let headlessKey = "relay.launch.headless"

    /// SMAppService.Status → i18n 키
    static func statusKey(for status: SMAppService.Status) -> String {
        switch status {
        case .enabled: return "settings.login.status.enabled"
        case .requiresApproval: return "settings.login.status.approval"
        case .notRegistered: return "settings.login.status.off"
        case .notFound: return "settings.login.status.notFound"
        @unknown default: return "settings.login.status.unknown"
        }
    }

    /// 등록/해제 오류 → 사용자 문구 키 (기본 실패)
    static func errorKey(from error: Error) -> String {
        _ = error
        return "settings.login.error"
    }

    /// 오류 상세 — 실제 원인을 함께 노출 (AGENTS.local §4 [표시②])
    static func errorDetail(from error: Error) -> String {
        error.localizedDescription
    }

    /// 헤드리스 시작 여부 — 기본 true (창 없이 메뉴바)
    static func defaultHeadless() -> Bool { true }

    /// 헤드리스면 accessory 강제, 아니면 기본 유지(true LSUIElement)
    static func shouldForceAccessory(headless: Bool) -> Bool { headless }

    /// 토글 바인딩에 쓸 안전한 register 결과 메시지 키
    static func successKey(enabled: Bool) -> String {
        enabled ? "settings.login.on" : "settings.login.off"
    }
}

/// 로그인 항목 컨트롤러 — SMAppService IO (MainActor)
@MainActor
final class LoginItemController: ObservableObject {
    static let shared = LoginItemController()

    @Published private(set) var launchAtLogin = false
    @Published private(set) var statusKey = LoginItemLogic.statusKey(for: .notRegistered)
    @Published var messageKey: String?
    /// 실패 원인 (성공 시 nil)
    @Published var messageDetail: String?
    @Published private(set) var busy = false

    private init() {
        refreshStatus()
    }

    func refreshStatus() {
        let status = SMAppService.mainApp.status
        statusKey = LoginItemLogic.statusKey(for: status)
        launchAtLogin = (status == .enabled)
        UserDefaults.standard.set(launchAtLogin, forKey: LoginItemLogic.launchAtLoginKey)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard !busy else { return }
        busy = true
        messageKey = nil
        messageDetail = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshStatus()
            messageKey = LoginItemLogic.successKey(enabled: enabled)
        } catch {
            refreshStatus()
            messageKey = LoginItemLogic.errorKey(from: error)
            messageDetail = LoginItemLogic.errorDetail(from: error)
        }
        busy = false
    }
}

/// 헤드리스 시작 — Dock/activation 없이 accessory 유지 (앱 진입 시 1회)
enum HeadlessLaunch {
    @MainActor
    static func apply() {
        let headless = UserDefaults.standard.object(forKey: LoginItemLogic.headlessKey) as? Bool
            ?? LoginItemLogic.defaultHeadless()
        guard LoginItemLogic.shouldForceAccessory(headless: headless) else { return }
        // LSUIElement(Info.plist) + accessory — 창 복원 플래그 방지
        NSApp.setActivationPolicy(.accessory)
    }
}
