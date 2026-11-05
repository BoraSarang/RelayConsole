import Compression
import Foundation
import Testing
@testable import RelayConsole

// MARK: - 테스트용 ZIP 작성기

/// 최소 ZIP 작성기 — stored(0) · deflate(8) 두 방식만 만든다.
/// 우리 리더가 실제로 읽는 구조(중앙 디렉터리·EOCD)를 그대로 흉내 낸다.
private enum ZipFixture {
    static func build(_ entries: [(name: String, data: Data, deflate: Bool)]) -> Data {
        var payloads: [(name: [UInt8], payload: Data, raw: Int, method: UInt16)] = []
        for entry in entries {
            payloads.append((
                name: Array(entry.name.utf8),
                payload: entry.deflate ? deflateRaw(entry.data) : entry.data,
                raw: entry.data.count,
                method: entry.deflate ? 8 : 0
            ))
        }

        var out = Data()
        var offsets: [UInt64] = []
        for entry in payloads {
            offsets.append(UInt64(out.count))
            out.append(le32(0x0403_4b50))
            out.append(le16(20))            // version needed
            out.append(le16(0))             // flags
            out.append(le16(entry.method))
            out.append(le16(0))             // mod time
            out.append(le16(0))             // mod date
            out.append(le32(0))             // crc — 리더는 검증하지 않는다
            out.append(le32(UInt32(entry.payload.count)))
            out.append(le32(UInt32(entry.raw)))
            out.append(le16(UInt16(entry.name.count)))
            out.append(le16(0))             // extra len
            out.append(contentsOf: entry.name)
            out.append(entry.payload)
        }

        let cdStart = UInt64(out.count)
        var central = Data()
        for (index, entry) in payloads.enumerated() {
            central.append(le32(0x0201_4b50))
            central.append(le16(20))        // version made by
            central.append(le16(20))        // version needed
            central.append(le16(0))         // flags
            central.append(le16(entry.method))
            central.append(le16(0))
            central.append(le16(0))
            central.append(le32(0))         // crc
            central.append(le32(UInt32(entry.payload.count)))
            central.append(le32(UInt32(entry.raw)))
            central.append(le16(UInt16(entry.name.count)))
            central.append(le16(0))         // extra
            central.append(le16(0))         // comment
            central.append(le16(0))         // disk
            central.append(le16(0))         // internal attrs
            central.append(le32(0))         // external attrs
            central.append(le32(UInt32(offsets[index])))
            central.append(contentsOf: entry.name)
        }
        out.append(central)
        out.append(le32(0x0605_4b50))
        out.append(le16(0))
        out.append(le16(0))
        out.append(le16(UInt16(entries.count)))
        out.append(le16(UInt16(entries.count)))
        out.append(le32(UInt32(central.count)))
        out.append(le32(UInt32(cdStart)))
        out.append(le16(0))                 // comment len
        return out
    }

    static func le16(_ value: UInt16) -> Data {
        var v = value.littleEndian
        return Data(bytes: &v, count: 2)
    }

    static func le32(_ value: UInt32) -> Data {
        var v = value.littleEndian
        return Data(bytes: &v, count: 4)
    }

    /// 원시 deflate 스트림 — ZIP 은 zlib 헤더 없는 raw deflate 를 쓴다.
    /// Apple `COMPRESSION_ZLIB` 이 바로 그 형식이다.
    static func deflateRaw(_ input: Data) -> Data {
        guard !input.isEmpty else { return Data() }
        let capacity = 64 * 1024
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        let src = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer {
            dst.deallocate()
            src.deallocate()
        }
        var stream = compression_stream(
            dst_ptr: dst,
            dst_size: capacity,
            src_ptr: src,
            src_size: 0,
            state: nil
        )
        guard compression_stream_init(&stream, COMPRESSION_STREAM_ENCODE, COMPRESSION_ZLIB)
                == COMPRESSION_STATUS_OK else { return input }
        defer { compression_stream_destroy(&stream) }

        let bytes = [UInt8](input)
        var output = Data()
        var cursor = 0

        func drain() {
            let produced = capacity - stream.dst_size
            if produced > 0 { output.append(dst, count: produced) }
        }

        while cursor < bytes.count {
            let n = min(capacity, bytes.count - cursor)
            bytes.withUnsafeBytes { raw in
                guard let baseAddress = raw.baseAddress else { return }
                memcpy(src, baseAddress.advanced(by: cursor), n)
            }
            cursor += n
            stream.src_ptr = UnsafePointer(src)
            stream.src_size = n
            repeat {
                stream.dst_ptr = dst
                stream.dst_size = capacity
                let status = compression_stream_process(&stream, 0)
                drain()
                if status == COMPRESSION_STATUS_ERROR { return input }
                if stream.src_size == 0 { break }
            } while true
        }

        while true {
            stream.dst_ptr = dst
            stream.dst_size = capacity
            let status = compression_stream_process(
                &stream,
                Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
            )
            drain()
            if status == COMPRESSION_STATUS_END { break }
            if status == COMPRESSION_STATUS_ERROR { return input }
        }
        return output
    }
}

private func tempFile(_ data: Data, name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("relay-bundle-\(UUID().uuidString)-\(name)")
    try data.write(to: url)
    return url
}

