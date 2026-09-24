import Foundation
import AppKit

/// A4 갤러리 순수 로직 — 확장자·ls 파싱·파일명·adb 인자 (테스트 대상)
enum GalleryLogic {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "heic"]
    static let remoteDirs = [
        "/sdcard/DCIM/Screenshots",
        "/sdcard/Pictures/Screenshots"
    ]

    static func isImage(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return imageExtensions.contains(ext)
    }

    /// 대소문자 무시 검색 · 빈 쿼리 = 전체 · 이미지 확장자만
    static func filter(_ names: [String], query: String) -> [String] {
        let images = names.filter { isImage($0) }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return images }
        return images.filter { $0.lowercased().contains(q) }
    }

    /// `ls -1` 한 줄 파일명 (공백 줄·`.` `..` 제외)
    static func parseLs(_ text: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let s = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty, s != ".", s != "..", !seen.contains(s) else { continue }
            seen.insert(s)
            out.append(s)
        }
        return out
    }

    /// `20260924-120000-capture-SERIAL.png` — 파일시스템 안전
    static func localFileName(source: String, serial: String, at: Date = .now) -> String {
        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: at)
        let ts = String(
            format: "%04d%02d%02d-%02d%02d%02d",
            c.year ?? 1970, c.month ?? 1, c.day ?? 1,
            c.hour ?? 0, c.minute ?? 0, c.second ?? 0
        )
        return "\(ts)-\(sanitize(source))-\(sanitize(serial)).png"
    }

    static func listArgs(remoteDir: String) -> [String] {
        ["shell", "ls", "-1", remoteDir]
    }

    static func pullArgs(remoteDir: String, file: String) -> [String] {
        ["pull", "\(remoteDir)/\(file)"]
    }

    private static func sanitize(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = String(s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        let trimmed = mapped.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "x" : trimmed
    }
}

/// 갤러리 항목 — 디렉터리 스캔 결과
struct GalleryEntry: Identifiable, Equatable, Sendable {
    let id: String
    let url: URL
    let createdAt: Date
    /// Android serial 또는 비어있음
    let serial: String?
    /// `capture` | `pull` | `remote`
    let source: String
}

/// Application Support/RelayConsole/gallery/
@MainActor
final class GalleryStore: ObservableObject {
    static let shared = GalleryStore()

    @Published private(set) var entries: [GalleryEntry] = []
    @Published private(set) var lastError: String?

    private let root: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        root = base
            .appendingPathComponent("RelayConsole", isDirectory: true)
            .appendingPathComponent("gallery", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        reload()
    }

    var rootURL: URL { root }

