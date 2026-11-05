import Foundation
import Compression

// MARK: - ZIP

/// ZIP 중앙 디렉터리 엔트리 — 우리가 쓰는 필드만 담는다.
struct ZipEntry: Equatable, Sendable {
    let path: String
    /// 0 = stored, 8 = deflate (그 외는 지원하지 않는다)
    let method: UInt16
    let compressedSize: UInt64
    let uncompressedSize: UInt64
    let localHeaderOffset: UInt64
}

enum ZipError: Error, Equatable {
    case notZip
    case unsupported
    case limitExceeded
    case corrupt
    case unsafePath
}

/// 로컬 ZIP 리더 — `.apks` · `.xapk` · `.apkm` · `.apk` 를 같은 코드로 읽는다.
///
/// ## 왜 직접 읽는가
/// 외부 프로세스는 **adb · scrcpy 둘로 못 박여 있다**(AGENTS.local). `unzip` 을 부르지 않고,
/// 번들 안에서 필요한 엔트리만 골라 스트리밍으로 풀어 쓴다. 300MB APK 를 통째로
/// 메모리에 올리지 않는 것이 이 타입의 존재 이유다.
///
/// ## 안전 상한
/// - 엔트리 150,000개 · 엔트리 512MB · 합계 8GB — 초과하면 읽지 않고 실패한다
/// - 절대경로·`..` 경로는 거부한다 (압축 폭탄·경로 순회 방지)
///
/// 엔트리 상한은 **번들**(수십 개)이 아니라 **APK**(수천~수만 개)를 기준으로 잡는다.
/// 256 으로 두었더니 일반 앱 APK 가 `limitExceeded` 로 열리지 않아 아이콘·앱 이름이
/// 전부 폴백했다(2026-10-24). 중앙 디렉터리 크기 상한(16MB)이 실질적인 메모리 방어선이다.
struct ZipArchive {
    /// 게임 APK 는 리소스가 수만 개다. 중앙 디렉터리 16MB 상한이 실질 방어선이므로
    /// 이 값은 "비정상적으로 큰 목록"만 막는 안전장치다.
    static let maxEntries = 150_000
    static let maxEntryBytes: UInt64 = 512 * 1024 * 1024
    static let maxTotalBytes: UInt64 = 8 * 1024 * 1024 * 1024

    let url: URL
    let entries: [ZipEntry]
    private let fileSize: UInt64

    init(url: URL) throws {
        self.url = url
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = (attrs[.size] as? NSNumber)?.uint64Value, size >= 22 else {
            throw ZipError.notZip
        }
        fileSize = size

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        // EOCD 는 파일 끝 22바이트 + 주석(최대 65535) — 뒤에서부터 시그니처를 찾는다
        let tailLen = min(size, 22 + 65535)
        try handle.seek(toOffset: size - tailLen)
        guard let tail = try handle.read(upToCount: Int(tailLen)), tail.count >= 22 else {
            throw ZipError.notZip
        }
        guard let eocd = Self.lastIndex(of: 0x06054b50, in: tail) else { throw ZipError.notZip }
        let e = tail[eocd...]
        guard e.count >= 22 else { throw ZipError.notZip }
        let total = Int(Self.u16(e, 10))
        let cdSize = UInt64(Self.u32(e, 12))
        let cdOffset = UInt64(Self.u32(e, 16))
        // ZIP64 은 번들 크기상 필요 없다 — 조용히 잘못 읽느니 명시적으로 거부한다
        guard total != 0xFFFF, cdSize != 0xFFFF_FFFF, cdOffset != 0xFFFF_FFFF else {
            throw ZipError.unsupported
        }
        guard total <= Self.maxEntries else { throw ZipError.limitExceeded }
        guard cdSize <= 16 * 1024 * 1024, cdOffset + cdSize <= size else {
            throw ZipError.corrupt
        }

        try handle.seek(toOffset: cdOffset)
        guard let cd = try handle.read(upToCount: Int(cdSize)), cd.count == Int(cdSize) else {
            throw ZipError.corrupt
        }

        var parsed: [ZipEntry] = []
        parsed.reserveCapacity(total)
        var offset = 0
        var totalBytes: UInt64 = 0
        for _ in 0..<total {
            guard offset + 46 <= cd.count, Self.u32(cd, offset) == 0x02014b50 else {
                throw ZipError.corrupt
            }
            let flags = Self.u16(cd, offset + 8)
            let method = Self.u16(cd, offset + 10)
            let compSize = Self.u32(cd, offset + 20)
            let uncompSize = Self.u32(cd, offset + 24)
            let nameLen = Int(Self.u16(cd, offset + 28))
            let extraLen = Int(Self.u16(cd, offset + 30))
            let commentLen = Int(Self.u16(cd, offset + 32))
            let localOffset = Self.u32(cd, offset + 42)
            let nameStart = offset + 46
            guard nameStart + nameLen <= cd.count else { throw ZipError.corrupt }
            let nameData = cd.subdata(in: nameStart..<(nameStart + nameLen))
            let name = String(decoding: nameData, as: UTF8.self)
            offset = nameStart + nameLen + extraLen + commentLen

            guard flags & 0x0001 == 0 else { throw ZipError.unsupported }   // 암호화
            guard method == 0 || method == 8 else { throw ZipError.unsupported }
            guard !name.isEmpty else { throw ZipError.corrupt }
            guard Self.isSafeEntryPath(name) else { throw ZipError.unsafePath }
            guard UInt64(uncompSize) <= Self.maxEntryBytes else { throw ZipError.limitExceeded }
            totalBytes += UInt64(uncompSize)
            guard totalBytes <= Self.maxTotalBytes else { throw ZipError.limitExceeded }
            guard localOffset < size else { throw ZipError.corrupt }

            if name.hasSuffix("/") { continue }   // 디렉터리 항목은 버린다
            parsed.append(ZipEntry(
                path: name,
                method: method,
                compressedSize: UInt64(compSize),
                uncompressedSize: UInt64(uncompSize),
                localHeaderOffset: UInt64(localOffset)
            ))
        }
        entries = parsed
    }

