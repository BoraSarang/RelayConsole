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

    @Test func watchEngineThermalClearAtModerate() {
        WatchEngine.shared.resetAll()
        defer { WatchEngine.shared.resetAll() }

        _ = WatchEngine.shared.feedThermal(serial: "T2", status: 3, now: t0)
        // clear ≤2 — SEVERE 이탈(2) 즉시 해제 (Status 2 공백 제거)
        let clear = WatchEngine.shared.feedThermal(serial: "T2", status: 2, now: t0.addingTimeInterval(1))
        #expect(clear?.isClear == true)
        #expect(clear?.severity == .info)
        // Status 1에서도 clear 경로 정상
        _ = WatchEngine.shared.feedThermal(serial: "T2", status: 1, now: t0.addingTimeInterval(120))
        let clear2 = WatchEngine.shared.feedThermal(serial: "T2", status: 2, now: t0.addingTimeInterval(121))
        #expect(clear2 == nil) // 비활성 상태에서 2는 clear 아님
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

    @Test func watchEngineProtectionClearWithinCooldown() {
        WatchEngine.shared.resetAll()
        defer { WatchEngine.shared.resetAll() }

        _ = WatchEngine.shared.feedProtection(serial: "P2", enabled: false, now: t0)
        _ = WatchEngine.shared.feedProtection(serial: "P2", enabled: true, now: t0.addingTimeInterval(1))
        // enter 직후 1s 만에 OFF — clear가 삼켜지면 가이드 영구잔류
        let off = WatchEngine.shared.feedProtection(serial: "P2", enabled: false, now: t0.addingTimeInterval(2))
        #expect(off?.isClear == true)
    }

    @Test func watchEngineLowPowerTransition() {
        WatchEngine.shared.resetAll()
        defer { WatchEngine.shared.resetAll() }

        #expect(WatchEngine.shared.feedLowPower(serial: "L1", enabled: false, now: t0) == nil)
        let on = WatchEngine.shared.feedLowPower(serial: "L1", enabled: true, now: t0.addingTimeInterval(1))
        #expect(on?.kind == .lowPowerChanged)
        #expect(on?.severity == .warning) // 가이드 진입용
        #expect(on?.isClear == false)
        #expect(WatchEngine.shared.feedLowPower(serial: "L1", enabled: true, now: t0.addingTimeInterval(5)) == nil)
        let off = WatchEngine.shared.feedLowPower(serial: "L1", enabled: false, now: t0.addingTimeInterval(6))
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

    @Test func watchEngineBatteryWarningClearsOnCharge() {
        WatchEngine.shared.resetAll()
        defer { WatchEngine.shared.resetAll() }

        // 20% info 먼저 소진 후 10% = warning (가이드 대상)
        let e20 = WatchEngine.shared.feedBatteryLevel(serial: "B3", level: 20, charging: false, now: t0)
        #expect(e20?.severity == .info)
        let e10 = WatchEngine.shared.feedBatteryLevel(serial: "B3", level: 10, charging: false, now: t0.addingTimeInterval(5))
        #expect(e10?.severity == .warning)
        // 충전 시작 → 미해결 warning clear
        let clear = WatchEngine.shared.feedBatteryLevel(serial: "B3", level: 12, charging: true, now: t0.addingTimeInterval(30))
        #expect(clear?.isClear == true)
        #expect(clear?.kind == .batteryThreshold)
        // 이미 clear 후 충전 유지 — 중복 clear 없음
        #expect(WatchEngine.shared.feedBatteryLevel(serial: "B3", level: 50, charging: true, now: t0.addingTimeInterval(60)) == nil)
    }

    // MARK: - Phase2 A5 (PSI / load / memory)

    @Test func watchEnginePsiEnterAtFiveClearAtThree() {
        WatchEngine.shared.resetAll()
        defer { WatchEngine.shared.resetAll() }

        #expect(WatchEngine.shared.feedPsi(serial: "P1", avg10: 4.9, now: t0) == nil)
        let enter = WatchEngine.shared.feedPsi(serial: "P1", avg10: 5.0, now: t0.addingTimeInterval(1))
        #expect(enter?.kind == .psiPressure)
        #expect(enter?.severity == .warning)
        #expect(enter?.isClear == false)
        // hysteresis: 4.0은 clear 아님 (clear ≤3.0)
        #expect(WatchEngine.shared.feedPsi(serial: "P1", avg10: 4.0, now: t0.addingTimeInterval(2)) == nil)
        let clear = WatchEngine.shared.feedPsi(serial: "P1", avg10: 3.0, now: t0.addingTimeInterval(3))
        #expect(clear?.isClear == true)
        // cooldown 120s — 즉시 재진입 불가
        #expect(WatchEngine.shared.feedPsi(serial: "P1", avg10: 6.0, now: t0.addingTimeInterval(10)) == nil)
        let reenter = WatchEngine.shared.feedPsi(serial: "P1", avg10: 6.0, now: t0.addingTimeInterval(130))
        #expect(reenter != nil)
    }

    @Test func watchEngineLoadSpikeEnterTwiceCores() {
        WatchEngine.shared.resetAll()
        defer { WatchEngine.shared.resetAll() }

        // cores=8 → enter ≥16, clear ≤8
        #expect(WatchEngine.shared.feedLoad(serial: "L1", load1: 15.9, cores: 8, now: t0) == nil)
        let enter = WatchEngine.shared.feedLoad(serial: "L1", load1: 16.0, cores: 8, now: t0.addingTimeInterval(1))
        #expect(enter?.kind == .loadSpike)
        #expect(enter?.severity == .warning)
        // 12는 hysteresis 구간 (8 < 12 < 16) — clear 아님
        #expect(WatchEngine.shared.feedLoad(serial: "L1", load1: 12.0, cores: 8, now: t0.addingTimeInterval(2)) == nil)
        let clear = WatchEngine.shared.feedLoad(serial: "L1", load1: 8.0, cores: 8, now: t0.addingTimeInterval(3))
        #expect(clear?.isClear == true)
        // critical: ≥ cores×3 = 24
        #expect(WatchEngine.shared.feedLoad(serial: "L1", load1: 8.0, cores: 8, now: t0.addingTimeInterval(4)) == nil)
        _ = WatchEngine.shared.feedLoad(serial: "L1", load1: 8.0, cores: 8, now: t0.addingTimeInterval(70))
        let crit = WatchEngine.shared.feedLoad(serial: "L1", load1: 24.0, cores: 8, now: t0.addingTimeInterval(71))
        #expect(crit?.severity == .critical)
        // cores=0이면 스킵
        #expect(WatchEngine.shared.feedLoad(serial: "L2", load1: 99, cores: 0, now: t0) == nil)
    }

    @Test func watchEngineMemoryUsedPctGate() {
        WatchEngine.shared.resetAll()
        defer { WatchEngine.shared.resetAll() }

        // enter ≥90 usedPct (avail<10%), clear ≤80 (avail>20%)
        #expect(WatchEngine.shared.feedMemory(serial: "M1", usedPct: 89.9, now: t0) == nil)
        let enter = WatchEngine.shared.feedMemory(serial: "M1", usedPct: 90.0, now: t0.addingTimeInterval(1))
        #expect(enter?.kind == .memoryLow)
        #expect(enter?.severity == .warning)
        #expect(WatchEngine.shared.feedMemory(serial: "M1", usedPct: 85.0, now: t0.addingTimeInterval(2)) == nil)
        let clear = WatchEngine.shared.feedMemory(serial: "M1", usedPct: 80.0, now: t0.addingTimeInterval(3))
        #expect(clear?.isClear == true)
        // critical ≥95
        #expect(WatchEngine.shared.feedMemory(serial: "M1", usedPct: 95.0, now: t0.addingTimeInterval(4)) == nil)
        _ = WatchEngine.shared.feedMemory(serial: "M1", usedPct: 80.0, now: t0.addingTimeInterval(5))
        _ = WatchEngine.shared.feedMemory(serial: "M1", usedPct: 80.0, now: t0.addingTimeInterval(70))
        let crit = WatchEngine.shared.feedMemory(serial: "M1", usedPct: 95.0, now: t0.addingTimeInterval(71))
        #expect(crit?.severity == .critical)
    }

    @Test func watchEngineForgetClearsPhase2Gates() {
        WatchEngine.shared.resetAll()
        defer { WatchEngine.shared.resetAll() }

        _ = WatchEngine.shared.feedPsi(serial: "F2", avg10: 6.0, now: t0)
        _ = WatchEngine.shared.feedLoad(serial: "F2", load1: 20, cores: 8, now: t0)
        _ = WatchEngine.shared.feedMemory(serial: "F2", usedPct: 92, now: t0)
        WatchEngine.shared.forget(serial: "F2")
        // forget 후 새 baseline → 즉시 enter 가능
        #expect(WatchEngine.shared.feedPsi(serial: "F2", avg10: 6.0, now: t0.addingTimeInterval(1)) != nil)
        #expect(WatchEngine.shared.feedLoad(serial: "F2", load1: 20, cores: 8, now: t0.addingTimeInterval(2)) != nil)
        #expect(WatchEngine.shared.feedMemory(serial: "F2", usedPct: 92, now: t0.addingTimeInterval(3)) != nil)
    }

    // MARK: - v0.7 (Bsoh / RSRP)

    @Test func watchEngineBsohBaselineThenDropFive() {
        WatchEngine.shared.resetAll()
        defer { WatchEngine.shared.resetAll() }

        // 첫 틱 baseline
        #expect(WatchEngine.shared.feedBsoh(serial: "H1", bsoh: 91, now: t0) == nil)
        // 4pt 하락 — 미발화
        #expect(WatchEngine.shared.feedBsoh(serial: "H1", bsoh: 87, now: t0.addingTimeInterval(60)) == nil)
        // 5pt 이상 하락 (baseline 91 → 85)
        let drop = WatchEngine.shared.feedBsoh(serial: "H1", bsoh: 85, now: t0.addingTimeInterval(120))
        #expect(drop?.kind == .bsohDrop)
        #expect(drop?.severity == .warning)
        #expect(drop?.isClear == false)
        // baseline 갱신 후 동일값 재발화 없음
        #expect(WatchEngine.shared.feedBsoh(serial: "H1", bsoh: 85, now: t0.addingTimeInterval(180)) == nil)
        // 추가 5pt 하락 재발화
        let drop2 = WatchEngine.shared.feedBsoh(serial: "H1", bsoh: 80, now: t0.addingTimeInterval(240))
        #expect(drop2 != nil)
    }

    @Test func watchEngineBsohClearOnRecoverToPreDrop() {
        WatchEngine.shared.resetAll()
        defer { WatchEngine.shared.resetAll() }

        _ = WatchEngine.shared.feedBsoh(serial: "H2", bsoh: 91, now: t0)
        let drop = WatchEngine.shared.feedBsoh(serial: "H2", bsoh: 85, now: t0.addingTimeInterval(60))
        #expect(drop?.severity == .warning)
        // pre-drop(91)까지 회복 → clear
        let clear = WatchEngine.shared.feedBsoh(serial: "H2", bsoh: 91, now: t0.addingTimeInterval(120))
        #expect(clear?.isClear == true)
        #expect(clear?.kind == .bsohDrop)
        // 회복 후 중복 clear 없음
        #expect(WatchEngine.shared.feedBsoh(serial: "H2", bsoh: 91, now: t0.addingTimeInterval(180)) == nil)
    }

    @Test func watchEngineForgetReturnsSyntheticClears() {
        WatchEngine.shared.resetAll()
        defer { WatchEngine.shared.resetAll() }

        _ = WatchEngine.shared.feedThermal(serial: "F4", status: 3, now: t0)
        _ = WatchEngine.shared.feedProtection(serial: "F4", enabled: false, now: t0)
        _ = WatchEngine.shared.feedProtection(serial: "F4", enabled: true, now: t0.addingTimeInterval(1))
        _ = WatchEngine.shared.feedPsi(serial: "F4", avg10: 6.0, now: t0)

        let clears = WatchEngine.shared.forget(serial: "F4")
        #expect(clears.contains { $0.kind == .throttling && $0.isClear })
        #expect(clears.contains { $0.kind == .protectionChanged && $0.isClear })
        #expect(clears.contains { $0.kind == .psiPressure && $0.isClear })
        #expect(clears.allSatisfy { $0.isClear })
    }

    @Test func watchEngineRsrpDropAndRecover() {
        WatchEngine.shared.resetAll()
        defer { WatchEngine.shared.resetAll() }

        // baseline
        #expect(WatchEngine.shared.feedRsrp(serial: "S1", rsrp: -100, now: t0) == nil)
        // 5dB 악화 — 미발화 (Δ≤−6 필요)
        #expect(WatchEngine.shared.feedRsrp(serial: "S1", rsrp: -105, now: t0.addingTimeInterval(5)) == nil)
        // Δ = -105 → -112 = -7
        let enter = WatchEngine.shared.feedRsrp(serial: "S1", rsrp: -112, now: t0.addingTimeInterval(10))
        #expect(enter?.kind == .signalDrop)
        #expect(enter?.severity == .warning)
        #expect(enter?.isClear == false)
        // 쿨다운 중 재진입 없음
        #expect(WatchEngine.shared.feedRsrp(serial: "S1", rsrp: -120, now: t0.addingTimeInterval(20)) == nil)
        // 회복 Δ≥+6 — last=-120 → -110 = +10
        let clear = WatchEngine.shared.feedRsrp(serial: "S1", rsrp: -110, now: t0.addingTimeInterval(70))
        #expect(clear?.isClear == true)
        #expect(clear?.kind == .signalDrop)
    }

    @Test func watchEngineForgetClearsV07Gates() {
        WatchEngine.shared.resetAll()
        defer { WatchEngine.shared.resetAll() }

        _ = WatchEngine.shared.feedBsoh(serial: "F3", bsoh: 91, now: t0)
        _ = WatchEngine.shared.feedRsrp(serial: "F3", rsrp: -100, now: t0)
        WatchEngine.shared.forget(serial: "F3")
        // forget 후 새 baseline
        #expect(WatchEngine.shared.feedBsoh(serial: "F3", bsoh: 91, now: t0.addingTimeInterval(1)) == nil)
        #expect(WatchEngine.shared.feedRsrp(serial: "F3", rsrp: -100, now: t0.addingTimeInterval(2)) == nil)
        #expect(WatchEngine.shared.feedBsoh(serial: "F3", bsoh: 85, now: t0.addingTimeInterval(3)) != nil)
    }

    // MARK: - Remediation guide (최신 우선 + TTL)

    @Test func activeRemediationLatestClearHidesEnter() {
        let enter = WatchEvent(
            kind: .throttling, severity: .critical, serial: "S1",
            title: "enter", detail: "", at: t0
        )
        let clear = WatchEvent(
            kind: .throttling, severity: .info, serial: "S1",
            title: "clear", detail: "", at: t0.addingTimeInterval(10), isClear: true
        )
        let active = ConsoleStore.activeRemediation(
            from: [clear, enter],
            now: t0.addingTimeInterval(20)
        )
        #expect(active.isEmpty)
    }

    @Test func activeRemediationKeepsUnclearedWarning() {
        let enter = WatchEvent(
            kind: .throttling, severity: .critical, serial: "S1",
            title: "enter", detail: "", at: t0
        )
        let active = ConsoleStore.activeRemediation(
            from: [enter],
            now: t0.addingTimeInterval(20)
        )
        #expect(active.count == 1)
        #expect(active.first?.kind == .throttling)
    }

    @Test func activeRemediationExpiresAfterTTL() {
        let enter = WatchEvent(
            kind: .throttling, severity: .critical, serial: "S1",
            title: "enter", detail: "", at: t0
        )
        let active = ConsoleStore.activeRemediation(
            from: [enter],
            now: t0.addingTimeInterval(1801),
            ttl: 1800
        )
        #expect(active.isEmpty)
    }

    @Test func activeRemediationIgnoresInfoSeverity() {
        let enter = WatchEvent(
            kind: .chargeChanged, severity: .info, serial: "S1",
            title: "chg", detail: "", at: t0
        )
        let active = ConsoleStore.activeRemediation(
            from: [enter],
            now: t0.addingTimeInterval(10)
        )
        #expect(active.isEmpty)
    }

    @Test func activeRemediationReenterAfterClearShowsAgain() {
        let enter1 = WatchEvent(
            kind: .throttling, severity: .critical, serial: "S1",
            title: "e1", detail: "", at: t0
        )
        let clear = WatchEvent(
            kind: .throttling, severity: .info, serial: "S1",
            title: "c", detail: "", at: t0.addingTimeInterval(10), isClear: true
        )
        let enter2 = WatchEvent(
            kind: .throttling, severity: .critical, serial: "S1",
            title: "e2", detail: "", at: t0.addingTimeInterval(20)
        )
        let active = ConsoleStore.activeRemediation(
            from: [enter2, clear, enter1],
            now: t0.addingTimeInterval(30)
        )
        #expect(active.count == 1)
        #expect(active.first?.title == "e2")
    }

    // MARK: - v0.8 ANR / crash

    @Test func feedAnrEmitsCriticalOnceWithCooldown() {
        WatchEngine.shared.resetAll()
        defer { WatchEngine.shared.resetAll() }

        let first = WatchEngine.shared.feedAnr(serial: "A1", detail: "hits 1", now: t0)
        #expect(first?.kind == .anr)
        #expect(first?.severity == .critical)
        #expect(first?.isClear == false)

        // 5분 쿨다운 내 재발화 없음
        #expect(WatchEngine.shared.feedAnr(serial: "A1", now: t0.addingTimeInterval(60)) == nil)
        #expect(WatchEngine.shared.feedAnr(serial: "A1", now: t0.addingTimeInterval(299)) == nil)

        // 쿨다운 이후 재발화
        let second = WatchEngine.shared.feedAnr(serial: "A1", now: t0.addingTimeInterval(301))
        #expect(second?.kind == .anr)
        #expect(second?.id != first?.id)
    }

    @Test func feedCrashEmitsCriticalOnceWithCooldown() {
        WatchEngine.shared.resetAll()
        defer { WatchEngine.shared.resetAll() }

        let first = WatchEngine.shared.feedCrash(serial: "C1", detail: "FATAL", now: t0)
        #expect(first?.kind == .crash)
        #expect(first?.severity == .critical)
        #expect(first?.isClear == false)

        #expect(WatchEngine.shared.feedCrash(serial: "C1", now: t0.addingTimeInterval(10)) == nil)
        #expect(WatchEngine.shared.feedCrash(serial: "C1", now: t0.addingTimeInterval(301)) != nil)
    }

    @Test func feedAnrAndCrashAreIndependentCooldowns() {
        WatchEngine.shared.resetAll()
        defer { WatchEngine.shared.resetAll() }

        #expect(WatchEngine.shared.feedAnr(serial: "X1", now: t0) != nil)
        #expect(WatchEngine.shared.feedCrash(serial: "X1", now: t0) != nil)
        // 같은 serial이어도 kind별 쿨다운 독립
        #expect(WatchEngine.shared.feedAnr(serial: "X1", now: t0.addingTimeInterval(1)) == nil)
        #expect(WatchEngine.shared.feedCrash(serial: "X1", now: t0.addingTimeInterval(1)) == nil)
    }

    @Test func forgetClearsAnrCrashCooldownWithoutSyntheticClear() {
        WatchEngine.shared.resetAll()
        defer { WatchEngine.shared.resetAll() }

        _ = WatchEngine.shared.feedAnr(serial: "F1", now: t0)
        _ = WatchEngine.shared.feedCrash(serial: "F1", now: t0)
        let clears = WatchEngine.shared.forget(serial: "F1")
        // clear 자동 없음 (가이드 TTL 의존)
        #expect(!clears.contains { $0.kind == .anr || $0.kind == .crash })

        // 쿨다운 초기화 → 즉시 재발화 가능
        #expect(WatchEngine.shared.feedAnr(serial: "F1", now: t0.addingTimeInterval(1)) != nil)
    }

    @Test func logcatKeywordClassificationHitsAnrAndCrash() {
        let anrText = """
        09-24 10:00:00.000 E/ActivityManager: ANR in com.example.app
        09-24 10:00:01.000 E/am_anr: [0,1234,com.example.app,552039,Input dispatching timed out]
        """
        let crashText = """
        09-24 10:01:00.000 E/AndroidRuntime: FATAL EXCEPTION: main
        09-24 10:01:01.000 I/Process: com.example.app has died, pid 1234
        """
        #expect(AdbClient.countLogcatHits(anrText, keywords: DeviceMonitor.anrKeywords) == 2)
        #expect(AdbClient.countLogcatHits(anrText, keywords: DeviceMonitor.crashKeywords) == 0)
        #expect(AdbClient.countLogcatHits(crashText, keywords: DeviceMonitor.crashKeywords) == 2)
        #expect(AdbClient.countLogcatHits(crashText, keywords: DeviceMonitor.anrKeywords) == 0)
        #expect(AdbClient.countLogcatHits("  ", keywords: DeviceMonitor.anrKeywords) == 0)
    }

    @Test func activeRemediationIncludesAnrAndCrashWithinTtl() {
        let anr = WatchEvent(
            kind: .anr, severity: .critical, serial: "S1",
            title: "ANR", detail: "", at: t0
        )
        let crash = WatchEvent(
            kind: .crash, severity: .critical, serial: "S1",
            title: "Crash", detail: "", at: t0.addingTimeInterval(5)
        )
        let active = ConsoleStore.activeRemediation(
            from: [crash, anr],
            now: t0.addingTimeInterval(10),
            ttl: 1800
        )
        #expect(active.count == 2)
        #expect(Set(active.map(\.kind)) == Set([.anr, .crash]))

        let expired = ConsoleStore.activeRemediation(
            from: [crash, anr],
            now: t0.addingTimeInterval(1810),
            ttl: 1800
        )
        #expect(expired.isEmpty)
    }

    @Test func watchEventCodableRoundTrip() throws {
        let original = WatchEvent(
            kind: .anr,
            severity: .critical,
            serial: "SER12345",
            title: "ANR 감지",
            detail: "SER12345 · hits 2",
            at: t0,
            isClear: false
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WatchEvent.self, from: data)
        #expect(decoded.kind == original.kind)
        #expect(decoded.severity == original.severity)
        #expect(decoded.serial == original.serial)
        #expect(decoded.title == original.title)
        #expect(decoded.detail == original.detail)
        #expect(decoded.isClear == original.isClear)
        #expect(decoded.at.timeIntervalSince1970 == original.at.timeIntervalSince1970)
    }
}

