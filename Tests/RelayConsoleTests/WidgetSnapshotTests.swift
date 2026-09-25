import XCTest
import Foundation
@testable import RelayConsole
import RelayWidgetCore

final class WidgetSnapshotTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func android(
        serial: String,
        online: Bool = true,
        battery: Int? = 80,
        charging: Bool? = false,
        connectionKind: ConnectionKind? = .usb,
        connectionLabel: String? = nil
    ) -> DeviceSnapshot {
        var d = DeviceSnapshot()
        d.serial = serial
        d.model = "S22"
        d.deviceName = "S22"
        d.isOnline = online
        d.connectionKind = connectionKind
        d.connectionLabel = connectionLabel
        d.batteryLevel = battery
        d.isCharging = charging
        return d
    }

    private func build(
        briefing: String? = nil,
        android: [DeviceSnapshot] = [],
        apple: [AppleSnapshot] = [],
        selectedSerial: String? = nil,
        selectedAppleUdid: String? = nil,
        sites: [Site] = [],
        jobs: [Job] = [],
        events: [WatchEvent] = []
    ) -> WidgetSnapshot {
        WidgetSnapshotBuilder.build(
            briefing: briefing,
            android: android,
            apple: apple,
            selectedSerial: selectedSerial,
            selectedAppleUdid: selectedAppleUdid,
            sites: sites,
            jobs: jobs,
            events: events,
            ident: { serial in
                if serial.hasPrefix("IP:") { return String(serial.dropFirst(3)) }
                return "LABEL·\(serial)"
            },
            now: now
        )
    }

    // MARK: - 모델 · 톤

    func testToneRules() {
        XCTAssertEqual(WidgetSnapshot().tone, .ok)
        XCTAssertEqual(WidgetSnapshot(critical: 1).tone, .bad)
        XCTAssertEqual(WidgetSnapshot(siteDown: 1).tone, .warn)
        XCTAssertEqual(WidgetSnapshot(jobsOverdue: 1).tone, .warn)
        XCTAssertEqual(WidgetSnapshot(critical: 1, siteDown: 1).tone, .bad)
    }

    func testIsEmpty() {
        XCTAssertTrue(WidgetSnapshot().isEmpty)
        XCTAssertFalse(WidgetSnapshot(critical: 1).isEmpty)
        XCTAssertFalse(WidgetSnapshot(devices: [
            WidgetDevice(ident: "A", online: true)
        ]).isEmpty)
    }

    func testCodableRoundTrip() throws {
        let snapshot = build(
            briefing: "3/4 사이트 · 0 지연 작업 · 1/1 폰 · critical 0",
            android: [android(serial: "192.168.0.5:5555", connectionKind: .network, connectionLabel: "192.168.0.5:5555")],
            selectedSerial: "192.168.0.5:5555",
            sites: [Site(name: "api", target: "https://a", probe: .http, history: [SiteCheck(at: now, ok: true)])],
            events: [WatchEvent(kind: .throttling, severity: .critical, serial: "R5CT", title: "T", detail: "D", at: now)]
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.schema, WidgetSnapshot.currentSchema)
    }

    // MARK: - Builder ([표시①] ident · 캡 · 집계)

    func testDeviceIdentUsesLabelNotMasking() {
        let network = android(
            serial: "192.168.0.5:5555",
            connectionKind: .network,
            connectionLabel: "192.168.0.5:5555"
        )
        let snapshot = build(android: [network])
        XCTAssertEqual(snapshot.devices.first?.ident, "192.168.0.5:5555")
        // 마스킹 금지 — Wi-Fi 기기 구분 가능해야 함 ([표시①])
        XCTAssertFalse(snapshot.devices.contains { $0.ident.contains("…") })
    }

    func testEventIdentResolvedAndSerialNotStored() {
        let events = [WatchEvent(kind: .memoryLow, severity: .warning, serial: "RAW-SERIAL-1234", title: "메모리", detail: "d", at: now)]
        let snapshot = build(events: events)
        XCTAssertEqual(snapshot.events.first?.ident, "LABEL·RAW-SERIAL-1234")
        // 원본 serial 필드는 스냅샷에 없음 — 표시는 identLabel만 ([표시①])
        XCTAssertFalse(snapshot.events.first?.ident.isEmpty ?? true)
    }

    func testSelectedDeviceFirstAndCapFour() {
        var devices = (0..<5).map { android(serial: "S\($0)") }
        devices[3] = android(serial: "S3")
        let snapshot = build(
            android: devices,
            apple: [makeApple(udid: "APPLE-1")],
            selectedSerial: "S3"
        )
        XCTAssertEqual(snapshot.devices.count, WidgetSnapshotBuilder.maxDevices)
        XCTAssertEqual(snapshot.devices.first?.ident.contains("S3"), true)
        XCTAssertFalse(snapshot.devices.contains { $0.ident.contains("APPLE-1") })
    }

    func testSelectedAppleDeviceFirst() {
        let snapshot = build(
            android: [android(serial: "S0")],
            apple: [makeApple(udid: "AP1"), makeApple(udid: "AP2")],
            selectedAppleUdid: "AP2"
        )
        XCTAssertTrue(snapshot.devices.first?.ident.contains("AP2") ?? false)
        XCTAssertEqual(snapshot.devices.count, 3)
    }

    func testSiteStateAndUptime() {
        let upSite = Site(name: "up", target: "https://u", probe: .http, failThreshold: 1, history: [
            SiteCheck(at: now.addingTimeInterval(-3600), ok: true)
        ])
        let downSite = Site(name: "down", target: "https://d", probe: .http, failThreshold: 1, history: [
            SiteCheck(at: now.addingTimeInterval(-3600), ok: false)
        ])
        let unknownSite = Site(name: "new", target: "https://n", probe: .http)
        let disabled = Site(name: "off", target: "https://o", probe: .http, enabled: false)
        let snapshot = build(sites: [upSite, downSite, unknownSite, disabled])

        XCTAssertEqual(snapshot.siteTotal, 3)
        XCTAssertEqual(snapshot.siteUp, 1)
        XCTAssertEqual(snapshot.siteDown, 1)
        XCTAssertEqual(snapshot.sites.map(\.name), ["up", "down", "new"])
        XCTAssertEqual(snapshot.sites.map(\.state), [.up, .down, .unknown])
        // 7d 가동률: 1건 전부 성공 → 100
        XCTAssertEqual(snapshot.sites[0].uptime7dPct ?? 0, 100.0, accuracy: 0.01)
        // 미측정 사이트는 nil ([표시②] 0으로 뭉뚱그리지 않음)
        XCTAssertNil(snapshot.sites[2].uptime7dPct)
    }

    func testJobsOverdueCountExcludesDisabled() {
        let overdue = Job(name: "late", expectEverySec: 30, lastBeatAt: nil, enabled: true, createdAt: now.addingTimeInterval(-100))
        let fine = Job(name: "ok", expectEverySec: 3600, lastBeatAt: now, enabled: true, createdAt: now)
        let off = Job(name: "off", expectEverySec: 30, lastBeatAt: nil, enabled: false, createdAt: now.addingTimeInterval(-100))
        let snapshot = build(jobs: [overdue, fine, off])
        XCTAssertEqual(snapshot.jobsTotal, 2)
        XCTAssertEqual(snapshot.jobsOverdue, 1)
    }

    func testEventsCapThreeAndCriticalCount() {
        let events = (0..<5).map {
            WatchEvent(kind: .throttling, severity: .critical, serial: "S\($0)", title: "e\($0)", detail: "d", at: now.addingTimeInterval(Double($0)))
        }
        let snapshot = build(events: events)
        XCTAssertEqual(snapshot.events.count, WidgetSnapshotBuilder.maxEvents)
        // critical 미해결 = 5 (clear 없음) — 메뉴바 배지와 동일 산식
        XCTAssertEqual(snapshot.critical, 5)
    }

    func testCriticalClearedByClearEvent() {
        let open = WatchEvent(kind: .throttling, severity: .critical, serial: "S1", title: "hot", detail: "d", at: now)
        let clear = WatchEvent(kind: .throttling, severity: .critical, serial: "S1", title: "ok", detail: "d", at: now.addingTimeInterval(10), isClear: true)
        // 최신이 위(인덱스 작음) — clear가 open보다 앞에 오는 정렬
        let snapshot = build(events: [clear, open])
        XCTAssertEqual(snapshot.critical, 0)
    }

    func testBriefingPassthrough() {
        let snapshot = build(briefing: "3/4 사이트 · 1 지연 작업 · 1/1 폰 · critical 2")
        XCTAssertEqual(snapshot.briefing, "3/4 사이트 · 1 지연 작업 · 1/1 폰 · critical 2")
        let none = build()
        XCTAssertNil(none.briefing)
    }

    // MARK: - Store (App Group 파일)

    func testStoreWriteReadRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("relay-widget-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let snapshot = build(briefing: "줄", android: [android(serial: "S1")], selectedSerial: "S1")
        XCTAssertTrue(WidgetSnapshotStore.write(snapshot, baseDir: dir))
        XCTAssertEqual(WidgetSnapshotStore.read(baseDir: dir), snapshot)
    }

    func testStoreReadMissingFileReturnsNil() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("relay-widget-missing-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertNil(WidgetSnapshotStore.read(baseDir: dir))
    }

    func testStoreReadCorruptedReturnsNil() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("relay-widget-corrupt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: WidgetSnapshotStore.fileURL(in: dir))
        XCTAssertNil(WidgetSnapshotStore.read(baseDir: dir))
    }

    func testStoreReadFutureSchemaReturnsNil() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("relay-widget-schema-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var dict = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: JSONEncoder().encode(build())
            ) as? [String: Any]
        )
        dict["schema"] = WidgetSnapshot.currentSchema + 1
        try JSONSerialization.data(withJSONObject: dict).write(to: WidgetSnapshotStore.fileURL(in: dir))
        XCTAssertNil(WidgetSnapshotStore.read(baseDir: dir))
    }

    func testStoreKindMatchesWidgetRegistration() {
        XCTAssertEqual(WidgetSnapshotStore.widgetKind, "RelayStatusWidget")
        XCTAssertEqual(WidgetSnapshotStore.groupID, "6GPJQ7BQC9.com.borasarang.relayconsole")
    }

    // MARK: - 위젯 i18n (en/ko 1:1 · 필수 키)

    func testWidgetL10nKeyParity() throws {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/RelayConsoleTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // 루트
            .appendingPathComponent("Sources/RelayConsole/Resources")
        func keys(_ lproj: String) throws -> Set<String> {
            let text = try String(contentsOf: base.appendingPathComponent("\(lproj).lproj/Localizable.strings"), encoding: .utf8)
            var set = Set<String>()
            for line in text.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("\"") else { continue }
                let key = trimmed.dropFirst().components(separatedBy: "\" = ").first ?? ""
                if !key.isEmpty { set.insert(key) }
            }
            return set
        }
        let ko = try keys("ko")
        let en = try keys("en")
        XCTAssertEqual(ko, en, "ko/en 키 집합 1:1 위반")

        let required = [
            "widget.name", "widget.desc", "widget.empty", "widget.updated",
            "widget.critical", "widget.overdue", "widget.ok", "widget.offline",
            "widget.summary", "widget.section.devices", "widget.section.sites",
            "widget.section.events", "widget.sites.none", "widget.sites.down",
            "widget.devices.none", "widget.events.none", "widget.jobs.ok"
        ]
        for key in required {
            XCTAssertTrue(ko.contains(key), "widget 키 누락: \(key)")
        }
    }

    // MARK: - 도메인 헬퍼

    private func makeApple(udid: String, battery: Int? = 55) -> AppleSnapshot {
        var a = AppleSnapshot()
        a.udid = udid
        a.deviceName = "iPad"
        a.isOnline = true
        a.batteryLevel = battery
        return a
    }
}