    /// 엔트리 이름 검색 — ZIP 은 대소문자를 구분하지만 번들 제작자는 일관적이지 않다
    func entry(named name: String) -> ZipEntry? {
        if let exact = entries.first(where: { $0.path == name }) { return exact }
        return entries.first { $0.path.lowercased() == name.lowercased() }
    }

    /// 작은 엔트리(JSON·manifest·리소스)를 메모리로 읽는다 — 64MB 상한
    func data(for entry: ZipEntry) throws -> Data {
        guard entry.uncompressedSize <= 64 * 1024 * 1024 else { throw ZipError.limitExceeded }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("zip-entry-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try write(entry, to: tmp)
        return try Data(contentsOf: tmp, options: .mappedIfSafe)
    }

    /// 엔트리를 파일로 스트리밍 추출 — 메모리에 통째로 올리지 않는다
    func write(_ entry: ZipEntry, to destination: URL) throws {
        guard entry.compressedSize <= fileSize else { throw ZipError.corrupt }
        let source = try FileHandle(forReadingFrom: url)
        defer { try? source.close() }

        try source.seek(toOffset: entry.localHeaderOffset)
        guard let header = try source.read(upToCount: 30), header.count == 30,
              Self.u32(header, 0) == 0x04034b50 else { throw ZipError.corrupt }
        let nameLen = Int(Self.u16(header, 26))
        let extraLen = Int(Self.u16(header, 28))
        let dataStart = entry.localHeaderOffset + 30 + UInt64(nameLen) + UInt64(extraLen)
        guard dataStart + entry.compressedSize <= fileSize else { throw ZipError.corrupt }
        try source.seek(toOffset: dataStart)

        FileManager.default.createFile(atPath: destination.path, contents: nil)
        guard let dest = FileHandle(forWritingAtPath: destination.path) else {
            throw ZipError.corrupt
        }
        defer { try? dest.close() }

        switch entry.method {
        case 0:
            var remaining = entry.compressedSize
            while remaining > 0 {
                let want = Int(min(remaining, 1 << 20))
                guard let chunk = try source.read(upToCount: want), !chunk.isEmpty else {
                    throw ZipError.corrupt
                }
                try dest.write(contentsOf: chunk)
                remaining -= UInt64(chunk.count)
            }
        default:
            try Self.inflate(source: source, compressedSize: entry.compressedSize, dest: dest)
        }

        let written = ((try? FileManager.default.attributesOfItem(atPath: destination.path))?[.size] as? NSNumber)?.uint64Value ?? 0
        if entry.uncompressedSize > 0, written != entry.uncompressedSize {
            throw ZipError.corrupt
        }
    }

    // MARK: - deflate

    private static func inflate(
        source: FileHandle,
        compressedSize: UInt64,
        dest: FileHandle
    ) throws {
        let bufferSize = 1 << 16
        let srcBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        let dstBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer {
            srcBuffer.deallocate()
            dstBuffer.deallocate()
        }
        var stream = compression_stream(
            dst_ptr: dstBuffer,
            dst_size: bufferSize,
            src_ptr: srcBuffer,
            src_size: 0,
            state: nil
        )
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
                == COMPRESSION_STATUS_OK else { throw ZipError.corrupt }
        defer { compression_stream_destroy(&stream) }

        var remaining = compressedSize
        var status = COMPRESSION_STATUS_OK
        while remaining > 0 {
            let want = Int(min(remaining, UInt64(bufferSize)))
            guard let chunk = try source.read(upToCount: want), !chunk.isEmpty else {
                throw ZipError.corrupt
            }
            remaining -= UInt64(chunk.count)
            chunk.copyBytes(to: srcBuffer, count: chunk.count)
            stream.src_ptr = UnsafePointer(srcBuffer)
            stream.src_size = chunk.count

            repeat {
                stream.dst_ptr = dstBuffer
                stream.dst_size = bufferSize
                status = compression_stream_process(&stream, 0)
                if status == COMPRESSION_STATUS_ERROR { throw ZipError.corrupt }
                let produced = bufferSize - stream.dst_size
                if produced > 0 {
                    try dest.write(contentsOf: Data(bytes: dstBuffer, count: produced))
                }
            } while stream.src_size > 0 && status == COMPRESSION_STATUS_OK
        }

        // 마지막 블록 플러시 — FINALIZE 는 빈 입력으로 반복 호출해도 안전하다
        while status != COMPRESSION_STATUS_END {
            stream.dst_ptr = dstBuffer
            stream.dst_size = bufferSize
            status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
            if status == COMPRESSION_STATUS_ERROR { throw ZipError.corrupt }
            let produced = bufferSize - stream.dst_size
            if produced > 0 {
                try dest.write(contentsOf: Data(bytes: dstBuffer, count: produced))
            }
            if status == COMPRESSION_STATUS_OK && produced == 0 { break }
        }
    }

    // MARK: - 바이트 도우미

    static func u16(_ data: Data, _ offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(data[data.startIndex + offset]) | (UInt16(data[data.startIndex + offset + 1]) << 8)
    }

    static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        let b0 = UInt32(data[data.startIndex + offset])
        let b1 = UInt32(data[data.startIndex + offset + 1]) << 8
        let b2 = UInt32(data[data.startIndex + offset + 2]) << 16
        let b3 = UInt32(data[data.startIndex + offset + 3]) << 24
        return b0 | b1 | b2 | b3
    }

