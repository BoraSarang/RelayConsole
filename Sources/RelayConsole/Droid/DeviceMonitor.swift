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
    /// logcat 적중 이벤트 집계 윈도우 — 5s 폴링 폭주 방지 (최소 간격)
    static let logcatEventInterval: TimeInterval = 300

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
        /// logcat 감지 집계 윈도우 (5s 폴링 폭주 방지)
        var logcatHitsPending: Int = 0
        var logcatBreakdown: [String: Int] = [:]
        var logcatEventAt: Date?
        var metaPrimed = false
        /// /proc/stat 코어 수 (load 임계용) — 첫 틱 후 캐시
        var coreCount: Int?
        /// MemAvailable % (15s meminfo) — usedPct = 100 − avail%
        var memAvailablePct: Double?
        /// 포그라운드 앱 패키지 (15s)
        var cacheForegroundPackage: String?
        /// uid별 앱 네트워크 누적량 이전 샘플 (15s delta)
        var prevAppNet: [AppNetStat]?
        var prevAppNetAt: Date?
        /// uid → 패키지명 (1회 조회 후 캐시)
        var packageUids: [Int: String]?
        /// 15s 앱 네트워크 속도 캐시 (5s 틱이 상속)
        var cacheAppNetRates: [AppNetRate]?
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
    /// serial → adb 비정상 상태 (unauthorized/offline/…) — 상태 변화 시 1회 통지용
    private var adbBadState: [String: String] = [:]
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
                // try? 가 CancellationError를 삼킨 뒤 루프 조건을 다시 보지 않으므로
                // 여기서 한 번 더 검사해야 종료 시 tick이 1회 더 실행되지 않는다.
                // (slow 틱이면 기기당 최대 25회 adb spawn이 그대로 날아간다)
                guard !Task.isCancelled else { break }
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

        // ── 수집은 **병렬**, 적용은 순차 ──
        // 종전에는 기기마다 순차 폴링이라, 한 기기의 느린 adb 호출(half-open TCP 등)이
        // 나머지 모든 기기의 갱신을 Head-of-Line 로 막았다. ProcessRunner 데드라인이
        // 무한 대기는 막아주지만 그만큼 지연은 남으므로, adb 대기 구간만 겹쳐 돌린다.
        // 상태 갱신(states/emitWatch)은 여전히 actor 격리 안에서 순차 수행된다.
        let isSlowTick = tickCount % 3 == 1
        let list = serials
        guard !list.isEmpty else { return }

        let cmds = isSlowTick ? PollBatch.slow : PollBatch.fast
        var collected: [String: [PollBatch.Cmd: String]] = [:]
        await withTaskGroup(of: (String, [PollBatch.Cmd: String]).self) { group in
            for serial in list {
                group.addTask { [weak self] in
                    // adb 실행은 actor 격리 밖에서 — 느린 기기가 다른 기기를 막지 않게
                    let text = await self?.fetchBatch(serial: serial, cmds: cmds)
                    return (serial, text ?? [:])
                }
            }
            for await (serial, out) in group {
                collected[serial] = out
            }
        }

        for serial in list {
            await pollDevice(serial, batch: collected[serial] ?? [:], isSlowTick: isSlowTick)
        }
    }

    /// 배치 1회 실행 — actor 격리 밖에서 호출되어 adb 대기가 기기끼리 겹친다
    private nonisolated func fetchBatch(
        serial: String,
        cmds: [PollBatch.Cmd]
    ) async -> [PollBatch.Cmd: String]? {
        guard let adb = Self.adbPathNow() else { return nil }
        let script = PollBatch.build(cmds)
        guard !script.isEmpty else { return nil }
        do {
            let out = try await ProcessRunner.captureAsync(adb, ["-s", serial, "shell", script])
            return PollBatch.parse(out.stdout, into: cmds)
        } catch {
            // 실패는 조용히 삼키지 않는다 — DebugPanel(1단계 1-6 정책)에 남긴다
            await MainActor.run {
                DebugLogger.shared.warn(
                    "Droid",
                    "[WARN] 배치 폴링 실패 serial=\(NotifyChannel.maskSerial(serial)) \(ProcessRunner.describe(error))"
                )
            }
            return nil
        }
    }

    // MARK: - Per-device poll

    private func pollDevice(
        _ serial: String,
        batch: [PollBatch.Cmd: String],
        isSlowTick: Bool
    ) async {
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

        // adb 호출은 tick()에서 병렬로 이미 수행되어 batch로 전달된다.
        // 종전에는 기기당 6회(fast)·25회(slow)를 개별 실행했다. 마커로 출력을 잘라
        // **종전과 동일한 문자열**을 각 파서에 넘기므로 파서 동작은 변하지 않는다.
        if let battText = batch[.battery] {
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
        if isSlowTick {
            if let lpText = batch[.lowPower],
               let lp = AdbClient.parseSettingValue(lpText) {
                let enabled = (Int(lp) ?? 0) != 0
                snap.isLowPowerMode = enabled
                await emitWatch(
                    WatchEngine.shared.feedLowPower(serial: serial, enabled: enabled)
                )
            }
        }

        if let thText = batch[.thermal] {
            let th = AdbClient.parseThermal(thText)
            snap.thermalStatus = th.status
            snap.deviceTempC = th.apTempC ?? th.skinTempC ?? th.batTempC
            if snap.batteryTempC == nil { snap.batteryTempC = th.batTempC }
            // zones는 15s tick에서
            if isSlowTick {
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
        if let loadText = batch[.loadavg] {
            let la = AdbClient.parseLoadAvg(loadText)
            snap.load1 = la.load1
            snap.load5 = la.load5
            snap.load15 = la.load15
            pendingLoad1 = la.load1
        }

        // 회전 감지 — settings 2종은 배치 결과에서 전달 (추가 adb 호출 0)
        await pollSettingWatch(
            serial: serial,
            accelRaw: batch[.accelRotation],
            userRaw: batch[.userRotation],
            state: &state,
            snap: &snap
        )

        // /proc/stat + cores
        if let statText = batch[.procStat] {
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

        // ── cpufreq (15s 또는 첫 틱) — 배치 결과에서 읽는다 (추가 adb 호출 0)
        if isSlowTick || state.cacheGovernor == nil {
            if let curText = batch[.scalingCur],
               let maxText = batch[.scalingMax] {
                var gov: String?
                if state.cacheGovernor == nil {
                    // governor 는 첫 1회만 필요하므로 배치에 넣지 않고 단발 호출
                    gov = try? shell(serial, "cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor")
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
        if isSlowTick {
            if let memText = batch[.meminfo] {
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
            if let psiText = batch[.psi] {
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
            if let psText = batch[.ps] {
                psRows = AdbClient.parsePsProcRows(psText, limit: 30)
            }
            var cpuRows: [ProcessRow] = []
            if let cpuText = batch[.cpuinfo] {
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

            if let netText = batch[.netdev] {
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

            // ── 앱(UID) 네트워크 사용량 — 15s, 추가 셸 최대 2회 (netstats + pm list)
            if let statsText = batch[.netstats] {
                let parsed = AdbClient.parseUidNetStats(statsText)
                if !parsed.isEmpty {
                    if state.packageUids == nil,
                       let pkgText = try? shell(serial, "pm", "list", "packages", "-U") {
                        state.packageUids = AdbClient.parsePackageUids(pkgText)
                    }
                    let uidToPkg = state.packageUids ?? [:]
                    let rows: [AppNetStat] = parsed.map {
                        AppNetStat(
                            uid: $0.uid,
                            packageName: uidToPkg[$0.uid],
                            rxBytes: $0.rxBytes,
                            txBytes: $0.txBytes
                        )
                    }
                    snap.appNetStats = rows
                    if let prev = state.prevAppNet, let at = state.prevAppNetAt {
                        let secs = Date().timeIntervalSince(at)
                        let rates = AdbClient.appNetRates(prev: prev, curr: rows, seconds: secs)
                        if !rates.isEmpty {
                            snap.appNetRates = rates
                            state.cacheAppNetRates = rates
                        }
                    }
                    state.prevAppNet = rows
                    state.prevAppNetAt = Date()
                }
            }
            if snap.appNetRates == nil { snap.appNetRates = state.cacheAppNetRates }

            // 프로세스 NET 열 — 패키지명 == 프로세스명 매핑
            if let rates = snap.appNetRates, var procRows = snap.processList {
                var speed: [String: Double] = [:]
                for r in rates {
                    if let name = r.packageName, speed[name] == nil {
                        speed[name] = r.totalMBps
                    }
                }
                for i in procRows.indices {
                    procRows[i].netMBps = speed[procRows[i].name]
                }
                snap.processList = procRows
            }

            if let connText = batch[.connectivity] {
                if let type = AdbClient.parseNetworkType(connText) {
                    state.cacheNetworkType = type
                }
            }

            // Signal (기기 내 grep — 배치에 포함, 추가 adb 호출 0)
            if let sigText = batch[.signal] {
                let sig = AdbClient.parseSignal(sigText)
                snap.rsrp = sig.rsrp
                snap.signalOperator = sig.carrier
                snap.rsrq = sig.rsrq
                snap.sinr = sig.sinr
                snap.signalRat = sig.rat
                snap.signalCA = sig.ca
                snap.signalBands = AdbClient.bandSummary(lte: sig.lteBands, nr: sig.nrBands)
                // ── 감시: RSRP 급락
                if let rsrp = sig.rsrp {
                    await emitWatch(
                        WatchEngine.shared.feedRsrp(serial: serial, rsrp: rsrp)
                    )
                }
            }

            // 포그라운드 앱 (15s) — 문제 순간 컨텍스트
            if let actText = batch[.activity] {
                if let fg = AdbClient.parseForegroundPackage(actText) {
                    state.cacheForegroundPackage = fg
                    snap.foregroundPackage = fg
                }
            } else {
                snap.foregroundPackage = state.cacheForegroundPackage
            }

            // Wi-Fi — `cmd wifi status`는 on/off 2줄만 출력해 SSID가 항상 nil이라
            // "Wi-Fi 꺼짐" 오출력. Wi-Fi 활성일 때만 `dumpsys wifi`에서 SSID/RSSI 조회.
            if state.cacheNetworkType == "Wi-Fi" {
                if let wifiText = try? shell(
                    serial,
                    "dumpsys wifi | grep -m3 -E 'mWifiInfo|Wi-Fi is'"
                ) {
                    let w = AdbClient.parseWifiStatus(wifiText)
                    snap.wifiSsid = w.ssid
                    snap.wifiRssi = w.rssi
                }
            } else {
                snap.wifiSsid = ""
                snap.wifiRssi = nil
            }

            // IP
            if let ipText = batch[.ipWlan] {
                state.cacheIP = parseInet4(ipText)
            }

            if let dfText = batch[.df] {
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
            if let busyText = batch[.gpuBusy],
               let busy = AdbClient.parseGpuBusyPercent(busyText) {
                snap.gpuUtilPercent = busy
            } else if let busy2 = batch[.gpuGpubusy],
                      let busy = AdbClient.parseGpuBusyPercent(busy2) {
                snap.gpuUtilPercent = busy
            }
            if let clkText = batch[.gpuClk],
               let mhz = AdbClient.parseGpuClkMHz(clkText) {
                snap.gpuFreqMHz = mhz
            }
            snap.gpuRenderer = state.cacheGpuRenderer
            snap.gpuEsVersion = state.cacheGpuEs

            // ── P2: SENSORS summary (기기内 grep — 단일 shell 문자열)
            if let sensText = batch[.sensors] {
                let s = AdbClient.parseSensorsSummary(sensText)
                if s.total != nil || s.activeCount != nil || !s.activeNames.isEmpty {
                    snap.sensorTotalCount = s.total
                    snap.sensorActiveCount = s.activeCount
                    snap.sensorActiveNames = s.activeNames.isEmpty ? nil : s.activeNames
                    snap.sensorActivePeriodsMs = s.activePeriodsMs.isEmpty ? nil : s.activePeriodsMs
                }
            }

            // ── P2: diskstats R/W delta (sda)
            if let diskText = batch[.diskstats] {
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
        accelRaw: String?,
        userRaw: String?,
        state: inout DeviceState,
        snap: inout DeviceSnapshot
    ) async {
        guard let autoRaw = accelRaw, let userRaw = userRaw else {
            return
        }
        let auto = AdbClient.parseSettingValue(autoRaw)
        let user = AdbClient.parseSettingValue(userRaw)

        if let prevA = state.prevAccelRotation, let auto, prevA != auto {
            state.settingsChangedCount += 1
            await emitDetect(
                kind: .settingsChanged,
                serial: serial,
                title: L10n.format(
                    "event.settingsChanged",
                    "accelerometer_rotation",
                    "\(prevA)→\(auto)"
                ),
                detail: L10n.string("event.settingsChanged.src")
            )
        }
        if let prevU = state.prevUserRotation, let user, prevU != user {
            state.settingsChangedCount += 1
            await emitDetect(
                kind: .settingsChanged,
                serial: serial,
                title: L10n.format(
                    "event.settingsChanged",
                    "user_rotation",
                    "\(prevU)→\(user)"
                ),
                detail: L10n.string("event.settingsChanged.src")
            )
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

        let breakdown = AdbClient.logcatHitBreakdown(
            output,
            keywords: Self.logcatKeywords,
            afterTimestamp: prevCursor
        )
        let hits = breakdown.reduce(0) { $0 + $1.count }
        if hits > 0 {
            state.logcatHitCount += hits
            // 5s 폴링 폭주 방지 — 최소 간격까지 적중을 모아 1건으로 발행 (원인은 키워드 분해로 노출)
            state.logcatHitsPending += hits
            for hit in breakdown {
                state.logcatBreakdown[hit.keyword, default: 0] += hit.count
            }
            let now = Date()
            let sinceLast = state.logcatEventAt.map { now.timeIntervalSince($0) }
            if sinceLast.map({ $0 >= Self.logcatEventInterval }) ?? true {
                let detail = state.logcatBreakdown
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key) ×\($0.value)" }
                    .joined(separator: " · ")
                let windowMin = sinceLast.map { max(1, Int($0 / 60)) } ?? 1
                await emitDetect(
                    kind: .logcatHits,
                    serial: serial,
                    title: L10n.format("event.logcatHits", state.logcatHitsPending),
                    detail: L10n.format("event.logcatHits.window", detail, windowMin)
                )
                state.logcatHitsPending = 0
                state.logcatBreakdown = [:]
                state.logcatEventAt = now
            }
        }
        // v0.8 ANR / 크래시 — 적중 시 WatchEngine 1회성 피드 (상세 컨텍스트 포함)
        let anrHits = AdbClient.countLogcatHits(
            output,
            keywords: Self.anrKeywords,
            afterTimestamp: prevCursor
        )
        if anrHits > 0 {
            // ANR 전용 파서 — ANR in / am_anr 패키지 추출
            let anrCtx = AdbClient.extractAnrContext(output, afterTimestamp: prevCursor)
                ?? AdbClient.extractCrashContext(output, afterTimestamp: prevCursor)
            let detail: String
            if let ctx = anrCtx, !ctx.summary.isEmpty {
                detail = ctx.summary
            } else {
                detail = L10n.format("event.anr.detail", anrHits)
            }
            if let ev = await WatchEngine.shared.feedAnr(
                serial: serial,
                detail: detail,
                packageName: anrCtx?.packageName,
                exceptionClass: anrCtx?.exceptionClass ?? "ANR"
            ) {
                await emitWatch(ev)
                await enrichFatal(ev, serial: serial)
            }
        }
        let crashHits = AdbClient.countLogcatHits(
            output,
            keywords: Self.crashKeywords,
            afterTimestamp: prevCursor
        )
        if crashHits > 0 {
            // 상세 컨텍스트 추출 — 패키지명, 예외 클래스, 메시지, 스택트레이스
            let crashCtx = AdbClient.extractCrashContext(output, afterTimestamp: prevCursor)
            // crash buffer 보강 — main logcat에 안 나온 경우
            var enrichedCtx = crashCtx
            if enrichedCtx?.packageName == nil,
               let crashBuf = try? shell(serial, "logcat", "-d", "-b", "crash", "-t", "50"),
               !crashBuf.isEmpty,
               let bufCtx = AdbClient.extractCrashBufferContext(crashBuf) {
                enrichedCtx = bufCtx
            }
            let detail: String
            if let ctx = enrichedCtx {
                var lines: [String] = []
                if !ctx.summary.isEmpty {
                    lines.append(ctx.summary)
                } else if let pkg = ctx.packageName {
                    lines.append(pkg)
                } else {
                    lines.append(L10n.format("event.crash.detail", crashHits))
                }
                if let pid = ctx.pid {
                    lines.append("PID: \(pid)")
                }
                if let firstTrace = ctx.stackTrace.first {
                    lines.append(firstTrace)
                }
                detail = lines.joined(separator: "\n")
            } else {
                detail = L10n.format("event.crash.detail", crashHits)
            }
            if let ev = await WatchEngine.shared.feedCrash(
                serial: serial,
                detail: detail,
                packageName: enrichedCtx?.packageName,
                exceptionClass: enrichedCtx?.exceptionClass
            ) {
                await emitWatch(ev)
                await enrichFatal(ev, serial: serial)
                await readDropboxOnce(serial: serial, state: &state, package: enrichedCtx?.packageName)
            }
        }
        if let ts = AdbClient.lastLogcatTimestamp(output) {
            state.logcatCursor = ts
        }
    }

    /// crash/ANR 이벤트 보강 — 앱 버전(dumpsys package)
    private func enrichFatal(_ event: WatchEvent, serial: String) async {
        guard let pkg = event.packageName, !pkg.isEmpty else { return }
        var enriched = event
        if let pkgText = try? shell(serial, "dumpsys", "package", pkg) {
            let ver = AdbClient.parsePackageVersion(pkgText)
            if let name = ver.versionName {
                enriched = enriched.structured(appVersion: name)
            }
        }
        if enriched.appVersion != nil {
            await MainActor.run {
                ConsoleStore.shared.refreshWatchEvent(enriched)
            }
        }
    }

    /// crash 시점 dropbox 1회 스캔 — 5분 쿨다운 (actor 격리)
    private func readDropboxOnce(serial: String, state: inout DeviceState, package: String?) async {
        _ = state
        _ = package
        if let last = dropboxScannedAt[serial],
           Date().timeIntervalSince(last) < 300 {
            return
        }
        dropboxScannedAt[serial] = Date()
        guard let text = try? shell(serial, "dumpsys", "dropbox", "--print", "-n", "20"),
              !text.isEmpty else { return }
        let tags = AdbClient.parseDropboxRecentTags(text, limit: 10)
        guard !tags.isEmpty else { return }
        await notifyEvent(L10n.format("event.dropbox.hits", tags.count))
    }

    /// dropbox 쿨다운 (actor 격리 상태)
    private var dropboxScannedAt: [String: Date] = [:]

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

    /// 설정 변경·logcat 감지 → 구조화 이벤트 (severity .info — 시스템 알림·일일 경고 집계 제외,
    /// Alerts·대시보드 타임라인에만 노출)
    private func emitDetect(kind: WatchKind, serial: String, title: String, detail: String) async {
        await emitWatch(WatchEvent.detect(
            kind: kind,
            serial: serial,
            title: title,
            detail: detail
        ))
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

        // adb 실행 실패 시 빈 목록으로 해석해 전 기기를 '연결 끊김'으로 위장하지 않음 (AGENTS.local §4 [표시②])
        guard let list = try? run(adb, ["devices"]) else {
            await log(.error, "[ERROR] [ADB] adb devices 실행 실패")
            return
        }
        var adbStates: [String: String] = [:]
        for rawLine in list.split(separator: "\n") {
            let line = String(rawLine)
            guard let idx = line.firstIndex(where: { $0.isWhitespace }) else { continue }
            let name = String(line[..<idx])
            let st = line[line.index(after: idx)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, name != "List", name != "adb", !name.hasPrefix("*"), !st.isEmpty else { continue }
            adbStates[name] = st
        }
        let found = adbStates.filter { $0.value.hasPrefix("device") }.map(\.key)
        let foundSet = Set(found)

        // unauthorized/offline 등 비정상 상태 — 사유를 그대로 통지 (필터로 사유 소멸 방지)
        for (name, st) in adbStates where !st.hasPrefix("device") {
            if adbBadState[name] == st { continue }
            adbBadState[name] = st
            let ident = await MainActor.run { ConsoleStore.shared.identLabel(for: name) }
            let reason = Self.adbStateReason(st)
            await notifyEvent(L10n.format("event.deviceState", ident, reason))
        }
        for name in Array(adbBadState.keys) where adbStates[name] == nil || adbStates[name] == "device" {
            adbBadState.removeValue(forKey: name)
        }

        // 신규 연결
        for s in found where !knownSerials.contains(s) {
            if states[s] == nil { states[s] = DeviceState() }
            knownSerials.insert(s)
            let conn = AdbClient.parseConnection(s)
            let ident = await MainActor.run { ConsoleStore.shared.identLabel(for: s) }
            await notifyEvent(L10n.format("event.deviceConnected", ident))
            await log(.info, "[INFO] [ADB] 기기 연결 meta=\(AdbClient.shortId(s)) kind=\(conn.kind.rawValue)")
            // Phase1 — Android 연결 WatchEvent (영구화 + 세션)
            let connectEvent = WatchEvent(
                kind: .androidConnected,
                severity: .info,
                serial: s,
                title: L10n.string("event.androidConnected"),
                detail: "\(ident) · \(conn.kind.rawValue)"
            )
            await emitWatch(connectEvent)
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
            let ident = await MainActor.run { ConsoleStore.shared.identLabel(for: s) }
            await notifyEvent(L10n.format("event.deviceDisconnected", ident))
            // Phase1 — Android 해제 WatchEvent (세션 close)
            let disconnectEvent = WatchEvent(
                kind: .androidDisconnected,
                severity: .info,
                serial: s,
                title: L10n.string("event.androidDisconnected"),
                detail: ident,
                isClear: true
            )
            await emitWatch(disconnectEvent)
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

    /// 배치 호출용 — adb 경로가 없으면 예외로 알린다
    private func adbForShell() throws -> String {
        guard let adb = adbPath else {
            throw ErrorCode.adbBinaryMissing
        }
        return adb
    }

    /// adb devices 상태 → 사용자 사유 문구 (AGENTS.local §4 [표시②])
    private nonisolated static func adbStateReason(_ state: String) -> String {
        switch state {
        case "unauthorized": return L10n.string("adb.state.unauthorized")
        case "offline": return L10n.string("adb.state.offline")
        case "recovery": return L10n.string("adb.state.recovery")
        case "sideload": return L10n.string("adb.state.sideload")
        case "bootloader": return L10n.string("adb.state.bootloader")
        default:
            if state.hasPrefix("no permissions") { return L10n.string("adb.state.noPermissions") }
            let token = state.split(separator: " ").first.map(String.init) ?? state
            return L10n.format("adb.state.other", token)
        }
    }

    private func run(_ path: String, _ args: [String]) throws -> String {
        // ProcessRunner: stderr 소진 + 데드라인 + 원인 보존을 한곳에서 처리한다.
        // 이전 구현은 stderr 파이프를 읽지 않아 adb가 64KB를 넘기면 교착했고,
        // 타임아웃이 없어 half-open TCP에서 actor 전체가 영구 정지했다.
        try ProcessRunner.run(
            path,
            args,
            failure: .init(base: ErrorCode.adbConnectFailed.koMessage, reason: "")
        )
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
