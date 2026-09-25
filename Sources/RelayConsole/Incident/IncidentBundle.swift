import Foundation
import AppKit

/// Incident 번들 순수 로직 — 대상 판별·디렉터리명·쿨다운·manifest (테스트 대상)
enum IncidentBundleLogic {
    static let autoCooldown: TimeInterval = 300
    static let logcatTailLines = 500

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
                if let text = Self.runCapture(adb: adb, args: ["-s", event.serial, "logcat", "-d", "-t", "\(IncidentBundleLogic.logcatTailLines)", "-v", "time"]),
                   !text.isEmpty,
                   let data = text.data(using: .utf8) {
                    try? data.write(to: dir.appendingPathComponent("logcat.txt"), options: .atomic)
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

    nonisolated private static func runCapture(adb: String, args: [String]) -> String? {
        guard let data = runCaptureData(adb: adb, args: args) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

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
}
