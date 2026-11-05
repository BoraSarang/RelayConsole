import Foundation
import AppKit
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// 앱 아이콘 캐시 — 기기에서 **한 번만** 꺼내 256pt@2x PNG 로 저장한다.
///
/// ## 왜 이렇게 하는가
/// `dumpsys` 에는 아이콘 바이트가 없다. APK 를 받아 `AndroidManifest.xml`(AXML) →
/// `resources.arsc` 로 아이콘 경로를 찾아 그 엔트리만 꺼내는 것이 유일한 표준 경로다.
/// 그래서 아이콘은 **기본 ON 이지만 토글로 끌 수 있고**, 보이는 행만·동시 2개로 제한한다.
/// 실패하면 조용히 타일로 폴백한다(빈칸 금지) — 사유는 디버그 로그에만 남긴다.
///
/// 캐시: `~/Library/Application Support/RelayConsole/icons/<pkg>-<versionCode>-512.png`
/// 보존: 30일 · 상한 50MB (넘으면 오래된 것부터 삭제)
@MainActor
final class AppIconStore: ObservableObject {
    static let shared = AppIconStore()

    nonisolated static let cacheKey = "relay.apphub.icons.enabled"
    nonisolated static let maxPixel = 512
    nonisolated static let maxAge: TimeInterval = 30 * 24 * 3600
    nonisolated static let maxBytes: Int64 = 50 * 1024 * 1024
    nonisolated static let maxAPKBytes: Int64 = 400 * 1024 * 1024

