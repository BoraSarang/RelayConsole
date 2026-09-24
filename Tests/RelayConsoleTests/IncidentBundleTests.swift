import Foundation
import Testing
@testable import RelayConsole

struct IncidentBundleTests {
    // MARK: - captures

    @Test func capturesOnlyAnrCrashSiteDown() {
        #expect(IncidentBundleLogic.captures(kind: .anr))
        #expect(IncidentBundleLogic.captures(kind: .crash))
        #expect(IncidentBundleLogic.captures(kind: .siteDown))
        #expect(!IncidentBundleLogic.captures(kind: .siteUp))
        #expect(!IncidentBundleLogic.captures(kind: .throttling))
        #expect(!IncidentBundleLogic.captures(kind: .sslExpiring))
        #expect(!IncidentBundleLogic.captures(kind: .jobOverdue))
        #expect(!IncidentBundleLogic.captures(kind: .chargeChanged))
    }

    // MARK: - directoryName

    @Test func directoryNameIsFilesystemSafe() {
        let e = WatchEvent(
            kind: .anr,
            severity: .critical,
            serial: "ABC123",
            title: "ANR",
            detail: ""
        )
        let cal = Calendar(identifier: .gregorian)
        let at = cal.date(from: DateComponents(
            year: 2026, month: 9, day: 24, hour: 19, minute: 59, second: 5
        ))!
        let name = IncidentBundleLogic.directoryName(event: e, at: at)
        #expect(name == "20260924-195905-anr-…C123" || name.hasPrefix("20260924-195905-anr-"))
        #expect(!name.contains("/"))
        #expect(!name.contains(":"))
    }

    @Test func directoryNameSanitizesSiteSerial() {
        let e = WatchEvent(
            kind: .siteDown,
            severity: .critical,
            serial: "site:ABC-DEF",
            title: "API",
            detail: ""
        )
        let name = IncidentBundleLogic.directoryName(
            event: e,
            at: Date(timeIntervalSince1970: 0)
        )
        #expect(name.contains("siteDown"))
        #expect(name.allSatisfy { $0.isLetter || $0.isNumber || "-_.".contains($0) } || name.contains("…") == false)
        #expect(!name.contains("/"))
    }

    // MARK: - shouldAutoCapture

    @Test func firstCaptureAlwaysAllowed() {
        #expect(IncidentBundleLogic.shouldAutoCapture(fingerprint: "fp1", lastAt: [:]))
    }

    @Test func cooldownBlocksWithinFiveMinutes() {
        let now = Date()
        let last = now.addingTimeInterval(-60)
        #expect(!IncidentBundleLogic.shouldAutoCapture(
            fingerprint: "fp",
            now: now,
            lastAt: ["fp": last]
        ))
    }

    @Test func cooldownAllowsAfterFiveMinutes() {
        let now = Date()
        let last = now.addingTimeInterval(-301)
        #expect(IncidentBundleLogic.shouldAutoCapture(
            fingerprint: "fp",
            now: now,
            lastAt: ["fp": last]
        ))
    }

    @Test func cooldownIsPerFingerprint() {
        let now = Date()
        let last = now.addingTimeInterval(-10)
        #expect(IncidentBundleLogic.shouldAutoCapture(
            fingerprint: "other",
            now: now,
            lastAt: ["fp": last]
        ))
    }

    // MARK: - isAndroidSerial

    @Test func isAndroidSerialAcceptsUsbAndNetwork() {
        #expect(IncidentBundleLogic.isAndroidSerial("ABC123"))
        #expect(IncidentBundleLogic.isAndroidSerial("192.168.0.5:5555"))
        #expect(!IncidentBundleLogic.isAndroidSerial(""))
        #expect(!IncidentBundleLogic.isAndroidSerial("site:UUID"))
        #expect(!IncidentBundleLogic.isAndroidSerial("job:UUID"))
        #expect(!IncidentBundleLogic.isAndroidSerial("TEST"))
        #expect(!IncidentBundleLogic.isAndroidSerial(String(repeating: "a", count: 40)))
    }

    // MARK: - manifestData

    @Test func manifestEncodesEventAndFiles() throws {
        let e = WatchEvent(
            kind: .crash,
            severity: .critical,
            serial: "XYZ",
            title: "크래시 감지",
            detail: "hits 2"
        )
        let data = try #require(IncidentBundleLogic.manifestData(
            event: e,
            appVersion: "1.7.0",
            files: ["manifest.json", "logcat.txt"]
        ))
        let obj = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(obj["appVersion"] as? String == "1.7.0")
        #expect(obj["schema"] as? Int == 1)
        let files = obj["files"] as? [String]
        #expect(files == ["manifest.json", "logcat.txt"])
        let event = try #require(obj["event"] as? [String: Any])
        #expect(event["kind"] as? String == "crash")
        #expect(event["title"] as? String == "크래시 감지")
    }

    @Test func manifestDataNeverNilForValidEvent() {
        let e = WatchEvent(kind: .siteDown, severity: .critical, serial: "site:1", title: "t", detail: "d")
        #expect(IncidentBundleLogic.manifestData(event: e, appVersion: "1.7.0") != nil)
    }

    // MARK: - listEntries

    @Test func listEntriesSortsNewestFirst() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("relay-incident-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let older = root.appendingPathComponent("20260101-000000-anr-A", isDirectory: true)
        let newer = root.appendingPathComponent("20260102-000000-crash-B", isDirectory: true)
        try FileManager.default.createDirectory(at: older, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newer, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: older.appendingPathComponent("logcat.txt"))
        try Data("x".utf8).write(to: newer.appendingPathComponent("screenshot.png"))

        // creationDate 정렬은 파일시스템 타이머 의존 — 순서 대신 집합·플래그 검증
        let entries = IncidentBundleStore.listEntries(root: root)
        #expect(entries.count == 2)
        #expect(Set(entries.map(\.id)) == Set(["20260101-000000-anr-A", "20260102-000000-crash-B"]))
        #expect(entries.first(where: { $0.id.hasSuffix("A") })?.hasLogcat == true)
        #expect(entries.first(where: { $0.id.hasSuffix("B") })?.hasScreenshot == true)
    }
}
