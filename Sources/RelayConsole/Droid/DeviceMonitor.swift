import Foundation

/// ADB 백그라운드 폴링 — 5s fast / 15s slow / 2회 샘델타 CPU·NET
/// IO는 이 actor 안에서만. UI는 ConsoleStore.inventory.devices만 읽음 (P0-a)
actor DeviceMonitor {
    static let shared = DeviceMonitor()

    private var timer: Task<Void, Never>?
    private var onSnapshot: (@Sendable (DeviceSnapshot) -> Void)?
    private var onEvent: (@Sendable (String) -> Void)?

    private var adbPath: String?
    private var serial: String?
    private var model: String?
    private var tickCount: Int = 0
    private var prevStat = AdbClient.ProcStatSample()
    private var prevNet = AdbClient.NetSample()
    private var prevNetAt: Date?
    private var lastErrorLogged: String?
    // 슬로우 필드 캐시 — 5s 틱에서도 이전 값 유지 (나왔다 사라졌다 방지)
    private var cacheMemoryUsedGB: Double?
    private var cacheMemoryTotalGB: Double?
    private var cacheStorageUsedGB: Double?
    private var cacheStorageTotalGB: Double?
    private var cacheNetworkInfo: String?
    private var cacheNetUp: Double?
    private var cacheNetDown: Double?
    private var cacheNetworkType: String?
    private var cacheCPU: Double?
    private var cacheAndroidVersion: String?
    private var cacheSDK: Int?

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
        // 첫 틱 즉시
        await tick()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func tick() async {
        tickCount += 1
        resolveDevice()

        guard let serial else {
            // 기기 없음 — 오프라인 통지하지 않음 (빈 스냅샷 병합 금지)
            return
        }

        var snap = DeviceSnapshot()
        snap.serial = serial
        snap.model = model ?? ""
        snap.isOnline = true

        // ── 5s fast: battery + thermal + loadavg + /proc/stat
        if let battText = try? shell("dumpsys", "battery") {
            let batt = AdbClient.parseBatteryEx(battText)
            snap.batteryLevel = batt.batteryLevel
            snap.batteryTempC = batt.batteryTempC
            snap.isCharging = batt.isCharging
            snap.voltageMV = batt.voltageMV
            snap.batteryHealthPct = batt.batteryHealthPct
            snap.isProtectionMode = batt.isProtectionMode
            snap.protectionThresholdPct = batt.protectionThresholdPct
            snap.cycleEstimate = batt.cycleEstimate
        } else {
            let msg = ErrorCode.adbParseFailed.koMessage
            snap.lastError = msg
            await logLast(msg)
        }

        if let thText = try? shell("dumpsys", "thermalservice") {
            let th = AdbClient.parseThermal(thText)
            snap.thermalStatus = th.status
            // AP 우선, 없으면 SKIN, BAT
            snap.deviceTempC = th.apTempC ?? th.skinTempC ?? th.batTempC
            if snap.batteryTempC == nil {
                snap.batteryTempC = th.batTempC
            }
        }

        if let loadText = try? shell("cat", "/proc/loadavg") {
            snap.load1 = AdbClient.parseLoadAvg(loadText).load1
        }

        if let statText = try? shell("cat", "/proc/stat") {
            let curr = AdbClient.parseProcStat(statText)
            if let use = AdbClient.cpuUsePercent(prev: prevStat, curr: curr) {
                snap.cpuUsePercent = use
                cacheCPU = use
            }
            prevStat = curr
        }
        // 첫 틱/실패 시 캐시 CPU
        if snap.cpuUsePercent == nil {
            snap.cpuUsePercent = cacheCPU
        }

        // ── 15s slow: meminfo + netdev + df (tick % 3 == 0)
        if tickCount % 3 == 1 {
            // tickCount 1,4,7… 첫 틱도 포함해 즉시 채움
            if let memText = try? shell("cat", "/proc/meminfo") {
                let mem = AdbClient.parseMemInfo(memText)
                cacheMemoryTotalGB = mem.totalGB
                cacheMemoryUsedGB = mem.usedGB
            }

            if let netText = try? shell("cat", "/proc/net/dev") {
                let curr = AdbClient.parseNetDev(netText)
                var upDown: (up: Double, down: Double)?
                if let at = prevNetAt {
                    upDown = AdbClient.netRatesMBps(
                        prev: prevNet,
                        curr: curr,
                        seconds: Date().timeIntervalSince(at)
                    )
                }
                prevNet = curr
                prevNetAt = Date()
                if let r = upDown {
                    cacheNetUp = r.up
                    cacheNetDown = r.down
                    cacheNetworkInfo = String(
                        format: "↑%.1f ↓%.1f MB/s", r.up, r.down
                    )
                }
            }

            if let connText = try? shell("dumpsys", "connectivity") {
                if let type = AdbClient.parseNetworkType(connText) {
                    cacheNetworkType = type
                }
            }

            if let dfText = try? shell("df", "-h", "/data") {
                let df = AdbClient.parseDf(dfText)
                cacheStorageUsedGB = df.usedGB
                cacheStorageTotalGB = df.totalGB
            }
        }

        // Android/SDK — 첫 틱 1회 (or 캐시)
        if cacheAndroidVersion == nil {
            if let v = (try? shell("getprop", "ro.build.version.release"))?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !v.isEmpty {
                cacheAndroidVersion = v
            }
            if let s = (try? shell("getprop", "ro.build.version.sdk"))?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               let n = Int(s) {
                cacheSDK = n
            }
        }

        // 캐시된 슬로우 값 항상 포함 — 빈 필드로 덮어쓰지 않음
        snap.memoryUsedGB = snap.memoryUsedGB ?? cacheMemoryUsedGB
        snap.memoryTotalGB = snap.memoryTotalGB ?? cacheMemoryTotalGB
        snap.storageUsedGB = snap.storageUsedGB ?? cacheStorageUsedGB
        snap.storageTotalGB = snap.storageTotalGB ?? cacheStorageTotalGB
        snap.networkInfo = snap.networkInfo ?? cacheNetworkInfo
        snap.netUpMBps = snap.netUpMBps ?? cacheNetUp
        snap.netDownMBps = snap.netDownMBps ?? cacheNetDown
        snap.networkType = snap.networkType ?? cacheNetworkType
        snap.androidVersion = snap.androidVersion ?? cacheAndroidVersion
        snap.sdkInt = snap.sdkInt ?? cacheSDK

        onSnapshot?(snap)
    }

    // MARK: - ADB

    private func resolveDevice() {
        if adbPath == nil {
            adbPath = findAdb()
            if adbPath == nil {
                Task { @MainActor in
                    DebugLogger.shared.error(
                        "Monitor",
                        "[ERROR] [ADB] " + ErrorCode.adbBinaryMissing.koMessage
                )}
                return
            }
        }
        guard let adb = adbPath else { return }

        // adb devices
        let list = (try? run(adb, ["devices"])) ?? ""
        let found = list.split(separator: "\n")
            .map(String.init)
            .filter { $0.contains("\tdevice") }
            .compactMap { line -> String? in
                line.split(whereSeparator: \.isWhitespace).first.map(String.init)
            }
            .first

        if let found, found != serial {
            serial = found
            let resolved = (try? run(adb, ["-s", found, "shell", "getprop", "ro.product.model"]))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            model = resolved
            // Android/SDK 즉시 1회
            if let v = (try? run(adb, ["-s", found, "shell", "getprop", "ro.build.version.release"]))?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !v.isEmpty {
                cacheAndroidVersion = v
            }
            if let s = (try? run(adb, ["-s", found, "shell", "getprop", "ro.build.version.sdk"]))?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               let n = Int(s) {
                cacheSDK = n
            }
            let short = AdbClient.shortId(found)
            let modelName = resolved ?? "?"
            Task { @MainActor in
                DebugLogger.shared.info(
                    "Monitor",
                    "[INFO] [ADB] 기기 연결",
                    meta: "serial=\(short) model=\(modelName)"
                )
                ConsoleStore.shared.pushEvent("기기 연결 \(short)")
            }
        } else if found == nil, let old = serial {
            serial = nil
            model = nil
            let short = AdbClient.shortId(old)
            Task { @MainActor in
                ConsoleStore.shared.markDeviceOffline(old)
                DebugLogger.shared.warn("Monitor", "[WARN] [ADB] 기기 연결 끊김")
                ConsoleStore.shared.pushEvent("기기 연결 끊김 \(short)")
            }
        }
    }

    private func findAdb() -> String? {
        let candidates = [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "/usr/bin/adb"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        // PATH 탐색
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in pathEnv.split(separator: ":") {
            let p = "\(dir)/adb"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    private func shell(_ args: String...) throws -> String {
        guard let adb = adbPath else {
            throw ErrorCode.adbBinaryMissing
        }
        return try run(adb, ["shell"] + args)
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
