import Testing
import ServiceManagement
@testable import RelayConsole

struct LoginItemTests {
    @Test func statusKeyMapsEnabled() {
        #expect(LoginItemLogic.statusKey(for: .enabled) == "settings.login.status.enabled")
    }

    @Test func statusKeyMapsRequiresApproval() {
        #expect(LoginItemLogic.statusKey(for: .requiresApproval) == "settings.login.status.approval")
    }

    @Test func statusKeyMapsNotRegistered() {
        #expect(LoginItemLogic.statusKey(for: .notRegistered) == "settings.login.status.off")
    }

    @Test func statusKeyMapsNotFound() {
        #expect(LoginItemLogic.statusKey(for: .notFound) == "settings.login.status.notFound")
    }

    @Test func errorKeyFallsBackToGeneric() {
        struct Dummy: Error {}
        #expect(LoginItemLogic.errorKey(from: Dummy()) == "settings.login.error")
    }

    @Test func successKeyToggle() {
        #expect(LoginItemLogic.successKey(enabled: true) == "settings.login.on")
        #expect(LoginItemLogic.successKey(enabled: false) == "settings.login.off")
    }

    @Test func defaultHeadlessIsTrue() {
        #expect(LoginItemLogic.defaultHeadless() == true)
        #expect(LoginItemLogic.shouldForceAccessory(headless: true) == true)
        #expect(LoginItemLogic.shouldForceAccessory(headless: false) == false)
    }

    @Test func preferenceKeysStable() {
        #expect(LoginItemLogic.launchAtLoginKey == "relay.login.launchAtLogin")
        #expect(LoginItemLogic.headlessKey == "relay.launch.headless")
    }
}
