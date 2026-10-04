import Foundation
import AppKit

/// ADB 파일 탐색기 순수 로직 — ls 파싱 · 경로 · 정렬 · 필터 · adb 인자 (테스트 대상)
/// 범위: 읽기 + 전송 (pull/push) + 삭제 (사용자 확인 + 화이트리스트 경로만)
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

    // MARK: - 내비게이션 (breadcrumb · 트리)

    /// 경로 조각 — (표시명, 전체경로). "/sdcard/Download" → [("sdcard","/sdcard"),("Download","/sdcard/Download")]
    static func crumbs(_ path: String) -> [(label: String, path: String)] {
        var p = path
        while p.hasSuffix("/"), p.count > 1 { p.removeLast() }
        guard !p.isEmpty else { return [("기기", "/")] }
        if p == "/" { return [("기기", "/")] }
        let parts = p.split(separator: "/").map(String.init)
        var out: [(String, String)] = []
        var acc = ""
        for part in parts {
            acc += "/" + part
            out.append((part, acc))
        }
        return out
    }

    /// 트리 자식 — 디렉터리만, 이름순
    static func childDirs(_ items: [Item]) -> [Item] {
        items.filter(\.isDir).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
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

    /// 삭제 허용 루트 — 사용자 데이터 범위. 밖은 **거부** (되돌릴 수 없으므로)
    /// 즐겨찾기와 같은 범위 (/sdcard 전체 + /data/local/tmp)
    static func canDelete(path: String) -> Bool {
        var p = path
        while p.hasSuffix("/"), p.count > 1 { p.removeLast() }
        guard !p.isEmpty, p != "/" else { return false }
        let roots = ["/sdcard", "/data/local/tmp"]
        // 루트 자체는 금지 · 접두어 함정 차단 ("/sdcardFake" 등)
        return roots.contains { r in p != r && p.hasPrefix(r + "/") }
    }

    static func deleteArgs(path: String) -> [String] {
        ["shell", "rm -rf " + shellQuote(path)]
    }

    // MARK: - 진행률

    /// 0…1 분율 — total 미확인·음수면 nil (모르면 indeterminate 로 표시, 거짓 % 금지)
    static func progressFraction(done: Int64, total: Int64) -> Double? {
        guard total > 0, done >= 0 else { return nil }
        return min(1, Double(done) / Double(total))
    }

    /// `stat -c %s` / `du -sb` 출력 첫 토큰 — 바이트 수
    static func parseByteCount(_ text: String) -> Int64? {
        let first = text.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        guard let v = Int64(first), v >= 0 else { return nil }
        return v
    }
}

// MARK: - 컨트롤러 (adb IO)

/// 파일 탐색기 컨트롤러 — 목록/가져오기/전송/삭제 (MainActor)
/// 실패 시 **stderr 원문을 상태줄에 노출** ([표시②]) + `E-MAC-ADB-0004~0007` 로그
@MainActor
final class FileBrowserController: ObservableObject {
    static let shared = FileBrowserController()

    /// 전송 진행 — nil = 진행 중 아님. fraction nil = indeterminate (모르면 %를 꾸미지 않는다)
    struct TransferProgress: Equatable {
        enum Direction: String { case pull, push }
        var direction: Direction
        var fileIndex: Int
        var fileCount: Int
        var fileName: String
        var fraction: Double?
    }

    @Published private(set) var serial: String = ""
    @Published private(set) var path: String = "/sdcard"
    @Published private(set) var items: [FileBrowserLogic.Item] = []
    @Published private(set) var loading = false
    @Published private(set) var busy = false
    @Published var statusMessage: String?
    @Published private(set) var destDir: String
    @Published private(set) var progress: TransferProgress?
    /// 삭제 확인 대기 — nil 이 아니면 확인 다이얼로그 표시
    @Published private(set) var pendingDelete: [FileBrowserLogic.Item]?
    /// 진행률 폴러 무효화 토큰 — 완료·취소 시 증가, 묵은 폴러의 화면 갱신 차단
    private var progressToken = 0
    /// 폴러가 읽는 슬롯 — 워커가 현재 항목마다 갱신 (값 복사, Sendable)
    private var pollSlot: PollSlot?

