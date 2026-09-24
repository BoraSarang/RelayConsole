import Foundation

/// Application Support + adb에서 읽기만 하는 MCP 데이터 원천 (MainActor 불필요)
public struct McpDataStore: Sendable {
    public var applicationSupportDir: URL
    public var adbPath: String?
    public var shellRunner: @Sendable (String, [String]) -> String?

    public init(
        applicationSupportDir: URL? = nil,
        adbPath: String? = nil,
        shellRunner: @escaping @Sendable (String, [String]) -> String? = { _, _ in nil }
    ) {
        if let applicationSupportDir {
            self.applicationSupportDir = applicationSupportDir
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.applicationSupportDir = base.appendingPathComponent("RelayConsole", isDirectory: true)
        }
        self.adbPath = adbPath ?? Self.findAdb()
        self.shellRunner = shellRunner
    }

    public static func findAdb() -> String? {
        let candidates = [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            (ProcessInfo.processInfo.environment["HOME"] ?? "") + "/Library/Android/sdk/platform-tools/adb",
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return c
        }
        // PATH 스캔
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for dir in path.split(separator: ":") {
                let c = String(dir) + "/adb"
                if FileManager.default.isExecutableFile(atPath: c) { return c }
            }
        }
        return nil
    }

    // MARK: - Store load

    public func loadSites() -> [[String: Any]] {
        decodeArray("sites.json")
    }

    public func loadJobs() -> [[String: Any]] {
        decodeArray("jobs.json")
    }

    public func loadEvents() -> [[String: Any]] {
        decodeArray("watch-events.json")
    }

    func decodeArray(_ name: String) -> [[String: Any]] {
        let url = applicationSupportDir.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return arr
    }

    // MARK: - Tools

    public func call(tool: McpToolName, arguments: McpValue) throws -> String {
        switch tool {
        case .listDevices:
            let enc = JSONEncoder()
            enc.outputFormatting = [.sortedKeys]
            let data = try enc.encode(devices())
            return String(decoding: data, as: UTF8.self)
        case .listSites:
            return try jsonString(sitesSummary())
        case .listJobs:
            return try jsonString(jobsSummary())
        case .listEvents:
            let limit = arguments["limit"]?.intValue ?? 20
            let severity = arguments["severity"]?.stringValue
            return try jsonString(eventsSummary(limit: limit, severity: severity))
        case .getSummary:
            return try jsonString(summary())
        }
    }

    func devices() throws -> [McpDevice] {
        guard let adb = adbPath else { return [] }
        let out = shellRunner(adb, ["devices", "-l"]) ?? ""
        return AdbDevicesParser.parse(out)
    }

    func sitesSummary() -> [[String: Any]] {
        loadSites().map { s in
            let history = (s["history"] as? [Any])?.count ?? 0
            let last = (s["history"] as? [[String: Any]])?.last
            return [
                "id": s["id"] as? String ?? "",
                "name": s["name"] as? String ?? "",
                "target": s["target"] as? String ?? "",
                "probe": s["probe"] as? String ?? "",
                "enabled": s["enabled"] as? Bool ?? true,
                "sslExpiresAt": s["sslExpiresAt"] as? String ?? "",
                "historyCount": history,
                "lastOk": last?["ok"] as? Bool ?? false,
                "lastAt": last?["at"] as? String ?? "",
                "lastLatencyMs": last?["latencyMs"] as? Int as Any? ?? NSNull(),
            ]
        }
    }

    func jobsSummary() -> [[String: Any]] {
        loadJobs().map { j in
            [
                "id": j["id"] as? String ?? "",
                "name": j["name"] as? String ?? "",
                "token": j["token"] as? String ?? "",
                "enabled": j["enabled"] as? Bool ?? true,
                "intervalSec": j["intervalSec"] as? Int ?? 0,
                "lastBeat": j["lastBeat"] as? String ?? "",
                "graceSec": j["graceSec"] as? Int ?? 0,
            ]
        }
    }

    func eventsSummary(limit: Int, severity: String?) -> [[String: Any]] {
        var events = loadEvents()
        if let severity {
            events = events.filter { ($0["severity"] as? String) == severity }
        }
        // 파일은 최신 우선 가정 — 안전하게 정렬 시도
        events.sort { a, b in
            let ta = a["at"] as? String ?? ""
            let tb = b["at"] as? String ?? ""
            return ta > tb
        }
        let cap = max(1, min(limit, 100))
        return Array(events.prefix(cap)).map { e in
            [
                "id": e["id"] as? String ?? "",
                "kind": e["kind"] as? String ?? "",
                "severity": e["severity"] as? String ?? "",
                "title": e["title"] as? String ?? "",
                "detail": e["detail"] as? String ?? "",
                "serial": e["serial"] as? String ?? "",
                "at": e["at"] as? String ?? "",
                "acknowledged": e["acknowledged"] as? Bool ?? false,
            ]
        }
    }

    func summary() -> [String: Any] {
        let devs = (try? devices()) ?? []
        let sites = loadSites()
        var down = 0
        for s in sites {
            let last = (s["history"] as? [[String: Any]])?.last
            if s["enabled"] as? Bool == true, last?["ok"] as? Bool == false {
                down += 1
            }
        }
        let jobs = loadJobs()
        let overdue = jobs.filter { j in
            guard j["enabled"] as? Bool == true else { return false }
            let lastBeat = j["lastBeat"] as? String ?? ""
            return lastBeat.isEmpty
        }.count
        let events = loadEvents()
        let critical = events.filter { ($0["severity"] as? String) == "critical" && ($0["acknowledged"] as? Bool) != true }.count
        let warning = events.filter { ($0["severity"] as? String) == "warning" && ($0["acknowledged"] as? Bool) != true }.count
        return [
            "deviceCount": devs.count,
            "deviceOnline": devs.filter { $0.state == "device" }.count,
            "siteCount": sites.count,
            "siteDown": down,
            "jobCount": jobs.count,
            "jobMissingBeat": overdue,
            "activeCriticalEvents": critical,
            "activeWarningEvents": warning,
            "server": McpRouter.serverName,
            "version": McpRouter.serverVersion,
        ]
    }

    func jsonString(_ value: Any) throws -> String {
        guard JSONSerialization.isValidJSONObject(value) else {
            throw McpStoreError.encodeFailed
        }
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}

public enum McpStoreError: Error, CustomStringConvertible {
    case encodeFailed

    public var description: String {
        switch self {
        case .encodeFailed: return "Failed to encode tool payload"
        }
    }
}