    nonisolated static func listEntries(root: URL) -> [GalleryEntry] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }
        var out: [GalleryEntry] = []
        for name in names {
            guard GalleryLogic.isImage(name) else { continue }
            let url = root.appendingPathComponent(name)
            guard fm.fileExists(atPath: url.path) else { continue }
            let values = try? url.resourceValues(forKeys: [.creationDateKey])
            let created = values?.creationDate ?? .distantPast
            out.append(GalleryEntry(
                id: name,
                url: url,
                createdAt: created,
                serial: serialFromFileName(name),
                source: sourceFromFileName(name)
            ))
        }
        return out.sorted { $0.createdAt > $1.createdAt }
    }

    /// `YYYYMMDD-HHMMSS-<source>-<serial>.png` → serial (없으면 nil)
    nonisolated static func serialFromFileName(_ name: String) -> String? {
        let base = (name as NSString).deletingPathExtension
        let parts = base.split(separator: "-")
        guard parts.count >= 4 else { return nil }
        let tail = parts.dropFirst(3).joined(separator: "-")
        return tail.isEmpty || tail == "x" ? nil : tail
    }

    nonisolated static func sourceFromFileName(_ name: String) -> String {
        let base = (name as NSString).deletingPathExtension
        let parts = base.split(separator: "-")
        guard parts.count >= 3 else { return "capture" }
        return String(parts[2])
    }

    func reload() {
        entries = Self.listEntries(root: root)
    }

    func openRoot() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        NSWorkspace.shared.open(root)
    }

    func reveal(_ entry: GalleryEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([entry.url])
    }

    func delete(_ entry: GalleryEntry) {
        try? FileManager.default.removeItem(at: entry.url)
        reload()
    }

    func save(data: Data, name: String, serial: String?, source: String) -> Bool {
        guard !data.isEmpty else { return false }
        let safe = GalleryLogic.localFileName(
            source: source,
            serial: serial ?? "local",
            at: .now
        )
        // name 인자 사용 시 정해진 로컬명 우선하지 않고 localFileName 사용 (충돌 회피)
        let url = root.appendingPathComponent(safe)
        do {
            try data.write(to: url, options: .atomic)
            lastError = nil
            reload()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
}

/// 갤러리 컨트롤러 — 현재 스샷 저장 · 기기 Screenshots ls/pull
@MainActor
final class GalleryController: ObservableObject {
    static let shared = GalleryController()

    @Published private(set) var loading = false
    @Published private(set) var remoteNames: [String] = []
    @Published private(set) var busyFile: String?
    @Published var lastMessage: String?

    private init() {}

    /// 현재 ScreenshotService 썸네일 PNG를 갤러리에 저장
    func saveCurrent(serial: String) {
        guard let img = ScreenshotService.shared.images[serial],
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            lastMessage = L10n.string("gallery.status.noImage")
            return
        }
        if GalleryStore.shared.save(data: png, name: "", serial: serial, source: "capture") {
            lastMessage = L10n.string("gallery.status.saved")
        } else {
            lastMessage = GalleryStore.shared.lastError ?? L10n.string("gallery.status.failed")
        }
    }

    /// 기기 표준 Screenshots 폴러 목록 (합집합·이미지만)
    func listRemote(serial: String) {
        guard !serial.isEmpty, !loading else { return }
        loading = true
        lastMessage = nil
        let adb = DeviceMonitor.adbPathNow()
        Task.detached(priority: .utility) {
            var names: [String] = []
            if let adb {
                for dir in GalleryLogic.remoteDirs {
                    let text = Self.run(adb: adb, args: ["-s", serial] + GalleryLogic.listArgs(remoteDir: dir))
                    if let text {
                        names.append(contentsOf: GalleryLogic.parseLs(text))
                    }
                }
            }
            let unique = GalleryLogic.filter(Array(Set(names)), query: "")
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedDescending }
            await MainActor.run {
                self.remoteNames = unique
                self.loading = false
                self.lastMessage = unique.isEmpty
                    ? L10n.string("gallery.status.emptyRemote")
                    : L10n.format("gallery.status.remoteCount", "\(unique.count)")
            }
        }
    }

    /// 기기 파일 → 로컬 갤러리 pull
    func pullRemote(serial: String, file: String) {
        guard !serial.isEmpty, !file.isEmpty, busyFile == nil else { return }
        busyFile = file
        lastMessage = nil
        let adb = DeviceMonitor.adbPathNow()
        let store = GalleryStore.shared
        Task.detached(priority: .utility) {
            defer { }
            guard let adb else {
                await MainActor.run {
                    self.busyFile = nil
                    self.lastMessage = L10n.string("gallery.status.failed")
                }
                return
            }
            // pull 을 stdout으로 받기보다 임시 파일로
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(GalleryLogic.localFileName(source: "pull", serial: serial, at: .now))
            // remote path 결정 — list 순서상 가능한 dir 시도
            var pulled = false
            for dir in GalleryLogic.remoteDirs {
                let remote = "\(dir)/\(file)"
                let ok = Self.runOk(adb: adb, args: ["-s", serial, "pull", remote, tmp.path])
                if ok, FileManager.default.fileExists(atPath: tmp.path) {
                    pulled = true
                    break
                }
            }
            await MainActor.run {
                self.busyFile = nil
                if pulled, let data = try? Data(contentsOf: tmp) {
                    let name = GalleryLogic.localFileName(source: "pull", serial: serial, at: .now)
                    _ = store.save(data: data, name: name, serial: serial, source: "pull")
                    self.lastMessage = L10n.string("gallery.status.pulled")
                    try? FileManager.default.removeItem(at: tmp)
                } else {
                    self.lastMessage = L10n.string("gallery.status.failed")
                }
            }
        }
    }

    nonisolated private static func run(adb: String, args: [String]) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: adb)
        proc.arguments = args
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    nonisolated private static func runOk(adb: String, args: [String]) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: adb)
        proc.arguments = args
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do { try proc.run() } catch { return false }
        proc.waitUntilExit()
        return proc.terminationStatus == 0
    }
}
