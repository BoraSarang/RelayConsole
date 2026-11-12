import Foundation
import Testing
@testable import RelayConsole

/// 부팅 후 첫 연결 훅 — 순수 판정 고정 (IO 없음)
struct PostBootHookTests {
    // MARK: - adb root 출력 판정

    @Test func rootOutcomeProductionBuild() {
        #expect(
            PostBootHookLogic.rootOutcome("adbd cannot run as root in production builds")
                == .unsupported
        )
    }

    @Test func rootOutcomeAlreadyRoot() {
        #expect(
            PostBootHookLogic.rootOutcome("adbd is already running as root")
                == .alreadyRoot
        )
    }

    @Test func rootOutcomeRestarting() {
        #expect(
            PostBootHookLogic.rootOutcome("restarting adbd as root")
                == .restarted
        )
    }

    @Test func rootOutcomeUnknown() {
        #expect(PostBootHookLogic.rootOutcome("") == .unknown)
        #expect(PostBootHookLogic.rootOutcome("error: device offline") == .unknown)
    }

    // MARK: - root 가능 판정

    @Test func rootCapableByDebuggable() {
        #expect(PostBootHookLogic.isRootCapable(debuggable: "1", uid: "2000"))
        #expect(!PostBootHookLogic.isRootCapable(debuggable: "0", uid: "2000"))
    }

    @Test func rootCapableWhenAlreadyRoot() {
        #expect(PostBootHookLogic.isRootCapable(debuggable: "0", uid: "0"))
        #expect(PostBootHookLogic.isRootCapable(debuggable: nil, uid: "0\n"))
    }

    @Test func rootCapableRejectsMissing() {
        #expect(!PostBootHookLogic.isRootCapable(debuggable: nil, uid: nil))
        #expect(!PostBootHookLogic.isRootCapable(debuggable: "", uid: ""))
    }

    // MARK: - 부팅 1회 판정

    @Test func shouldHandleRequiresEnabledAndNewToken() {
        #expect(PostBootHookLogic.shouldHandle(enabled: true, bootToken: "id:A", handledToken: "id:B"))
        #expect(!PostBootHookLogic.shouldHandle(enabled: true, bootToken: "id:A", handledToken: "id:A"))
        #expect(!PostBootHookLogic.shouldHandle(enabled: false, bootToken: "id:A", handledToken: nil))
        #expect(!PostBootHookLogic.shouldHandle(enabled: true, bootToken: nil, handledToken: nil))
        #expect(!PostBootHookLogic.shouldHandle(enabled: true, bootToken: "  ", handledToken: nil))
    }

    @Test func bootTokenPrefersBootID() {
        #expect(
            PostBootHookLogic.bootToken(bootID: " 8f1c\n", procStat: "btime 123")
                == "id:8f1c"
        )
    }

    @Test func bootTokenFallsBackToBtime() {
        let stat = """
        cpu  1 2 3 4
        btime 1762900000
        processes 123
        """
        #expect(PostBootHookLogic.bootToken(bootID: "", procStat: stat) == "btime:1762900000")
        #expect(PostBootHookLogic.bootToken(bootID: nil, procStat: stat) == "btime:1762900000")
    }

    @Test func bootTokenRejectsGarbage() {
        #expect(PostBootHookLogic.bootToken(bootID: "", procStat: "btime abc") == nil)
        #expect(PostBootHookLogic.bootToken(bootID: nil, procStat: nil) == nil)
    }

    @Test func bootTokenCacheExpires() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(PostBootHookLogic.cacheIsFresh(cachedAt: nil, now: now) == false)
        #expect(
            PostBootHookLogic.cacheIsFresh(
                cachedAt: now.addingTimeInterval(-30),
                now: now
            )
        )
        #expect(
            PostBootHookLogic.cacheIsFresh(
                cachedAt: now.addingTimeInterval(-61),
                now: now
            ) == false
        )
    }

    // MARK: - 물리 ID

    @Test func physicalIdRejectsEmptyAndErrors() {
        #expect(PostBootHookLogic.validPhysicalId("R5CT215F4QK") == "R5CT215F4QK")
        #expect(PostBootHookLogic.validPhysicalId("  R5CT215F4QK\n") == "R5CT215F4QK")
        #expect(PostBootHookLogic.validPhysicalId("") == nil)
        #expect(PostBootHookLogic.validPhysicalId(nil) == nil)
        #expect(PostBootHookLogic.validPhysicalId("error: device offline") == nil)
        #expect(PostBootHookLogic.validPhysicalId("not found") == nil)
        #expect(PostBootHookLogic.validPhysicalId(String(repeating: "A", count: 65)) == nil)
    }

    // MARK: - persist · wake lock

    @Test func screenTimeoutParsing() {
        #expect(PostBootHookLogic.screenTimeoutMS("30000") == 30_000)
        #expect(PostBootHookLogic.screenTimeoutMS("-1") == -1)
        #expect(PostBootHookLogic.screenTimeoutMS(" 600000\n") == 600_000)
        #expect(PostBootHookLogic.screenTimeoutMS("0") == nil)
        #expect(PostBootHookLogic.screenTimeoutMS("") == nil)
        #expect(PostBootHookLogic.screenTimeoutMS(nil) == nil)
        #expect(PostBootHookLogic.screenTimeoutMS("null") == nil)
    }

    @Test func temporaryScreenTimeoutKeepsLongerUserSetting() {
        #expect(PostBootHookLogic.temporaryScreenTimeoutMS(original: 30_000) == 120_000)
        #expect(PostBootHookLogic.temporaryScreenTimeoutMS(original: 600_000) == 600_000)
        #expect(PostBootHookLogic.temporaryScreenTimeoutMS(original: -1) == -1)
        #expect(PostBootHookLogic.temporaryScreenTimeoutMS(original: nil) == nil)
    }

    @Test func pendingScreenTimeoutRestoreWindow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(PostBootHookLogic.screenOffRestoreIsFresh(savedAt: nil, now: now) == false)
        #expect(
            PostBootHookLogic.screenOffRestoreIsFresh(
                savedAt: now.addingTimeInterval(-60),
                now: now
            )
        )
        #expect(
            PostBootHookLogic.screenOffRestoreIsFresh(
                savedAt: now.addingTimeInterval(-601),
                now: now
            ) == false
        )
    }

    @Test func screenOffKeysAreStable() {
        #expect(
            PostBootHookLogic.screenOffKey(physicalId: "R5CT215F4QK")
                == "relay.postBoot.screenOff.R5CT215F4QK"
        )
        #expect(
            PostBootHookLogic.screenOffAtKey(physicalId: "R5CT215F4QK")
                == "relay.postBoot.screenOffAt.R5CT215F4QK"
        )
    }

    @Test func persistPortOnlyWhenDifferent() {
        #expect(PostBootHookLogic.needsPersistPort(nil))
        #expect(PostBootHookLogic.needsPersistPort(""))
        #expect(PostBootHookLogic.needsPersistPort("5554"))
        #expect(!PostBootHookLogic.needsPersistPort("5555"))
        #expect(!PostBootHookLogic.needsPersistPort(" 5555\n"))
    }

    @Test func wakeLockHeldParsing() {
        #expect(PostBootHookLogic.isWakeLockHeld("relayconsole"))
        #expect(PostBootHookLogic.isWakeLockHeld("foo\nrelayconsole\nbar"))
        #expect(!PostBootHookLogic.isWakeLockHeld(""))
        #expect(!PostBootHookLogic.isWakeLockHeld(nil))
        #expect(!PostBootHookLogic.isWakeLockHeld("relayconsole2"))
        #expect(
            PostBootHookLogic.wakeLockCommand()
                == "echo relayconsole > /sys/power/wake_lock"
        )
    }

    // MARK: - 재시도

    @Test func retryAllowedFirstAttempt() {
        #expect(PostBootHookLogic.retryAllowed(attempts: 0, lastAttemptAt: nil, now: Date()))
    }

    @Test func retryAllowedCooldown() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(
            PostBootHookLogic.retryAllowed(
                attempts: 1,
                lastAttemptAt: now.addingTimeInterval(-60),
                now: now
            ) == false
        )
        #expect(
            PostBootHookLogic.retryAllowed(
                attempts: 1,
                lastAttemptAt: now.addingTimeInterval(-601),
                now: now
            )
        )
    }

    @Test func retryStopsAfterMaxAttempts() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(
            PostBootHookLogic.retryAllowed(
                attempts: PostBootHookLogic.maxAttempts,
                lastAttemptAt: now.addingTimeInterval(-86_400),
                now: now
            ) == false
        )
    }

    // MARK: - 기타

    @Test func mdnsSerialDetection() {
        #expect(PostBootHookLogic.isMdnsSerial("adb-R5CT215F4QK-iL8Q9e._adb-tls-connect._tcp"))
        #expect(!PostBootHookLogic.isMdnsSerial("192.168.190.216:5555"))
        #expect(!PostBootHookLogic.isMdnsSerial("R5CT215F4QK"))
    }

    @Test func handledKeyIsStable() {
        #expect(
            PostBootHookLogic.handledKey(physicalId: "R5CT215F4QK")
                == "relay.postBoot.boot.R5CT215F4QK"
        )
    }
}
