import Foundation
import Testing
@testable import RelayMcpCore

struct McpProtocolTests {
    // MARK: - AdbDevicesParser

    @Test func parseAdbDevicesList() {
        let text = """
        List of devices attached
        R5CT20ABCDE            device product:beyond1q model:SM_G973F device:beyond1
        192.168.0.5:5555       device product:foo model:Pixel_7
        emulator-5554          offline
        """
        let devices = AdbDevicesParser.parse(text)
        #expect(devices.count == 3)
        #expect(devices[0].serial == "R5CT20ABCDE")
        #expect(devices[0].state == "device")
        #expect(devices[0].model == "SM G973F")
        #expect(devices[1].serial == "192.168.0.5:5555")
        #expect(devices[1].model == "Pixel 7")
        #expect(devices[2].state == "offline")
    }

    @Test func parseAdbEmpty() {
        #expect(AdbDevicesParser.parse("").isEmpty)
        #expect(AdbDevicesParser.parse("List of devices attached\n\n").isEmpty)
    }

    // MARK: - tools/list

    @Test func toolsListMatchesToolNames() {
        let tools = McpRouter.toolsList()
        let names = Set(tools.compactMap { $0["name"] as? String })
        #expect(names == Set(McpToolName.allCases.map(\.rawValue)))
        // 진단 축 도구가 함께 노출된다(읽기 전용 유지)
        #expect(names.contains("list_diagnoses"))
        #expect(names.contains("list_incidents"))
        #expect(names.contains("get_device_history"))
        for t in tools {
            #expect(t["description"] as? String != nil)
            #expect(t["inputSchema"] is [String: Any])
        }
    }

    // MARK: - initialize / ping / tools/list / unknown

    @Test func initializeHandshake() {
        let store = McpDataStore(applicationSupportDir: URL(fileURLWithPath: "/tmp/none-relay"), adbPath: nil, shellRunner: { _, _ in nil })
        let line = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#
        let out = McpRouter.handle(line: line, store: store)
        #expect(out != nil)
        #expect(out?.contains("\"protocolVersion\"") == true)
        #expect(out?.contains(McpRouter.protocolVersion) == true)
        #expect(out?.contains("\"serverInfo\"") == true)
        #expect(out?.contains("\"id\":1") == true)
    }