private func tempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("relay-bundle-dir-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

// MARK: - ZIP 리더

struct AppBundleTests {
    @Test func readsStoredEntry() throws {
        let payload = Data(repeating: 0x41, count: 4096)
        let url = try tempFile(ZipFixture.build([("base.apk", payload, false)]), name: "stored.zip")
        defer { try? FileManager.default.removeItem(at: url) }

        let zip = try ZipArchive(url: url)
        #expect(zip.entries.count == 1)
        #expect(zip.entries[0].path == "base.apk")
        #expect(zip.entries[0].method == 0)
        #expect(try zip.data(for: zip.entries[0]) == payload)
    }

    @Test func readsDeflatedEntry() throws {
        // 실제 APK 처럼 압축이 잘 되는 데이터 — 8KB 반복
        let payload = Data(String(repeating: "relay-console-bundle ", count: 400).utf8)
        let url = try tempFile(ZipFixture.build([("split.apk", payload, true)]), name: "deflate.zip")
        defer { try? FileManager.default.removeItem(at: url) }

        let zip = try ZipArchive(url: url)
        guard let entry = zip.entry(named: "split.apk") else {
            Issue.record("엔트리를 찾지 못했다")
            return
        }
        #expect(entry.method == 8)
        #expect(entry.compressedSize < UInt64(payload.count))
        #expect(try zip.data(for: entry) == payload)
    }

    @Test func streamsEntryToFile() throws {
        let payload = Data((0..<200_000).map { UInt8($0 % 251) })
        let url = try tempFile(ZipFixture.build([("obb.bin", payload, true)]), name: "stream.zip")
        let dir = try tempDir()
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: dir)
        }

        let zip = try ZipArchive(url: url)
        guard let entry = zip.entry(named: "obb.bin") else {
            Issue.record("엔트리를 찾지 못했다")
            return
        }
        let dest = dir.appendingPathComponent("out.bin")
        try zip.write(entry, to: dest)
        #expect(try Data(contentsOf: dest) == payload)
    }

    /// 디렉터리 항목(`/` 로 끝남)은 엔트리 목록에서 빠진다
    @Test func skipsDirectoryEntries() throws {
        let url = try tempFile(
            ZipFixture.build([
                ("splits/", Data(), false),
                ("splits/base.apk", Data("x".utf8), false)
            ]),
            name: "dirs.zip"
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let zip = try ZipArchive(url: url)
        #expect(zip.entries.map(\.path) == ["splits/base.apk"])
    }

    @Test func lookupIsCaseInsensitive() throws {
        let url = try tempFile(ZipFixture.build([("Base.APK", Data("x".utf8), false)]), name: "case.zip")
        defer { try? FileManager.default.removeItem(at: url) }

        let zip = try ZipArchive(url: url)
        #expect(zip.entry(named: "base.apk")?.path == "Base.APK")
        #expect(zip.entry(named: "Base.APK")?.path == "Base.APK")
        #expect(zip.entry(named: "nope.apk") == nil)
    }

    /// 경로 순회 · 절대경로 · 백슬래시는 **열지 않고 거부**한다 (압축 폭탄 방지)
    @Test func rejectsUnsafePaths() {
        #expect(!ZipArchive.isSafeEntryPath("../evil.apk"))
        #expect(!ZipArchive.isSafeEntryPath("a/../../evil.apk"))
        #expect(!ZipArchive.isSafeEntryPath("/etc/passwd"))
        #expect(!ZipArchive.isSafeEntryPath("a\\b.apk"))
        #expect(!ZipArchive.isSafeEntryPath("./x.apk"))
        #expect(ZipArchive.isSafeEntryPath("base.apk"))
        #expect(ZipArchive.isSafeEntryPath("splits/base-arm64_v8a.apk"))

        let data = ZipFixture.build([("../evil.apk", Data("x".utf8), false)])
        let url = try? tempFile(data, name: "unsafe.zip")
        defer { if let url { try? FileManager.default.removeItem(at: url) } }
        #expect(throws: ZipError.unsafePath) {
            _ = try ZipArchive(url: url!)
        }
    }

    @Test func rejectsNonZip() throws {
        let url = try tempFile(Data("not a zip at all, just text".utf8), name: "notzip.bin")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: ZipError.notZip) {
            _ = try ZipArchive(url: url)
        }
    }

    // MARK: - 번들 판별

    @Test func detectsBundleKindByExtension() {
        #expect(AppBundleKind.detect(path: "/tmp/a.apk") == .apk)
        #expect(AppBundleKind.detect(path: "/tmp/a.APKS") == .apks)
        #expect(AppBundleKind.detect(path: "/tmp/a.xapk") == .xapk)
        #expect(AppBundleKind.detect(path: "/tmp/a.apkm") == .apkm)
        #expect(AppBundleKind.detect(path: "/tmp/a.zip") == nil)
        #expect(AppBundleKind.detect(path: "/tmp/a") == nil)
        #expect(!AppBundleKind.apk.isBundle)
        #expect(AppBundleKind.apks.isBundle)
    }

    @Test func installKindRequiresAbsolutePath() {
        #expect(AppHubLogic.installKind(path: "/tmp/a.apks") == .apks)
        #expect(AppHubLogic.installKind(path: "/tmp/a.xapk") == .xapk)
        #expect(AppHubLogic.installKind(path: "/tmp/a.apkm") == .apkm)
        #expect(AppHubLogic.installKind(path: "relative/a.apk") == nil)
        #expect(AppHubLogic.installKind(path: "") == nil)
        #expect(AppHubLogic.installKind(path: "/tmp/a.zip") == nil)
    }

    // MARK: - 분할 선택

    @Test func universalWins() {
        let picked = BundlePlanner.apkEntries(
            from: ["base.apk", "base-arm64_v8a.apk", "universal.apk"],
            profile: DeviceProfile(abis: ["arm64-v8a"], density: 480)
        )
        #expect(picked == ["universal.apk"])
    }

    @Test func picksMatchingABI() {
        let picked = BundlePlanner.apkEntries(
            from: ["base.apk", "base-arm64_v8a.apk", "base-armeabi_v7a.apk", "base-x86_64.apk"],
            profile: DeviceProfile(abis: ["arm64-v8a", "armeabi-v7a"])
        )
        #expect(picked == ["base.apk", "base-arm64_v8a.apk"])
    }

    @Test func picksNearestDensityBelow() {
        // 420dpi 기기 → xxhdpi(480) 가 아니라 **같거나 작은 것 중 최대**인 xhdpi(320)
        let picked = BundlePlanner.apkEntries(
            from: ["base.apk", "base-hdpi.apk", "base-xhdpi.apk", "base-xxhdpi.apk"],
            profile: DeviceProfile(density: 420)
        )
        #expect(picked == ["base.apk", "base-xhdpi.apk"])
    }

    @Test func picksSmallestDensityWhenAllAbove() {
        let picked = BundlePlanner.apkEntries(
            from: ["base.apk", "base-xxhdpi.apk", "base-xxxhdpi.apk"],
            profile: DeviceProfile(density: 120)
        )
        #expect(picked == ["base.apk", "base-xxhdpi.apk"])
    }

    @Test func picksLanguageSplitOnlyForDeviceLanguage() {
        let picked = BundlePlanner.apkEntries(
            from: ["base.apk", "base-ko.apk", "base-en.apk"],
            profile: DeviceProfile(languages: ["ko_kr", "ko"])
        )
        #expect(picked == ["base.apk", "base-ko.apk"])
    }

    /// 기기 언어를 모르면 언어 분할은 **생략** — 빠뜨려도 앱은 뜨고, 잘못 넣으면 용량만 늘어난다
    @Test func skipsLanguageSplitsWithoutDeviceLanguage() {
        let picked = BundlePlanner.apkEntries(
            from: ["base.apk", "base-ko.apk", "base-en.apk"],
            profile: DeviceProfile()
        )
        #expect(picked == ["base.apk"])
    }

    /// 모르는 설정 토큰은 **포함** — 빠뜨려 설치가 실패하는 것보다 낫다
    @Test func includesUnknownConfigSplit() {
        let picked = BundlePlanner.apkEntries(
            from: ["base.apk", "base-someunknownconfig.apk"],
            profile: DeviceProfile()
        )
        #expect(Set(picked) == Set(["base.apk", "base-someunknownconfig.apk"]))
    }

    @Test func excludesStandalonesWhenSplitsExist() {
        let picked = BundlePlanner.apkEntries(
            from: ["standalones/base.apk", "base.apk", "base-arm64_v8a.apk"],
            profile: DeviceProfile(abis: ["arm64-v8a"])
        )
        #expect(picked == ["base.apk", "base-arm64_v8a.apk"])
    }

    @Test func fallbackKeepsEverythingWhenNothingSelected() {
        let picked = BundlePlanner.apkEntries(
            from: ["odd-name.apk"],
            profile: DeviceProfile()
        )
        #expect(picked == ["odd-name.apk"])
    }

    @Test func emptyWhenNoAPKEntries() {
        #expect(BundlePlanner.apkEntries(from: ["manifest.json", "icon.png"], profile: DeviceProfile()) == [])
    }

    // MARK: - XAPK 메타데이터

    @Test func parsesXapkManifest() throws {
        let json = """
        {
          "package_name": "com.example.game",
          "apks": [{"file": "base.apk"}, {"file": "config.arm64_v8a.apk"}],
          "expansions": [
            {"file": "Android/obb/com.example.game/main.1.obb",
             "install_path": "Android/obb/com.example.game/main.1.obb"}
          ]
        }
        """
        let manifest = try #require(BundleMetadata.parseXapk(Data(json.utf8)))
        #expect(manifest.packageName == "com.example.game")
        #expect(manifest.apks == ["base.apk", "config.arm64_v8a.apk"])
        #expect(manifest.obb == [
            ObbFile(
                entryPath: "Android/obb/com.example.game/main.1.obb",
                relativePath: "Android/obb/com.example.game/main.1.obb"
            )
        ])
    }

    /// 스키마가 제각각이라 **키 이름이 아니라 확장자**로 찾는다
    @Test func collectsFileNamesByExtensionAnywhereInJSON() throws {
        let json = """
        {"info": {"files": ["a.apk", "b.APK", "note.txt"]}, "extra": [{"path": "c.apk"}], "dup": "a.apk"}
        """
        let names = BundleMetadata.fileNames(inJSON: Data(json.utf8), suffix: ".apk")
        // JSON 객체 순회 순서는 보장되지 않는다 — 내용만 확인한다
        #expect(Set(names) == Set(["a.apk", "b.APK", "c.apk"]))
        #expect(BundleMetadata.fileNames(inJSON: Data("not json".utf8), suffix: ".apk") == [])
    }

    @Test func parsesXapkWithStringArraySchema() throws {
        let json = """
        {"packageName": "com.x", "split_apks": ["base.apk", "split_1.apk"]}
        """
        let manifest = try #require(BundleMetadata.parseXapk(Data(json.utf8)))
        #expect(manifest.packageName == "com.x")
        #expect(manifest.apks == ["base.apk", "split_1.apk"])
        #expect(manifest.obb.isEmpty)
    }

    // MARK: - 번들 추출

    @Test func prepareXapkExtractsSplitsAndObb() throws {
        let json = """
        {
          "package_name": "com.example.game",
          "apks": [{"file": "base.apk"}, {"file": "config.arm64_v8a.apk"}],
          "expansions": [
            {"file": "Android/obb/com.example.game/main.1.obb",
             "install_path": "Android/obb/com.example.game/main.1.obb"}
          ]
        }
        """
        let baseBytes = Data(repeating: 0x01, count: 500)
        let splitBytes = Data(repeating: 0x02, count: 120)
        let obbBytes = Data(repeating: 0x03, count: 64)
        let url = try tempFile(
            ZipFixture.build([
                ("base.apk", baseBytes, false),
                ("config.arm64_v8a.apk", splitBytes, true),
                ("Android/obb/com.example.game/main.1.obb", obbBytes, true),
                ("manifest.json", Data(json.utf8), true)
            ]),
            name: "game.xapk"
        )
        let dir = try tempDir()
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: dir)
        }

        let prepared = try BundleInstaller.prepare(
            url: url,
            kind: .xapk,
            profile: DeviceProfile(abis: ["arm64-v8a"], density: 480),
            into: dir
        )
        #expect(prepared.packageHint == "com.example.game")
        #expect(prepared.apkFiles.count == 2)
        #expect(prepared.obbFiles.count == 1)
        #expect(prepared.obbFiles[0].relativePath == "Android/obb/com.example.game/main.1.obb")
        #expect(try Data(contentsOf: prepared.apkFiles[0]) == baseBytes)
        #expect(try Data(contentsOf: prepared.obbFiles[0].url) == obbBytes)
        #expect(prepared.totalBytes == UInt64(baseBytes.count + splitBytes.count + obbBytes.count))
    }

    /// `.apkm` 은 `info.json` 안의 목록을 쓰고, 이름 대소문자가 달라도 찾는다
    @Test func prepareApkmResolvesDeclaredNamesCaseInsensitively() throws {
        let json = """
        {"apks": ["Base.APK", "Split.APK"]}
        """
        let url = try tempFile(
            ZipFixture.build([
                ("base.apk", Data(repeating: 0x0A, count: 200), false),
                ("split.apk", Data(repeating: 0x0B, count: 100), true),
                ("info.json", Data(json.utf8), false)
            ]),
            name: "app.apkm"
        )
        let dir = try tempDir()
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: dir)
        }

        let prepared = try BundleInstaller.prepare(
            url: url,
            kind: .apkm,
            profile: DeviceProfile(abis: ["arm64-v8a"]),
            into: dir
        )
        #expect(prepared.apkFiles.count == 2)
        #expect(prepared.totalBytes == 300)
    }

    /// `.apks` 에 메타데이터가 없으면 ZIP 안 APK 를 직접 고른다
    @Test func prepareApksWithoutMetadataUsesPlanner() throws {
        let url = try tempFile(
            ZipFixture.build([
                ("splits/base.apk", Data(repeating: 0x11, count: 300), false),
                ("splits/base-arm64_v8a.apk", Data(repeating: 0x12, count: 150), true),
                ("splits/base-x86_64.apk", Data(repeating: 0x13, count: 150), true)
            ]),
            name: "app.apks"
        )
        let dir = try tempDir()
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: dir)
        }

        let prepared = try BundleInstaller.prepare(
            url: url,
            kind: .apks,
            profile: DeviceProfile(abis: ["arm64-v8a"]),
            into: dir
        )
        #expect(prepared.apkFiles.count == 2)
        // 패키지 힌트는 base APK 매니페스트에서 읽으려 하지만, 픽스처는 껍데기라 nil 이 정상
        #expect(prepared.packageHint == nil)
    }

    @Test func prepareRejectsEmptyBundle() throws {
        let url = try tempFile(
            ZipFixture.build([("readme.txt", Data("hi".utf8), false)]),
            name: "empty.apks"
        )
        let dir = try tempDir()
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: dir)
        }
        #expect(throws: BundleInstallError.empty) {
            _ = try BundleInstaller.prepare(url: url, kind: .apks, profile: DeviceProfile(), into: dir)
        }
    }

    // MARK: - 경로 안전화

    @Test func safeNameStripsSeparators() {
        #expect(BundleInstaller.safeName("base arm64!.apk") == "base_arm64_.apk")
        #expect(BundleInstaller.safeName("../../etc/passwd") == ".._.._etc_passwd")
        #expect(BundleInstaller.safeName("") == "file")
    }

    @Test func safeRelativePathRemovesTraversal() {
        #expect(BundleInstaller.safeRelativePath("../../evil.obb") == "evil.obb")
        #expect(BundleInstaller.safeRelativePath("Android/obb/com.x/main.obb") == "Android/obb/com.x/main.obb")
        #expect(BundleInstaller.safeRelativePath("//a//b//c.obb") == "a/b/c.obb")
        #expect(BundleInstaller.safeRelativePath("") == "obb")
    }

    @Test func obbDestinationKeepsManifestPathOrFallsBackToPackageDir() {
        #expect(BundleInstaller.obbDestination(
            relativePath: "Android/obb/com.x/main.1.com.x.obb",
            package: "com.x"
        ) == "/sdcard/Android/obb/com.x/main.1.com.x.obb")
        #expect(BundleInstaller.obbDestination(
            relativePath: "main.1.com.x.obb",
            package: "com.x"
        ) == "/sdcard/Android/obb/com.x/main.1.com.x.obb")
        // 경로 순회는 목적지에도 영향을 주지 못한다
        #expect(BundleInstaller.obbDestination(
            relativePath: "../../main.obb",
            package: "com.x"
        ) == "/sdcard/Android/obb/com.x/main.obb")
    }

    // MARK: - 설치 인자 (번들)

    @Test func installMultipleArgsOrder() {
        var options = AppInstallOptions()
        options.allowDowngrade = true
        #expect(AppHubLogic.installMultipleArgs(
            remotePaths: ["/data/local/tmp/a/base.apk", "/data/local/tmp/a/split.apk"],
            options: options
        ) == [
            "shell", "pm", "install-multiple", "-r", "-d",
            "/data/local/tmp/a/base.apk", "/data/local/tmp/a/split.apk"
        ])
    }

    // MARK: - 기기 밀도 이름

    @Test func bestDensityNameNeverExceedsDeviceDensity() {
        #expect(DeviceProfile.bestDensityName(for: 420) == "xhdpi")
        #expect(DeviceProfile.bestDensityName(for: 480) == "xxhdpi")
        #expect(DeviceProfile.bestDensityName(for: 640) == "xxxhdpi")
        #expect(DeviceProfile.bestDensityName(for: 0) == nil)
    }

    // MARK: - 백업 메타

    @Test func backupManifestRoundTrips() throws {
        let manifest = BackupManifest(
            package: "com.example.app",
            versionName: "2.5.1",
            versionCode: 42,
            serial: "R5CT215F4QK",
            savedAt: "2026-10-24T10:00:00Z",
            files: [BackupManifest.File(name: "base.apk", bytes: 1024, sha256: "abc")],
            note: "APK only — app data is not included"
        )
        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(BackupManifest.self, from: data)
        #expect(decoded == manifest)
    }
}

