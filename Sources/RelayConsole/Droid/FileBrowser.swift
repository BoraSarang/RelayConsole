import Foundation
import AppKit

/// ADB 파일 탐색기 순수 로직 — ls 파싱 · 경로 · 정렬 · 필터 · adb 인자 (테스트 대상)
/// 범위: 읽기 + 전송 (pull/push) — 삭제·이동·설치는 OUT (PLAN_file_browser §1)
enum FileBrowserLogic {

    // MARK: - 모델

    struct Item: Identifiable, Equatable, Sendable {
        let name: String
        let path: String
        let isDir: Bool
        let size: Int64
        let modified: Date?
        let perms: String
        var id: String { path }
    }

    enum SortKey: String, CaseIterable {
        case name, size, modified
    }

    /// 사이드바 즐겨찾기 — (표시명, 절대경로)
    static let favorites: [(label: String, path: String)] = [
        ("Download", "/sdcard/Download"),
        ("DCIM", "/sdcard/DCIM"),
        ("Documents", "/sdcard/Documents"),
        ("Movies", "/sdcard/Movies"),
        ("Pictures", "/sdcard/Pictures"),
        ("Android/data", "/sdcard/Android/data"),
        ("tmp", "/data/local/tmp")
    ]

    /// 더블클릭 열기 허용 크기 (50MB) — 초과 시 가져오기 안내
    static let previewMaxBytes: Int64 = 50 * 1024 * 1024

    static func previewAllows(size: Int64) -> Bool {
        size >= 0 && size <= previewMaxBytes
    }

    // MARK: - ls 파싱 (`ls -la --full-time <dir>/`)

