import Testing
@testable import RelayConsole

struct AdbParsingTests {
    @Test func parseBatteryCoreFields() {
        let sample = """
        level: 84
        voltage: 4143
        temperature: 423
        status: 4
        """
        let snap = AdbClient.parseBattery(sample)
        #expect(snap.batteryLevel == 84)
        #expect(snap.batteryTempC == 42.3)
        #expect(snap.isCharging == false)
    }

    @Test func parseBatteryChargingStatus() {
        let sample = "status: 2\nlevel: 50"
        let snap = AdbClient.parseBattery(sample)
        #expect(snap.isCharging == true)
    }

    @Test func shortIdMasksSerial() {
        #expect(AdbClient.shortId("R5CT10ABCDE") == "…BCDE")
        #expect(AdbClient.shortId("ab") == "ab")
    }

    @Test func missingFieldFallsBackNil() {
        let snap = AdbClient.parseBattery("")
        #expect(snap.batteryLevel == nil)
        #expect(snap.batteryTempC == nil)
        #expect(snap.isCharging == nil)
    }

    @Test func metricsRingCapacity60() {
        var m = DroidMetrics()
        for i in 0..<70 {
            m.push(cpu: Double(i))
        }
        #expect(m.cpuHistory.count == 60)
        #expect(m.cpuHistory.first == 10)
        #expect(m.cpuHistory.last == 69)
    }
}