// MARK: - 아이콘 리소스 후보 선택

struct AndroidResourceTests {
    @Test func bestPrefersLargestDensityNotAboveTarget() {
        let candidates = [
            AndroidResourceTable.Candidate(path: "res/mipmap-hdpi/ic.png", density: 240),
            AndroidResourceTable.Candidate(path: "res/mipmap-xhdpi/ic.png", density: 320),
            AndroidResourceTable.Candidate(path: "res/mipmap-xxhdpi/ic.png", density: 480)
        ]
        #expect(AndroidResourceTable.best(candidates, targetDensity: 420) == "res/mipmap-xhdpi/ic.png")
        #expect(AndroidResourceTable.best(candidates, targetDensity: 320) == "res/mipmap-xhdpi/ic.png")
        #expect(AndroidResourceTable.best(candidates, targetDensity: 640) == "res/mipmap-xxhdpi/ic.png")
    }

    @Test func bestPicksSmallestWhenAllAboveTarget() {
        let candidates = [
            AndroidResourceTable.Candidate(path: "res/mipmap-xxhdpi/ic.png", density: 480),
            AndroidResourceTable.Candidate(path: "res/mipmap-xxxhdpi/ic.png", density: 640)
        ]
        #expect(AndroidResourceTable.best(candidates, targetDensity: 160) == "res/mipmap-xxhdpi/ic.png")
    }

