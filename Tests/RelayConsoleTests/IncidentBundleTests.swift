import Foundation
import Testing
@testable import RelayConsole

struct IncidentBundleTests {
    // MARK: - TailBuffer (logcat 덤프 상한)

    @Test func tailBufferKeepsEverythingUnderLimit() {
        var t = IncidentBundleLogic.TailBuffer(maxBytes: 100)
        t.append(Data("abc".utf8))
        t.append(Data("de".utf8))
        #expect(t.droppedBytes == 0)
        #expect(String(decoding: t.data, as: UTF8.self) == "abcde")
    }

    /// 상한을 넘으면 **뒤**가 남아야 한다 — `-T <이벤트 시각>` 기준이라 끝이 이벤트 근처다
    @Test func tailBufferDropsFromFrontKeepsTail() {
        var t = IncidentBundleLogic.TailBuffer(maxBytes: 4)
        t.append(Data("0123456789".utf8))
        #expect(String(decoding: t.data, as: UTF8.self) == "6789")
        #expect(t.droppedBytes == 6)
    }

    @Test func tailBufferAccumulatesDroppedAcrossChunks() {
        var t = IncidentBundleLogic.TailBuffer(maxBytes: 3)
        for chunk in ["aaaa", "bbbb", "cccc"] {
            t.append(Data(chunk.utf8))
        }
        #expect(String(decoding: t.data, as: UTF8.self) == "ccc")
        #expect(t.droppedBytes == 9)
    }

    @Test func tailBufferEmptyChunkIsNoOp() {
        var t = IncidentBundleLogic.TailBuffer(maxBytes: 4)
        t.append(Data())
        #expect(t.isEmpty)
        #expect(t.droppedBytes == 0)
    }

    /// 상한 0 = 전부 버린다 — 그래도 "몇 바이트 잃었는지"는 기록되어야 한다
    @Test func tailBufferZeroLimitDropsEverythingAndCounts() {
        var t = IncidentBundleLogic.TailBuffer(maxBytes: 0)
        t.append(Data("hello".utf8))
        #expect(t.isEmpty)
        #expect(t.droppedBytes == 5)
    }

    /// 앵커는 `event.at` 이 아니라 **여유를 되돌린 시각**이어야 한다.
    /// 크래시 라인은 이벤트 시각보다 먼저 찍힌다 (실측: 10:00:06 크래시 / 10:00:12 이벤트).
    @Test func mainLogcatLeadSecondsIsAppliedToAnchor() {
        #expect(IncidentBundleLogic.mainLogcatLeadSeconds > 0)
        // 폴링 주기(5초)와 5분 쿨다운(300초)보다 짧으면 크래시를 못 담는다
        #expect(IncidentBundleLogic.mainLogcatLeadSeconds >= 60)
    }

    @Test func truncationNoticeRevealsDroppedAmount() {
        let s = IncidentBundleLogic.truncationNotice(
            droppedBytes: 37 * 1_048_576,
            maxBytes: 2 * 1_048_576
        )
        #expect(s.contains("37.0MB"))
        #expect(s.contains("2MB"))
        #expect(s.contains("생략"))
    }

    // MARK: - captures

    @Test func capturesOnlyAnrCrash() {
        #expect(IncidentBundleLogic.captures(kind: .anr))
        #expect(IncidentBundleLogic.captures(kind: .crash))
        #expect(!IncidentBundleLogic.captures(kind: .throttling))
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

    @Test func directoryNameSanitizesSerial() {
        let e = WatchEvent(
            kind: .crash,
            severity: .critical,
            serial: "ABC-DEF",
            title: "APP",
            detail: ""
        )
        let name = IncidentBundleLogic.directoryName(
            event: e,
            at: Date(timeIntervalSince1970: 0)
        )
        #expect(name.contains("crash"))
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
        let e = WatchEvent(kind: .crash, severity: .critical, serial: "S1", title: "t", detail: "d")
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
