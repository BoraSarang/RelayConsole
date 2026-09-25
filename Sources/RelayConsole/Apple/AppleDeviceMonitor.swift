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
            let msg = "[\(ErrorCode.appleBinaryMissing.rawValue)] \(ErrorCode.appleBinaryMissing.koMessage)"
            await logLast(msg)
            await publishError(msg)
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
        await publishError(nil)

        guard let idPath = IdeviceClient.locateIdeviceId(),
              let infoPath = IdeviceClient.locateIdeviceInfo() else { return }

        let idOut = run(idPath, ["-l"])
        if idOut == nil {
            let msg = "[\(ErrorCode.appleConnectFailed.rawValue)] \(ErrorCode.appleConnectFailed.koMessage)"
            await logLast(msg)
            await publishError(msg)
        }
        let found = Set(IdeviceClient.parseDeviceIds(idOut ?? ""))

        // 이전 → 오프라인
        for udid in cache.keys where !found.contains(udid) && cache[udid]?.isOnline == true {
            var off = cache[udid]!
            off.isOnline = false
            off.at = .now
            cache[udid] = off
            emit(off)
            let short = off.identLabel
            await notify(L10n.format("apple.event.disconnected", short))
            await emitWatch(
                kind: .appleDisconnected,
                serial: udid,
                title: L10n.string("event.appleDisconnected"),
                detail: short
            )
        }

        var anyOnline = false
        var failDetail: String?
        for udid in found {
            let infoRes = runCapture(infoPath, ["-u", udid])
            guard let infoText = infoRes.out, !infoText.isEmpty else {
                // ideviceinfo 실패 — 이전 스냅샷을 오프라인으로 강등 (성공으로 위장 금지 · AGENTS.local §4 [표시②])
                if var off = cache[udid] {
                    off.isOnline = false
                    off.at = .now
                    cache[udid] = off
                    emit(off)
                }
                if failDetail == nil { failDetail = infoRes.err }
                continue
            }
            anyOnline = true
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
                await emitWatch(
                    kind: .appleConnected,
                    serial: udid,
                    title: L10n.string("event.appleConnected"),
                    detail: snap.identLabel
                )
            }
        }
        // 오류 배너 — 실패 시 실제 원인, 전부 성공 시 해제
        if let failDetail {
            let reason = failDetail.isEmpty
                ? ErrorCode.appleConnectFailed.koMessage
                : "\(ErrorCode.appleConnectFailed.koMessage) — \(failDetail)"
            await publishError("[\(ErrorCode.appleConnectFailed.rawValue)] \(reason)")
        } else if anyOnline {
            await publishError(nil)
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

    /// WatchEvent 발행 → ConsoleStore.ingestWatch (EventStore 영구화 포함)
    private func emitWatch(kind: WatchKind, serial: String, title: String, detail: String) async {
        let event = WatchEvent(
            kind: kind,
            severity: .info,
            serial: serial,
            title: title,
            detail: detail,
            source: .apple
        )
        await MainActor.run {
            ConsoleStore.shared.ingestWatch(event)
        }
    }

    private func publishError(_ message: String?) async {
        await MainActor.run {
            ConsoleStore.shared.setAppleError(message)
        }
    }

    private func run(_ path: String, _ args: [String]) -> String? {
        runCapture(path, args).out
    }

    /// stdout + stderr 함께 수집 — 실패 원인을 화면에 노출 (AGENTS.local §4 [표시②])
    private func runCapture(_ path: String, _ args: [String]) -> (out: String?, err: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let out = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = out
        proc.standardError = errPipe
        do {
            try proc.run()
        } catch {
            return (nil, error.localizedDescription)
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let errText = String(decoding: errData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard proc.terminationStatus == 0 else { return (nil, errText) }
        return (String(decoding: data, as: UTF8.self), errText)
    }

    private func logLast(_ message: String) async {
        guard message != lastErrorLogged else { return }
        lastErrorLogged = message
        await MainActor.run {
            DebugLogger.shared.warn("Apple", "[WARN] [APPLE] \(message)")
        }
    }
}