    @Test func bestIgnoresNonImageEntries() {
        let candidates = [
            AndroidResourceTable.Candidate(path: "res/xml/ic.xml", density: 320),
            AndroidResourceTable.Candidate(path: "res/mipmap/ic.webp", density: 160)
        ]
        #expect(AndroidResourceTable.best(candidates, targetDensity: 320) == "res/mipmap/ic.webp")
        #expect(AndroidResourceTable.best(
            [AndroidResourceTable.Candidate(path: "res/xml/ic.xml", density: 320)],
            targetDensity: 320
        ) == nil)
    }
}

// MARK: - 바이너리 XML (AndroidManifest.xml)

/// 합성 AXML 을 만들어 파서가 실제 청크 레이아웃을 읽는지 확인한다.
/// (실제 APK 는 실기기 검증에서 확인 — 여기서는 **오프셋 계산**이 틀어지면 잡힌다)
private enum AXMLFixture {
    static func build() -> Data {
        let strings = [
            "versionCode", "versionName", "icon",
            "com.example.app", "1.2.3",
            "manifest", "application", "package"
        ]
        var chunks = Data()
        chunks.append(stringPool(strings))
        // 리소스 맵 — 문자열 인덱스 0…2 가 안드로이드 속성 ID 에 대응
        var map = Data()
        map.append(ZipFixture.le16(0x0180))
        map.append(ZipFixture.le16(8))
        map.append(ZipFixture.le32(UInt32(8 + 3 * 4)))
        map.append(ZipFixture.le32(0x0101_021b))   // versionCode
        map.append(ZipFixture.le32(0x0101_021c))   // versionName
        map.append(ZipFixture.le32(0x0101_0002))   // icon
        chunks.append(map)

        chunks.append(startElement(
            nameIndex: 5,                           // "manifest"
            attributes: [
                (name: 7, raw: 0xFFFF_FFFF, type: 0x03, data: 3),   // package = "com.example.app"
                (name: 1, raw: 0xFFFF_FFFF, type: 0x03, data: 4),   // versionName = "1.2.3"
                (name: 0, raw: 0xFFFF_FFFF, type: 0x10, data: 42)   // versionCode = 42
            ]
        ))
        chunks.append(startElement(
            nameIndex: 6,                           // "application"
            attributes: [
                (name: 2, raw: 0xFFFF_FFFF, type: 0x01, data: 0x7F02_0001)  // icon → resId
            ]
        ))

        var out = Data()
        out.append(ZipFixture.le16(0x0003))         // RES_XML_TYPE
        out.append(ZipFixture.le16(8))
        out.append(ZipFixture.le32(UInt32(8 + chunks.count)))
        out.append(chunks)
        return out
    }