    static func lastIndex(of signature: UInt32, in data: Data) -> Int? {
        guard data.count >= 4 else { return nil }
        var i = data.count - 4
        while i >= 0 {
            if u32(data, i) == signature { return i }
            i -= 1
        }
        return nil
    }

    /// 절대경로 · `..` · 백슬래시 · NUL 거부
    static func isSafeEntryPath(_ path: String) -> Bool {
        guard !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0") else { return false }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return parts.allSatisfy { $0 != ".." && $0 != "." }
    }
}

// MARK: - 번들 판별 · 분할 선택

enum AppBundleKind: String, CaseIterable, Sendable {
    case apk, apks, xapk, apkm

    /// 확장자만으로 판별 — 내용 검사는 열어 본 뒤 한다
    static func detect(path: String) -> AppBundleKind? {
        let ext = (path as NSString).pathExtension.lowercased()
        return AppBundleKind(rawValue: ext)
    }

    var isBundle: Bool { self != .apk }
}

/// 분할 선택에 쓰는 기기 특성 — `getprop` · `wm density` 로 채운다
struct DeviceProfile: Equatable, Sendable {
    var abis: [String] = []
    var density: Int = 0
    var languages: [String] = []

    static let densityNames: [String: Int] = [
        "ldpi": 120, "mdpi": 160, "tvdpi": 213, "hdpi": 240,
        "xhdpi": 320, "xxhdpi": 480, "xxxhdpi": 640,
        "anydpi": 0, "nodpi": 0
    ]

    /// 기기 밀도에 가장 가까운(= 같거나 작은 것 중 최대) 이름
    static func bestDensityName(for density: Int) -> String? {
        guard density > 0 else { return nil }
        let candidates = densityNames
            .filter { $0.value > 0 && $0.value <= density }
            .max { $0.value < $1.value }
        return candidates?.key ?? "mdpi"
    }
}

/// 분할 APK 한 건 — 파일명에서 기능 이름과 설정 토큰을 뽑아 둔 것
private struct BundleSplit {
    let path: String
    let feature: String
    let configs: [String]
}

