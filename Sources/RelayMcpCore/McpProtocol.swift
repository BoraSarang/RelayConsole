import Foundation

// MARK: - JSON-RPC 2.0

public struct McpRequest: Decodable, Sendable {
    public let jsonrpc: String
    public let id: McpId?
    public let method: String
    public let params: McpValue?
}

/// id: number | string | null
public enum McpId: Decodable, Sendable, Equatable {
    case int(Int)
    case string(String)
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let i = try? c.decode(Int.self) {
            self = .int(i)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "unsupported id")
        }
    }

    public var jsonValue: Any {
        switch self {
        case .int(let i): return i
        case .string(let s): return s
        case .null: return NSNull()
        }
    }
}

/// 최소 value — dict/string/int/bool/array/nil
public enum McpValue: Decodable, Sendable {
    case object([String: McpValue])
    case array([McpValue])
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? c.decode(Int.self) {
            self = .int(i)
        } else if let d = try? c.decode(Double.self) {
            self = .double(d)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([McpValue].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: McpValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "unsupported value")
        }
    }

    public subscript(key: String) -> McpValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var intValue: Int? {
        if case .int(let i) = self { return i }
        return nil
    }

    public var anyValue: Any {
        switch self {
        case .object(let o): return o.mapValues { $0.anyValue }
        case .array(let a): return a.map { $0.anyValue }
        case .string(let s): return s
        case .int(let i): return i
        case .double(let d): return d
        case .bool(let b): return b
        case .null: return NSNull()
        }
    }

    public static func json(_ any: Any) -> McpValue {
        let data = (try? JSONSerialization.data(withJSONObject: any, options: [.sortedKeys])) ?? Data("null".utf8)
        return (try? JSONDecoder().decode(McpValue.self, from: data)) ?? .null
    }
}

// MARK: - Router (순수 · 테스트)

public enum McpToolName: String, CaseIterable, Sendable {
    case listDevices = "list_devices"
    case listSites = "list_sites"
    case listJobs = "list_jobs"
    case listEvents = "list_events"
    case getSummary = "get_summary"
}

public enum McpRouter {
    public static let protocolVersion = "2024-11-05"
    public static let serverName = "relay-console"
    public static let serverVersion = "1.14.0"

    /// tools/list 페이로드
    public static func toolsList() -> [[String: Any]] {
        func tool(_ name: McpToolName, _ description: String, props: [String: Any] = [:], required: [String] = []) -> [String: Any] {
            var schema: [String: Any] = [
                "type": "object",
                "properties": props,
            ]
            if !required.isEmpty { schema["required"] = required }
            return [
                "name": name.rawValue,
                "description": description,
                "inputSchema": schema,
            ]
        }
        return [
            tool(.listDevices, "List Android devices visible to adb (serial, state, model when present)."),
            tool(.listSites, "List configured uptime sites with last check status, SSL expiry, and recent history size."),
            tool(.listJobs, "List heartbeat jobs with overdue flag and last beat time."),
            tool(.listEvents, "List recent watch/alert events (newest first). Optional limit and severity filter.", props: [
                "limit": ["type": "integer", "description": "Max events (1-100), default 20"],
                "severity": ["type": "string", "enum": ["info", "warning", "critical"], "description": "Filter by severity"],
            ]),
            tool(.getSummary, "Aggregate summary: device count, down sites, overdue jobs, active critical events."),
        ]
    }

    /// JSON-RPC 한 줄 → 응답 JSON 한 줄 (notification이면 nil)
    public static func handle(line: String, store: McpDataStore) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let req = try? JSONDecoder().decode(McpRequest.self, from: data)
        else {
            return encodeError(id: .null, code: -32700, message: "Parse error")
        }
        guard req.jsonrpc == "2.0" else {
            return encodeError(id: req.id ?? .null, code: -32600, message: "Invalid Request")
        }
        // notification (id 없음)
        if req.id == nil || req.id == .null {
            return nil
        }
        let id = req.id ?? .null

        switch req.method {
        case "initialize":
            let result: [String: Any] = [
                "protocolVersion": protocolVersion,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": serverName, "version": serverVersion],
            ]
            return encodeResult(id: id, result: result)
        case "ping":
            return encodeResult(id: id, result: [String: Any]())
        case "tools/list":
            return encodeResult(id: id, result: ["tools": toolsList()])
        case "tools/call":
            guard let name = req.params?["name"]?.stringValue,
                  let tool = McpToolName(rawValue: name)
            else {
                return encodeError(id: id, code: -32602, message: "Unknown tool")
            }
            let args = req.params?["arguments"] ?? .object([:])
            do {
                let payload = try store.call(tool: tool, arguments: args)
                let result: [String: Any] = [
                    "content": [
                        ["type": "text", "text": payload],
                    ],
                    "isError": false,
                ]
                return encodeResult(id: id, result: result)
            } catch {
                let result: [String: Any] = [
                    "content": [
                        ["type": "text", "text": String(describing: error)],
                    ],
                    "isError": true,
                ]
                return encodeResult(id: id, result: result)
            }
        default:
            return encodeError(id: id, code: -32601, message: "Method not found: \(req.method)")
        }
    }

    static func encodeResult(id: McpId, result: [String: Any]) -> String? {
        let obj: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id.jsonValue,
            "result": result,
        ]
        return jsonString(obj)
    }

    static func encodeError(id: McpId, code: Int, message: String) -> String? {
        let obj: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id.jsonValue,
            "error": ["code": code, "message": message],
        ]
        return jsonString(obj)
    }

    static func jsonString(_ obj: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - ADB devices 파서

public struct McpDevice: Codable, Equatable, Sendable {
    public let serial: String
    public let state: String
    public var model: String?
    public var product: String?

    public init(serial: String, state: String, model: String? = nil, product: String? = nil) {
        self.serial = serial
        self.state = state
        self.model = model
        self.product = product
    }
}

public enum AdbDevicesParser {
    /// `adb devices -l` 출력 → 기기 목록 (헤더·빈 줄 제외)
    public static func parse(_ text: String) -> [McpDevice] {
        var out: [McpDevice] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.isEmpty || s.hasPrefix("List of devices") || s.hasPrefix("*") { continue }
            let parts = s.split(separator: " ", omittingEmptySubsequences: true)
            guard let first = parts.first, parts.count >= 2 else { continue }
            let serial = String(first)
            let state = String(parts[1])
            guard !serial.isEmpty, !state.isEmpty, state != "offline" || true else { continue }
            var dev = McpDevice(serial: serial, state: state)
            for p in parts.dropFirst(2) {
                let kv = p.split(separator: ":", maxSplits: 1)
                if kv.count == 2 {
                    let k = String(kv[0])
                    let v = String(kv[1])
                    if k == "model" { dev.model = v.replacingOccurrences(of: "_", with: " ") }
                    if k == "product" { dev.product = v }
                }
            }
            out.append(dev)
        }
        return out
    }
}