    static func stringPool(_ strings: [String]) -> Data {
        var data = Data()
        var offsets: [UInt32] = []
        for s in strings {
            offsets.append(UInt32(data.count))
            let bytes = Array(s.utf8)
            // UTF-8 풀은 길이가 두 개다 — 문자 수(UTF-16 length) → 바이트 수.
            // 실제 APK 와 같은 레이아웃으로 만들어야 파서의 오프셋 계산이 검증된다.
            data.append(UInt8(s.utf16.count))        // 문자 수
            data.append(UInt8(bytes.count))          // 바이트 수
            data.append(contentsOf: bytes)
            data.append(0)                           // NUL
        }
        while data.count % 4 != 0 { data.append(0) } // 4바이트 정렬

        let stringsStart = 28 + strings.count * 4
        let size = stringsStart + data.count
        var out = Data()
        out.append(ZipFixture.le16(0x0001))          // RES_STRING_POOL_TYPE
        out.append(ZipFixture.le16(28))              // headerSize
        out.append(ZipFixture.le32(UInt32(size)))
        out.append(ZipFixture.le32(UInt32(strings.count)))
        out.append(ZipFixture.le32(0))               // styleCount
        out.append(ZipFixture.le32(0x100))           // UTF8_FLAG
        out.append(ZipFixture.le32(UInt32(stringsStart)))
        out.append(ZipFixture.le32(0))               // stylesStart
        for offset in offsets { out.append(ZipFixture.le32(offset)) }
        out.append(data)
        return out
    }

