import Testing
@testable import RelayConsole

struct AdbParsingTests {
    // MARK: - Battery

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
        #expect(snap.voltageMV == 4143)
    }

    @Test func parseBatteryChargingStatus() {
        let sample = "status: 2\nlevel: 50"
        let snap = AdbClient.parseBattery(sample)
        #expect(snap.isCharging == true)
    }

    @Test func parseBatteryExSamsung() {
        let sample = """
        level: 84
        voltage: 4143
        temperature: 423
        status: 2
        mProtectBatteryMode: 1
        mProtectionThreshold: 80
        mSavedBatteryAsoc: [93]
        mSavedBatteryUsage: [80739]
        mSavedBatteryBsoh: 91
        """
        let snap = AdbClient.parseBatteryEx(sample)
        #expect(snap.batteryHealthPct == 91)
        #expect(snap.isProtectionMode == true)
        #expect(snap.protectionThresholdPct == 80)
        #expect(snap.cycleEstimate == 807)
        #expect(snap.isCharging == true)
    }

    @Test func shortIdMasksSerial() {
        #expect(AdbClient.shortId("R5CT10ABCDE") == "…BCDE")
        #expect(AdbClient.shortId("ab") == "ab")
    }

    @Test func parseNetworkTypeWifi() {
        let sample = """
        Active default network: 115
        NetworkAgentInfo{network{115} ni{ CONNECTED } nc{[ Transports: WIFI Capabilities: VALIDATED]}}
        NetworkAgentInfo{network{116} ni{MOBILE[LTE] CONNECTED} nc{[ Transports: CELLULAR]}}
        """
        #expect(AdbClient.parseNetworkType(sample) == "Wi-Fi")
    }

    @Test func parseNetworkTypeLte() {
        let sample = """
        Active default network: 116
        NetworkAgentInfo{network{115} nc{[ Transports: WIFI]}}
        NetworkAgentInfo{network{116} ni{MOBILE[LTE] CONNECTED extra: lte.ktfwing.com} nc{[ Transports: CELLULAR]}}
        """
        #expect(AdbClient.parseNetworkType(sample) == "LTE")
    }

    @Test func parseNetworkTypeEmptyNil() {
        #expect(AdbClient.parseNetworkType("") == nil)
    }

    @Test func missingFieldFallsBackNil() {
        let snap = AdbClient.parseBattery("")
        #expect(snap.batteryLevel == nil)
        #expect(snap.batteryTempC == nil)
        #expect(snap.isCharging == nil)
        #expect(snap.voltageMV == nil)
        #expect(snap.batteryHealthPct == nil)
    }

    // MARK: - Thermal

    @Test func parseThermalSample() {
        let sample = """
        Thermal Status: 3
        Temperature{mValue=53.0, mType=0, mName=AP, mStatus=0}
        Temperature{mValue=44.3, mType=3, mName=SKIN, mStatus=3}
        Temperature{mValue=42.3, mType=2, mName=BAT, mStatus=0}
        """
        let th = AdbClient.parseThermal(sample)
        #expect(th.status == 3)
        #expect(th.apTempC == 53.0)
        #expect(th.skinTempC == 44.3)
        #expect(th.batTempC == 42.3)
    }

    @Test func parseThermalEmptyNil() {
        let th = AdbClient.parseThermal("")
        #expect(th.status == nil)
        #expect(th.apTempC == nil)
    }

    // MARK: - Load

    @Test func parseLoadAvgSample() {
        let la = AdbClient.parseLoadAvg("4.49 5.13 4.45 14/4457 3975")
        #expect(la.load1 == 4.49)
        #expect(la.load5 == 5.13)
        #expect(la.load15 == 4.45)
    }

    @Test func parseLoadAvgShortNil() {
        let la = AdbClient.parseLoadAvg("4.49")
        #expect(la.load1 == 4.49)
        #expect(la.load5 == nil)
    }

    // MARK: - Memory

    @Test func parseMemInfoSample() {
        let sample = """
        MemTotal:       7394216 kB
        MemAvailable:   2841964 kB
        SwapTotal:      1234560 kB
        """
        let mem = AdbClient.parseMemInfo(sample)
        #expect(mem.totalGB != nil)
        #expect(mem.totalGB! > 7.0 && mem.totalGB! < 7.5)
        #expect(mem.availableGB != nil)
        #expect(mem.usedGB != nil)
        #expect(mem.usedGB! > 4.0 && mem.usedGB! < 5.0)
        #expect(mem.swapTotalGB != nil)
    }

    @Test func parseMemInfoEmptyAllNil() {
        let mem = AdbClient.parseMemInfo("")
        #expect(mem.totalGB == nil)
        #expect(mem.usedGB == nil)
    }

    // MARK: - CPU /proc/stat

    @Test func parseProcStatAggregate() {
        let sample = """
        cpu  100 0 50 800 20 0 10 0 0 0
        cpu0 50 0 25 400 10 0 5 0 0 0
        """
        let s = AdbClient.parseProcStat(sample)
        #expect(s.total != nil)
        #expect(s.idle != nil)
        #expect(s.total == 980)
        #expect(s.idle == 820)
    }

    @Test func cpuUsePercentDelta() {
        let a = AdbClient.ProcStatSample(total: 1000, idle: 900)
        let b = AdbClient.ProcStatSample(total: 1100, idle: 980)
        // totalD=100, idleD=80 → busyD=20 → 20%
        let use = AdbClient.cpuUsePercent(prev: a, curr: b)
        #expect(use != nil)
        #expect(abs(use! - 20.0) < 0.01)
    }

    @Test func cpuUsePercentFirstTickNil() {
        let a = AdbClient.ProcStatSample()
        let b = AdbClient.ProcStatSample(total: 100, idle: 90)
        #expect(AdbClient.cpuUsePercent(prev: a, curr: b) == nil)
    }

    // MARK: - Storage df

    @Test func parseDfHumanSample() {
        let sample = """
        Filesystem      Size  Used Avail Use% Mounted on
        /dev/block/dm-52 223G   23G  200G  11% /data
        """
        let df = AdbClient.parseDf(sample)
        #expect(df.totalGB == 223)
        #expect(df.usedGB == 23)
        #expect(df.usePercent == 11)
    }

    @Test func parseDfOneUiStorageMount() {
        // 실측: df -h /data → /storage/emulated/0/Android/obb
        let sample = """
        Filesystem       Size Used Avail Use% Mounted on
        /dev/block/dm-58 223G  23G  200G  11% /storage/emulated/0/Android/obb
        """
        let df = AdbClient.parseDf(sample)
        #expect(df.totalGB == 223)
        #expect(df.usedGB == 23)
        #expect(df.usePercent == 11)
    }

    @Test func parseDfEmptyNil() {
        let df = AdbClient.parseDf("")
        #expect(df.totalGB == nil)
        #expect(df.usedGB == nil)
    }

    // MARK: - Network /proc/net/dev

    @Test func parseNetDevSumsNonLoopback() {
        let sample = """
        Inter-|   Receive                                                |  Transmit
         face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
            lo: 1000       10    0    0    0     0          0         0     1000      10    0    0    0     0       0          0
         wlan0: 5000       20    0    0    0     0          0         0     3000      15    0    0    0     0       0          0
           rmnet0: 7000     30    0    0    0     0          0         0     2000      12    0    0    0     0       0          0
        """
        let net = AdbClient.parseNetDev(sample)
        #expect(net.rxBytes == 12000)
        #expect(net.txBytes == 5000)
    }

    @Test func netRateFromDelta() {
        let a = AdbClient.NetSample(rxBytes: 1024 * 1024, txBytes: 0)
        let b = AdbClient.NetSample(rxBytes: 3 * 1024 * 1024, txBytes: 1024 * 1024)
        let rate = AdbClient.netRatesMBps(prev: a, curr: b, seconds: 1)
        #expect(rate != nil)
        #expect(abs(rate!.down - 2.0) < 0.01)
        #expect(abs(rate!.up - 1.0) < 0.01)
    }

    @Test func netRateFirstTickNil() {
        let a = AdbClient.NetSample()
        let b = AdbClient.NetSample(rxBytes: 100, txBytes: 100)
        #expect(AdbClient.netRatesMBps(prev: a, curr: b, seconds: 1) == nil)
    }

    // MARK: - Metrics ring

    @Test func metricsRingCapacity60() {
        var m = DroidMetrics()
        for i in 0..<70 {
            m.push(cpu: Double(i))
        }
        #expect(m.cpuHistory.count == 60)
        #expect(m.cpuHistory.first == 10)
        #expect(m.cpuHistory.last == 69)
    }

    // MARK: - Inventory merge (P0-a)

    @Test func inventoryMergeUpdatesSameSerial() {
        var inv = DeviceInventory()
        var a = DeviceSnapshot(serial: "SER1", model: "SM_S901N", isOnline: true)
        a.batteryLevel = 80
        a.memoryUsedGB = 4.3
        inv.merge(a)
        var b = DeviceSnapshot(serial: "SER1", model: "SM_S901N", isOnline: true)
        b.batteryLevel = 79
        // b는 mem 미포함 → 이전 mem 유지 (5s 틱이 15s 필드 덮지 않음)
        inv.merge(b)
        #expect(inv.devices.count == 1)
        #expect(inv.devices[0].batteryLevel == 79)
        #expect(inv.devices[0].memoryUsedGB == 4.3)
    }

    @Test func inventoryMergeIgnoresEmptySerial() {
        var inv = DeviceInventory()
        inv.merge(DeviceSnapshot())
        #expect(inv.devices.isEmpty)
    }

    @Test func thermalAlertTriggersAt40OrStatus2() {
        var s = DeviceSnapshot()
        #expect(!s.isThermalAlert)
        s.batteryTempC = 40
        #expect(s.isThermalAlert)
        s.batteryTempC = nil
        s.thermalStatus = 2
        #expect(s.isThermalAlert)
        s.thermalStatus = 1
        #expect(!s.isThermalAlert)
    }
}