    /// total 헤더 · `.`/`..` 제외 · 심링크 `-> 타깃` 제거 · 오류 줄 무시
    static func parseLs(_ text: String, dir: String) -> [Item] {
        var out: [Item] = []
        var seen = Set<String>()
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(raw)
            if line.hasPrefix("total ") { continue }
            guard let item = parseLsLine(line, dir: dir), !seen.contains(item.path) else { continue }
            seen.insert(item.path)
            out.append(item)
        }
        return out
    }

    /// 한 줄: `perms links owner group size date time [tz] name…`
    /// 8필드 고정 후 나머지 = 이름 (공백 포함) · short 포맷(time에 tz 없는 구형)도 허용
    static func parseLsLine(_ line: String, dir: String) -> Item? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 8 else { return nil }
        let perms = String(parts[0])
        guard perms.count >= 10, let head = perms.first, "bcdlps-".contains(head) else { return nil }
        guard let size = Int64(parts[4]) else { return nil }
        let dateS = String(parts[5])
        let timeS = String(parts[6])
        guard dateS.count == 10, dateS.contains("-"), timeS.contains(":") else { return nil }

        // tz 필드(+0900) 판별 — 없으면 다음 토큰부터 이름
        var nameStart = 7
        var tz: String?
        let maybeTz = String(parts[7])
        if (maybeTz.hasPrefix("+") || maybeTz.hasPrefix("-")),
           maybeTz.count >= 4, maybeTz.count <= 6,
           maybeTz.dropFirst().allSatisfy(\.isNumber) {
            tz = maybeTz
            nameStart = 8
        }
        guard parts.count > nameStart else { return nil }
        var name = parts[nameStart...].joined(separator: " ")
        if let arrow = name.range(of: " -> ") {
            name = String(name[..<arrow.lowerBound])
        }
        name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != ".", name != ".." else { return nil }

        return Item(
            name: name,
            path: join(dir: dir, name: name),
            isDir: head == "d",
            size: size,
            modified: parseDateTime(date: dateS, time: timeS, tz: tz),
            perms: perms
        )
    }

    /// `2026-08-25` + `11:28:20.728804402` + `+0900` → Date
    static func parseDateTime(date: String, time: String, tz: String?) -> Date? {
        let d = date.split(separator: "-")
        guard d.count == 3, let year = Int(d[0]), let month = Int(d[1]), let day = Int(d[2]) else { return nil }
        let t = time.split(separator: ":")
        guard t.count >= 2, let hour = Int(t[0]), let minute = Int(t[1]) else { return nil }
        var second = 0
        var nanosecond = 0
        if t.count >= 3 {
            let secPart = t[2].split(separator: ".")
            if let s = Int(secPart[0]) { second = s }
            if secPart.count >= 2 {
                let frac = String(secPart[1])
                let padded = frac.count >= 9 ? String(frac.prefix(9)) : frac.padding(toLength: 9, withPad: "0", startingAt: 0)
                nanosecond = Int(padded) ?? 0
            }
        }
        var offset = TimeZone.current
        if let tz, tz.count >= 4 {
            let sign: Int = tz.hasPrefix("-") ? -1 : 1
            let digits = tz.dropFirst()
            if digits.count >= 4,
               let hh = Int(digits.prefix(2)), let mm = Int(digits.suffix(2)),
               let tzObj = TimeZone(secondsFromGMT: sign * (hh * 3600 + mm * 60)) {
                offset = tzObj
            }
        }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.second = second
        comps.nanosecond = nanosecond
        comps.timeZone = offset
        return Calendar(identifier: .gregorian).date(from: comps)
    }

    // MARK: - 포맷 · 정렬 · 필터

    /// 69602 → "68.0 KB" (1024 기준)
    static func formatSize(_ bytes: Int64) -> String {
        guard bytes >= 0 else { return "—" }
        if bytes < 1024 { return "\(bytes) B" }
        let units = ["KB", "MB", "GB", "TB"]
        var value = Double(bytes) / 1024.0
        var idx = 0
        while value >= 1024.0, idx < units.count - 1 {
            value /= 1024.0
            idx += 1
        }
        return String(format: "%.1f %@", value, units[idx])
    }

    /// 폴더 우선 + 키 정렬 (asc/desc 모두 폴더가 항상 위)
    static func sort(_ items: [Item], by key: SortKey, ascending: Bool) -> [Item] {
        func comesFirst(_ a: Item, _ b: Item) -> Bool {
            switch key {
            case .name:
                let r = a.name.localizedCaseInsensitiveCompare(b.name)
                return ascending ? r == .orderedAscending : r == .orderedDescending
            case .size:
                return ascending ? a.size < b.size : a.size > b.size
            case .modified:
                let am = a.modified ?? .distantPast
                let bm = b.modified ?? .distantPast
                return ascending ? am < bm : am > bm
            }
        }
        let dirs = items.filter(\.isDir).sorted(by: comesFirst)
        let files = items.filter { !$0.isDir }.sorted(by: comesFirst)
        return dirs + files
    }

    /// 대소문자 무시 이름 필터 · 빈 쿼리 = 전체
    static func filter(_ items: [Item], query: String) -> [Item] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter { $0.name.lowercased().contains(q) }
    }

    // MARK: - 경로

    /// "/sdcard/Download" → "/sdcard" · "/" → nil
    static func parentPath(_ path: String) -> String? {
        var p = path
        while p.hasSuffix("/"), p.count > 1 { p.removeLast() }
        guard !p.isEmpty, p != "/" else { return nil }
        let parent = (p as NSString).deletingLastPathComponent
        return parent.isEmpty ? "/" : parent
    }

    static func join(dir: String, name: String) -> String {
        let d = dir.hasSuffix("/") ? String(dir.dropLast()) : dir
        return d + "/" + name
    }

    /// 목록 ls용 — **`/sdcard`는 심링크라 trailing slash 필수** (RESEARCH §2 함정)
    static func normalizedListDir(_ dir: String) -> String {
        if dir == "/" { return "/" }
        return dir.hasSuffix("/") ? dir : dir + "/"
    }

    /// 로컬 중복 회피 — "a.png" 선점 시 "a (1).png"
    static func uniqueDest(dir: String, name: String, exists: (String) -> Bool) -> String {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = join(dir: dir, name: name)
        var i = 1
        while exists(candidate) {
            let fname = ext.isEmpty ? "\(base) (\(i))" : "\(base) (\(i)).\(ext)"
            candidate = join(dir: dir, name: fname)
            i += 1
        }
        return candidate
    }

    // MARK: - adb 인자

    /// POSIX 셸 싱글쿼트 인용 — 공백·한글·일본어·`'` 포함 경로 보존
    /// 근거(RESEARCH 실측): **adb client는 argv를 공백으로 이어붙일 때 인용하지 않음** →
    /// 원격 sh가 재분리 (`ls: .../Windows: No such file` 재현 확인) → 명령 전체를 1 argv로 전달
    static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func listArgs(dir: String) -> [String] {
        ["shell", "ls -la --full-time " + shellQuote(normalizedListDir(dir))]
    }

    static func pullArgs(remote: String, local: String) -> [String] {
        ["pull", remote, local]
    }

    /// push는 반드시 trailing slash — 없으면 동명 디렉터리와 충돌 가능
    static func pushArgs(local: String, remoteDir: String) -> [String] {
        ["push", local, normalizedListDir(remoteDir)]
    }
}

// MARK: - 컨트롤러 (adb IO)

/// 파일 탐색기 컨트롤러 — 목록/가져오기/전송 (MainActor)
/// 실패 시 **stderr 원문을 상태줄에 노출** ([표시②]) + `E-MAC-ADB-0004~0006` 로그
@MainActor
final class FileBrowserController: ObservableObject {
    static let shared = FileBrowserController()