    @Test func pingReturnsEmptyResult() {
        let store = McpDataStore(applicationSupportDir: URL(fileURLWithPath: "/tmp/none-relay"), adbPath: nil, shellRunner: { _, _ in nil })
        let out = McpRouter.handle(line: #"{"jsonrpc":"2.0","id":"p","method":"ping"}"#, store: store)
        #expect(out?.contains("\"result\"") == true)
        #expect(out?.contains("\"id\":\"p\"") == true)
    }

    @Test func toolsListResponse() {
        let store = McpDataStore(applicationSupportDir: URL(fileURLWithPath: "/tmp/none-relay"), adbPath: nil, shellRunner: { _, _ in nil })
        let out = McpRouter.handle(line: #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#, store: store)
        #expect(out?.contains("list_devices") == true)
        #expect(out?.contains("get_summary") == true)
        #expect(out?.contains("\"tools\"") == true)
    }

    @Test func notificationInitializeInitializedIgnored() {
        let store = McpDataStore(applicationSupportDir: URL(fileURLWithPath: "/tmp/none-relay"), adbPath: nil, shellRunner: { _, _ in nil })
        let out = McpRouter.handle(
            line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
            store: store
        )
        #expect(out == nil)
    }

    @Test func unknownMethodError() {
        let store = McpDataStore(applicationSupportDir: URL(fileURLWithPath: "/tmp/none-relay"), adbPath: nil, shellRunner: { _, _ in nil })
        let out = McpRouter.handle(line: #"{"jsonrpc":"2.0","id":9,"method":"resources/list"}"#, store: store)
        #expect(out?.contains("-32601") == true)
    }

    @Test func parseErrorOnGarbage() {
        let store = McpDataStore(applicationSupportDir: URL(fileURLWithPath: "/tmp/none-relay"), adbPath: nil, shellRunner: { _, _ in nil })
        let out = McpRouter.handle(line: "not-json", store: store)
        #expect(out?.contains("-32700") == true)
    }

    @Test func unknownToolError() {
        let store = McpDataStore(applicationSupportDir: URL(fileURLWithPath: "/tmp/none-relay"), adbPath: nil, shellRunner: { _, _ in nil })
        let line = #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"nope","arguments":{}}}"#
        let out = McpRouter.handle(line: line, store: store)
        #expect(out?.contains("-32602") == true)
    }

    // MARK: - DataStore (temp fixtures)

    @Test func toolsCallDevicesEventsSummary() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("relay-mcp-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let events: [[String: Any]] = [
            ["id": "e1", "kind": "throttling", "severity": "critical", "title": "hot", "at": "2026-09-24T01:00:00Z", "acknowledged": false],
            ["id": "e2", "kind": "memoryLow", "severity": "warning", "title": "mem", "at": "2026-09-24T02:00:00Z", "acknowledged": false],
            ["id": "e3", "kind": "anr", "severity": "info", "title": "anr", "at": "2026-09-24T03:00:00Z", "acknowledged": false],
        ]
        try JSONSerialization.data(withJSONObject: events).write(to: dir.appendingPathComponent("watch-events.json"))

        let adbOut = "List of devices attached\nSERIAL1 device product:p model:Test_Phone\n"
        let store = McpDataStore(
            applicationSupportDir: dir,
            adbPath: "/usr/bin/true",
            shellRunner: { _, _ in adbOut }
        )

        let devicesJSON = try store.call(tool: .listDevices, arguments: .object([:]))
        #expect(devicesJSON.contains("SERIAL1"))
        #expect(devicesJSON.contains("Test Phone"))

        let eventsJSON = try store.call(
            tool: .listEvents,
            arguments: .object(["limit": .int(2)])
        )
        #expect(eventsJSON.contains("e3") || eventsJSON.contains("e2"))

        let sevJSON = try store.call(
            tool: .listEvents,
            arguments: .object(["severity": .string("critical")])
        )
        #expect(sevJSON.contains("throttling"))

        let sumJSON = try store.call(tool: .getSummary, arguments: .object([:]))
        #expect(sumJSON.contains("\"activeCriticalEvents\":1"))
        #expect(sumJSON.contains("\"deviceOnline\":1"))
        #expect(!sumJSON.contains("siteDown"), "사이트 집계는 제거됐다")
    }

    @Test func toolsCallViaRouter() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("relay-mcp-router-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try JSONSerialization.data(withJSONObject: [[String: Any]]()).write(to: dir.appendingPathComponent("watch-events.json"))

        let store = McpDataStore(applicationSupportDir: dir, adbPath: nil, shellRunner: { _, _ in nil })
        let line = #"{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"get_summary","arguments":{}}}"#
        let out = McpRouter.handle(line: line, store: store)
        #expect(out?.contains("\"isError\":false") == true)
        #expect(out?.contains("deviceCount") == true)
    }

    // MARK: - 진단 축 도구 (1.20.0)

    /// 테스트용 데이터 한 벌 — diagnoses · incidents · device-daily · watch-events
    private func makeDiagnosticFixture() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("relay-mcp-dx-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let diagnoses: [String: [String: [String: Any]]] = [
            "crash": [
                "A:5555:crash:com.x:OldExc": [
                    "count7d": 1, "diagnosedAt": "2026-10-01T00:00:00Z", "exception": "OldExc",
                    "fingerprint": "A:5555:crash:com.x:OldExc", "package": "com.x",
                ],
                "A:5555:crash:com.y:NewExc": [
                    "count7d": 3, "diagnosedAt": "2026-10-09T00:00:00Z", "exception": "NewExc",
                    "fingerprint": "A:5555:crash:com.y:NewExc", "package": "com.y",
                ],
                "B:5555:crash:com.z:Exc": [
                    "count7d": 1, "diagnosedAt": "2026-10-05T00:00:00Z", "exception": "Exc",
                    "fingerprint": "B:5555:crash:com.z:Exc", "package": "com.z",
                ],
            ],
            "throttling": [
                "A:5555:throttling": [
                    "diagnosedAt": "2026-10-07T00:00:00Z", "fingerprint": "A:5555:throttling",
                    "hotspot": true, "hotZones": ["gpu"],
                ],
            ],
        ]
        try JSONSerialization.data(withJSONObject: diagnoses).write(to: dir.appendingPathComponent("diagnoses.json"))

        let daily: [String: [String: Any]] = [
            "A:5555|20261017": [
                "serial": "A:5555", "dayKey": "20261017", "onlineMinutes": 120, "samples": 240,
                "cpuAvg": 12.3456, "cpuMax": 40.0, "memUsedPctAvg": 51.25, "batteryStartLevel": 90,
                "batteryEndLevel": 80, "netUpMB": 10.5, "netDownMB": 200.25, "crashEvents": 1,
                "anrEvents": 0, "warnEvents": 2, "criticalEvents": 1, "tempMax": 38.9,
            ],
            "A:5555|20261018": [
                "serial": "A:5555", "dayKey": "20261018", "onlineMinutes": 300, "samples": 600,
                "cpuAvg": 20.0, "crashEvents": 0, "anrEvents": 1,
            ],
            "B:5555|20261018": [
                "serial": "B:5555", "dayKey": "20261018", "onlineMinutes": 30, "cpuAvg": 5.0,
            ],
        ]
        try JSONSerialization.data(withJSONObject: daily).write(to: dir.appendingPathComponent("device-daily.json"))

        let incidents = dir.appendingPathComponent("incidents", isDirectory: true)
        for name in ["20261018-120000-crash-A-5555", "20261018-090000-anr-B-5555"] {
            let bundle = incidents.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
            let serial = name.contains("-A-") ? "A:5555" : "B:5555"
            let kind = name.contains("crash") ? "crash" : "anr"
            let manifest: [String: Any] = [
                "appVersion": "1.20.0",
                "capturedAt": "2026-10-18T12:00:00Z",
                "event": [
                    "at": "2026-10-18T11:59:59Z", "kind": kind, "serial": serial,
                    "severity": "critical", "title": "크래시 감지", "packageName": "com.x",
                ],
                "files": ["manifest.json", "logcat.txt"],
            ]
            try JSONSerialization.data(withJSONObject: manifest)
                .write(to: bundle.appendingPathComponent("manifest.json"))
            try Data(repeating: 0x41, count: 2048).write(to: bundle.appendingPathComponent("logcat.txt"))
        }

        let events: [[String: Any]] = [
            ["id": "e1", "kind": "crash", "severity": "critical", "title": "c", "serial": "A:5555", "at": "2026-10-18T10:00:00Z"],
            ["id": "e2", "kind": "throttling", "severity": "warning", "title": "t", "serial": "B:5555", "at": "2026-10-18T09:00:00Z"],
        ]
        try JSONSerialization.data(withJSONObject: events).write(to: dir.appendingPathComponent("watch-events.json"))
        return dir
    }

    @Test func fingerprintSerialParsing() {
        #expect(McpDataStore.fingerprintSerial("192.168.86.30:5555:crash:com.x:Exc", kind: "crash") == "192.168.86.30:5555")
        #expect(McpDataStore.fingerprintSerial("A:5555:throttling", kind: "throttling") == "A:5555")
        #expect(McpDataStore.fingerprintSerial("no-kind-here", kind: "crash") == "")
    }

    @Test func listDiagnosesFiltersAndSorts() throws {
        let dir = try makeDiagnosticFixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = McpDataStore(applicationSupportDir: dir, adbPath: nil, shellRunner: { _, _ in nil })

        let all = try store.call(tool: .listDiagnoses, arguments: .object([:]))
        #expect(all.contains("NewExc"))
        #expect(all.contains("throttling"))
        // 최신순 — 첫 항목이 가장 최근 진단(2026-10-09)
        #expect(all.range(of: "NewExc")!.lowerBound < all.range(of: "OldExc")!.lowerBound)

        let crashes = try store.call(tool: .listDiagnoses, arguments: .object(["kind": .string("crash")]))
        #expect(!crashes.contains("throttling"))

        let serialOnly = try store.call(tool: .listDiagnoses, arguments: .object(["serial": .string("B:5555")]))
        #expect(serialOnly.contains("B:5555"))
        #expect(!serialOnly.contains("NewExc"))

        let limited = try store.call(tool: .listDiagnoses, arguments: .object(["limit": .int(1)]))
        #expect(limited.contains("NewExc"))
        #expect(!limited.contains("OldExc"))
    }

    @Test func listIncidentsReadsManifests() throws {
        let dir = try makeDiagnosticFixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = McpDataStore(applicationSupportDir: dir, adbPath: nil, shellRunner: { _, _ in nil })

        let all = try store.call(tool: .listIncidents, arguments: .object([:]))
        #expect(all.contains("20261018-120000-crash-A-5555"))
        // 번들 크기는 매니페스트가 나열한 파일 합 — logcat.txt(2048B) + manifest.json
        let bundle = dir.appendingPathComponent("incidents/20261018-120000-crash-A-5555", isDirectory: true)
        #expect(McpDataStore.bundleSize(bundle, files: ["logcat.txt"]) == 2048)
        #expect(all.contains("\"sizeBytes\":"))
        // 최신 번들이 먼저
        #expect(all.range(of: "120000")!.lowerBound < all.range(of: "090000")!.lowerBound)

        let anr = try store.call(tool: .listIncidents, arguments: .object(["kind": .string("anr")]))
        #expect(anr.contains("090000"))
        #expect(!anr.contains("120000"))

        let other = try store.call(tool: .listIncidents, arguments: .object(["serial": .string("A:5555")]))
        #expect(other.contains("120000"))
        #expect(!other.contains("090000"))
    }

    @Test func deviceHistoryKeepsNewestDaysPerDevice() throws {
        let dir = try makeDiagnosticFixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = McpDataStore(applicationSupportDir: dir, adbPath: nil, shellRunner: { _, _ in nil })

        let oneDay = try store.call(tool: .getDeviceHistory, arguments: .object(["days": .int(1)]))
        #expect(oneDay.contains("20261018"))
        #expect(!oneDay.contains("20261017"))

        let week = try store.call(tool: .getDeviceHistory, arguments: .object(["serial": .string("A:5555")]))
        #expect(week.contains("20261017"))
        #expect(!week.contains("B:5555"))
        // 오래된 → 최신 순(추세 읽기) · 수치는 소수 1자리로 반올림
        #expect(week.range(of: "20261017")!.lowerBound < week.range(of: "20261018")!.lowerBound)
        #expect(week.contains("\"cpuAvg\":12.3"))
        #expect(week.contains("\"netDownMB\":200.3"))
    }

    @Test func listEventsSerialFilter() throws {
        let dir = try makeDiagnosticFixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = McpDataStore(applicationSupportDir: dir, adbPath: nil, shellRunner: { _, _ in nil })

        let onlyB = try store.call(tool: .listEvents, arguments: .object(["serial": .string("B:5555")]))
        #expect(onlyB.contains("B:5555"))
        #expect(!onlyB.contains("A:5555"))
    }

    @Test func summaryCountsDiagnosesAndBundles() throws {
        let dir = try makeDiagnosticFixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = McpDataStore(applicationSupportDir: dir, adbPath: nil, shellRunner: { _, _ in nil })

        let summary = try store.call(tool: .getSummary, arguments: .object([:]))
        #expect(summary.contains("\"diagnosedCrashes\":3"))
        #expect(summary.contains("\"incidentBundles\":2"))
    }

    @Test func diagnosticToolsViaRouter() throws {
        let dir = try makeDiagnosticFixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = McpDataStore(applicationSupportDir: dir, adbPath: nil, shellRunner: { _, _ in nil })

        let line = #"{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"list_diagnoses","arguments":{"kind":"crash"}}}"#
        let out = McpRouter.handle(line: line, store: store)
        #expect(out?.contains("\"isError\":false") == true)
        #expect(out?.contains("NewExc") == true)

        let incidents = McpRouter.handle(
            line: #"{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"list_incidents","arguments":{}}}"#,
            store: store
        )
        #expect(incidents?.contains("20261018-120000-crash-A-5555") == true)
    }
}
