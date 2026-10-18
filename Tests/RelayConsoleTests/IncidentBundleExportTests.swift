import Foundation
import Testing
@testable import RelayConsole

/// 번들 내보내기 — 실제 임시 디렉터리로 복사 동작을 검증한다
struct IncidentBundleExportTests {
    /// 임시 번들 디렉터리 — manifest + 로그 + 스크린샷 구성
    private func makeBundle(_ files: [String: String]) throws -> (entry: IncidentBundleEntry, url: URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("relay-export-src-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for (name, body) in files {
            try Data(body.utf8).write(to: url.appendingPathComponent(name))
        }
        let entry = IncidentBundleEntry(
            id: url.lastPathComponent,
            url: url,
            createdAt: .now,
            hasLogcat: files["logcat.txt"] != nil,
            hasCrashLogcat: files["crash-logcat.txt"] != nil,
            hasScreenshot: files["screenshot.png"] != nil
        )
        return (entry, url)
    }

    private func makeDestination() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("relay-export-dst-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func copiesEveryFileAndReturnsNames() throws {
        let (entry, source) = try makeBundle([
            "manifest.json": "{\"schema\":2}",
            "logcat.txt": "log line",
            "dropbox.txt": "dropbox line",
            "screenshot.png": "pngbytes",
        ])
        let dest = makeDestination()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: dest)
        }

        let copied = try IncidentBundleExport.export(entry: entry, to: dest)
        #expect(copied == ["dropbox.txt", "logcat.txt", "manifest.json", "screenshot.png"])
        // 내용까지 그대로 (재인코딩 없음)
        let manifest = try String(contentsOf: dest.appendingPathComponent("manifest.json"), encoding: .utf8)
        #expect(manifest == "{\"schema\":2}")
        #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent("screenshot.png").path))
    }

    @Test func originalBundleIsLeftIntact() throws {
        let (entry, source) = try makeBundle(["manifest.json": "{}"])
        let dest = makeDestination()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: dest)
        }
        _ = try IncidentBundleExport.export(entry: entry, to: dest)
        // 내보내기는 **사본**이다 — 사본을 지워도 원본이 남아야 한다(감시 이력 보존)
        try FileManager.default.removeItem(at: dest)
        #expect(FileManager.default.fileExists(atPath: source.appendingPathComponent("manifest.json").path))
    }

    @Test func existingDestinationIsNotOverwritten() throws {
        let (entry, source) = try makeBundle(["manifest.json": "{}"])
        let dest = makeDestination()
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: dest)
        }
        #expect(throws: IncidentBundleExport.Failure.destinationExists) {
            try IncidentBundleExport.export(entry: entry, to: dest)
        }
    }

    @Test func emptyBundleThrowsNoFiles() throws {
        let (entry, source) = try makeBundle([:])
        let dest = makeDestination()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: dest)
        }
        #expect(throws: IncidentBundleExport.Failure.noFiles) {
            try IncidentBundleExport.export(entry: entry, to: dest)
        }
        #expect(!FileManager.default.fileExists(atPath: dest.path))
    }

    @Test func hiddenFilesAreSkipped() throws {
        let (entry, source) = try makeBundle([
            "manifest.json": "{}",
            ".DS_Store": "junk",
        ])
        let dest = makeDestination()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: dest)
        }
        let copied = try IncidentBundleExport.export(entry: entry, to: dest)
        #expect(copied == ["manifest.json"])
    }
}
