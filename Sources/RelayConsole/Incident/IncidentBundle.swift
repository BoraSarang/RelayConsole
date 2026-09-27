import Foundation
import AppKit

/// Incident 번들 순수 로직 — 대상 판별·디렉터리명·쿨다운·manifest (테스트 대상)
enum IncidentBundleLogic {
    static let autoCooldown: TimeInterval = 300
    /// main 버퍼 폴백 덤프 줄 수 (`-T` 미지원 기기용)
    static let logcatTailLines = 500
    /// `-T` 앵커를 이벤트 시각보다 **얼마나 되돌릴지** (초)
    ///
    /// **`event.at` 은 크래시 그 자체의 시각이 아니다.** 크래시가 10:00:06 에 났어도
    /// 폴링(5초)·번들 캡처 지연 때문에 이벤트는 10:00:12 에 발행된다.
    /// 실측: 이벤트 `at`=10:00:12, 실제 `has died` 라인=**10:00:06**.
    /// → 앵커를 `event.at` 에 정확히 두면 **크래시 라인이 창 밖으로 밀려난다.**
    ///   (`-T 10:00:12` → 17건, `-T 10:00:00` → 18건으로 실측 차이 확인)
    ///
    /// 60초는 폴링 5초 + 캡처 지연 + `logcatEventInterval`(300초) 쿨다운을 감안한 여유다.
    /// 앞쪽은 `mainLogcatMaxBytes` 로 잘라 나가므로 비용은 늘지 않는다.
    static let mainLogcatLeadSeconds: TimeInterval = 60
    /// crash 버퍼 덤프 줄 수 — 스택 트레이스가 사는 곳
    static let crashBufferTailLines = 300
    /// main 버퍼 덤프 상한 (bytes) — **상한 없으면 디스크를 태운다**
    ///
    /// 실측 (2026-09-27, 10.233.247.205:5555 — SM-S901N):
    /// `logcat -d -T <5분 전>` = **39.0MB / 33만 줄**. 종전 `-t 500` 은 52KB.
    /// = 이벤트 1건당 **750배** 부풀고, 이 기기는 초당 약 9천 줄을 뱉는다.
    /// 쿨다운 300초 + ANR/크래시/사이트 down 캡처가 겹치면 GB 단위로 쌓인다.
    ///
    /// adb 쪽에서 자를 수는 없다 — **실측: `-T` 에 `-t` 를 같이 주면 `-T` 가 이긴다**
    /// (`-T … -t 3000` → 336,024줄 / 39MB). 그래서 읽는 쪽에서 뒤를 자른다.
    static let mainLogcatMaxBytes = 2 * 1024 * 1024

    /// 상한을 넘으면 **앞을 버리고 뒤만 남기는** 바이트 버퍼 (테스트 대상).
    ///
    /// `logcat -d -T` 는 39MB 를 뱉는데 adb 쪽에서 자를 방법이 없다
    /// (실측: `-T` + `-t` 동시 지정 시 `-T` 가 이긴다). 그래서 읽는 쪽에서 자른다.
    /// **뒤를 남기는 이유** — `-T <이벤트 시각>` 기준이라 덤프의 끝이 이벤트에 가장 가깝다.
    struct TailBuffer {
        private let maxBytes: Int
        private var buf = Data()
        /// 상한 때문에 버려진 총 바이트 — "뭘 잃었는지"를 숨기지 않기 위함 ([표시②])
        private(set) var droppedBytes = 0

        init(maxBytes: Int) {
            self.maxBytes = max(0, maxBytes)
        }

        mutating func append(_ chunk: Data) {
            guard !chunk.isEmpty else { return }
            guard maxBytes > 0 else {
                droppedBytes &+= chunk.count
                return
            }
            buf.append(chunk)
            if buf.count > maxBytes {
                let overflow = buf.count - maxBytes
                buf.removeFirst(overflow)
                droppedBytes &+= overflow
            }
        }

        var data: Data { buf }
        var isEmpty: Bool { buf.isEmpty }
    }

    /// 잘려서 빠진 앞부분을 **숨기지 않는다** ([표시②]) — 번들을 연 사람이 알 수 있어야 한다.
    static func truncationNotice(droppedBytes: Int, maxBytes: Int) -> String {
        let mb = Double(droppedBytes) / 1_048_576
        return "===== RelayConsole: logcat 앞부분 \(String(format: "%.1f", mb))MB 생략 "
            + "(상한 \(maxBytes / 1_048_576)MB) — 끝쪽( 이벤트 시각 이후 최신)만 보존됨 ====="
    }