/// 번들 안의 OBB — `/sdcard/Android/obb/<pkg>/` 로 밀어 넣는다
struct ObbFile: Equatable, Sendable {
    let entryPath: String
    /// install_path 가 있으면 그 경로를, 없으면 파일명만
    let relativePath: String
}

struct BundlePlan: Equatable, Sendable {
    /// ZIP 안 APK 엔트리 — **base 가 첫 번째**
    var apkEntries: [String]
    var obb: [ObbFile]
    var packageHint: String?
    var usedUniversal: Bool

    var isEmpty: Bool { apkEntries.isEmpty }
}

/// 번들 내용 → 설치 계획 (순수 로직)
enum BundlePlanner {
    /// 언어 분할로 볼 토큰인지 판별하기 위한 최소 집합 — 여기 없으면 "알 수 없는 설정"으로 포함한다
    private static let abiTokens: Set<String> = [
        "armeabi", "armeabi_v7a", "arm64_v8a", "x86", "x86_64", "mips", "mips64"
    ]

    /// `.apks`/`.apkm`/일반 zip: APK 엔트리 목록에서 이 기기에 필요한 것만 고른다.
    ///
    /// 규칙 (실패하면 **전체 포함으로 폴백** — 설치는 되고 용량만 커진다):
    /// 1. `universal.apk` 가 있으면 그것 하나 (bundletool 기본 산출물)
    /// 2. `standalones/` 는 splits 가 있으면 제외 (구형 기기 전용)
    /// 3. 기능(feature)별로 master 1개 + ABI 1개 + 밀도 1개 + 언어(기기 언어만)
    static func apkEntries(from paths: [String], profile: DeviceProfile) -> [String] {
        let apks = paths.filter { $0.lowercased().hasSuffix(".apk") }
        guard !apks.isEmpty else { return [] }

        if let universal = apks.first(where: { baseName($0).lowercased() == "universal.apk" }) {
            return [universal]
        }

        let withoutStandalone = apks.filter { !$0.lowercased().hasPrefix("standalones/") }
        let candidates = withoutStandalone.isEmpty ? apks : withoutStandalone

        // 파일명에서 `-` 뒤 토큰들을 설정으로 본다 (base-arm64_v8a.apk · base-xxhdpi.apk · base-ko.apk)
        let splits: [BundleSplit] = candidates.map { path in
            let name = baseName(path)
            let stem = (name as NSString).deletingPathExtension
            let parts = stem.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
            return BundleSplit(path: path, feature: parts.first ?? stem, configs: Array(parts.dropFirst()))
        }

        var selected: [String] = []
        let features = Set(splits.map(\.feature))
        for feature in features.sorted() {
            let group = splits.filter { $0.feature == feature }
            let masters = group.filter { $0.configs.isEmpty || $0.configs == ["master"] }
            selected.append(contentsOf: masters.map(\.path))

            let abiSplits = group.filter { split in
                split.configs.contains { abiTokens.contains($0.lowercased()) }
            }
            if !abiSplits.isEmpty {
                if let pick = pickABI(abiSplits, profile: profile) { selected.append(pick) }
            }

            let densitySplits = group.filter { split in
                split.configs.contains { DeviceProfile.densityNames[$0.lowercased()] != nil }
            }
            if !densitySplits.isEmpty, let pick = pickDensity(densitySplits, profile: profile) {
                selected.append(pick)
            }

            for split in group where !masters.contains(where: { $0.path == split.path })
                && !abiSplits.contains(where: { $0.path == split.path })
                && !densitySplits.contains(where: { $0.path == split.path }) {
                // 남은 것은 언어 분할 또는 알 수 없는 설정
                let langs = split.configs.map { $0.lowercased() }
                let knownLang = langs.allSatisfy { isLanguageToken($0) }
                if !knownLang {
                    selected.append(split.path)       // 모르면 포함 — 빠뜨려 설치 실패하는 것보다 낫다
                } else if profile.languages.isEmpty {
                    continue                          // 기기 언어를 모르면 언어 분할은 생략 가능
                } else if langs.contains(where: { l in profile.languages.contains(where: { $0.hasPrefix(l) || l.hasPrefix($0) }) }) {
                    selected.append(split.path)
                }
            }
        }

        // base/master 를 **맨 앞**으로 — pm install-multiple 은 순서에 민감하지 않지만
        // 로그와 진행 표시가 읽기 쉬워지고, base 가 먼저 올라가야 실패도 빨리 드러난다
        func rank(_ path: String) -> Int {
            let name = baseName(path).lowercased()
            if name == "base.apk" || name == "master.apk" || name.hasSuffix("-master.apk") {
                return 0
            }
            return 1
        }
        let ordered = selected.sorted { a, b in
            let ra = rank(a)
            let rb = rank(b)
            if ra != rb { return ra < rb }
            return a < b
        }
        // 아무것도 못 골랐으면 전체 폴백 (사용자가 설치를 끝낼 수 있게)
        return ordered.isEmpty ? candidates : ordered
    }

