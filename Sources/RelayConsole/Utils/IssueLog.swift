import Foundation

/// JSONL 원가 로그 — AppHub 액션 / 알림 발송 / 임계 설정 등
/// Application Support/RelayConsole/logs/{name}.jsonl
enum IssueLog {
    struct Entry: Codable, Equatable, Sendable {
        let at: Date
        let kind: String
        let serial: String?
        let package: String?
        let detail: String
        let ok: Bool?

        init(
            kind: String,
            detail: String,
            serial: String? = nil,
            package: String? = nil,
            ok: Bool? = nil,
            at: Date = .now
        ) {
            self.at = at
            self.kind = kind
            self.serial = serial
            self.package = package
            self.detail = detail
            self.ok = ok
        }
    }

    enum Kind {
        static let appLaunch = "app.launch"
        static let appForceStop = "app.forceStop"
        static let appUninstall = "app.uninstall"
        static let notifySystem = "notify.system"
        static let notifyNtfy = "notify.ntfy"
        static let notifySlack = "notify.slack"
        static let androidConnected = "device.connected"
        static let androidDisconnected = "device.disconnected"
    }

    private static let dirName = "logs"
    private static let queue = DispatchQueue(label: "relay.issuelog", qos: .utility)

    /// 파일 경로 — name은 안전 문자열만 (apphub, notify, device)
    static func url(name: String) -> URL {
        let safe = name.replacingOccurrences(
            of: "[^a-zA-Z0-9_-]",
            with: "_",
            options: .regularExpression
        )
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base
            .appendingPathComponent("RelayConsole", isDirectory: true)
            .appendingPathComponent(dirName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(safe).jsonl")
    }

    /// append 1줄 (동기 encode, 비동기 write)
    static func append(_ entry: Entry, name: String) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys]
        guard var data = try? enc.encode(entry) else { return }
        data.append(0x0A) // \n
        let payload = data
        let target = url(name: name)
        queue.async {
            if let handle = try? FileHandle(forWritingTo: target) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: payload)
            } else {
                try? payload.write(to: target)
            }
        }
    }

    /// 최근 N줄 읽기 (역순 아님 — 과거→최신, tail만)
    static func tail(name: String, limit: Int = 200) -> [Entry] {
        guard let text = try? String(contentsOf: url(name: name), encoding: .utf8) else {
            return []
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        let slice = lines.suffix(limit)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return slice.compactMap { line in
            try? dec.decode(Entry.self, from: Data(line.utf8))
        }
    }
}