    static func startElement(
        nameIndex: UInt32,
        attributes: [(name: UInt32, raw: UInt32, type: UInt8, data: UInt32)]
    ) -> Data {
        // 16(노드 헤더: chunk header 8 + lineNumber 4 + comment 4) + 20(attrExt) + 속성들
        let size = 16 + 20 + attributes.count * 20
        var out = Data()
        out.append(ZipFixture.le16(0x0102))          // RES_XML_START_ELEMENT_TYPE
        out.append(ZipFixture.le16(16))              // headerSize — 노드까지
        out.append(ZipFixture.le32(UInt32(size)))
        out.append(ZipFixture.le32(1))               // lineNumber
        out.append(ZipFixture.le32(0xFFFF_FFFF))     // comment
        out.append(ZipFixture.le32(0xFFFF_FFFF))     // ns
        out.append(ZipFixture.le32(nameIndex))
        out.append(ZipFixture.le16(20))              // attributeStart (attrExt 기준)
        out.append(ZipFixture.le16(20))              // attributeSize
        out.append(ZipFixture.le16(UInt16(attributes.count)))
        out.append(ZipFixture.le16(0))               // idIndex
        out.append(ZipFixture.le16(0))               // classIndex
        out.append(ZipFixture.le16(0))               // styleIndex
        for a in attributes {
            out.append(ZipFixture.le32(0xFFFF_FFFF)) // ns
            out.append(ZipFixture.le32(a.name))
            out.append(ZipFixture.le32(a.raw))
            out.append(ZipFixture.le16(8))           // Res_value.size
            out.append(0)                            // res0
            out.append(a.type)
            out.append(ZipFixture.le32(a.data))
        }
        return out
    }

    /// END_ELEMENT — 파서는 이름을 읽지 않고 스택만 되감는다
    static func endElement(nameIndex: UInt32) -> Data {
        var out = Data()
        out.append(ZipFixture.le16(0x0103))
        out.append(ZipFixture.le16(16))
        out.append(ZipFixture.le32(24))
        out.append(ZipFixture.le32(1))               // lineNumber
        out.append(ZipFixture.le32(0xFFFF_FFFF))     // comment
        out.append(ZipFixture.le32(0xFFFF_FFFF))     // ns
        out.append(ZipFixture.le32(nameIndex))
        return out
    }
}

struct AndroidBinaryXMLTests {
    @Test func parsesPackageVersionAndIcon() throws {
        let info = try #require(AndroidBinaryXML.parse(AXMLFixture.build()))
        #expect(info.packageName == "com.example.app")
        #expect(info.versionName == "1.2.3")
        #expect(info.versionCode == 42)
        #expect(info.iconResId == 0x7F02_0001)
    }

    @Test func returnsNilForGarbage() {
        #expect(AndroidBinaryXML.parse(Data()) == nil)
        #expect(AndroidBinaryXML.parse(Data("plain text".utf8)) == nil)
        #expect(AndroidBinaryXML.parse(Data(repeating: 0, count: 64)) == nil)
    }

    /// 잘린 버퍼 — 크래시 없이 물러나야 한다 (아이콘은 타일로 폴백)
    @Test func toleratesTruncatedChunks() {
        let full = AXMLFixture.build()
        for cut in [8, 20, 40, full.count / 2, full.count - 1] {
            _ = AndroidBinaryXML.parse(full.prefix(cut))
        }
    }
}

// MARK: - 리소스 값 · 아이콘 후보 · 벡터 경로