    private static func pickABI(_ splits: [BundleSplit], profile: DeviceProfile) -> String? {
        for abi in profile.abis {
            let target = abi.lowercased().replacingOccurrences(of: "-", with: "_")
            if let hit = splits.first(where: { $0.configs.contains { $0.lowercased() == target } }) {
                return hit.path
            }
        }
        // 기기 ABI 를 모르면 첫 후보 — 실패하면 adb 가 NO_MATCHING_ABIS 로 알려준다
        return splits.first?.path
    }

    private static func pickDensity(_ splits: [BundleSplit], profile: DeviceProfile) -> String? {
        let want = profile.density > 0 ? profile.density : 320
        let scored: [(path: String, value: Int)] = splits.compactMap { split in
            let values = split.configs.compactMap { DeviceProfile.densityNames[$0.lowercased()] }
            guard let best = values.max() else { return nil }
            return (split.path, best)
        }
        guard !scored.isEmpty else { return splits.first?.path }
        let below = scored.filter { $0.value > 0 && $0.value <= want }.max { $0.value < $1.value }
        if let below { return below.path }
        return scored.filter { $0.value > 0 }.min { $0.value < $1.value }?.path ?? splits.first?.path
    }

    private static func isLanguageToken(_ token: String) -> Bool {
        // ko · ko_kr · pt_br · zh_hans 같은 2~7자 소문자 토큰
        guard (2...7).contains(token.count) else { return false }
        return token.allSatisfy { $0.isLetter || $0 == "_" || $0 == "-" }
    }

    private static func baseName(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }
}

// MARK: - XAPK / APKM 메타데이터

/// `.xapk` 의 `manifest.json` — 파일 목록과 OBB 경로를 알려준다
struct XapkManifest: Equatable, Sendable {
    var packageName: String?
    var apks: [String] = []
    var obb: [ObbFile] = []
}

enum BundleMetadata {
    /// JSON 트리에서 `*.apk` / `*.obb` 로 끝나는 문자열을 모은다.
    /// `.xapk`(manifest.json) · `.apkm`(info.json) 의 스키마가 제각각이라
    /// **키 이름에 의존하지 않고 확장자로** 찾는다 — 모르는 형식도 놓치지 않는다.
    static func fileNames(inJSON data: Data, suffix: String) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var out: [String] = []
        var seen = Set<String>()
        func walk(_ node: Any, depth: Int) {
            guard depth < 12, out.count < ZipArchive.maxEntries else { return }
            switch node {
            case let s as String:
                if s.lowercased().hasSuffix(suffix), !seen.contains(s) {
                    seen.insert(s)
                    out.append(s)
                }
            case let arr as [Any]:
                for item in arr { walk(item, depth: depth + 1) }
            case let dict as [String: Any]:
                for (_, value) in dict { walk(value, depth: depth + 1) }
            default:
                break
            }
        }
        walk(root, depth: 0)
        return out
    }

    /// `manifest.json` → XAPK 모델. 경로는 ZIP 안 경로와 대소문자가 다를 수 있어
    /// 호출측이 실제 엔트리와 대조한다.
    static func parseXapk(_ data: Data) -> XapkManifest? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        var manifest = XapkManifest()
        manifest.packageName = (root["package_name"] as? String)
            ?? (root["packageName"] as? String)

        var seen = Set<String>()
        func appendAPK(_ name: String) {
            guard name.lowercased().hasSuffix(".apk"), seen.insert(name).inserted else { return }
            manifest.apks.append(name)
        }
        for key in ["apks", "split_apks"] {
            for item in (root[key] as? [[String: Any]] ?? []) {
                if let file = item["file"] as? String { appendAPK(file) }
            }
        }
        // 스키마가 다른 변형 — 문자열 배열
        for key in ["apks", "split_apks"] {
            for item in (root[key] as? [String] ?? []) { appendAPK(item) }
        }

        for item in (root["expansions"] as? [[String: Any]] ?? []) {
            guard let file = item["file"] as? String else { continue }
            let installPath = (item["install_path"] as? String)
                ?? (item["installPath"] as? String)
            manifest.obb.append(ObbFile(
                entryPath: file,
                relativePath: installPath ?? (file as NSString).lastPathComponent
            ))
        }
        return manifest
    }
}
