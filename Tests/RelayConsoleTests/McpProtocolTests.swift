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

    @Test func toolsListHasFiveReadOnlyTools() {
        let tools = McpRouter.toolsList()
        let names = Set(tools.compactMap { $0["name"] as? String })
        #expect(names == Set(McpToolName.allCases.map(\.rawValue)))
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

    @Test func toolsCallSitesJobsEventsSummary() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("relay-mcp-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let sites: [[String: Any]] = [
            [
                "id": "s1",
                "name": "API",
                "target": "https://example.com",
                "probe": "http",
                "enabled": true,
                "history": [["ok": false, "at": "2026-09-24T00:00:00Z"]],
            ],
        ]
        let jobs: [[String: Any]] = [
            ["id": "j1", "name": "backup", "enabled": true, "lastBeat": "", "intervalSec": 60],
        ]
        let events: [[String: Any]] = [
            ["id": "e1", "kind": "siteDown", "severity": "critical", "title": "down", "at": "2026-09-24T01:00:00Z", "acknowledged": false],
            ["id": "e2", "kind": "throttling", "severity": "warning", "title": "hot", "at": "2026-09-24T02:00:00Z", "acknowledged": false],
            ["id": "e3", "kind": "anr", "severity": "info", "title": "anr", "at": "2026-09-24T03:00:00Z", "acknowledged": false],
        ]
        try JSONSerialization.data(withJSONObject: sites).write(to: dir.appendingPathComponent("sites.json"))
        try JSONSerialization.data(withJSONObject: jobs).write(to: dir.appendingPathComponent("jobs.json"))
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

        let sitesJSON = try store.call(tool: .listSites, arguments: .object([:]))
        #expect(sitesJSON.contains("API"))
        #expect(sitesJSON.contains("\"lastOk\":false"))

        let jobsJSON = try store.call(tool: .listJobs, arguments: .object([:]))
        #expect(jobsJSON.contains("backup"))

        let eventsJSON = try store.call(
            tool: .listEvents,
            arguments: .object(["limit": .int(2)])
        )
        #expect(eventsJSON.contains("e3") || eventsJSON.contains("e2"))

        let sevJSON = try store.call(
            tool: .listEvents,
            arguments: .object(["severity": .string("critical")])
        )
        #expect(sevJSON.contains("siteDown"))

        let sumJSON = try store.call(tool: .getSummary, arguments: .object([:]))
        #expect(sumJSON.contains("\"siteDown\":1"))
        #expect(sumJSON.contains("\"activeCriticalEvents\":1"))
        #expect(sumJSON.contains("\"deviceOnline\":1"))
    }

    @Test func toolsCallViaRouter() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("relay-mcp-router-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try JSONSerialization.data(withJSONObject: [[String: Any]]()).write(to: dir.appendingPathComponent("sites.json"))
        try JSONSerialization.data(withJSONObject: [[String: Any]]()).write(to: dir.appendingPathComponent("jobs.json"))
        try JSONSerialization.data(withJSONObject: [[String: Any]]()).write(to: dir.appendingPathComponent("watch-events.json"))

        let store = McpDataStore(applicationSupportDir: dir, adbPath: nil, shellRunner: { _, _ in nil })
        let line = #"{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"get_summary","arguments":{}}}"#
        let out = McpRouter.handle(line: line, store: store)
        #expect(out?.contains("\"isError\":false") == true)
        #expect(out?.contains("deviceCount") == true)
    }
}