/// 테스트용 AXML — 벡터 드로어블 한 장(색·실수·문자열 속성).
private enum VectorFixture {
    static func build() -> Data {
        let strings = [
            "vector", "viewportWidth", "viewportHeight",
            "path", "pathData", "fillColor",
            "M0,0L10,0L10,10Z"
        ]
        var chunks = Data()
        chunks.append(AXMLFixture.stringPool(strings))
        chunks.append(AXMLFixture.startElement(
            nameIndex: 0,
            attributes: [
                (name: 1, raw: 0xFFFF_FFFF, type: 0x04, data: floatBits(24)),
                (name: 2, raw: 0xFFFF_FFFF, type: 0x04, data: floatBits(24))
            ]
        ))
        chunks.append(AXMLFixture.startElement(
            nameIndex: 3,
            attributes: [
                (name: 4, raw: 0xFFFF_FFFF, type: 0x03, data: 6),
                (name: 5, raw: 0xFFFF_FFFF, type: 0x1c, data: 0xFFFF_0000)
            ]
        ))
        chunks.append(AXMLFixture.endElement(nameIndex: 3))
        chunks.append(AXMLFixture.endElement(nameIndex: 0))

        var out = Data()
        out.append(ZipFixture.le16(0x0003))
        out.append(ZipFixture.le16(8))
        out.append(ZipFixture.le32(UInt32(8 + chunks.count)))
        out.append(chunks)
        return out
    }

    private static func floatBits(_ value: Float) -> UInt32 {
        value.bitPattern
    }
}

struct ResourceValueTests {
    @Test func decodesScalarTypes() {
        #expect(ResourceValue.decode(type: 0x01, data: 0x7F02_0001, strings: []) == .reference(0x7F02_0001))
        #expect(ResourceValue.decode(type: 0x01, data: 0, strings: []) == nil)
        #expect(ResourceValue.decode(type: 0x03, data: 1, strings: ["a", "b"]) == .text("b"))
        #expect(ResourceValue.decode(type: 0x03, data: 5, strings: ["a"]) == nil)
        #expect(ResourceValue.decode(type: 0x10, data: 0xFFFF_FFFF, strings: []) == .integer(-1))
        #expect(ResourceValue.decode(type: 0x12, data: 1, strings: []) == .integer(1))
        #expect(ResourceValue.decode(type: 0x04, data: Float(1.5).bitPattern, strings: []) == .float(1.5))
        // 차원: mantissa 0x500 → 1280/256 = 5.0
        #expect(ResourceValue.decode(type: 0x05, data: 0x0000_0500, strings: []) == .dimension(5))
        #expect(ResourceValue.decode(type: 0x00, data: 0, strings: []) == nil)
    }

    @Test func decodesColorTypes() {
        #expect(ResourceValue.decode(type: 0x1c, data: 0x80FF_0000, strings: []) == .color(0x80FF_0000))
        #expect(ResourceValue.decode(type: 0x1d, data: 0x00FF_0000, strings: []) == .color(0xFFFF_0000))
        // ARGB4: a=8 r=F g=0 b=0
        #expect(ResourceValue.decode(type: 0x1e, data: 0x8F00, strings: []) == .color(0x88FF_0000))
        // RGB4: r=1 g=2 b=3
        #expect(ResourceValue.decode(type: 0x1f, data: 0x0123, strings: []) == .color(0xFF11_2233))
    }
}

struct ResourceTableOffsetTests {
    @Test func readsPlainOffsetTable() {
        var bytes = [UInt8](repeating: 0, count: 32)
        writeU32(&bytes, 8, 40)                    // index 0
        writeU32(&bytes, 12, 0xFFFF_FFFF)          // index 1 = 없음
        writeU32(&bytes, 16, 64)                   // index 2
        #expect(AndroidResourceTable.entryOffset(
            bytes, at: 0, headerSize: 8, typeFlags: 0,
            entryCount: 3, index: 0, limit: bytes.count
        ) == 40)
        #expect(AndroidResourceTable.entryOffset(
            bytes, at: 0, headerSize: 8, typeFlags: 0,
            entryCount: 3, index: 1, limit: bytes.count
        ) == nil)
        #expect(AndroidResourceTable.entryOffset(
            bytes, at: 0, headerSize: 8, typeFlags: 0,
            entryCount: 3, index: 2, limit: bytes.count
        ) == 64)
    }

    @Test func readsOffset16Table() {
        var bytes = [UInt8](repeating: 0, count: 24)
        writeU16(&bytes, 8, 10)                    // 10 * 4 = 40
        writeU16(&bytes, 10, 0xFFFF)               // 없음
        #expect(AndroidResourceTable.entryOffset(
            bytes, at: 0, headerSize: 8, typeFlags: 0x02,
            entryCount: 2, index: 0, limit: bytes.count
        ) == 40)
        #expect(AndroidResourceTable.entryOffset(
            bytes, at: 0, headerSize: 8, typeFlags: 0x02,
            entryCount: 2, index: 1, limit: bytes.count
        ) == nil)
    }

    /// 구글 포토 실측 — 희소 표에서 `entryCount` 는 **쌍의 개수**이고
    /// 엔트리 인덱스(예: 4, 7)는 그보다 클 수 있다.
    @Test func readsSparseTableByIndexBeyondCount() {
        var bytes = [UInt8](repeating: 0, count: 24)
        writeU16(&bytes, 8, 7); writeU16(&bytes, 10, 3)      // index 7 → 12
        writeU16(&bytes, 12, 2); writeU16(&bytes, 14, 5)     // index 2 → 20
        #expect(AndroidResourceTable.entryOffset(
            bytes, at: 0, headerSize: 8, typeFlags: 0x01,
            entryCount: 2, index: 7, limit: bytes.count
        ) == 12)
        #expect(AndroidResourceTable.entryOffset(
            bytes, at: 0, headerSize: 8, typeFlags: 0x01,
            entryCount: 2, index: 2, limit: bytes.count
        ) == 20)
        #expect(AndroidResourceTable.entryOffset(
            bytes, at: 0, headerSize: 8, typeFlags: 0x01,
            entryCount: 2, index: 0, limit: bytes.count
        ) == nil)
    }

    private func writeU16(_ bytes: inout [UInt8], _ offset: Int, _ value: UInt16) {
        bytes[offset] = UInt8(value & 0xFF)
        bytes[offset + 1] = UInt8(value >> 8)
    }

    private func writeU32(_ bytes: inout [UInt8], _ offset: Int, _ value: UInt32) {
        bytes[offset] = UInt8(value & 0xFF)
        bytes[offset + 1] = UInt8((value >> 8) & 0xFF)
        bytes[offset + 2] = UInt8((value >> 16) & 0xFF)
        bytes[offset + 3] = UInt8((value >> 24) & 0xFF)
    }
}

