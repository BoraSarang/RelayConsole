import Foundation

/// ADB 백그라운드 폴링 — 5s fast / 15s slow / 다중 serial
/// IO는 이 actor 안에서만. UI는 ConsoleStore.inventory.devices만 읽음 (P0-a)
actor DeviceMonitor {
    static let shared = DeviceMonitor()
    /// SKILLPACK §4 고정 키워드
    static let logcatKeywords = ["accelerometer_rotation", "wm_user_rotation_changed", "thermal"]
    /// v0.8 — ANR / 크래시 감지 (대소문자 무시 부분 매칭)
    static let anrKeywords = ["anr in", "am_anr", "application not responding", "input dispatching timed out"]
    static let crashKeywords = ["fatal exception", "fatal signal", "has died", "force finishing"]

    /// 기기별 폴링 상태 (다중 serial)
    private struct DeviceState {
        var model: String?
        var deviceName: String?
        var connectionKind: ConnectionKind?
        var connectionLabel: String?
        var prevStat = AdbClient.ProcStatSample()
        var prevCoreStat = AdbClient.CoreStatSample()
        var prevNet = AdbClient.NetSample()
        var prevNetAt: Date?
        var cacheMemoryUsedGB: Double?
        var cacheMemoryTotalGB: Double?
        var cacheStorageUsedGB: Double?
        var cacheStorageTotalGB: Double?
        var cacheNetworkInfo: String?
        var cacheNetUp: Double?
        var cacheNetDown: Double?
        var cacheNetworkType: String?
        var cacheCPU: Double?
        var cacheAndroidVersion: String?
        var cacheSDK: Int?
        var cacheGovernor: String?
        var cacheIP: String?
        var cacheGpuRenderer: String?
        var cacheGpuEs: String?
        var prevDisk = AdbClient.DiskSample()
        var prevDiskAt: Date?
        var prevAccelRotation: String?
        var prevUserRotation: String?
        var settingsChangedCount: Int = 0
        var logcatCursor: String?
        var logcatHitCount: Int = 0
        var logcatPrimed = false
        var metaPrimed = false
        /// /proc/stat 코어 수 (load 임계용) — 첫 틱 후 캐시
        var coreCount: Int?
        /// MemAvailable % (15s meminfo) — usedPct = 100 − avail%
        var memAvailablePct: Double?
    }

    private var timer: Task<Void, Never>?
    private var onSnapshot: (@Sendable (DeviceSnapshot) -> Void)?
    private var onEvent: (@Sendable (String) -> Void)?

    private var adbPath: String?
    /// UI(썸네일·로그뷰어)용 경로 — resolveDevices가 찾은 경로 공유
    var adbPathForUI: String? { adbPath }
    private var serials: [String] = []
    private var states: [String: DeviceState] = [:]
    private var knownSerials: Set<String> = []
    private var tickCount: Int = 0
    private var lastErrorLogged: String?

    func attach(_ handler: @escaping @Sendable (DeviceSnapshot) -> Void) {
        onSnapshot = handler
    }

    func attachEvent(_ handler: @escaping @Sendable (String) -> Void) {
        onEvent = handler
    }

    func start() async {
        guard timer == nil else { return }
        await log(.info, "[INFO] [FEATURE] DeviceMonitor 5s 틱 시작")
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self else { break }
                await self.tick()
            }
        }
        await tick()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func tick() async {
        tickCount += 1
        await resolveDevices()

        for serial in serials {
            await pollDevice(serial)
        }
    }

    // MARK: - Per-device poll

    private func pollDevice(_ serial: String) async {
        var state = states[serial] ?? DeviceState()

        var snap = DeviceSnapshot()
        snap.serial = serial
        snap.model = state.model ?? ""
        snap.isOnline = true
        let conn = AdbClient.parseConnection(serial)
        snap.connectionKind = conn.kind
        snap.connectionLabel = conn.label
        snap.deviceName = state.deviceName

        // ── 메타 1회 (model/device_name/android/sdk)
        if !state.metaPrimed {
            primeMeta(serial: serial, state: &state)
            snap.model = state.model ?? ""
            snap.deviceName = state.deviceName
            snap.androidVersion = state.cacheAndroidVersion
            snap.sdkInt = state.cacheSDK
        }

        // ── 5s fast: battery + thermal + loadavg + /proc/stat
        if let battText = try? shell(serial, "dumpsys", "battery") {
            let batt = AdbClient.parseBatteryEx(battText)
            snap.batteryLevel = batt.batteryLevel
            snap.batteryTempC = batt.batteryTempC
            snap.isCharging = batt.isCharging
            snap.voltageMV = batt.voltageMV
            snap.batteryHealthPct = batt.batteryHealthPct
            snap.isProtectionMode = batt.isProtectionMode
            snap.protectionThresholdPct = batt.protectionThresholdPct
            snap.cycleEstimate = batt.cycleEstimate

            // ── 감시 이벤트 (PLAN_v0.5 Phase1): 충전·보호모드·배터리 임계 전이
            if let charging = batt.isCharging {
                await emitWatch(
                    WatchEngine.shared.feedCharging(serial: serial, charging: charging)
                )
            }
            if let prot = batt.isProtectionMode {
                await emitWatch(
                    WatchEngine.shared.feedProtection(serial: serial, enabled: prot)
                )
            }
            if let level = batt.batteryLevel {
                let charging = batt.isCharging ?? false
                await emitWatch(
                    WatchEngine.shared.feedBatteryLevel(
                        serial: serial,
                        level: level,
                        charging: charging
                    )
                )
            }
            // ── 감시: Bsoh 급락 (Samsung 필드 부재 시 생략)
            if let bsoh = batt.batteryHealthPct {
                await emitWatch(
                    WatchEngine.shared.feedBsoh(serial: serial, bsoh: bsoh)
                )
            }
        } else {
            let msg = ErrorCode.adbParseFailed.koMessage
            snap.lastError = msg
            await logLast(msg)
        }

        // 저전력 모드 (settings global low_power 0/1) — 15s 틱
        if tickCount % 3 == 1 {
            if let lpText = try? shell(serial, "settings", "get", "global", "low_power"),
               let lp = AdbClient.parseSettingValue(lpText) {
                let enabled = (Int(lp) ?? 0) != 0
                snap.isLowPowerMode = enabled
                await emitWatch(
                    WatchEngine.shared.feedLowPower(serial: serial, enabled: enabled)
                )
            }
        }

        if let thText = try? shell(serial, "dumpsys", "thermalservice") {
            let th = AdbClient.parseThermal(thText)
            snap.thermalStatus = th.status
            snap.deviceTempC = th.apTempC ?? th.skinTempC ?? th.batTempC
            if snap.batteryTempC == nil { snap.batteryTempC = th.batTempC }
            // zones는 15s tick에서
            if tickCount % 3 == 1 {
                snap.thermalZones = AdbClient.parseThermalZones(thText).zones
            }
            // ── 감시 이벤트: 스로틀링 전이 (hysteresis gate)
            if let status = th.status {
                await emitWatch(
                    WatchEngine.shared.feedThermal(serial: serial, status: status)
                )
            }
        }

        var pendingLoad1: Double?
        if let loadText = try? shell(serial, "cat", "/proc/loadavg") {
            let la = AdbClient.parseLoadAvg(loadText)
            snap.load1 = la.load1
            snap.load5 = la.load5
            snap.load15 = la.load15
            pendingLoad1 = la.load1
        }

        await pollSettingWatch(serial: serial, state: &state, snap: &snap)

        // /proc/stat + cores
        if let statText = try? shell(serial, "cat", "/proc/stat") {
            let curr = AdbClient.parseProcStat(statText)
            if let use = AdbClient.cpuUsePercent(prev: state.prevStat, curr: curr) {
                snap.cpuUsePercent = use
                state.cacheCPU = use
            }
            state.prevStat = curr

            let coreCurr = AdbClient.parseProcStatCores(statText)
            if let uses = AdbClient.coreUsePercents(prev: state.prevCoreStat, curr: coreCurr) {
                snap.coreUsePercents = uses
            }
            state.prevCoreStat = coreCurr
            if state.coreCount == nil, !coreCurr.cores.isEmpty {
                state.coreCount = coreCurr.cores.count
            }
        }
        if snap.cpuUsePercent == nil { snap.cpuUsePercent = state.cacheCPU }

        // ── 감시: load1 급증 (코어 수 확정 후)
        if let load1 = pendingLoad1, let cores = state.coreCount {
            await emitWatch(
                WatchEngine.shared.feedLoad(serial: serial, load1: load1, cores: cores)
            )
        }

        // ── cpufreq (15s 또는 첫 틱) — 단일 shell 문자열로 glob 확장 (sh -c 인자 분리 시 cat 만 실행되는 버그 회피)
        if tickCount % 3 == 1 || state.cacheGovernor == nil {
            let curCmd = "cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq"
            let maxCmd = "cat /sys/devices/system/cpu/cpu*/cpufreq/cpuinfo_max_freq"
            if let curText = try? shell(serial, curCmd),
               let maxText = try? shell(serial, maxCmd) {
                var gov: String?
                if state.cacheGovernor == nil {
                    gov = (try? shell(serial, "cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"))
                }
                let cores = AdbClient.parseCpuCores(curText: curText, maxText: maxText, governorText: gov)
                if !cores.curMHz.isEmpty { snap.coreFreqsMHz = cores.curMHz }
                if !cores.maxMHz.isEmpty { snap.coreMaxMHz = cores.maxMHz }
                if let g = cores.governor { state.cacheGovernor = g }
                snap.cpuGovernor = state.cacheGovernor
            }
        } else {
            snap.cpuGovernor = state.cacheGovernor
        }

        // ── 15s slow
        if tickCount % 3 == 1 {
            if let memText = try? shell(serial, "cat", "/proc/meminfo") {
                let mem = AdbClient.parseMemInfo(memText)
                state.cacheMemoryTotalGB = mem.totalGB
                state.cacheMemoryUsedGB = mem.usedGB
                if let total = mem.totalGB, let avail = mem.availableGB, total > 0 {
                    let availPct = avail / total * 100.0
                    state.memAvailablePct = availPct
                    // usedPct Gate — enter ≥90 (avail<10%), clear ≤80 (avail>20%)
                    await emitWatch(
                        WatchEngine.shared.feedMemory(
                            serial: serial,
                            usedPct: 100.0 - availPct
                        )
                    )
                }
                // swap used = total - free (SwapFree)
                if let total = mem.swapTotalGB {
                    snap.swapUsedGB = estimateSwapUsed(memText: memText, totalGB: total)
                }
            }

            // PSI pressure
            if let psiText = try? shell(serial, "cat", "/proc/pressure/memory") {
                let p = AdbClient.parsePressure(psiText)
                snap.memPressurePct = p.pct
                snap.memPressureLabel = p.label
                if let avg10 = p.pct {
                    await emitWatch(
                        WatchEngine.shared.feedPsi(serial: serial, avg10: avg10)
                    )
                }
            }
            // swap fallback 라벨
            if snap.memPressureLabel == nil, let swap = snap.swapUsedGB, swap > 1.5 {
                snap.memPressureLabel = "moderate"
            }

            // Top RSS+ARGS + CPU → 프로세스 목록
            var psRows: [ProcessRow] = []
            if let psText = try? shell(serial, "ps", "-A", "-o", "PID,RSS,NAME,ARGS", "--sort=-rss") {
                psRows = AdbClient.parsePsProcRows(psText, limit: 30)
            }
            var cpuRows: [ProcessRow] = []
            if let cpuText = try? shell(serial, "dumpsys", "cpuinfo") {
                cpuRows = AdbClient.parseCpuInfoProcs(cpuText, limit: 30)
            }
            if !psRows.isEmpty || !cpuRows.isEmpty {
                let merged = AdbClient.mergeProcessRows(rss: psRows, cpu: cpuRows)
                // 카드용 상위 5 (RSS 기준)
                let top5 = merged
                    .filter { $0.rssMB != nil }
                    .sorted { ($0.rssMB ?? 0) > ($1.rssMB ?? 0) }
                    .prefix(5)
                    .map { ProcessRSS(name: $0.name, rssMB: $0.rssMB ?? 0) }
                if !top5.isEmpty { snap.topProcesses = top5 }
                // 시트/윈도우용 전체
                let full = merged.sorted {
                    let c0 = $0.cpuPercent ?? -1
                    let c1 = $1.cpuPercent ?? -1
                    if c0 != c1 { return c0 > c1 }
                    return ($0.rssMB ?? 0) > ($1.rssMB ?? 0)
                }
                if !full.isEmpty { snap.processList = full }
            }

            if let netText = try? shell(serial, "cat", "/proc/net/dev") {
                let curr = AdbClient.parseNetDev(netText)
                var upDown: (up: Double, down: Double)?
                if let at = state.prevNetAt {
                    upDown = AdbClient.netRatesMBps(
                        prev: state.prevNet,
                        curr: curr,
                        seconds: Date().timeIntervalSince(at)
                    )
                }
                state.prevNet = curr
                state.prevNetAt = Date()
                if let r = upDown {
                    state.cacheNetUp = r.up
                    state.cacheNetDown = r.down
                    state.cacheNetworkInfo = AdbClient.formatNetRatePair(up: r.up, down: r.down)
                }
            }

            if let connText = try? shell(serial, "dumpsys", "connectivity") {
                if let type = AdbClient.parseNetworkType(connText) {
                    state.cacheNetworkType = type
                }
            }

            // Signal (기기内 grep — 단일 shell 문자열)
            if let sigText = try? shell(serial, "dumpsys telephony.registry | grep -E 'mSignalStrength|mOperatorAlphaLong'") {
                let sig = AdbClient.parseSignal(sigText)
                snap.rsrp = sig.rsrp
                snap.signalOperator = sig.carrier
                // ── 감시: RSRP 급락
                if let rsrp = sig.rsrp {
                    await emitWatch(
                        WatchEngine.shared.feedRsrp(serial: serial, rsrp: rsrp)
                    )
                }
            }

            // Wi-Fi
            if let wifiText = try? shell(serial, "cmd", "wifi", "status") {
                let w = AdbClient.parseWifiStatus(wifiText)
                snap.wifiSsid = w.ssid
                snap.wifiRssi = w.rssi
            }

            // IP
            if let ipText = try? shell(serial, "ip", "-f", "inet", "addr", "show", "wlan0") {
                state.cacheIP = parseInet4(ipText)
            }

            if let dfText = try? shell(serial, "df", "-h", "/data") {
                let df = AdbClient.parseDf(dfText)
                state.cacheStorageUsedGB = df.usedGB
                state.cacheStorageTotalGB = df.totalGB
            }

            // ── P2: GPU (SurfaceFlinger GLES + kgsl sysfs)
            if state.cacheGpuRenderer == nil || state.cacheGpuEs == nil {
                if let glesText = try? shell(serial, "dumpsys SurfaceFlinger | grep -E 'GLES:|OpenGL ES'") {
                    let g = AdbClient.parseGpuGles(glesText)
                    if let r = g.renderer { state.cacheGpuRenderer = r }
                    if let e = g.esVersion { state.cacheGpuEs = e }
                }
            }
            if let busyText = try? shell(serial, "cat /sys/class/kgsl/kgsl-3d0/gpu_busy_percentage"),
               let busy = AdbClient.parseGpuBusyPercent(busyText) {
                snap.gpuUtilPercent = busy
            } else if let busy2 = try? shell(serial, "cat /sys/class/kgsl/kgsl-3d0/gpubusy"),
                      let busy = AdbClient.parseGpuBusyPercent(busy2) {
                snap.gpuUtilPercent = busy
            }
            if let clkText = try? shell(serial, "cat /sys/class/kgsl/kgsl-3d0/gpuclk"),
               let mhz = AdbClient.parseGpuClkMHz(clkText) {
                snap.gpuFreqMHz = mhz
            }
            snap.gpuRenderer = state.cacheGpuRenderer
            snap.gpuEsVersion = state.cacheGpuEs

            // ── P2: SENSORS summary (기기内 grep — 단일 shell 문자열)
            if let sensText = try? shell(serial, "dumpsys sensorservice | grep -E 'Total [0-9]+ h/w sensors|active-count|\\) type 0x|active connections|Sensor Device|Sensor List'") {
                let s = AdbClient.parseSensorsSummary(sensText)
                if s.total != nil || s.activeCount != nil || !s.activeNames.isEmpty {
                    snap.sensorTotalCount = s.total
                    snap.sensorActiveCount = s.activeCount
                    snap.sensorActiveNames = s.activeNames.isEmpty ? nil : s.activeNames
                    snap.sensorActivePeriodsMs = s.activePeriodsMs.isEmpty ? nil : s.activePeriodsMs
                }
            }

            // ── P2: diskstats R/W delta (sda)
            if let diskText = try? shell(serial, "cat /proc/diskstats") {
                let curr = AdbClient.parseDiskStats(diskText)
                var rates: (read: Double, write: Double)?
                if let at = state.prevDiskAt {
                    rates = AdbClient.diskRatesMBps(prev: state.prevDisk, curr: curr, seconds: Date().timeIntervalSince(at))
                }
                state.prevDisk = curr
                state.prevDiskAt = Date()
                if let r = rates {
                    snap.diskReadMBps = r.read
                    snap.diskWriteMBps = r.write
                }
            }

            await pollLogcatWatch(serial: serial, state: &state)
        }

        snap.memoryUsedGB = snap.memoryUsedGB ?? state.cacheMemoryUsedGB
        snap.memoryTotalGB = snap.memoryTotalGB ?? state.cacheMemoryTotalGB
        snap.storageUsedGB = snap.storageUsedGB ?? state.cacheStorageUsedGB
        snap.storageTotalGB = snap.storageTotalGB ?? state.cacheStorageTotalGB
        snap.networkInfo = snap.networkInfo ?? state.cacheNetworkInfo
        snap.netUpMBps = snap.netUpMBps ?? state.cacheNetUp
        snap.netDownMBps = snap.netDownMBps ?? state.cacheNetDown
        snap.networkType = snap.networkType ?? state.cacheNetworkType
        snap.androidVersion = snap.androidVersion ?? state.cacheAndroidVersion
        snap.sdkInt = snap.sdkInt ?? state.cacheSDK
        snap.ipV4 = snap.ipV4 ?? state.cacheIP
        snap.gpuRenderer = snap.gpuRenderer ?? state.cacheGpuRenderer
        snap.gpuEsVersion = snap.gpuEsVersion ?? state.cacheGpuEs
        snap.settingsChangedCount = state.settingsChangedCount
        snap.logcatHitCount = state.logcatHitCount

        states[serial] = state
        onSnapshot?(snap)
    }

    private func primeMeta(serial: String, state: inout DeviceState) {
        let conn = AdbClient.parseConnection(serial)
        state.connectionKind = conn.kind
        state.connectionLabel = conn.label

        if let m = (try? shell(serial, "getprop", "ro.product.model"))?
            .trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty {
            state.model = m
        }
        if let n = (try? shell(serial, "settings", "get", "global", "device_name")),
           let name = AdbClient.parseDeviceName(n) {
            state.deviceName = name
        }
        if let v = (try? shell(serial, "getprop", "ro.build.version.release"))?
            .trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
            state.cacheAndroidVersion = v
        }
        if let s = (try? shell(serial, "getprop", "ro.build.version.sdk"))?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           let n = Int(s) {
            state.cacheSDK = n
        }
        state.metaPrimed = true
    }

    private func estimateSwapUsed(memText: String, totalGB: Double) -> Double? {
        for line in memText.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2, parts[0] == "SwapFree" else { continue }
            let kb = parts[1].split(whereSeparator: \.isWhitespace).first
                .flatMap { Double($0) }
            guard let kb else { return nil }
            let freeGB = kb / (1024 * 1024)
            return max(0, totalGB - freeGB)
        }
        return nil
    }

    private func parseInet4(_ text: String) -> String? {
        for line in text.split(separator: "\n") {
            let s = String(line)
            guard s.contains("inet ") else { continue }
            guard let range = s.range(of: "inet ") else { continue }
            let after = s[range.upperBound...]
            let addr = after.prefix { $0.isNumber || $0 == "." }
            if addr.contains(".") { return String(addr) }
        }
        return nil
    }

    // MARK: - SettingWatch / LogcatWatch

    private func pollSettingWatch(
        serial: String,
        state: inout DeviceState,
        snap: inout DeviceSnapshot
    ) async {
        guard let autoRaw = try? shell(serial, "settings", "get", "system", "accelerometer_rotation"),
              let userRaw = try? shell(serial, "settings", "get", "system", "user_rotation") else {
            return
        }
        let auto = AdbClient.parseSettingValue(autoRaw)
        let user = AdbClient.parseSettingValue(userRaw)

        if let prevA = state.prevAccelRotation, let auto, prevA != auto {
            state.settingsChangedCount += 1
            await notifyEvent(L10n.format(
                "event.settingsChanged",
                "accelerometer_rotation",
                "\(prevA)→\(auto)"
            ))
        }
        if let prevU = state.prevUserRotation, let user, prevU != user {
            state.settingsChangedCount += 1
            await notifyEvent(L10n.format(
                "event.settingsChanged",
                "user_rotation",
                "\(prevU)→\(user)"
            ))
        }
        if auto != nil { state.prevAccelRotation = auto }
        if user != nil { state.prevUserRotation = user }
        snap.settingsChangedCount = state.settingsChangedCount
    }

    private func pollLogcatWatch(serial: String, state: inout DeviceState) async {
        let output: String?
        if let cursor = state.logcatCursor {
            output = try? shell(serial, "logcat", "-d", "-T", cursor)
        } else {
            output = try? shell(serial, "logcat", "-d", "-t", "30")
        }
        guard let output, !output.isEmpty else { return }

        let prevCursor = state.logcatCursor
        if !state.logcatPrimed {
            state.logcatPrimed = true
            state.logcatCursor = AdbClient.lastLogcatTimestamp(output) ?? prevCursor
            return
        }

        let hits = AdbClient.countLogcatHits(
            output,
            keywords: Self.logcatKeywords,
            afterTimestamp: prevCursor
        )
        if hits > 0 {
            state.logcatHitCount += hits
            await notifyEvent(L10n.format("event.logcatHits", hits))
        }
        // v0.8 ANR / 크래시 — 적중 시 WatchEngine 1회성 피드
        let anrHits = AdbClient.countLogcatHits(
            output,
            keywords: Self.anrKeywords,
            afterTimestamp: prevCursor
        )
        if anrHits > 0 {
            let detail = L10n.format("event.anr.detail", anrHits)
            if let ev = await WatchEngine.shared.feedAnr(serial: serial, detail: detail) {
                await emitWatch(ev)
            }
        }
        let crashHits = AdbClient.countLogcatHits(
            output,
            keywords: Self.crashKeywords,
            afterTimestamp: prevCursor
        )
        if crashHits > 0 {
            let detail = L10n.format("event.crash.detail", crashHits)
            if let ev = await WatchEngine.shared.feedCrash(serial: serial, detail: detail) {
                await emitWatch(ev)
            }
        }
        if let ts = AdbClient.lastLogcatTimestamp(output) {
            state.logcatCursor = ts
        }
    }

    private func notifyEvent(_ text: String) async {
        await MainActor.run {
            DebugLogger.shared.info("Watch", "[INFO] [WATCH] \(text)")
            ConsoleStore.shared.pushEvent(text)
        }
    }

    /// WatchEngine emit → ConsoleStore (구조화 이벤트 + 문자열 요약 병행)
    private func emitWatch(_ event: WatchEvent?) async {
        guard let event else { return }
        await MainActor.run {
            DebugLogger.shared.info(
                "Watch",
                "[WATCH] \(event.kind.rawValue) sev=\(event.severity.rawValue) \(event.summary)"
            )
            ConsoleStore.shared.ingestWatch(event)
        }
    }

    // MARK: - Device list

    private func resolveDevices() async {
        if adbPath == nil {
            adbPath = findAdb()
            if adbPath == nil {
                Task { @MainActor in
                    DebugLogger.shared.error(
                        "Monitor",
                        "[ERROR] [ADB] " + ErrorCode.adbBinaryMissing.koMessage
                    )
                }
                return
            }
            // 신규 adb 탐지 → UI(썸네일) 갱신 트리거
            let found = adbPath
            Task { @MainActor in
                NotificationCenter.default.post(name: .adbPathReady, object: found)
            }
        }
        guard let adb = adbPath else { return }

        let list = (try? run(adb, ["devices"])) ?? ""
        let found = list.split(separator: "\n")
            .map(String.init)
            .filter { $0.contains("\tdevice") }
            .compactMap { line -> String? in
                line.split(whereSeparator: \.isWhitespace).first.map(String.init)
            }

        let foundSet = Set(found)

        // 신규 연결
        for s in found where !knownSerials.contains(s) {
            if states[s] == nil { states[s] = DeviceState() }
            knownSerials.insert(s)
            let conn = AdbClient.parseConnection(s)
            let short = conn.kind == .network ? s : AdbClient.shortId(s)
            await notifyEvent(L10n.format("event.deviceConnected", short))
            await log(.info, "[INFO] [ADB] 기기 연결 meta=\(short) kind=\(conn.kind.rawValue)")
            // 연결 직후 썸네일 1회 (상시 폴링 아님)
            let path = adbPath
            Task { @MainActor in
                ScreenshotService.shared.refresh(serial: s, adbPath: path)
            }
        }

        // 끊김 — 활성 gate synthetic clear (후속조치 영구잔류 방지)
        for s in knownSerials where !foundSet.contains(s) {
            knownSerials.remove(s)
            states.removeValue(forKey: s)
            await MainActor.run {
                ConsoleStore.shared.markDeviceOffline(s)
                for e in WatchEngine.shared.forget(serial: s) {
                    ConsoleStore.shared.ingestWatch(e, forceNotify: false)
                }
            }
            let short = AdbClient.parseConnection(s).kind == .network ? s : AdbClient.shortId(s)
            await notifyEvent(L10n.format("event.deviceDisconnected", short))
        }

        serials = found
    }

    nonisolated private static func locateAdb() -> String? {
        let candidates = [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "/usr/bin/adb"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in pathEnv.split(separator: ":") {
            let p = "\(dir)/adb"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    private func findAdb() -> String? {
        Self.locateAdb()
    }

    /// UI(썸네일·로그뷰어) 동기 조회 — actor 밖에서 사용
    nonisolated static func adbPathNow() -> String? {
        locateAdb()
    }

    /// 모든 셸은 반드시 `-s serial` (PLAN_v0.3 DoD)
    private func shell(_ serial: String, _ args: String...) throws -> String {
        guard let adb = adbPath else {
            throw ErrorCode.adbBinaryMissing
        }
        return try run(adb, ["-s", serial, "shell"] + args)
    }

    private func run(_ path: String, _ args: [String]) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        try proc.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw ErrorCode.adbConnectFailed
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func logLast(_ message: String) async {
        guard message != lastErrorLogged else { return }
        lastErrorLogged = message
        await log(.error, "[ERROR] [ADB] \(message)")
    }

    private func log(_ level: DebugLogLevel, _ message: String) async {
        await MainActor.run {
            switch level {
            case .error: DebugLogger.shared.error("Monitor", message)
            case .warn: DebugLogger.shared.warn("Monitor", message)
            default: DebugLogger.shared.info("Monitor", message)
            }
        }
    }
}
