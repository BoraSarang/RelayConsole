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

    func decodeObject(_ name: String) -> [String: Any] {
        let url = applicationSupportDir.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj
    }

    /// `diagnoses.json` — `{ "crash": { 지문: 기록 }, "throttling": { … } }`
    func loadDiagnoses() -> [String: [String: [String: Any]]] {
        var out: [String: [String: [String: Any]]] = [:]
        for (kind, value) in decodeObject("diagnoses.json") {
            guard let records = value as? [String: [String: Any]] else { continue }
            out[kind] = records
        }
        return out
    }

    /// 인시던트 번들 루트 — 앱이 만든 `incidents/<타임스탬프>-<kind>-<serial>/`
    var incidentsDir: URL {
        applicationSupportDir.appendingPathComponent("incidents", isDirectory: true)
    }

    /// 지문에서 시리얼만 뽑는다 — `192.168.86.30:5555:crash:com.x:Exception` → `192.168.86.30:5555`
    /// (시리얼 자체가 `:` 를 품으므로 `<kind>` 토큰 **앞부분**이 시리얼이다)
    public static func fingerprintSerial(_ fingerprint: String, kind: String) -> String {
        guard !kind.isEmpty, let range = fingerprint.range(of: ":\(kind)") else { return "" }
        return String(fingerprint[..<range.lowerBound])
    }

    /// JSON 수치(Int·Double·NSNumber) → Double
    static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        return nil
    }

    /// 도구 인자 상한 — 도구마다 같은 규칙(1~100)
    static func capped(_ limit: Int) -> Int {
        max(1, min(limit, 100))
    }

    // MARK: - Tools

    public func call(tool: McpToolName, arguments: McpValue) throws -> String {
        switch tool {
        case .listDevices:
            let enc = JSONEncoder()
            enc.outputFormatting = [.sortedKeys]
            let data = try enc.encode(devices())
            return String(decoding: data, as: UTF8.self)
        case .listEvents:
            let limit = arguments["limit"]?.intValue ?? 20
            let severity = arguments["severity"]?.stringValue
            let serial = arguments["serial"]?.stringValue
            return try jsonString(eventsSummary(limit: limit, severity: severity, serial: serial))
        case .listDiagnoses:
            let limit = arguments["limit"]?.intValue ?? 20
            return try jsonString(diagnoses(
                kind: arguments["kind"]?.stringValue,
                serial: arguments["serial"]?.stringValue,
                limit: limit
            ))
        case .listIncidents:
            let limit = arguments["limit"]?.intValue ?? 20
            return try jsonString(incidentBundles(
                kind: arguments["kind"]?.stringValue,
                serial: arguments["serial"]?.stringValue,
                limit: limit
            ))
        case .getDeviceHistory:
            let days = arguments["days"]?.intValue ?? 7
            return try jsonString(deviceHistory(
                serial: arguments["serial"]?.stringValue,
                days: days
            ))
        case .getSummary:
            return try jsonString(summary())
        }
    }

    func devices() throws -> [McpDevice] {
        guard let adb = adbPath else { return [] }
        let out = shellRunner(adb, ["devices", "-l"]) ?? ""
        return AdbDevicesParser.parse(out)
    }

    func eventsSummary(limit: Int, severity: String?, serial: String? = nil) -> [[String: Any]] {
        var events = loadEvents()
        if let severity {
            events = events.filter { ($0["severity"] as? String) == severity }
        }
        if let serial, !serial.isEmpty {
            events = events.filter { (($0["serial"] as? String) ?? "").contains(serial) }
        }
        // 파일은 최신 우선 가정 — 안전하게 정렬 시도
        events.sort { a, b in
            let ta = a["at"] as? String ?? ""
            let tb = b["at"] as? String ?? ""
            return ta > tb
        }
        let cap = Self.capped(limit)
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

    /// 자동 진단 기록 — `kind`(crash·throttling) · `serial` 필터 · 최신순
    func diagnoses(kind: String?, serial: String?, limit: Int) -> [[String: Any]] {
        var rows: [[String: Any]] = []
        for (recordKind, records) in loadDiagnoses() {
            if let kind, !kind.isEmpty, kind != recordKind { continue }
            for (fingerprint, record) in records {
                let recordSerial = Self.fingerprintSerial(fingerprint, kind: recordKind)
                if let serial, !serial.isEmpty,
                   !(recordSerial == serial || recordSerial.contains(serial)) { continue }
                var row: [String: Any] = [
                    "kind": recordKind,
                    "fingerprint": fingerprint,
                    "serial": recordSerial,
                    "diagnosedAt": record["diagnosedAt"] as? String ?? "",
                ]
                if let package = record["package"] as? String { row["package"] = package }
                if let exception = record["exception"] as? String { row["exception"] = exception }
                if let count = record["count7d"] { row["count7d"] = count }
                if let hotspot = record["hotspot"] { row["hotspot"] = hotspot }
                if let zones = record["hotZones"] as? [String], !zones.isEmpty { row["hotZones"] = zones }
                rows.append(row)
            }
        }
        rows.sort { ($0["diagnosedAt"] as? String ?? "") > ($1["diagnosedAt"] as? String ?? "") }
        return Array(rows.prefix(Self.capped(limit)))
    }

    /// 인시던트 번들 목록 — 디렉터리 이름이 최신순 정렬 키(`yyyyMMdd-HHmmss-…`)
    func incidentBundles(kind: String?, serial: String?, limit: Int) -> [[String: Any]] {
        let cap = Self.capped(limit)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: incidentsDir.path)) ?? []
        var rows: [[String: Any]] = []
        for name in names.filter({ !$0.hasPrefix(".") }).sorted(by: >) {
            let dir = incidentsDir.appendingPathComponent(name, isDirectory: true)
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
                  let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let event = manifest["event"] as? [String: Any]
            else { continue }
            let recordSerial = event["serial"] as? String ?? ""
            let recordKind = event["kind"] as? String ?? ""
            if let serial, !serial.isEmpty,
               !(recordSerial == serial || recordSerial.contains(serial)) { continue }
            if let kind, !kind.isEmpty, kind != recordKind { continue }

            let files = manifest["files"] as? [String] ?? []
            var row: [String: Any] = [
                "bundle": name,
                "serial": recordSerial,
                "kind": recordKind,
                "severity": event["severity"] as? String ?? "",
                "title": event["title"] as? String ?? "",
                "at": event["at"] as? String ?? "",
                "capturedAt": manifest["capturedAt"] as? String ?? "",
                "appVersion": manifest["appVersion"] as? String ?? "",
                "files": files,
                "sizeBytes": Self.bundleSize(dir, files: files),
            ]
            if let package = event["packageName"] as? String, !package.isEmpty { row["package"] = package }
            rows.append(row)
            if rows.count >= cap { break }
        }
        return rows
    }

    /// 번들 크기 — 매니페스트가 나열한 파일만 합산(디렉터리 전체 스캔 회피)
    static func bundleSize(_ dir: URL, files: [String]) -> Int {
        var total = 0
        for name in files {
            let path = dir.appendingPathComponent(name).path
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let size = attrs[.size] as? NSNumber {
                total += size.intValue
            }
        }
        return total
    }

    /// 일일 집계 추이 — 기기별 최신 `days` 일, 오래된 → 최신 순(추세 읽기)
    func deviceHistory(serial: String?, days: Int) -> [[String: Any]] {
        let cap = max(1, min(days, 90))
        let all = decodeObject("device-daily.json").compactMapValues { $0 as? [String: Any] }
        var rows: [[String: Any]] = []
        for record in all.values {
            let recordSerial = record["serial"] as? String ?? ""
            if let serial, !serial.isEmpty,
               !(recordSerial == serial || recordSerial.contains(serial)) { continue }
            var row: [String: Any] = [
                "serial": recordSerial,
                "day": record["dayKey"] as? String ?? "",
            ]
            for key in ["onlineMinutes", "samples", "crashEvents", "anrEvents", "warnEvents", "criticalEvents"] {
                if let value = record[key] { row[key] = value }
            }
            for key in [
                "cpuAvg", "cpuMax", "memUsedPctAvg", "tempMax",
                "batteryStartLevel", "batteryEndLevel", "netUpMB", "netDownMB",
            ] {
                if let value = Self.number(record[key]) {
                    row[key] = (value * 10).rounded() / 10
                }
            }
            rows.append(row)
        }
        // 기기별 최신 N일만 남긴다
        rows.sort { ($0["day"] as? String ?? "") > ($1["day"] as? String ?? "") }
        var seen: [String: Int] = [:]
        var kept: [[String: Any]] = []
        for row in rows {
            let recordSerial = row["serial"] as? String ?? ""
            let count = seen[recordSerial] ?? 0
            if count >= cap { continue }
            seen[recordSerial] = count + 1
            kept.append(row)
        }
        return kept.sorted {
            let left = ($0["day"] as? String ?? "", $0["serial"] as? String ?? "")
            let right = ($1["day"] as? String ?? "", $1["serial"] as? String ?? "")
            return left < right
        }
    }

    func summary() -> [String: Any] {
        let devs = (try? devices()) ?? []
        let events = loadEvents()
        let critical = events.filter { ($0["severity"] as? String) == "critical" && ($0["acknowledged"] as? Bool) != true }.count
        let warning = events.filter { ($0["severity"] as? String) == "warning" && ($0["acknowledged"] as? Bool) != true }.count
        let diagnoses = loadDiagnoses()
        let bundles = (try? FileManager.default.contentsOfDirectory(atPath: incidentsDir.path)) ?? []
        return [
            "deviceCount": devs.count,
            "deviceOnline": devs.filter { $0.state == "device" }.count,
            "activeCriticalEvents": critical,
            "activeWarningEvents": warning,
            "diagnosedCrashes": diagnoses["crash"]?.count ?? 0,
            "incidentBundles": bundles.filter { !$0.hasPrefix(".") }.count,
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
