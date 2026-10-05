import XCTest
@testable import RelayConsole

/// 충전 방치 — **시간 축**이라 오차가 눈에 바로 보인다. 전이를 전부 고정한다
final class BatteryNeglectTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    private func tracker(_ percent: Int = 20) -> BatteryNeglectTracker {
        BatteryNeglectTracker(percentThreshold: percent)
    }

    // MARK: - 전이

    func testFirstObservationStartsTheClock() {
        let t = tracker()
        XCTAssertEqual(t.observe(serial: "a", level: 15, isCharging: false, now: t0), 0)
    }

    func testDurationGrowsWhileBelowThreshold() {
        let t = tracker()
        t.observe(serial: "a", level: 15, isCharging: false, now: t0)
        XCTAssertEqual(t.observe(serial: "a", level: 14, isCharging: false, now: at(10)), 600)
        XCTAssertEqual(t.observe(serial: "a", level: 5, isCharging: false, now: at(360)), 21_600)
    }

    func testThresholdBoundaryIsInclusive() {
        // "20% 이하" 라면 20 자체는 방치다 — 21 은 아니다
        let t = tracker(20)
        XCTAssertEqual(t.observe(serial: "a", level: 20, isCharging: false, now: t0), 0)
        XCTAssertEqual(t.observe(serial: "a", level: 20, isCharging: false, now: at(5)), 300)
        let t2 = tracker(20)
        XCTAssertEqual(t2.observe(serial: "b", level: 21, isCharging: false, now: t0), 0)
    }

    func testChargingResetsTheClock() {
        // 충전이 방치를 **끊는다** — 5시간째 방치였다가 충전하면 0 부터 다시
        let t = tracker()
        t.observe(serial: "a", level: 10, isCharging: false, now: t0)
        XCTAssertEqual(t.observe(serial: "a", level: 10, isCharging: true, now: at(300)), 0)
        XCTAssertTrue(t.snapshot(now: at(300)).isEmpty, "충전 후에는 방치 행이 없다")
    }

    func testRechargeThenDropStartsOver() {
        // 중간에 충전이 있었으니 "그 이전 5시간" 은 이번 방치에 합치지 않는다
        let t = tracker()
        t.observe(serial: "a", level: 10, isCharging: false, now: t0)
        t.observe(serial: "a", level: 10, isCharging: true, now: at(300))
        XCTAssertEqual(t.observe(serial: "a", level: 10, isCharging: false, now: at(310)), 0)
        XCTAssertEqual(t.observe(serial: "a", level: 10, isCharging: false, now: at(370)), 3_600)
    }

    func testAboveThresholdResets() {
        let t = tracker(20)
        t.observe(serial: "a", level: 10, isCharging: false, now: t0)
        XCTAssertEqual(t.observe(serial: "a", level: 30, isCharging: false, now: at(60)), 0)
        XCTAssertTrue(t.snapshot(now: at(60)).isEmpty)
    }

    /// ★ 배터리 **미확인은 끊지 않는다** — 모르는 구간이 방치를 끝낸다고 볼 근거가 없다
    func testUnknownBatteryDoesNotEndTheClock() {
        let t = tracker()
        t.observe(serial: "a", level: 10, isCharging: false, now: t0)
        XCTAssertEqual(t.observe(serial: "a", level: nil, isCharging: false, now: at(60)), 3_600,
                       "미확인 구간이 방치를 끊지 않아야 한다")
        XCTAssertEqual(t.observe(serial: "a", level: 10, isCharging: false, now: at(120)), 7_200)
    }

    func testUnknownChargingFlagIsNotAssumedCharging() {
        // isCharging 이 nil 이어도 충전이라고 **추측하지 않는다** — 배터리 값으로만 판단한다
        let t = tracker()
        t.observe(serial: "a", level: 10, isCharging: nil, now: t0)
        XCTAssertEqual(t.observe(serial: "a", level: 10, isCharging: nil, now: at(60)), 3_600)
    }

    func testDevicesAreTrackedSeparately() {
        let t = tracker()
        t.observe(serial: "a", level: 10, isCharging: false, now: t0)
        t.observe(serial: "b", level: 10, isCharging: false, now: at(100))
        let snap = t.snapshot(now: at(100))
        XCTAssertEqual(snap["a"], 6_000)
        XCTAssertEqual(snap["b"], 0)
    }

    func testForgetRemovesVanishedDevices() {
        let t = tracker()
        t.observe(serial: "a", level: 10, isCharging: false, now: t0)
        t.observe(serial: "b", level: 10, isCharging: false, now: t0)
        t.forget(serials: ["a"])
        let snap = t.snapshot(now: at(60))
        XCTAssertNil(snap["a"], "폴링이 사라진 기기는 영원히 방치로 남지 않는다")
        XCTAssertNotNil(snap["b"])
    }

    func testResetClearsAll() {
        let t = tracker()
        t.observe(serial: "a", level: 10, isCharging: false, now: t0)
        t.reset()
        XCTAssertTrue(t.snapshot(now: t0).isEmpty)
    }

    // MARK: - 설정이 **실제로** 닿는가

    /// ★ 파싱만 되고 적용되지 않는 경로(조용한 실패)를 막는다
    func testSetThresholdChangesWhatCountsAsNeglect() {
        let t = tracker(20)
        t.observe(serial: "a", level: 50, isCharging: false, now: t0)
        XCTAssertTrue(t.snapshot(now: at(60)).isEmpty, "20% 기준에서 50% 는 방치가 아니다")

        t.setThreshold(60)
        // 기준이 60 이면 **지금부터** 50% 가 방치다 — 이전 60 초를 되돌려 붙이지 않는다
        XCTAssertEqual(t.observe(serial: "a", level: 50, isCharging: false, now: at(60)), 0)
    }

    func testSetThresholdClearsAccumulatedTime() {
        // 임계가 바뀌면 지금까지 잰 시간은 **다른 기준의 시간**이므로 버린다
        let t = tracker(20)
        t.observe(serial: "a", level: 10, isCharging: false, now: t0)
        XCTAssertEqual(t.observe(serial: "a", level: 10, isCharging: false, now: at(600)), 36_000)
        t.setThreshold(10)
        XCTAssertTrue(t.snapshot(now: at(600)).isEmpty, "기준이 바뀌면 누적은 0 부터")
    }

    func testSetThresholdToSameValueKeepsAccumulation() {
        // 같은 값이면 재설정으로 봐야 하지 않는다 — 재시작마다 시간이 리셋되면 안 된다
        let t = tracker(20)
        t.observe(serial: "a", level: 10, isCharging: false, now: t0)
        t.setThreshold(20)
        XCTAssertEqual(t.observe(serial: "a", level: 10, isCharging: false, now: at(60)), 3_600)
    }

    func testConfigThresholdReachesTracker() throws {
        // 설정 → 트래커 경로가 끊기면 "사용자가 고른 값이 버려진다"
        let result = RulesConfig.parse("""
        version: 1
        rules:
          memoryLow: { enter: 90, clear: 80, cooldown: 60 }
        battery: { neglectPercent: 50 }
        """)
        guard case .ok(let cfg) = result else { return XCTFail("파싱 실패") }
        let t = BatteryNeglectTracker(percentThreshold: cfg.safeBattery().neglectPercent)
        // 50% 가 임계가 되므로 51 은 방치 아님
        t.observe(serial: "a", level: 51, isCharging: false, now: t0)
        XCTAssertTrue(t.snapshot(now: t0).isEmpty)
        // 50 은 방치
        t.observe(serial: "b", level: 50, isCharging: false, now: t0)
        XCTAssertNotNil(t.snapshot(now: t0)["b"])
    }

    // MARK: - 지표로 이어짐

    func testNeglectRowAppearsOnlyForNeglectedDevice() {
        let t = tracker()
        t.observe(serial: "a", level: 10, isCharging: false, now: t0)
        t.observe(serial: "b", level: 10, isCharging: true, now: t0)

        var devA = DeviceSnapshot()
        devA.serial = "a"
        devA.isOnline = true
        var devB = DeviceSnapshot()
        devB.serial = "b"
        devB.isOnline = true
        devB.batteryLevel = 10

        let snap = MetricsSnapshotBuilder.make(
            devices: [devA, devB], events: [],
            now: at(30), version: "1", neglect: t.snapshot(now: at(30))
        )
        XCTAssertEqual(snap.devices.first { $0.serial == "a" }?.neglectSeconds, 1_800)
        XCTAssertNil(snap.devices.first { $0.serial == "b" }?.neglectSeconds, "충전 중은 방치 행이 없다")

        let text = MetricsTextBuilder.render(snap)
        XCTAssertTrue(text.contains("relay_device_battery_neglect_seconds{serial=\"a\"} 1800"))
        XCTAssertFalse(text.contains("relay_device_battery_neglect_seconds{serial=\"b\"}"))
    }

    func testOfflineDeviceHasNoNeglectRow() {
        // 오프라인 기기는 방치 계산이 아니라 **관측 없음**이다 — 방치로 세지 않는다
        var dev = DeviceSnapshot()
        dev.serial = "a"
        dev.isOnline = false
        let snap = MetricsSnapshotBuilder.make(
            devices: [dev], events: [], now: t0, version: "1",
            neglect: ["a": 3_600]
        )
        XCTAssertNil(snap.devices[0].neglectSeconds)
    }
}

