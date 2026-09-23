import Foundation
import Testing
@testable import RelayConsole

@MainActor
struct WatchEventTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func fingerprintIsSerialColonKind() {
        let e = WatchEvent(
            kind: .throttling,
            severity: .critical,
            serial: "R5CR10ABCDE",
            title: "t",
            detail: "d"
        )
        #expect(e.fingerprint == "R5CR10ABCDE:throttling")
    }

    @Test func severityOrderWarningAboveInfo() {
        #expect(WatchSeverity.info < WatchSeverity.warning)
        #expect(WatchSeverity.warning < WatchSeverity.critical)
        #expect(!(WatchSeverity.critical < WatchSeverity.info))
    }

    @Test func fingerprintSameKindSameSerialCollides() {
        let a = WatchEvent(kind: .chargeChanged, severity: .info, serial: "X1", title: "", detail: "")
        let b = WatchEvent(kind: .chargeChanged, severity: .info, serial: "X1", title: "", detail: "chg")
        #expect(a.fingerprint == b.fingerprint)
        #expect(a.id != b.id)
    }

    @Test func differentKindDifferentFingerprint() {
        let a = WatchEvent(kind: .throttling, severity: .info, serial: "X1", title: "", detail: "")
        let b = WatchEvent(kind: .protectionChanged, severity: .info, serial: "X1", title: "", detail: "")
        #expect(a.fingerprint != b.fingerprint)
    }

    @Test func watchEngineThermalEnterCriticalAtSevere() {
        WatchEngine.shared.resetAll()
        defer { WatchEngine.shared.resetAll() }

        let enter = WatchEngine.shared.feedThermal(serial: "T1", status: 3, now: t0)
        #expect(enter != nil)
        #expect(enter?.kind == .throttling)
        #expect(enter?.severity == .critical)
        #expect(enter?.isClear == false)

        // active 중 재진입 없음
        #expect(WatchEngine.shared.feedThermal(serial: "T1", status: 5, now: t0.addingTimeInterval(10)) == nil)
    }

    @Test func watchEngineThermalClearBelowHysteresis() {
        WatchEngine.shared.resetAll()
        defer { WatchEngine.shared.resetAll() }

        _ = WatchEngine.shared.feedThermal(serial: "T2", status: 3, now: t0)
        #expect(WatchEngine.shared.feedThermal(serial: "T2", status: 2, now: t0.addingTimeInterval(1)) == nil)
        let clear = WatchEngine.shared.feedThermal(serial: "T2", status: 1, now: t0.addingTimeInterval(2))
        #expect(clear?.isClear == true)
        #expect(clear?.severity == .info)
    }

    @Test func watchEngineChargingTransitionOnce() {
        WatchEngine.shared.resetAll()
        defer { WatchEngine.shared.resetAll() }

        // 첫 틱 baseline
        #expect(WatchEngine.shared.feedCharging(serial: "C1", charging: false, now: t0) == nil)
        let on = WatchEngine.shared.feedCharging(serial: "C1", charging: true, now: t0.addingTimeInterval(1))
        #expect(on?.kind == .chargeChanged)
        // 유지
        #expect(WatchEngine.shared.feedCharging(serial: "C1", charging: true, now: t0.addingTimeInterval(2)) == nil)
    }

    @Test func watchEngineForgetClearsGates() {
        WatchEngine.shared.resetAll()
        defer { WatchEngine.shared.resetAll() }

        _ = WatchEngine.shared.feedThermal(serial: "F1", status: 3, now: t0)
        WatchEngine.shared.forget(serial: "F1")
        // forget 후 새 baseline + 즉시 enter 가능
        let again = WatchEngine.shared.feedThermal(serial: "F1", status: 3, now: t0.addingTimeInterval(1))
        #expect(again != nil)
    }

    @Test func watchEngineProtectionTransition() {
        WatchEngine.shared.resetAll()
        defer { WatchEngine.shared.resetAll() }

        #expect(WatchEngine.shared.feedProtection(serial: "P1", enabled: false, now: t0) == nil)
        let on = WatchEngine.shared.feedProtection(serial: "P1", enabled: true, now: t0.addingTimeInterval(1))
        #expect(on?.kind == .protectionChanged)
        #expect(on?.severity == .warning)
        #expect(on?.isClear == false)
        let off = WatchEngine.shared.feedProtection(serial: "P1", enabled: false, now: t0.addingTimeInterval(20))
        #expect(off?.isClear == true)
    }

    @Test func watchEngineLowPowerTransition() {
        WatchEngine.shared.resetAll()
        defer { WatchEngine.shared.resetAll() }

        #expect(WatchEngine.shared.feedLowPower(serial: "L1", enabled: false, now: t0) == nil)
        let on = WatchEngine.shared.feedLowPower(serial: "L1", enabled: true, now: t0.addingTimeInterval(1))
        #expect(on?.kind == .lowPowerChanged)
        #expect(on?.isClear == false)
        #expect(WatchEngine.shared.feedLowPower(serial: "L1", enabled: true, now: t0.addingTimeInterval(5)) == nil)
        let off = WatchEngine.shared.feedLowPower(serial: "L1", enabled: false, now: t0.addingTimeInterval(20))
        #expect(off?.isClear == true)
    }

    @Test func watchEngineBatteryThresholdFiresOnce() {
        WatchEngine.shared.resetAll()
        defer { WatchEngine.shared.resetAll() }

        // baseline 아님 — discharge로 20% 통과 시 1회
        let e20 = WatchEngine.shared.feedBatteryLevel(serial: "B1", level: 20, charging: false, now: t0)
        #expect(e20?.kind == .batteryThreshold)
        #expect(e20?.title.contains("20") == true)
        // 같은 임계 재발화 없음
        #expect(WatchEngine.shared.feedBatteryLevel(serial: "B1", level: 19, charging: false, now: t0.addingTimeInterval(5)) == nil)
        // 10% 별도 임계
        let e10 = WatchEngine.shared.feedBatteryLevel(serial: "B1", level: 10, charging: false, now: t0.addingTimeInterval(10))
        #expect(e10 != nil)
        #expect(e10?.title.contains("10") == true)
    }

    @Test func watchEngineBatteryRearmsWhileCharging() {
        WatchEngine.shared.resetAll()
        defer { WatchEngine.shared.resetAll() }

        _ = WatchEngine.shared.feedBatteryLevel(serial: "B2", level: 20, charging: false, now: t0)
        // 충전 중 상승 — 20% 재무장
        #expect(WatchEngine.shared.feedBatteryLevel(serial: "B2", level: 80, charging: true, now: t0.addingTimeInterval(60)) == nil)
        // 다음 방전에서 재발화
        let again = WatchEngine.shared.feedBatteryLevel(serial: "B2", level: 20, charging: false, now: t0.addingTimeInterval(120))
        #expect(again != nil)
    }
}