    /// 폴링 슬롯 — 폴러가 읽는다 (Sendable, 값 복사)
    struct PollSlot: Sendable {
        /// pull: 로컬 증가분 경로. push: nil (원격 조회)
        var localPath: String?
        /// 예상 전체 바이트 — 0 이하면 indeterminate
        var expected: Int64
        /// push: 원격 조회 스펙. pull: nil
        var remote: RemoteSpec?
    }

    struct RemoteSpec: Sendable {
        var adb: String
        var serial: String
        var path: String
        var isDir: Bool
    }

    /// 진행 폴러 시작 — 워커와 형제 태스크 (중첩 detached 는 격리 에러)
    /// - Returns: 무효화 토큰 + 폴러 핸들 (종료 시 워커가 cancel)
    private func startProgressPoller() -> (Int, Task<Void, Never>) {
        progressToken += 1
        progress = nil
        pollSlot = nil
        let token = progressToken
        let poller = Task.detached(priority: .utility) {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { break }
                let alive: Bool = await MainActor.run { self.progressToken == token }
                guard alive else { break }
                let slot: PollSlot? = await MainActor.run { self.pollSlot }
                guard let slot, slot.expected > 0 else { continue }
                let cur: Int64?
                if let local = slot.localPath {
                    cur = (try? FileManager.default.attributesOfItem(atPath: local)[.size] as? NSNumber)?
                        .int64Value ?? 0
                } else if let r = slot.remote {
                    cur = Self.remoteByteSize(adb: r.adb, serial: r.serial, path: r.path, isDir: r.isDir)
                } else {
                    cur = nil
                }
                let frac = cur.flatMap { FileBrowserLogic.progressFraction(done: $0, total: slot.expected) }
                await MainActor.run {
                    if self.progressToken == token { self.progress?.fraction = frac }
                }
            }
        }
        return (token, poller)
    }

    /// 진행 종료 — 상태 정리 (폴러 취소 포함)
    private func finishProgress(poller: Task<Void, Never>?) {
        poller?.cancel()
        progressToken += 1
        progress = nil
        pollSlot = nil
    }

    // MARK: 전송 취소

    /// 실행 중인 adb 프로세스 + 취소 플래그 — 취소는 현재 항목에서 멈춘다
    private var currentProc: Process?
    private var cancelRequested = false

    /// 전송 취소 — 실행 중 프로세스를 죽인다 (부분 파일은 남을 수 있음)
    func cancelTransfer() {
        guard busy else { return }
        cancelRequested = true
        currentProc?.terminate()
    }

    /// 취소 가능한 실행 — 프로세스를 등록해 두었다가 끝나면 해제
    nonisolated private static func runTransfer(
        adb: String,
        args: [String],
        register: @Sendable (Process?) async -> Void
    ) async -> (out: String, err: String, code: Int32) {
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
        await register(proc)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        await register(nil)
        let text = String(decoding: data, as: UTF8.self)
        return (text, text, proc.terminationStatus)
    }

    static let destKey = "relay.files.destDir"

    private init() {
        let downloads = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true).path
        destDir = UserDefaults.standard.string(forKey: Self.destKey) ?? downloads
    }

    // MARK: 진입 · 이동

    /// 뒤로/앞으로 — Finder식 히스토리
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    private var backStack: [String] = []
    private var forwardStack: [String] = []

    /// 트리 — 루트 고정 (/sdcard + /data/local/tmp, 삭제 허용 범위와 동일).
    /// 자식은 펼칠 때 lazy 로드. 조용한 로드 (상태줄 오염 금지)
    static let treeRoots = ["/sdcard", "/data/local/tmp"]
    @Published private(set) var treeChildren: [String: [FileBrowserLogic.Item]] = [:]
    @Published private(set) var treeExpanded: Set<String> = []

    func open(serial: String) {
        if serial != self.serial {
            self.serial = serial
            path = "/sdcard"
            items = []
            statusMessage = nil
            backStack = []
            forwardStack = []
            updateNavFlags()
            treeChildren = [:]
            treeExpanded = []
        }
        DebugLogger.shared.info(
            "FileBrowser",
            "[INFO] [FEATURE] 파일 탐색기 serial=…\(serial.suffix(4)) path=\(path)"
        )
        load()
    }

    func navigate(to target: String, recordHistory: Bool = true) {
        guard !busy, !loading else { return }
        let clean = target.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, clean != path else { return }
        if recordHistory {
            backStack.append(path)
            forwardStack = []
        }
        path = clean
        updateNavFlags()
        load()
    }

    func goBack() {
        guard canGoBack, !busy, !loading, let p = backStack.popLast() else { return }
        forwardStack.append(path)
        path = p
        updateNavFlags()
        load()
    }

    func goForward() {
        guard canGoForward, !busy, !loading, let p = forwardStack.popLast() else { return }
        backStack.append(path)
        path = p
        updateNavFlags()
        load()
    }

    private func updateNavFlags() {
        canGoBack = !backStack.isEmpty
        canGoForward = !forwardStack.isEmpty
    }

    /// 트리 펼치기/접기 — 펼 때 자식 없으면 조용히 로드
    func toggleTree(_ dir: String) {
        if treeExpanded.contains(dir) {
            treeExpanded.remove(dir)
        } else {
            treeExpanded.insert(dir)
            if treeChildren[dir] == nil {
                loadTreeChildren(dir)
            }
        }
    }

    private func loadTreeChildren(_ dir: String) {
        guard !serial.isEmpty, let adb = DeviceMonitor.adbPathNow() else { return }
        let serial = self.serial
        Task.detached(priority: .utility) {
            let res = Self.runCapture(
                adb: adb,
                args: ["-s", serial] + FileBrowserLogic.listArgs(dir: dir)
            )
            guard res.code == 0 else { return }
            let dirs = FileBrowserLogic.childDirs(FileBrowserLogic.parseLs(res.out, dir: dir))
            await MainActor.run {
                // 다른 기기로 바뀌었으면 버린다
                guard self.serial == serial else { return }
                self.treeChildren[dir] = dirs
            }
        }
    }

    /// 기기 변경 시 트리 무효화 — 경로가 통째로 달라진다
    private func invalidateTree() {
        treeChildren = [:]
        treeExpanded = []
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
        cancelRequested = false
        currentProc = nil
        let adb = DeviceMonitor.adbPathNow()
        let serial = self.serial
        let dest = destDir
        let (token, poller) = startProgressPoller()
        Task.detached(priority: .utility) {
            var okCount = 0
            var errorText: String?
            if let adb {
                let fm = FileManager.default
                try? fm.createDirectory(atPath: dest, withIntermediateDirectories: true)
                let total = chosen.count
                for (i, item) in chosen.enumerated() {
                    let target = FileBrowserLogic.uniqueDest(dir: dest, name: item.name) {
                        fm.fileExists(atPath: $0)
                    }
                    await MainActor.run {
                        guard self.progressToken == token else { return }
                        self.progress = TransferProgress(
                            direction: .pull, fileIndex: i + 1, fileCount: total,
                            fileName: item.name, fraction: nil
                        )
                        // 디렉터리는 전체 크기를 모르니 슬롯 비움 (indeterminate)
                        self.pollSlot = (!item.isDir && item.size > 0)
                            ? PollSlot(localPath: target, expected: item.size, remote: nil)
                            : nil
                    }
                    let res = await Self.runTransfer(
                        adb: adb,
                        args: ["-s", serial] + FileBrowserLogic.pullArgs(remote: item.path, local: target),
                        register: { [weak self] proc in
                            await MainActor.run { self?.currentProc = proc }
                        }
                    )
                    if await MainActor.run(body: { self.cancelRequested }) { break }
                    let alive = await MainActor.run { self.progressToken == token }
                    guard alive else { break }
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
                self.finishProgress(poller: poller)
                self.busy = false
                self.currentProc = nil
                if self.cancelRequested {
                    self.cancelRequested = false
                    self.statusMessage = L10n.string("files.transfer.cancelled")
                } else if let errorText, !errorText.isEmpty {
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
        cancelRequested = false
        currentProc = nil
        let adb = DeviceMonitor.adbPathNow()
        let serial = self.serial
        let dir = path
        let (token, poller) = startProgressPoller()
        Task.detached(priority: .utility) {
            var okCount = 0
            var errorText: String?
            if let adb {
                let total = targets.count
                for (i, url) in targets.enumerated() {
                    let remotePath = FileBrowserLogic.join(dir: dir, name: url.lastPathComponent)
                    let expected = Self.localTreeSize(url)
                    let isDir = (try? FileManager.default.attributesOfItem(atPath: url.path)[.type]
                        as? FileAttributeType) == .typeDirectory
                    await MainActor.run {
                        guard self.progressToken == token else { return }
                        self.progress = TransferProgress(
                            direction: .push, fileIndex: i + 1, fileCount: total,
                            fileName: url.lastPathComponent, fraction: nil
                        )
                        // 원격 증가분 폴링 — stat/du 가 없으면 indeterminate 로 둔다
                        self.pollSlot = expected > 0
                            ? PollSlot(
                                localPath: nil, expected: expected,
                                remote: RemoteSpec(adb: adb, serial: serial, path: remotePath, isDir: isDir)
                            )
                            : nil
                    }
                    let res = await Self.runTransfer(
                        adb: adb,
                        args: ["-s", serial] + FileBrowserLogic.pushArgs(local: url.path, remoteDir: dir),
                        register: { [weak self] proc in
                            await MainActor.run { self?.currentProc = proc }
                        }
                    )
                    if await MainActor.run(body: { self.cancelRequested }) { break }
                    let alive = await MainActor.run { self.progressToken == token }
                    guard alive else { break }
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
                self.finishProgress(poller: poller)
                self.busy = false
                self.currentProc = nil
                if self.cancelRequested {
                    self.cancelRequested = false
                    self.statusMessage = L10n.string("files.transfer.cancelled")
                } else if let errorText, !errorText.isEmpty {
                    self.statusMessage = errorText
                } else if errorText != nil {
                    self.statusMessage = L10n.string("files.error.push")
                } else {
                    self.statusMessage = L10n.format("files.push.done", "\(okCount)")
                    self.invalidateTree()
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
        cancelRequested = false
        currentProc = nil
        let adb = DeviceMonitor.adbPathNow()
        let serial = self.serial
        let (token, poller) = startProgressPoller()
        Task.detached(priority: .utility) {
            var errorText: String?
            var opened = false
            if let adb {
                await MainActor.run {
                    self.progress = TransferProgress(
                        direction: .pull, fileIndex: 1, fileCount: 1,
                        fileName: item.name, fraction: nil
                    )
                    self.pollSlot = item.size > 0
                        ? PollSlot(localPath: target, expected: item.size, remote: nil)
                        : nil
                }
                let res = Self.runCapture(
                    adb: adb,
                    args: ["-s", serial] + FileBrowserLogic.pullArgs(remote: item.path, local: target)
                )
                let alive = await MainActor.run { self.progressToken == token }
                if alive {
                    if res.code == 0, FileManager.default.fileExists(atPath: target) {
                        opened = true
                    } else {
                        errorText = Self.firstLine(res.err.isEmpty ? res.out : res.err)
                        await DebugLogger.shared.error(
                            "FileBrowser",
                            "[ERROR] E-MAC-ADB-0005 미리보기 pull 실패 code=\(res.code) \(item.path) \(errorText ?? "")"
                        )
                    }
                }
            } else {
                errorText = ErrorCode.adbBinaryMissing.koMessage
            }
            await MainActor.run {
                self.finishProgress(poller: poller)
                self.busy = false
                self.currentProc = nil
                if self.cancelRequested {
                    self.cancelRequested = false
                    self.statusMessage = L10n.string("files.transfer.cancelled")
                } else if opened {
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

    // MARK: 삭제 (rm — 확인 + 화이트리스트 경로만)

    /// 삭제 확인 요청 — 조건이 맞으면 확인 다이얼로그용으로 보관
    func requestDelete(selection: Set<String>) {
        guard !busy, !loading else { return }
        let chosen = items.filter { selection.contains($0.id) }
        guard !chosen.isEmpty else {
            statusMessage = L10n.string("files.delete.noSelection")
            return
        }
        // 허용 밖이 1개라도 있으면 전체 중단 — 부분 삭제는 혼란만 남긴다
        if let bad = chosen.first(where: { !FileBrowserLogic.canDelete(path: $0.path) }) {
            statusMessage = L10n.format("files.delete.forbidden", bad.path)
            return
        }
        pendingDelete = chosen
    }

    func cancelDelete() {
        pendingDelete = nil
    }

    func confirmDelete() {
        guard !busy, !loading, let targets = pendingDelete else { return }
        pendingDelete = nil
        busy = true
        statusMessage = nil
        cancelRequested = false
        currentProc = nil
        let adb = DeviceMonitor.adbPathNow()
        let serial = self.serial
        let dir = path
        Task.detached(priority: .utility) {
            var okCount = 0
            var errorText: String?
            if let adb {
                for item in targets {
                    let res = Self.runCapture(
                        adb: adb,
                        args: ["-s", serial] + FileBrowserLogic.deleteArgs(path: item.path)
                    )
                    if res.code == 0 {
                        okCount += 1
                    } else {
                        errorText = Self.firstLine(res.err.isEmpty ? res.out : res.err)
                        await DebugLogger.shared.error(
                            "FileBrowser",
                            "[ERROR] E-MAC-ADB-0007 삭제 실패 code=\(res.code) \(item.path) \(errorText ?? "")"
                        )
                        break
                    }
                }
            } else {
                errorText = ErrorCode.adbBinaryMissing.koMessage
                await DebugLogger.shared.error("FileBrowser", "[ERROR] E-MAC-ADB-0007 adb 바이너리 없음")
            }
            await MainActor.run {
                self.busy = false
                if let errorText, !errorText.isEmpty {
                    self.statusMessage = errorText
                } else if errorText != nil {
                    self.statusMessage = L10n.string("files.error.delete")
                } else {
                    self.statusMessage = L10n.format("files.delete.done", okCount)
                    self.invalidateTree()
                    self.reloadQuietly(adb: adb, serial: serial, dir: dir)
                }
            }
        }
    }

    // MARK: 원격 크기 조회 (push 진행률용)

    /// 기기 측 바이트 수 — 파일은 `stat`, 디렉터리는 `du -sb`. 없으면 nil (indeterminate)
    nonisolated static func remoteByteSize(adb: String, serial: String, path: String, isDir: Bool) -> Int64? {
        let cmd = (isDir ? "du -sb " : "stat -c %s ") + FileBrowserLogic.shellQuote(path)
        let res = runCapture(adb: adb, args: ["-s", serial, "shell", cmd])
        guard res.code == 0 else { return nil }
        return FileBrowserLogic.parseByteCount(res.out)
    }

    /// 로컬 트리 전체 바이트 수 (push 예상치) — 없으면 0
    nonisolated static func localTreeSize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        }
        var total: Int64 = 0
        if let e = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) {
            for case let f as URL in e {
                let vs = try? f.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                if vs?.isDirectory != true {
                    total += Int64(vs?.fileSize ?? 0)
                }
            }
        }
        return total
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