    @Published private(set) var images: [String: NSImage] = [:]
    /// 패키지 → 사람이 읽는 앱 이름 (APK 의 `android:label`)
    @Published private(set) var labels: [String: String] = [:]
    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.cacheKey)
            if !enabled { images = [:] }
        }
    }

    /// 동시에 두 개까지만 — 네트워크 ADB 에서 아이콘 pull 이 대역폭을 먹지 않게
    private let concurrency = 2
    private var active = 0
    private var loading = Set<String>()
    private var pending: [(serial: String, package: String, versionCode: Int64)] = []
    /// 이번 실행에서 이미 시도한 `package-versionCode` — 실패한 앱을 행이 보일 때마다
    /// 다시 pull 하지 않는다(네트워크 ADB 에서 APK 하나가 수백 MB 다).
    private var attempted = Set<String>()
    /// 이름이 어느 versionCode 의 APK 에서 나왔는지 — 버전이 바뀌면 다시 읽는다
    private var labelVersions: [String: Int64] = [:]

    private init() {
        let stored = UserDefaults.standard.object(forKey: Self.cacheKey)
        enabled = stored as? Bool ?? true          // 사용자 결정: 기본 ON
        Self.evict()
        Self.loadLabels(into: &labels, versions: &labelVersions)
    }

    nonisolated static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("RelayConsole", isDirectory: true)
            .appendingPathComponent("icons", isDirectory: true)
    }

    private nonisolated static var labelsFile: URL {
        cacheDirectory.appendingPathComponent("labels.json")
    }

    private struct LabelRecord: Codable {
        var versionCode: Int64
        var label: String
    }

    private nonisolated static func loadLabels(
        into labels: inout [String: String],
        versions: inout [String: Int64]
    ) {
        guard let data = try? Data(contentsOf: labelsFile),
              let decoded = try? JSONDecoder().decode([String: LabelRecord].self, from: data) else { return }
        for (package, record) in decoded where !record.label.isEmpty {
            labels[package] = record.label
            versions[package] = record.versionCode
        }
    }

    private func persistLabels() {
        var out: [String: LabelRecord] = [:]
        for (package, label) in labels {
            out[package] = LabelRecord(versionCode: labelVersions[package] ?? 0, label: label)
        }
        guard let data = try? JSONEncoder().encode(out) else { return }
        try? FileManager.default.createDirectory(at: Self.cacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: Self.labelsFile, options: .atomic)
    }

    private nonisolated static func cacheFile(package: String, versionCode: Int64) -> URL {
        let safe = package.replacingOccurrences(
            of: "[^a-zA-Z0-9._-]",
            with: "_",
            options: .regularExpression
        )
        return cacheDirectory.appendingPathComponent("\(safe)-\(versionCode)-\(maxPixel).png")
    }

    /// 행이 보일 때 호출 — 캐시가 있으면 즉시, 없으면 큐에 넣는다.
    ///
    /// 아이콘과 이름은 **같은 APK pull** 에서 나오므로 한 번에 받는다.
    /// 아이콘은 캐시에 있는데 이름이 없으면(구버전 캐시) 이름을 위해 한 번 더 읽는다.
    func request(serial: String, package: String, versionCode: Int64) {
        guard enabled, !package.isEmpty else { return }
        let key = "\(package)-\(versionCode)"
        if loading.contains(package) || attempted.contains(key) { return }
        if let cached = Self.cachedData(package: package, versionCode: versionCode) {
            images[package] = NSImage(data: cached)
        }
        if images[package] != nil, labelVersions[package] == versionCode, labels[package] != nil {
            return
        }
        attempted.insert(key)
        loading.insert(package)
        pending.append((serial, package, versionCode))
        pump()
    }

    private func pump() {
        while active < concurrency, !pending.isEmpty {
            let job = pending.removeFirst()
            active += 1
            Task.detached(priority: .utility) {
                let result = await Self.fetch(serial: job.serial, package: job.package, versionCode: job.versionCode)
                await MainActor.run {
                    self.active -= 1
                    self.loading.remove(job.package)
                    if let data = result.image, let image = NSImage(data: data) {
                        self.images[job.package] = image
                    }
                    if let label = result.label, !label.isEmpty {
                        self.labels[job.package] = label
                        self.labelVersions[job.package] = result.versionCode ?? job.versionCode
                        self.persistLabels()
                    }
                    self.pump()
                }
            }
        }
    }

    // MARK: - 캐시

    private nonisolated static func cachedData(package: String, versionCode: Int64) -> Data? {
        let url = cacheFile(package: package, versionCode: versionCode)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < maxAge else { return nil }
        return try? Data(contentsOf: url)
    }

    private nonisolated static func store(_ data: Data, package: String, versionCode: Int64) {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let url = cacheFile(package: package, versionCode: versionCode)
        try? data.write(to: url, options: .atomic)
        evict()
    }

    /// 30일 초과 삭제 → 50MB 초과분은 오래된 것부터 삭제
    nonisolated static func evict() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return }

        var rows: [(url: URL, date: Date, size: Int64)] = []
        for file in files where file.pathExtension == "png" {
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let date = values?.contentModificationDate ?? .distantPast
            let size = Int64(values?.fileSize ?? 0)
            if Date().timeIntervalSince(date) > maxAge {
                try? fm.removeItem(at: file)
            } else {
                rows.append((file, date, size))
            }
        }
        var total = rows.reduce(Int64(0)) { $0 + $1.size }
        guard total > maxBytes else { return }
        for row in rows.sorted(by: { $0.date < $1.date }) {
            try? fm.removeItem(at: row.url)
            total -= row.size
            if total <= maxBytes { break }
        }
    }

    // MARK: - 기기에서 꺼내기

    private struct FetchResult: Sendable {
        var image: Data?
        var label: String?
        var versionCode: Int64?
    }

    private nonisolated static func fetch(serial: String, package: String, versionCode: Int64) async -> FetchResult {
        guard !serial.isEmpty, let adb = DeviceMonitor.adbPathNow() else { return FetchResult() }
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("relay-icon-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workDir) }
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        guard let remote = baseAPKPath(adb: adb, serial: serial, package: package) else {
            await DebugLogger.shared.warn("AppHub", "[WARN] 아이콘 — base.apk 경로 없음 \(package)")
            return FetchResult()
        }
        if let size = remoteSize(adb: adb, serial: serial, path: remote), size > maxAPKBytes {
            await DebugLogger.shared.warn("AppHub", "[WARN] 아이콘 — APK 가 너무 큼 \(size)B \(package)")
            return FetchResult()
        }

        let local = workDir.appendingPathComponent("base.apk")
        let pulled = try? ProcessRunner.capture(
            adb,
            ["-s", serial, "pull", remote, local.path],
            timeout: 180
        )
        guard let pulled, pulled.exitCode == 0, !pulled.timedOut else {
            await DebugLogger.shared.warn("AppHub", "[WARN] 아이콘 pull 실패 \(package)")
            return FetchResult()
        }

        guard let meta = try? APKInspector.inspect(apk: local) else {
            await DebugLogger.shared.warn("AppHub", "[WARN] APK 메타데이터 없음 \(package)")
            return FetchResult()
        }
        // 아이콘이 없어도 **이름은 살린다** — 결과표·목록 가독성은 이름이 더 중요하다
        var result = FetchResult(
            image: nil,
            label: meta.label,
            versionCode: meta.versionCode ?? versionCode
        )

        // 비트맵이면 그대로, 적응형/벡터 아이콘이면 직접 그려서 512px PNG 로 만든다
        guard let rendered = APKIconRenderer.render(
            apk: local,
            resIds: meta.iconResIds,
            pixels: maxPixel
        ), let png = pngData(rendered) else {
            await DebugLogger.shared.warn("AppHub", "[WARN] 아이콘 렌더 실패 \(package)")
            return result
        }
        store(png, package: package, versionCode: result.versionCode ?? versionCode)
        result.image = png
        return result
    }

    /// `pm path` → 기본 APK (split 이면 base.apk 를 고른다)
    private nonisolated static func baseAPKPath(adb: String, serial: String, package: String) -> String? {
        guard let out = try? ProcessRunner.capture(
            adb,
            ["-s", serial, "shell", "pm", "path", package],
            timeout: ProcessRunner.pollTimeout
        ), out.exitCode == 0, !out.timedOut else { return nil }
        let paths = out.stdout
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("package:") }
            .map { String($0.dropFirst("package:".count)) }
        guard !paths.isEmpty else { return nil }
        return paths.first(where: { $0.lowercased().hasSuffix("/base.apk") })
            ?? paths.first(where: { $0.lowercased().hasSuffix(".apk") })
            ?? paths.first
    }

    private nonisolated static func remoteSize(adb: String, serial: String, path: String) -> Int64? {
        guard let out = try? ProcessRunner.capture(
            adb,
            ["-s", serial, "shell", "wc", "-c", "<", path],
            timeout: ProcessRunner.pollTimeout
        ), out.exitCode == 0, !out.timedOut else { return nil }
        let digits = out.stdout.filter(\.isNumber)
        return Int64(digits)
    }

    /// CGImage → PNG (ImageIO — AppKit 없이 스레드 안전)
    private nonisolated static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