    /// 자동/수동 캡처 대상 — ANR·크래시·사이트 down (clear 제외)
    static func captures(kind: WatchKind) -> Bool {
        switch kind {
        case .anr, .crash, .siteDown: return true
        default: return false
        }
    }

    /// `20260924-195900-anr-A1B2C3` — 파일시스템 안전·정렬 가능
    static func directoryName(event: WatchEvent, at: Date = .now) -> String {
        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: at)
        let ts = String(
            format: "%04d%02d%02d-%02d%02d%02d",
            c.year ?? 1970, c.month ?? 1, c.day ?? 1,
            c.hour ?? 0, c.minute ?? 0, c.second ?? 0
        )
        let ident = sanitize(event.serial)
        return "\(ts)-\(sanitize(event.kind.rawValue))-\(ident)"
    }

    /// fingerprint 기준 5분 쿨다운 (nil lastAt = 첫 시도)
    static func shouldAutoCapture(
        fingerprint: String,
        now: Date = .now,
        lastAt: [String: Date] = [:]
    ) -> Bool {
        guard let last = lastAt[fingerprint] else { return true }
        return now.timeIntervalSince(last) >= autoCooldown
    }

    /// Android USB/network serial 판별 — `site:`·`job:`·Apple udid 제외
    static func isAndroidSerial(_ serial: String) -> Bool {
        guard !serial.isEmpty else { return false }
        if serial.hasPrefix("site:") || serial.hasPrefix("job:") { return false }
        if serial == "TEST" { return false }
        // Apple udid는 40자 hex· `-` 무 — ADB serial은 보통 짧거나 `IP:PORT`
        if serial.count == 40, serial.allSatisfy({ $0.isHexDigit }) { return false }
        return true
    }

    /// manifest.json 본문 — 이벤트 + 캡처 시각 + 앱 버전 + 첨부 파일
    static func manifestData(
        event: WatchEvent,
        capturedAt: Date = .now,
        appVersion: String,
        files: [String] = ["manifest.json"]
    ) -> Data? {
        struct Manifest: Encodable {
            let schema = 1
            let appVersion: String
            let capturedAt: Date
            let event: WatchEvent
            let files: [String]
        }
        let m = Manifest(
            appVersion: appVersion,
            capturedAt: capturedAt,
            event: event,
            files: files
        )
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? enc.encode(m)
    }

    private static func sanitize(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let mapped = String(s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        let trimmed = mapped.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "x" : trimmed
    }
}

/// 번들 항목 — 디렉터리 스캔 결과
struct IncidentBundleEntry: Identifiable, Equatable, Sendable {
    let id: String
    let url: URL
    let createdAt: Date
    let hasLogcat: Bool
    /// crash 버퍼 덤프 — 스택 트레이스가 사는 곳 (없으면 "왜 죽었는지"를 볼 수 없다)
    let hasCrashLogcat: Bool
    let hasScreenshot: Bool
}

/// Incident 번들 저장소 — Application Support/RelayConsole/incidents/
@MainActor
final class IncidentBundleStore: ObservableObject {
    static let shared = IncidentBundleStore()

    @Published private(set) var bundles: [IncidentBundleEntry] = []
    @Published private(set) var lastCaptureError: String?

    private let root: URL
    private var capturing: Set<String> = []

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        root = base
            .appendingPathComponent("RelayConsole", isDirectory: true)
            .appendingPathComponent("incidents", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        reload()
    }

    var rootURL: URL { root }