/// `rules.yaml` 의 `battery:` 블록 — S3 파서 확장
final class BatteryRulesParseTests: XCTestCase {

    private func parse(_ text: String) -> RulesConfig.LoadResult {
        RulesConfig.parse(text)
    }

    private func config(_ text: String) throws -> RulesConfig {
        guard case .ok(let c) = parse(text) else {
            XCTFail("파싱 실패: \(parse(text))")
            throw NSError(domain: "t", code: 1)
        }
        return c
    }

    func testNoBatteryBlockUsesBuiltIn() {
        let c = try? config("""
        version: 1
        rules:
          memoryLow: { enter: 90, clear: 80, cooldown: 60 }
        """)
        XCTAssertEqual(c?.battery, .builtIn, "쓰지 않으면 기본값 (20%)")
        XCTAssertEqual(c?.battery.neglectPercent, 20)
    }

    func testBatteryBlockOverrides() throws {
        let c = try config("""
        version: 1
        rules:
          memoryLow: { enter: 90, clear: 80, cooldown: 60 }
        battery: { neglectPercent: 30 }
        """)
        XCTAssertEqual(c.battery.neglectPercent, 30)
    }

    func testBatteryBeforeRulesStillWorks() throws {
        let c = try config("""
        version: 1
        battery: { neglectPercent: 15 }
        rules:
          memoryLow: { enter: 90, clear: 80, cooldown: 60 }
        """)
        XCTAssertEqual(c.battery.neglectPercent, 15)
        XCTAssertEqual(c.rule(.memoryLow).enter, 90)
    }

