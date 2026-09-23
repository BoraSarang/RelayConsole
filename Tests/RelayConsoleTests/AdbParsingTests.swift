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

    // MARK: - SettingWatch (parseSettingValue)

    @Test func parseSettingValueOneZero() {
        #expect(AdbClient.parseSettingValue("1") == "1")
        #expect(AdbClient.parseSettingValue("0\n") == "0")
    }

    @Test func parseSettingValueNullEmptyNil() {
        #expect(AdbClient.parseSettingValue("null") == nil)
        #expect(AdbClient.parseSettingValue("") == nil)
        #expect(AdbClient.parseSettingValue("  \n") == nil)
    }

    // MARK: - LogcatWatch (countLogcatHits / timestamp)

    @Test func countLogcatHitsKeywords() {
        let sample = """
        09-23 19:30:04.962  1235  1235 I WindowManager: accelerometer_rotation set to 1
        09-23 19:30:05.100  1235  1235 I wm: wm_user_rotation_changed rotation=0
        09-23 19:30:05.200  1235  1235 I ThermalEngine: thermal level changed
        09-23 19:30:05.300  1235  1235 I unrelated: hello world
        """
        #expect(AdbClient.countLogcatHits(sample) == 3)
    }

    @Test func countLogcatHitsEmptyNilKeywords() {
        #expect(AdbClient.countLogcatHits("") == 0)
        #expect(AdbClient.countLogcatHits("any line", keywords: []) == 0)
    }

    @Test func countLogcatHitsCaseInsensitive() {
        let sample = "09-23 10:00:00.000  1  1 I T: THERMAL throttling"
        #expect(AdbClient.countLogcatHits(sample) == 1)
    }

    @Test func logcatTimestampParses() {
        let line = "09-23 19:30:04.962  12350 12350 I adbd    : service requested"
        #expect(AdbClient.logcatLineTimestamp(line) == "09-23 19:30:04.962")
        #expect(AdbClient.logcatLineTimestamp("not a log line") == nil)
    }

    @Test func firstLogcatTimestampSkipsEmpty() {
        let text = "\n\n09-23 19:30:04.962  1  1 I tag: msg\n"
        #expect(AdbClient.firstLogcatTimestamp(text) == "09-23 19:30:04.962")
        #expect(AdbClient.firstLogcatTimestamp("") == nil)
    }

    @Test func lastLogcatTimestampTakesNewest() {
        let text = """
        09-23 19:30:04.962  1  1 I a: first
        09-23 19:30:10.100  1  1 I b: last
        """
        #expect(AdbClient.lastLogcatTimestamp(text) == "09-23 19:30:10.100")
        #expect(AdbClient.lastLogcatTimestamp("") == nil)
    }

    @Test func countLogcatHitsExcludesCursorLine() {
        let text = """
        09-23 19:30:04.962  1  1 I a: accelerometer_rotation hit
        09-23 19:30:10.100  1  1 I b: thermal hit
        """
        // cursor = first line ts → first line 제외, second만 카운트
        #expect(AdbClient.countLogcatHits(text, afterTimestamp: "09-23 19:30:04.962") == 1)
        // cursor 없음 → 둘 다
        #expect(AdbClient.countLogcatHits(text) == 2)
        // cursor가 마지막보다 같거나 큼 → 0
        #expect(AdbClient.countLogcatHits(text, afterTimestamp: "09-23 19:30:10.100") == 0)
    }

    // MARK: - Inventory merge (watch counts)

    @Test func inventoryMergePreservesWatchCounts() {
        var inv = DeviceInventory()
        var a = DeviceSnapshot(serial: "SER1", model: "SM", isOnline: true)
        a.settingsChangedCount = 2
        a.logcatHitCount = 5
        inv.merge(a)
        var b = DeviceSnapshot(serial: "SER1", model: "SM", isOnline: true)
        b.settingsChangedCount = nil
        b.logcatHitCount = nil
        inv.merge(b)
        #expect(inv.devices[0].settingsChangedCount == 2)
        #expect(inv.devices[0].logcatHitCount == 5)
        var c = DeviceSnapshot(serial: "SER1", model: "SM", isOnline: true)
        c.settingsChangedCount = 3
        c.logcatHitCount = 7
        inv.merge(c)
        #expect(inv.devices[0].settingsChangedCount == 3)
        #expect(inv.devices[0].logcatHitCount == 7)
    }

    // MARK: - Connection (PLAN_v0.3)

    @Test func parseConnectionNetworkSerial() {
        let c = AdbClient.parseConnection("10.233.247.205:5555")
        #expect(c.kind == .network)
        #expect(c.label == "10.233.247.205:5555")
    }

    @Test func parseConnectionUsbSerial() {
        let c = AdbClient.parseConnection("R5CT10ABCDE")
        #expect(c.kind == .usb)
        #expect(c.label == "USB")
    }

    @Test func parseDeviceNameFromSettings() {
        #expect(AdbClient.parseDeviceName("S22\n") == "S22")
        #expect(AdbClient.parseDeviceName("null") == nil)
        #expect(AdbClient.parseDeviceName("") == nil)
    }

    @Test func displayDeviceNamePrefersNameThenModel() {
        #expect(AdbClient.displayDeviceName(deviceName: "S22", model: "SM_S901N", serial: "x") == "S22")
        #expect(AdbClient.displayDeviceName(deviceName: nil, model: "SM_S901N", serial: "x") == "SM_S901N")
        #expect(AdbClient.displayDeviceName(deviceName: nil, model: "", serial: "ABCD1234") == "…1234")
    }

    // MARK: - Two-serial inventory merge (PLAN_v0.3)

    @Test func inventoryMergeTwoDistinctSerials() {
        var inv = DeviceInventory()
        var a = DeviceSnapshot(serial: "10.0.0.1:5555", model: "A", isOnline: true)
        a.batteryLevel = 80
        a.connectionKind = .network
        a.deviceName = "Alpha"
        inv.merge(a)
        var b = DeviceSnapshot(serial: "R5USB2222", model: "B", isOnline: true)
        b.batteryLevel = 91
        b.connectionKind = .usb
        b.deviceName = "Beta"
        inv.merge(b)
        #expect(inv.devices.count == 2)
        #expect(inv.device(serial: "10.0.0.1:5555")?.batteryLevel == 80)
        #expect(inv.device(serial: "R5USB2222")?.batteryLevel == 91)
        #expect(inv.device(serial: "10.0.0.1:5555")?.connectionKind == .network)
        #expect(inv.device(serial: "R5USB2222")?.connectionKind == .usb)
        #expect(inv.onlineDevices.count == 2)
    }

    // MARK: - CPU cores

    @Test func parseCpuCoresFreqs() {
        let cur = "1171200\n1800000\n2400000\n800000\n"
        let max = "1363200\n2400000\n3000000\n1800000\n"
        let s = AdbClient.parseCpuCores(curText: cur, maxText: max, governorText: "walt\nwalt\n")
        #expect(s.curMHz.count == 4)
        #expect(abs(s.curMHz[0] - 1171.2) < 0.1)
        #expect(s.maxMHz[2] == 3000)
        #expect(s.governor == "walt")
    }

    @Test func parseProcStatCoresAndDelta() {
        let text = """
        cpu  100 0 50 800 20 0 10 0 0 0
        cpu0 50 0 25 400 10 0 5 0 0 0
        cpu1 50 0 25 400 10 0 5 0 0 0
        """
        let a = AdbClient.parseProcStatCores(text)
        #expect(a.cores.count == 2)
        let text2 = """
        cpu  200 0 100 900 40 0 20 0 0 0
        cpu0 100 0 50 450 20 0 10 0 0 0
        cpu1 100 0 50 450 20 0 10 0 0 0
        """
        let b = AdbClient.parseProcStatCores(text2)
        let uses = AdbClient.coreUsePercents(prev: a, curr: b)
        #expect(uses != nil)
        #expect(uses!.count == 2)
    }

    // MARK: - Pressure / Top RSS / Zones / Signal / Wi-Fi

    @Test func parsePressureSomeAvg10() {
        let sample = """
        some avg10=12.50 avg60=8.20 avg300=5.10 total=123456
        full avg10=1.00 avg60=0.50 avg300=0.20 total=999
        """
        let p = AdbClient.parsePressure(sample)
        #expect(p.pct != nil)
        #expect(abs(p.pct! - 12.5) < 0.01)
        #expect(p.label == "moderate")
    }

    @Test func parseTopRssRows() {
        let sample = """
        RSS NAME
        714368 com.example.app
        532480 system_server
        10240 lowmemkiller
        """
        let top = AdbClient.parseTopRss(sample, limit: 2)
        #expect(top.count == 2)
        #expect(top[0].name == "com.example.app")
        #expect(top[0].rssMB > 600)
    }

    @Test func parseThermalZonesMulti() {
        let sample = """
        Temperature{mValue=53.0, mType=0, mName=AP, mStatus=0}
        Temperature{mValue=44.3, mType=3, mName=SKIN, mStatus=3}
        Temperature{mValue=42.3, mType=2, mName=BAT, mStatus=0}
        """
        let z = AdbClient.parseThermalZones(sample)
        #expect(z.zones.count == 3)
        #expect(z.zones[0].name == "AP")
        #expect(z.zones[2].tempC == 42.3)
    }

    @Test func parseSignalRsrp() {
        let sample = """
        mSignalStrength=CellSignalStrengthLte: rssi=-67 rsrp=-100 rsrq=-13 rssnr=15 level=3
        mOperatorAlphaLong=KT
        """
        let s = AdbClient.parseSignal(sample)
        #expect(s.rsrp == -100)
        #expect(s.carrier == "KT")
    }

    @Test func parseWifiStatusDisabled() {
        #expect(AdbClient.parseWifiStatus("Wifi is disabled\n").enabled == false)
        #expect(AdbClient.parseWifiStatus("Wi-Fi is disabled\n").enabled == false)
    }

    @Test func parseWifiStatusSsidRssi() {
        let sample = """
        Wi-Fi is enabled
        SSID: PixelLab_5G, RSSI: -42
        """
        let w = AdbClient.parseWifiStatus(sample)
        #expect(w.enabled == true)
        #expect(w.ssid == "PixelLab_5G")
        #expect(w.rssi == -42)
    }

    // MARK: - P2 GPU / Sensors / Disk (PLAN_v0.4)

    @Test func parseGpuGlesAdreno() {
        let sample = """
        GLES: Qualcomm, Adreno (TM) 730, OpenGL ES 3.2 V@0615.98 (GIT8e3c4e392d)
        """
        let g = AdbClient.parseGpuGles(sample)
        #expect(g.renderer != nil)
        #expect(g.renderer!.contains("Adreno"))
        #expect(g.esVersion == "3.2")
    }

    @Test func parseGpuGlesEmptyNil() {
        let g = AdbClient.parseGpuGles("no gpu here")
        #expect(g.renderer == nil)
        #expect(g.esVersion == nil)
    }

    @Test func parseGpuBusyPercentAndGpubusy() {
        #expect(AdbClient.parseGpuBusyPercent("12 %\n") == 12)
        #expect(AdbClient.parseGpuBusyPercent("0 %") == 0)
        // busy idle jiffies → ratio
        let b = AdbClient.parseGpuBusyPercent("100 900")
        #expect(b != nil)
        #expect(abs(b! - 10.0) < 0.01)
        #expect(AdbClient.parseGpuBusyPercent("") == nil)
    }

    @Test func parseGpuClkMHz() {
        #expect(AdbClient.parseGpuClkMHz("285000000") == 285)
        #expect(AdbClient.parseGpuClkMHz("315\n") == 315)
        #expect(AdbClient.parseGpuClkMHz("") == nil)
    }

    @Test func parseSensorsSummaryTotalAndActive() {
        let sample = """
        Total 39 h/w sensors, 39 running 0 disabled
        active connections:
          Connection Number: 0, active-count = 1 rate = 200000000 ns
            0x00000001) type 0x00000001 (accelerometer) | ver=1 | min=0ms | max=0ms
            0x00000004) type 0x00000004 (gyroscope) | ver=1 | min=0ms | max=0ms
        """
        let s = AdbClient.parseSensorsSummary(sample)
        #expect(s.total == 39)
        #expect(s.activeCount == 1)
        #expect(s.activeNames.contains("accelerometer"))
        #expect(s.activeNames.contains("gyroscope"))
    }

    @Test func parseSensorsSummarySamsungActiveLines() {
        // 실측 SM_S901N 형식 — 이름(handle=) + active-count 동일 라인
        let sample = """
        Sensor Device:
        Total 39 h/w sensors, 39 running 0 disabled clients:
        lsm6dso LSM6DSO Accelerometer Non-wakeup(handle=0x0000000b)  active-count = 1; sampling_period(ms) = {20.0}, selected = 20.00 ms; batching_period(ms) = {0.0}, selected = 0.00 ms
        STK33915 Light Ambient Light Sensor Non-wakeup(handle=0x00000033)  active-count = 1; sampling_period(ms) = {200.0}, selected = 200.00 ms; batching_period(ms) = {0.0}, selected = 0.00 ms
        smd  Wakeup                        (handle=0x000000ac)  active-count = 3; sampling_period(ms) = {1.0, 1.0, 1.0}, selected = 1.00 ms; batching_period(ms) = {0.0, 0.0, 0.0}, selected = 0.00 ms
        step_counter  Non-wakeup           (handle=0x000000bf)  active-count = 1; sampling_period(ms) = {200.0}, selected = 200.00 ms; batching_period(ms) = {0.0}, selected = 0.00 ms
        SensorHub type                     (handle=0x000005dd)  active-count = 1; sampling_period(ms) = {1.0}, selected = 1.00 ms; batching_period(ms) = {0.0}, selected = 0.00 ms
        Flip Cover Detector  Wakeup        (handle=0x000007f0)  active-count = 1; sampling_period(ms) = {200.0}, selected = 200.00 ms; batching_period(ms) = {0.0}, selected = 0.00 ms
        Sensor List:
        """
        let s = AdbClient.parseSensorsSummary(sample)
        #expect(s.total == 39)
        #expect(s.activeCount == 6)
        #expect(s.activeNames.count == 6)
        #expect(s.activeNames.contains { $0.contains("Accelerometer") })
        #expect(s.activeNames.contains("smd"))
        #expect(s.activeNames.contains("step_counter"))
        #expect(s.activeNames.contains("Flip Cover Detector"))
        #expect(s.activeNames.contains("SensorHub type"))
        #expect(s.activePeriodsMs.first == 20.0)
        // Non-wakeup suffix stripped
        #expect(!s.activeNames.contains { $0.hasSuffix("Non-wakeup") })
        #expect(!s.activeNames.contains { $0.hasSuffix("Wakeup") })
    }

    @Test func parseDiskStatsSdaOnly() {
        let sample = """
         8       0 sda 1000 0 8000 10 2000 0 16000 20 0 30 40
         8       1 sda1 900 0 7000 10 1000 0 8000 20 0 10 10
        """
        let d = AdbClient.parseDiskStats(sample)
        #expect(d.readSectors == 8000)
        #expect(d.writeSectors == 16000)
    }

    @Test func diskRateFirstTickNil() {
        let a = AdbClient.DiskSample()
        let b = AdbClient.DiskSample(readSectors: 2048, writeSectors: 2048)
        #expect(AdbClient.diskRatesMBps(prev: a, curr: b, seconds: 1) == nil)
    }

    @Test func diskRateFromDelta() {
        // 2048 sectors * 512 B = 1 MiB over 1s → 1 MB/s
        let a = AdbClient.DiskSample(readSectors: 0, writeSectors: 0)
        let b = AdbClient.DiskSample(readSectors: 2048, writeSectors: 4096)
        let r = AdbClient.diskRatesMBps(prev: a, curr: b, seconds: 1)
        #expect(r != nil)
        #expect(abs(r!.read - 1.0) < 0.01)
        #expect(abs(r!.write - 2.0) < 0.01)
    }

    @Test func inventoryMergePreservesP2Fields() {
        var inv = DeviceInventory()
        var a = DeviceSnapshot(serial: "SER1", model: "SM", isOnline: true)
        a.gpuRenderer = "Adreno (TM) 730"
        a.gpuEsVersion = "3.2"
        a.sensorTotalCount = 39
        a.sensorActiveCount = 2
        inv.merge(a)
        var b = DeviceSnapshot(serial: "SER1", model: "SM", isOnline: true)
        b.gpuUtilPercent = 12
        b.diskReadMBps = 0.5
        inv.merge(b)
        #expect(inv.devices[0].gpuRenderer == "Adreno (TM) 730")
        #expect(inv.devices[0].sensorTotalCount == 39)
        #expect(inv.devices[0].gpuUtilPercent == 12)
        #expect(inv.devices[0].diskReadMBps == 0.5)
    }
}
