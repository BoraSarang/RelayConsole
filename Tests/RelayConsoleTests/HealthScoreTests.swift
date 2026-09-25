import Foundation
@testable import RelayConsole
import Testing

struct HealthScoreTests {
    @Test func bandBoundaries() {
        #expect(HealthScoreLogic.bandKey(total: 100) == "health.band.good")
        #expect(HealthScoreLogic.bandKey(total: 80) == "health.band.good")
        #expect(HealthScoreLogic.bandKey(total: 79) == "health.band.fair")
        #expect(HealthScoreLogic.bandKey(total: 50) == "health.band.fair")
        #expect(HealthScoreLogic.bandKey(total: 49) == "health.band.poor")
        #expect(HealthScoreLogic.bandKey(total: 0) == "health.band.poor")
    }

    @Test func offlineReturnsNil() {
        var d = DeviceSnapshot()
        d.isOnline = false
        d.batteryLevel = 100
        d.thermalStatus = 0
        d.cpuUsePercent = 0
        #expect(HealthScoreLogic.score(from: d) == nil)
    }

    @Test func onlineNoSignalsReturnsNil() {
        var d = DeviceSnapshot()
        d.isOnline = true
        #expect(HealthScoreLogic.score(from: d) == nil)
    }

    @Test func perfectSnapshotScoresHigh() throws {
        var d = DeviceSnapshot()
        d.isOnline = true
        d.batteryLevel = 100
        d.batteryHealthPct = 100
        d.isCharging = true
        d.thermalStatus = 0
        d.deviceTempC = 30
        d.cpuUsePercent = 0
        d.load1 = 0.5
        let s = try #require(HealthScoreLogic.score(from: d))
        #expect(s.total == 100)
        #expect(s.battery == 100)
        #expect(s.thermal == 100)
        #expect(s.throttle == 100)
        #expect(s.bandKey == "health.band.good")
    }

    @Test func stressedSnapshotScoresLow() throws {
        var d = DeviceSnapshot()
        d.isOnline = true
        d.batteryLevel = 5
        d.isCharging = false
        d.thermalStatus = 5
        d.deviceTempC = 55
        d.cpuUsePercent = 100
        d.load1 = 32
        let s = try #require(HealthScoreLogic.score(from: d))
        #expect(s.total <= 30)
        #expect(s.bandKey == "health.band.poor")
    }

    @Test func chargingRaisesLowBatteryFloor() {
        var low = DeviceSnapshot()
        low.isOnline = true
        low.batteryLevel = 5
        low.isCharging = false
        let discharged = HealthScoreLogic.batteryScore(low)

        var charging = low
        charging.isCharging = true
        let charged = HealthScoreLogic.batteryScore(charging)

        #expect(discharged == 5)
        #expect(charged == 40)
    }

    @Test func thermalUsesBestOfStatusAndTemp() {
        var d = DeviceSnapshot()
        d.thermalStatus = 4
        d.deviceTempC = 30
        #expect(HealthScoreLogic.thermalScore(d) == 100)

        d.thermalStatus = 0
        d.deviceTempC = 55
        #expect(HealthScoreLogic.thermalScore(d) == 100)
    }

    @Test func statusAndTempScores() {
        #expect(HealthScoreLogic.statusScore(0) == 100)
        #expect(HealthScoreLogic.statusScore(3) == 50)
        #expect(HealthScoreLogic.statusScore(6) == 0)
        #expect(HealthScoreLogic.tempScore(35) == 100)
        #expect(HealthScoreLogic.tempScore(55) == 0)
        #expect(HealthScoreLogic.tempScore(45) == 70)
    }

    @Test func throttleTakesConservativeMin() throws {
        var d = DeviceSnapshot()
        d.cpuUsePercent = 10
        d.load1 = 40
        let score = try #require(HealthScoreLogic.throttleScore(d))
        #expect(score == HealthScoreLogic.loadScore(40))
        #expect(score < HealthScoreLogic.cpuLoadScore(10))
    }

    @Test func missingMetricsAreExcludedNotInterpolated() throws {
        var d = DeviceSnapshot()
        d.isOnline = true
        d.batteryLevel = 100
        d.batteryHealthPct = 100
        let s = try #require(HealthScoreLogic.score(from: d))
        // 결측을 50으로 보간하면 70이 됨 — 미측정은 가중치에서 제외 (AGENTS.local §4 [표시②])
        #expect(s.battery == 100)
        #expect(s.thermal == nil)
        #expect(s.throttle == nil)
        #expect(s.total == 100)
    }

    @Test func clampBounds() {
        #expect(HealthScoreLogic.clamp(-5) == 0)
        #expect(HealthScoreLogic.clamp(150) == 100)
        #expect(HealthScoreLogic.cpuLoadScore(-1) == 100)
        #expect(HealthScoreLogic.cpuLoadScore(100) == 20)
    }
}
