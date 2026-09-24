import Foundation

/// Trust-only Apple 기기 폴링 — idevice_id / ideviceinfo (60s, 백그라운드)
/// IO는 이 actor 안에서만. UI는 ConsoleStore.appleDevices만 읽음
actor AppleDeviceMonitor {
    static let shared = AppleDeviceMonitor()

    private var timer: Task<Void, Never>?
    private var handler: (@Sendable (AppleSnapshot) -> Void)?
    private var eventHandler: (@Sendable (String) -> Void)?
    private var cache: [String: AppleSnapshot] = [:]
    private var lastErrorLogged: String?
    private let pollSeconds: UInt64 = 60

    private init() {}

    func attach(_ handler: @escaping @Sendable (AppleSnapshot) -> Void) {
        self.handler = handler
    }

    func attachEvent(_ handler: @escaping @Sendable (String) -> Void) {
        self.eventHandler = handler
    }

    func start() {
        guard timer == nil else { return }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.pollOnce()
                try? await Task.sleep(nanoseconds: self.pollSeconds * 1_000_000_000)
            }
        }
        Task { await pollOnce() }
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// UI·테스트 강제 조회
    func refreshNow() async {
        await pollOnce()
    }

    private func pollOnce() async {
        guard IdeviceClient.toolsAvailable else {
            await logLast(L10n.string("apple.tools.missing"))
            // 도구 없음 → 오프라인으로 정리
            for (udid, prev) in cache where prev.isOnline {
                var off = prev
                off.isOnline = false
                off.at = .now
                cache[udid] = off
                emit(off)
            }
            return
        }
        lastErrorLogged = nil

        guard let idPath = IdeviceClient.locateIdeviceId(),
              let infoPath = IdeviceClient.locateIdeviceInfo() else { return }

        let idOut = run(idPath, ["-l"])
        let found = Set(IdeviceClient.parseDeviceIds(idOut ?? ""))

        // 이전 → 오프라인
        for udid in cache.keys where !found.contains(udid) && cache[udid]?.isOnline == true {
            var off = cache[udid]!
            off.isOnline = false
            off.at = .now
            cache[udid] = off
            emit(off)
            await notify(L10n.format("apple.event.disconnected", IdeviceClient.shortUdid(udid)))
        }

        for udid in found {
            let infoText = run(infoPath, ["-u", udid]) ?? ""
            var info = IdeviceClient.parseInfo(infoText)
            // disk_usage 병합 (실패해도 배터리·디바이스 정보는 유지)
            let diskText = run(infoPath, ["-u", udid, "-q", "com.apple.disk_usage"]) ?? ""
            let disk = IdeviceClient.parseInfo(diskText)
            if diskText.isEmpty == false {
                info.merge(disk) { _, new in new }
            }
            var snap = IdeviceClient.snapshot(udid: udid, info: info, disk: [:])
            // disk merge 이미 info에 들어갔으면 snapshot이 처리, 아니면 disk 키로 재시도
            if snap.storageTotalGB == nil, !disk.isEmpty {
                snap = IdeviceClient.snapshot(udid: udid, info: info, disk: disk)
            }
            let isNew = cache[udid] == nil
            let wasOffline = cache[udid]?.isOnline == false
            cache[udid] = snap
            emit(snap)
            if isNew || wasOffline {
                await notify(L10n.format("apple.event.connected", snap.displayName))
            }
        }
    }

    private func emit(_ snap: AppleSnapshot) {
        guard let handler else { return }
        handler(snap)
    }

    private func notify(_ text: String) async {
        guard let eventHandler else { return }
        eventHandler(text)
    }

    private func run(_ path: String, _ args: [String]) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private func logLast(_ message: String) async {
        guard message != lastErrorLogged else { return }
        lastErrorLogged = message
        await MainActor.run {
            DebugLogger.shared.warn("Apple", "[WARN] [APPLE] \(message)")
        }
    }
}