    @Published private(set) var serial: String = ""
    @Published private(set) var path: String = "/sdcard"
    @Published private(set) var items: [FileBrowserLogic.Item] = []
    @Published private(set) var loading = false
    @Published private(set) var busy = false
    @Published var statusMessage: String?
    @Published private(set) var destDir: String

    static let destKey = "relay.files.destDir"

    private init() {
        let downloads = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true).path
        destDir = UserDefaults.standard.string(forKey: Self.destKey) ?? downloads
    }

    // MARK: 진입 · 이동

    func open(serial: String) {
        if serial != self.serial {
            self.serial = serial
            path = "/sdcard"
            items = []
            statusMessage = nil
        }
        DebugLogger.shared.info(
            "FileBrowser",
            "[INFO] [FEATURE] 파일 탐색기 serial=…\(serial.suffix(4)) path=\(path)"
        )
        load()
    }

    func navigate(to target: String) {
        guard !busy, !loading else { return }
        let clean = target.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        path = clean
        load()
    }

    func up() {
        guard let parent = FileBrowserLogic.parentPath(path) else { return }
        navigate(to: parent)
    }

    func refresh() {
        load()
    }

    private func load() {
        guard !serial.isEmpty, !loading, !busy else { return }
        loading = true
        statusMessage = nil
        let adb = DeviceMonitor.adbPathNow()
        let serial = self.serial
        let dir = path
        Task.detached(priority: .utility) {
            var result: [FileBrowserLogic.Item] = []
            var errorText: String?
            if let adb {
                let res = Self.runCapture(
                    adb: adb,
                    args: ["-s", serial] + FileBrowserLogic.listArgs(dir: dir)
                )
                if res.code == 0 {
                    result = FileBrowserLogic.parseLs(res.out, dir: dir)
                } else {
                    errorText = Self.firstLine(res.err.isEmpty ? res.out : res.err)
                    await DebugLogger.shared.error(
                        "FileBrowser",
                        "[ERROR] E-MAC-ADB-0004 목록 조회 실패 code=\(res.code) dir=\(dir) \(errorText ?? "")"
                    )
                }
            } else {
                errorText = ErrorCode.adbBinaryMissing.koMessage
                await DebugLogger.shared.error("FileBrowser", "[ERROR] E-MAC-ADB-0004 adb 바이너리 없음")
            }
            await MainActor.run {
                self.loading = false
                self.items = result
                if let errorText {
                    self.statusMessage = errorText.isEmpty
                        ? L10n.string("files.error.list")
                        : errorText
                }
            }
        }
    }

    // MARK: 가져오기 (pull → Mac)

    func pull(selection: Set<String>) {
        guard !busy, !loading else { return }
        let chosen = items.filter { selection.contains($0.id) }
        guard !chosen.isEmpty else {
            statusMessage = L10n.string("files.pull.noSelection")
            return
        }
        busy = true
        statusMessage = nil
        let adb = DeviceMonitor.adbPathNow()
        let serial = self.serial
        let dest = destDir
        Task.detached(priority: .utility) {
            var okCount = 0
            var errorText: String?
            if let adb {
                let fm = FileManager.default
                try? fm.createDirectory(atPath: dest, withIntermediateDirectories: true)
                for item in chosen {
                    let target = FileBrowserLogic.uniqueDest(dir: dest, name: item.name) {
                        fm.fileExists(atPath: $0)
                    }
                    let res = Self.runCapture(
                        adb: adb,
                        args: ["-s", serial] + FileBrowserLogic.pullArgs(remote: item.path, local: target)
                    )
                    if res.code == 0, fm.fileExists(atPath: target) {
                        okCount += 1
                    } else {
                        errorText = Self.firstLine(res.err.isEmpty ? res.out : res.err)
                        await DebugLogger.shared.error(
                            "FileBrowser",
                            "[ERROR] E-MAC-ADB-0005 가져오기 실패 code=\(res.code) \(item.path) \(errorText ?? "")"
                        )
                        break
                    }
                }
            } else {
                errorText = ErrorCode.adbBinaryMissing.koMessage
                await DebugLogger.shared.error("FileBrowser", "[ERROR] E-MAC-ADB-0005 adb 바이너리 없음")
            }
            await MainActor.run {
                self.busy = false
                if let errorText, !errorText.isEmpty {
                    self.statusMessage = errorText
                } else if errorText != nil {
                    self.statusMessage = L10n.string("files.error.pull")
                } else {
                    self.statusMessage = L10n.format("files.pull.done", "\(okCount)", dest)
                }
            }
        }
    }

    // MARK: 전송 (push → 기기)

    func push(urls: [URL]) {
        guard !busy, !loading, !serial.isEmpty, !urls.isEmpty else { return }
        let targets = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !targets.isEmpty else { return }
        busy = true
        statusMessage = nil
        let adb = DeviceMonitor.adbPathNow()
        let serial = self.serial
        let dir = path
        Task.detached(priority: .utility) {
            var okCount = 0
            var errorText: String?
            if let adb {
                for url in targets {
                    let res = Self.runCapture(
                        adb: adb,
                        args: ["-s", serial] + FileBrowserLogic.pushArgs(local: url.path, remoteDir: dir)
                    )
                    if res.code == 0 {
                        okCount += 1
                    } else {
                        errorText = Self.firstLine(res.err.isEmpty ? res.out : res.err)
                        await DebugLogger.shared.error(
                            "FileBrowser",
                            "[ERROR] E-MAC-ADB-0006 전송 실패 code=\(res.code) \(url.lastPathComponent) \(errorText ?? "")"
                        )
                        break
                    }
                }
            } else {
                errorText = ErrorCode.adbBinaryMissing.koMessage
                await DebugLogger.shared.error("FileBrowser", "[ERROR] E-MAC-ADB-0006 adb 바이너리 없음")
            }
            await MainActor.run {
                self.busy = false
                if let errorText, !errorText.isEmpty {
                    self.statusMessage = errorText
                } else if errorText != nil {
                    self.statusMessage = L10n.string("files.error.push")
                } else {
                    self.statusMessage = L10n.format("files.push.done", "\(okCount)", dir)
                    self.reloadQuietly(adb: adb, serial: serial, dir: dir)
                }
            }
        }
    }

    /// 전송 직후 목록 갱신 (상태 유지)
    private func reloadQuietly(adb: String?, serial: String, dir: String) {
        guard let adb else { return }
        loading = true
        Task.detached(priority: .utility) {
            let res = Self.runCapture(
                adb: adb,
                args: ["-s", serial] + FileBrowserLogic.listArgs(dir: dir)
            )
            let parsed = res.code == 0
                ? FileBrowserLogic.parseLs(res.out, dir: dir)
                : []
            await MainActor.run {
                self.loading = false
                if dir == self.path { self.items = parsed }
            }
        }
    }

    // MARK: 열기 (더블클릭)

    func openItem(_ item: FileBrowserLogic.Item) {
        if item.isDir {
            navigate(to: item.path)
            return
        }
        guard FileBrowserLogic.previewAllows(size: item.size) else {
            statusMessage = L10n.format("files.open.tooLarge", item.name)
            return
        }
        guard !busy, !loading else { return }
        let previewDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileBrowserPreview", isDirectory: true)
        try? FileManager.default.removeItem(at: previewDir)
        try? FileManager.default.createDirectory(at: previewDir, withIntermediateDirectories: true)
        let target = previewDir.appendingPathComponent(item.name).path
        busy = true
        statusMessage = L10n.string("files.preview.pulling")
        let adb = DeviceMonitor.adbPathNow()
        let serial = self.serial
        Task.detached(priority: .utility) {
            var errorText: String?
            var opened = false
            if let adb {
                let res = Self.runCapture(
                    adb: adb,
                    args: ["-s", serial] + FileBrowserLogic.pullArgs(remote: item.path, local: target)
                )
                if res.code == 0, FileManager.default.fileExists(atPath: target) {
                    opened = true
                } else {
                    errorText = Self.firstLine(res.err.isEmpty ? res.out : res.err)
                    await DebugLogger.shared.error(
                        "FileBrowser",
                        "[ERROR] E-MAC-ADB-0005 미리보기 pull 실패 code=\(res.code) \(item.path) \(errorText ?? "")"
                    )
                }
            } else {
                errorText = ErrorCode.adbBinaryMissing.koMessage
            }
            await MainActor.run {
                self.busy = false
                if opened {
                    self.statusMessage = nil
                    NSWorkspace.shared.open(URL(fileURLWithPath: target))
                } else if let errorText, !errorText.isEmpty {
                    self.statusMessage = errorText
                } else {
                    self.statusMessage = L10n.string("files.error.pull")
                }
            }
        }
    }

    // MARK: 가져오기 폴더

    func chooseDestDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: destDir)
        panel.prompt = L10n.string("files.dest.change")
        if panel.runModal() == .OK, let url = panel.url {
            destDir = url.path
            UserDefaults.standard.set(destDir, forKey: Self.destKey)
        }
    }

    // MARK: adb 실행 (stdout+stderr 병합 — 대용량 push 진행률 pipe 폐쇄 방지)

    nonisolated private static func runCapture(
        adb: String,
        args: [String]
    ) -> (out: String, err: String, code: Int32) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: adb)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do {
            try proc.run()
        } catch {
            return ("", error.localizedDescription, -1)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        return (text, text, proc.terminationStatus)
    }

    nonisolated private static func firstLine(_ text: String) -> String {
        text.split(separator: "\n").first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }
}
