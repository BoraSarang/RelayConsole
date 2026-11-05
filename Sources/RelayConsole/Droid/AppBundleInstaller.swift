import Foundation

/// 번들 설치 준비 결과 — 로컬 임시 폴더에 풀어 둔 파일들
struct PreparedBundle: Sendable {
    var apkFiles: [URL]
    var obbFiles: [(url: URL, relativePath: String)]
    var packageHint: String?
    var totalBytes: UInt64

    var apkBytes: UInt64 { totalBytes }
}

enum BundleInstallError: Error, Equatable {
    case unsupported
    case empty
    case metadata
    case local(String)

    /// 사용자에게 보여줄 한국어 문구 (원인은 detail 로 로그에 남긴다)
    var message: String {
        switch self {
        case .unsupported: return L10n.string("apphub.install.bundleUnsupported")
        case .empty: return L10n.string("apphub.install.bundleEmpty")
        case .metadata: return L10n.string("apphub.install.bundleMetadata")
        case .local(let detail): return detail
        }
    }

    var detail: String {
        switch self {
        case .unsupported: return "unsupported"
        case .empty: return "no apk entries"
        case .metadata: return "manifest/metadata unreadable"
        case .local(let detail): return detail
        }
    }
}

/// 번들(.apks/.xapk/.apkm) → 설치용 파일 묶음.
///
/// 모든 단계는 **로컬 파일 작업**이다(adb 는 호출측). 그래야 순수하게 테스트할 수 있고,
/// 실패 지점(형식·빈 번들)을 사용자 문구로 구분할 수 있다.
enum BundleInstaller {
    /// 번들을 열어 기기에 맞는 APK·OBB 를 임시 폴더로 푼다
    static func prepare(
        url: URL,
        kind: AppBundleKind,
        profile: DeviceProfile,
        into directory: URL
    ) throws -> PreparedBundle {
        let zip: ZipArchive
        do {
            zip = try ZipArchive(url: url)
        } catch {
            throw BundleInstallError.unsupported
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var selected: [String] = []
        var obb: [ObbFile] = []
        var packageHint: String?

        switch kind {
        case .xapk:
            if let entry = resolve("manifest.json", in: zip),
               let data = try? zip.data(for: entry),
               let manifest = BundleMetadata.parseXapk(data) {
                packageHint = manifest.packageName
                selected = manifest.apks.compactMap { resolve($0, in: zip)?.path }
                obb = manifest.obb
            }
            if selected.isEmpty {
                selected = BundlePlanner.apkEntries(from: zip.entries.map(\.path), profile: profile)
            }
            if obb.isEmpty {
                obb = zip.entries
                    .filter { $0.path.lowercased().hasSuffix(".obb") }
                    .map { ObbFile(entryPath: $0.path, relativePath: ($0.path as NSString).lastPathComponent) }
            }

        case .apks, .apkm:
            var pool = zip.entries.map(\.path)
            // info.json(apkm) · manifest.json(xapk 변형) 이 있으면 그 목록을 우선한다
            for name in ["info.json", "manifest.json"] {
                guard let entry = resolve(name, in: zip),
                      let data = try? zip.data(for: entry) else { continue }
                if name == "manifest.json",
                   let manifest = BundleMetadata.parseXapk(data) {
                    packageHint = packageHint ?? manifest.packageName
                    obb = obb.isEmpty ? manifest.obb : obb
                }
                let declared = BundleMetadata.fileNames(inJSON: data, suffix: ".apk")
                let resolved = declared.compactMap { resolve($0, in: zip)?.path }
                if !resolved.isEmpty {
                    pool = resolved
                    break
                }
            }
            selected = BundlePlanner.apkEntries(from: pool, profile: profile)
            if obb.isEmpty {
                obb = zip.entries
                    .filter { $0.path.lowercased().hasSuffix(".obb") }
                    .map { ObbFile(entryPath: $0.path, relativePath: ($0.path as NSString).lastPathComponent) }
            }

        case .apk:
            throw BundleInstallError.unsupported
        }

        // 중복 제거 + base 우선
        var seen = Set<String>()
        selected = selected.filter { seen.insert($0).inserted }
        guard !selected.isEmpty else { throw BundleInstallError.empty }

        var apkFiles: [URL] = []
        var total: UInt64 = 0
        for (index, path) in selected.enumerated() {
            guard let entry = zip.entry(named: path) else { continue }
            let name = String(format: "%02d-%@", index, safeName((path as NSString).lastPathComponent))
            let dest = directory.appendingPathComponent(name)
            try zip.write(entry, to: dest)
            total += entry.uncompressedSize
            apkFiles.append(dest)
        }
        guard !apkFiles.isEmpty else { throw BundleInstallError.empty }

        var obbFiles: [(URL, String)] = []
        for (index, item) in obb.enumerated() {
            guard let entry = zip.entry(named: item.entryPath) else { continue }
            let relative = safeRelativePath(item.relativePath)
            let name = String(format: "obb-%02d-%@", index, (relative as NSString).lastPathComponent)
            let dest = directory.appendingPathComponent(name)
            try zip.write(entry, to: dest)
            total += entry.uncompressedSize
            obbFiles.append((dest, relative))
        }

        // 패키지명이 없으면 base APK 매니페스트에서 읽는다 (OBB 목적지·로그에 필요)
        if packageHint == nil, let base = apkFiles.first,
           let meta = try? APKInspector.inspect(apk: base) {
            packageHint = meta.packageName
        }

        return PreparedBundle(
            apkFiles: apkFiles,
            obbFiles: obbFiles,
            packageHint: packageHint,
            totalBytes: total
        )
    }

    /// JSON 이 가리키는 이름을 ZIP 엔트리로 해석 — 경로 우선, 없으면 고유한 파일명
    static func resolve(_ name: String, in zip: ZipArchive) -> ZipEntry? {
        if let exact = zip.entry(named: name) { return exact }
        let base = (name as NSString).lastPathComponent
        let matches = zip.entries.filter {
            ($0.path as NSString).lastPathComponent.caseInsensitiveCompare(base) == .orderedSame
        }
        return matches.count == 1 ? matches[0] : nil
    }

    /// 파일명 안전화 — 경로 구분자·상위 참조 제거
    static func safeName(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(
            of: "[^A-Za-z0-9._-]",
            with: "_",
            options: .regularExpression
        )
        return cleaned.isEmpty ? "file" : cleaned
    }

    /// OBB 상대 경로 — `..`·절대경로를 제거하고 `Android/obb/...` 형태를 유지
    static func safeRelativePath(_ path: String) -> String {
        let parts = path
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .filter { $0 != "." && $0 != ".." }
            .map(String.init)
        guard !parts.isEmpty else { return "obb" }
        return parts.joined(separator: "/")
    }

    /// OBB 원격 목적지 — 매니페스트가 준 경로를 최대한 존중한다
    static func obbDestination(relativePath: String, package: String) -> String {
        let relative = safeRelativePath(relativePath)
        if relative.hasPrefix("Android/") {
            return "/sdcard/" + relative
        }
        let base = (relative as NSString).lastPathComponent
        return "/sdcard/Android/obb/\(package)/\(base)"
    }
}

/// 완료 여부만 공유하는 최소 플래그 — push 진행률 폴링용
final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