    /// 디렉터리 목록 — 최신 우선
    nonisolated static func listEntries(root: URL) -> [IncidentBundleEntry] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }
        var out: [IncidentBundleEntry] = []
        for name in names {
            let dir = root.appendingPathComponent(name, isDirectory: true)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let values = try? dir.resourceValues(forKeys: [.creationDateKey])
            let created = values?.creationDate ?? .distantPast
            out.append(IncidentBundleEntry(
                id: name,
                url: dir,
                createdAt: created,
                hasLogcat: fm.fileExists(atPath: dir.appendingPathComponent("logcat.txt").path),
                hasCrashLogcat: fm.fileExists(
                    atPath: dir.appendingPathComponent("crash-logcat.txt").path
                ),
                hasScreenshot: fm.fileExists(atPath: dir.appendingPathComponent("screenshot.png").path)
            ))
        }
        return out.sorted { $0.createdAt > $1.createdAt }
    }

    func reload() {
        bundles = Self.listEntries(root: root)
    }

    func openRoot() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        NSWorkspace.shared.open(root)
    }

    func reveal(_ entry: IncidentBundleEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([entry.url])
    }

    /// 번들 캡처 — manifest 필수, Android면 logcat+스크린샷 (이미 캡처 중이면 스킵)
    func capture(event: WatchEvent, adbPath: String?, appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0") {
        guard IncidentBundleLogic.captures(kind: event.kind), !event.isClear else { return }
        let name = IncidentBundleLogic.directoryName(event: event)
        guard !capturing.contains(name) else { return }
        capturing.insert(name)
        lastCaptureError = nil

        let dir = root.appendingPathComponent(name, isDirectory: true)
        let adb = IncidentBundleLogic.isAndroidSerial(event.serial) ? adbPath : nil

        Task.detached(priority: .utility) {
            let fm = FileManager.default
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                await MainActor.run {
                    self.capturing.remove(name)
                    self.lastCaptureError = error.localizedDescription
                }
                return
            }

            var files = ["manifest.json"]
            if let adb {
                // ① crash 버퍼 — **스택 트레이스가 실제로 사는 곳**.
                //    main 버퍼는 수십 초 만에 밀려나지만 crash 버퍼는 크래시 원문이 남는다.
                //
                //    실측 (2026-09-27, SM-S901N): 이 기기는 **crash 버퍼가 비어 있다**(0줄).
                //    그래도 덤프는 건다 — 비어 있는 기기에서만 놓치고,
                //    버퍼를 쓰는 기기에서는 여기에 스택이 실제로 남는다.
                if let got = Self.runCaptureTail(
                    adb: adb,
                    args: ["-s", event.serial, "logcat", "-d", "-b", "crash",
                           "-t", "\(IncidentBundleLogic.crashBufferTailLines)", "-v", "time"],
                    maxBytes: IncidentBundleLogic.mainLogcatMaxBytes
                ), !got.text.isEmpty {
                    let body = got.droppedBytes > 0
                        ? IncidentBundleLogic.truncationNotice(
                            droppedBytes: got.droppedBytes,
                            maxBytes: IncidentBundleLogic.mainLogcatMaxBytes
                        ) + "\n" + got.text
                        : got.text
                    try? Data(body.utf8)
                        .write(to: dir.appendingPathComponent("crash-logcat.txt"), options: .atomic)
                    files.append("crash-logcat.txt")
                }

                // ② main 버퍼 — **이벤트 시각 이후**를 덤프해야 크래시 전후 문맥이 남는다.
                //
                //    종전엔 `logcat -d -t 500` 이었다. 이 기기는 초당 3만 줄이라 500줄은
                //    약 2초분이고, 번들 캡처는 이벤트로부터 2분 뒤에 돌아갔다.
                //    = 크래시 라인이 이미 롤아웃돼 번들에 스택이 하나도 안 들어갔다.
                let main = Self.captureMainLogcat(adb: adb, serial: event.serial, at: event.at)
                if !main.isEmpty {
                    try? Data(main.utf8)
                        .write(to: dir.appendingPathComponent("logcat.txt"), options: .atomic)
                    files.append("logcat.txt")
                }

                if let png = Self.runCaptureData(adb: adb, args: ["-s", event.serial, "exec-out", "screencap", "-p"]),
                   !png.isEmpty,
                   NSImage(data: png) != nil {
                    try? png.write(to: dir.appendingPathComponent("screenshot.png"), options: .atomic)
                    files.append("screenshot.png")
                }
            }
            if let manifest = IncidentBundleLogic.manifestData(
                event: event,
                appVersion: appVersion,
                files: files
            ) {
                try? manifest.write(to: dir.appendingPathComponent("manifest.json"), options: .atomic)
            }

            await MainActor.run {
                self.capturing.remove(name)
                self.reload()
                DebugLogger.shared.info(
                    "Incident",
                    "[INFO] [INCIDENT] 번들 캡처 \(name)"
                )
            }
        }
    }

    /// main 버퍼를 **이벤트 시각 이후**부터 덤프 — 앞뒤 문맥이 남는다.
    ///
    /// `logcat -T` 는 기기 로컬 시간 `MM-DD HH:MM:SS.mmm` 형식을 받는다.
    /// `-T` 를 지원하지 않는 기기나 결과가 비면 `-t` 폴백으로 넘어간다
    /// (어차피 crash 버퍼에 스택은 있으므로 문맥만 약해진다 — 파일은 사라지지 않는다).
    ///
    /// **양쪽 모두 상한을 건다** — `-T` 경로는 39MB 가 나온다(`IncidentBundleLogic.mainLogcatMaxBytes`).
    nonisolated private static func captureMainLogcat(
        adb: String,
        serial: String,
        at: Date
    ) -> String {
        let cap = IncidentBundleLogic.mainLogcatMaxBytes
        let base = ["-s", serial, "logcat", "-d", "-v", "time"]
        let stamp = logcatStampFormatter.string(
            from: at.addingTimeInterval(-IncidentBundleLogic.mainLogcatLeadSeconds)
        )
        if let got = runCaptureTail(adb: adb, args: base + ["-T", stamp], maxBytes: cap) {
            guard got.droppedBytes > 0 else { return got.text }
            return IncidentBundleLogic.truncationNotice(droppedBytes: got.droppedBytes, maxBytes: cap)
                + "\n" + got.text
        }
        // 폴백 — `-t` 는 애초에 작지만, 기기가 개입적이라 상한은 그대로 건다
        if let got = runCaptureTail(
            adb: adb,
            args: base + ["-t", "\(IncidentBundleLogic.logcatTailLines)"],
            maxBytes: cap
        ) {
            guard got.droppedBytes > 0 else { return got.text }
            return IncidentBundleLogic.truncationNotice(droppedBytes: got.droppedBytes, maxBytes: cap)
                + "\n" + got.text
        }
        return ""
    }

    /// logcat `-T` 규격 — 기기 로컬 시간 기준
    nonisolated private static let logcatStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    nonisolated private static func runCaptureData(adb: String, args: [String]) -> Data? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: adb)
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
        guard proc.terminationStatus == 0, !data.isEmpty else { return nil }
        return data
    }

    /// stdout 을 **상한만 유지하며** 읽는다 — 전체를 메모리에 올리지 않는다.
    ///
    /// 두 가지 위험을 함께 막는다.
    ///
    /// 1. **메모리** — `logcat -d -T` 는 39MB를 뱉는다. `readDataToEndOfFile()` 로 받으면
    ///    Data 39MB + String 39MB 가 동시에 살아 있다. 여기서는 `maxBytes` 를 넘으면
    ///    **앞에서부터 버리며** 항상 상한 이하만 붙든다.
    /// 2. **교착** — 종전 `runCaptureData` 는 `standardError = Pipe()` 만 해놓고 읽지 않았다.
    ///    stderr 가 64KB 를 넘으면 adb 가 `write()` 에서 블로킹돼 stdout 이 멎는다
    ///    (`LogViewerView` stderr 교착과 동일 함정). 여기는 stderr 도 함께 배수한다.
    ///
    /// **뒤를 남기는 이유** — 호출부가 `-T <이벤트 시각>` 이므로 덤프의 **끝**이 이벤트에
    /// 가장 가깝다. 앞을 자르면 크래시 직후 문맥이 지워진다.
    nonisolated private static func runCaptureTail(
        adb: String,
        args: [String],
        maxBytes: Int
    ) -> (text: String, droppedBytes: Int)? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: adb)
        proc.arguments = args
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        do {
            try proc.run()
        } catch {
            return nil
        }

        // stderr 배수 — 64KB 파이프가 차면 stdout 생산이 멎는다
        let errHandle = err.fileHandleForReading
        errHandle.readabilityHandler = { h in
            _ = h.availableData
        }

        let handle = out.fileHandleForReading
        let sink = TailSink(maxBytes: maxBytes)
        let sem = DispatchSemaphore(value: 0)
        handle.readabilityHandler = { h in
            let chunk = h.availableData
            if chunk.isEmpty {
                h.readabilityHandler = nil
                sem.signal()
                return
            }
            sink.append(chunk)
        }
        sem.wait()
        handle.readabilityHandler = nil
        errHandle.readabilityHandler = nil
        _ = errHandle.readDataToEndOfFile()
        proc.waitUntilExit()
        let tail = sink.snapshot
        guard proc.terminationStatus == 0, !tail.isEmpty else { return nil }
        return (String(decoding: tail.data, as: UTF8.self), tail.droppedBytes)
    }

    /// `readabilityHandler` 는 `@Sendable` 이라 `var` 를 캡처할 수 없다.
    /// 잠금으로 감싼 참조 박스 (`LogViewerView.StderrTail` 와 같은 패턴).
    private final class TailSink: @unchecked Sendable {
        private let lock = NSLock()
        private var buf: IncidentBundleLogic.TailBuffer

        init(maxBytes: Int) {
            buf = IncidentBundleLogic.TailBuffer(maxBytes: maxBytes)
        }

        func append(_ chunk: Data) {
            lock.lock()
            buf.append(chunk)
            lock.unlock()
        }

        var snapshot: IncidentBundleLogic.TailBuffer {
            lock.lock()
            defer { lock.unlock() }
            return buf
        }
    }
}