struct IconCandidateTests {
    @Test func pickPrefersBitmapOverAdaptiveXML() {
        let candidates = [
            AndroidResourceTable.Candidate(path: "res/mipmap-xxhdpi/ic.png", density: 480),
            AndroidResourceTable.Candidate(path: "res/mipmap-anydpi-v26/ic.xml", density: 65534)
        ]
        #expect(AndroidResourceTable.pick(candidates, targetDensity: 480) == "res/mipmap-xxhdpi/ic.png")
    }

    @Test func pickFallsBackToVectorXML() {
        #expect(AndroidResourceTable.pick(
            [AndroidResourceTable.Candidate(path: "res/6TY.xml", density: 65534)],
            targetDensity: 480
        ) == "res/6TY.xml")
    }

    /// 네이버 웨일 레이어 — 확장자 없는 난독화 엔트리도 후보로 인정해야 한다
    @Test func pickAcceptsEntriesWithoutExtension() {
        let candidates = [
            AndroidResourceTable.Candidate(path: "res/4jn", density: 240),
            AndroidResourceTable.Candidate(path: "res/H9N", density: 320)
        ]
        #expect(AndroidResourceTable.pick(candidates, targetDensity: 480) == "res/H9N")
    }

    @Test func parsesHexColors() {
        #expect(APKIconRenderer.parseColor("#fff") == 0xFFFF_FFFF)
        #expect(APKIconRenderer.parseColor("#80ff0000") == 0x80FF_0000)
        #expect(APKIconRenderer.parseColor("#123456") == 0xFF12_3456)
        #expect(APKIconRenderer.parseColor("red") == nil)
        #expect(APKIconRenderer.parseColor("#12") == nil)
    }
}

struct SVGPathTests {
    @Test func absoluteCommandsBoundingBox() throws {
        let path = try #require(SVGPath.cgPath("M0,0 L10,0 L10,10 Z"))
        let box = path.boundingBoxOfPath
        #expect(abs(box.width - 10) < 0.01)
        #expect(abs(box.height - 10) < 0.01)
    }

    @Test func relativeCommandsBoundingBox() throws {
        let path = try #require(SVGPath.cgPath("m10,10 l5,0 l0,5 z"))
        let box = path.boundingBoxOfPath
        #expect(abs(box.minX - 10) < 0.01)
        #expect(abs(box.minY - 10) < 0.01)
        #expect(abs(box.width - 5) < 0.01)
        #expect(abs(box.height - 5) < 0.01)
    }

    @Test func implicitLineToAfterMove() throws {
        let path = try #require(SVGPath.cgPath("M0,0 10,0 10,10Z"))
        let box = path.boundingBoxOfPath
        #expect(abs(box.width - 10) < 0.01)
        #expect(abs(box.height - 10) < 0.01)
    }

    @Test func arcApproximatesSemicircle() throws {
        let path = try #require(SVGPath.cgPath("M0,0 A5,5 0 0 1 10,0"))
        let box = path.boundingBoxOfPath
        #expect(abs(box.width - 10) < 0.2)
        #expect(abs(box.height - 5) < 0.2)
    }

    @Test func cubicAndQuadraticCommands() throws {
        let cubic = try #require(SVGPath.cgPath("M0,0 C0,10 10,10 10,0"))
        #expect(abs(cubic.boundingBoxOfPath.width - 10) < 0.2)
        let quad = try #require(SVGPath.cgPath("M0,0 Q5,10 10,0"))
        #expect(abs(quad.boundingBoxOfPath.width - 10) < 0.2)
    }

    @Test func rejectsGarbage() {
        #expect(SVGPath.cgPath("") == nil)
        #expect(SVGPath.cgPath("garbage") == nil)
    }
}

struct AXMLTreeTests {
    @Test func parsesVectorTree() throws {
        let root = try #require(AndroidBinaryXML.parseTree(VectorFixture.build()))
        #expect(root.name == "vector")
        #expect(root.attribute("viewportWidth") == .float(24))
        #expect(root.attribute("viewportHeight") == .float(24))
        let child = try #require(root.children.first)
        #expect(child.name == "path")
        #expect(child.attribute("pathData") == .text("M0,0L10,0L10,10Z"))
        #expect(child.attribute("fillColor") == .color(0xFFFF_0000))
    }

    @Test func escapesWhenGarbage() {
        #expect(AndroidBinaryXML.parseTree(Data()) == nil)
        #expect(AndroidBinaryXML.parseTree(Data("not xml".utf8)) == nil)
    }
}