    func testOutOfRangeIsRejectedNotApplied() throws {
        // ★ 죽지 않는다 — 검증에서 걸러 **기본값으로 남는다**
        let c = try config("""
        version: 1
        rules:
          memoryLow: { enter: 90, clear: 80, cooldown: 60 }
        battery: { neglectPercent: 0 }
        """)
        XCTAssertEqual(c.battery.neglectPercent, 20, "0% 는 모호하므로 거부된다")
        XCTAssertEqual(c.rejected.count, 1)
        XCTAssertTrue(c.rejected[0].contains("neglectPercent"))
    }

    func testOver100IsRejected() throws {
        let c = try config("""
        version: 1
        rules:
          memoryLow: { enter: 90, clear: 80, cooldown: 60 }
        battery: { neglectPercent: 101 }
        """)
        XCTAssertEqual(c.battery.neglectPercent, 20)
        XCTAssertEqual(c.rejected.count, 1)
    }

    func testNonIntegerIsRejected() throws {
        let c = try config("""
        version: 1
        rules:
          memoryLow: { enter: 90, clear: 80, cooldown: 60 }
        battery: { neglectPercent: 20.5 }
        """)
        XCTAssertEqual(c.battery.neglectPercent, 20)
        XCTAssertTrue(c.rejected[0].contains("정수"))
    }

    func testUnknownBatteryKeyIsRejected() throws {
        let c = try config("""
        version: 1
        rules:
          memoryLow: { enter: 90, clear: 80, cooldown: 60 }
        battery: { neglectPercent: 20, neglectMinutes: 90 }
        """)
        XCTAssertTrue(c.rejected.contains { $0.contains("neglectMinutes") },
                      "지원하지 않는 키는 조용히 버리지 않고 사유를 남긴다")
    }

    func testUnknownTopLevelKeyStillFails() {
        // 새 키를 추가한다고 "모르는 최상위 키" 검사가 약해지지 않는다
        guard case .failed(let why) = parse("""
        version: 1
        rules:
          memoryLow: { enter: 90, clear: 80, cooldown: 60 }
        bogus: { a: 1 }
        """) else { return XCTFail("모르는 최상위 키는 실패해야 한다") }
        XCTAssertTrue(why.contains("bogus"))
    }

    func testBatteryOnlyFileIsAccepted() throws {
        // rules 블록 없이 battery 만 있어도 로드된다 (기존 파일 규칙과 충돌 없음)
        let c = try config("""
        version: 1
        battery: { neglectPercent: 25 }
        """)
        XCTAssertEqual(c.battery.neglectPercent, 25)
    }

    func testSafeBatteryFallsBackOnInvalidState() {
        var bad = RulesConfig.Battery.builtIn
        bad.neglectPercent = 0
        let cfg = RulesConfig(battery: bad)
        XCTAssertEqual(cfg.safeBattery().neglectPercent, 20)
    }
}
