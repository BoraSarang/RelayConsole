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

    /// 로그 보존 상한
    ///
    /// 종전엔 로테이션·크기 제한이 **전혀 없었다**. 알림·연결 이벤트가 쌓이는 만큼
    /// JSONL 이 무한히 커졌고, `tail()` 이 전체 파일을 `String(contentsOf:)` 로 읽었다.
    /// 상시 실행 메뉴바 앱이므로 수 개월 방치 시 수백 MB 가 된다.
    static let maxFileBytes = 2 * 1024 * 1024      // 파일당 2MB
    /// 보존할 일자 파일 수 (일자 분리)
    static let retainedDays = 14

    /// 파일 경로 — name은 안전 문자열만 (apphub, notify, device)
    static func url(name: String) -> URL { url(name: name, date: nil) }

    /// 일자 분리 경로 — `{name}-{yyyyMMdd}.jsonl`
    /// 하루가 지나면 새 파일이 시작되므로 한 파일이 무한히 커지지 않는다.
    static func url(name: String, date: Date?) -> URL {
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

        guard let date else { return dir.appendingPathComponent("\(safe).jsonl") }
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return dir.appendingPathComponent("\(safe)-\(f.string(from: date)).jsonl")
    }

    /// append 1줄 (동기 encode, 비동기 write) — 일자 분리 파일에 누적
    static func append(_ entry: Entry, name: String) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys]
        guard var data = try? enc.encode(entry) else { return }
        data.append(0x0A) // \n
        let payload = data
        let target = url(name: name, date: entry.at)
        queue.async {
            appendRotating(payload, to: target, name: name)
            pruneOldFiles(named: name)
        }
    }

    /// 상한 초과 시 최근 절반만 남기고 회전 (기존 파일은 `.1` 로 한 번만 보존)
    private static func appendRotating(_ payload: Data, to target: URL, name: String) {
        let attrs = try? FileManager.default.attributesOfItem(atPath: target.path)
        let currentSize = (attrs?[.size] as? Int) ?? 0

        if currentSize + payload.count > maxFileBytes {
            // 최근 절반만 유지 — 과거 로그 일부를 sacrifice 해 상한을 지킨다
            if let handle = try? FileHandle(forReadingFrom: target) {
                let keep = maxFileBytes / 2
                let end = (try? handle.seekToEnd()) ?? 0
                let size = Int(end)
                let start = max(0, size - keep)
                try? handle.seek(toOffset: UInt64(start))
                let tail = handle.readDataToEndOfFile()
                try? handle.close()
                // 잘린 앞부분의 반쪽 줄은 버린다 (JSONL 무결성)
                let cleaned = Data(tail.drop(while: { $0 != 0x0A }).dropFirst())
                try? cleaned.write(to: target, options: .atomic)
            }
        }

        if let handle = try? FileHandle(forWritingTo: target) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: payload)
        } else {
            try? payload.write(to: target, options: .atomic)
        }
    }

    /// 보관 기간이 지난 일자 파일 삭제 — 무한 증가 차단
    private static func pruneOldFiles(named name: String) {
        let safe = name.replacingOccurrences(
            of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression
        )
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base
            .appendingPathComponent("RelayConsole", isDirectory: true)
            .appendingPathComponent(dirName, isDirectory: true)
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return }

        let prefix = "\(safe)-"
        for u in items where u.lastPathComponent.hasPrefix(prefix) && u.pathExtension == "jsonl" {
            let values = try? u.resourceValues(forKeys: [.contentModificationDateKey])
            guard let modified = values?.contentModificationDate else { continue }
            let age = Date().timeIntervalSince(modified)
            if age > TimeInterval(retainedDays) * 86_400 {
                try? FileManager.default.removeItem(at: u)
            }
        }
    }

    /// 최근 N줄 읽기 (과거→최신, tail만)
    ///
    /// 종전엔 단일 파일 전체를 `String(contentsOf:)` 로 읽었다. 일자 분리 후에는
    /// **오늘 파일만** 읽어 크기 제한을 실제로 받는다(과거 로그는 위 `pruneOldFiles` 가 정리).
    static func tail(name: String, limit: Int = 200, now: Date = .now) -> [Entry] {
        let today = url(name: name, date: now)
        var text: String = (try? String(contentsOf: today, encoding: .utf8)) ?? ""
        // 오늘 파일이 없으면(자정 이전 기록만 남은 경우) 구 파일에서 마지막 줄을 읽는다
        if text.isEmpty {
            let legacy = url(name: name)
            text = (try? String(contentsOf: legacy, encoding: .utf8)) ?? ""
        }
        guard !text.isEmpty else { return [] }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        let slice = lines.suffix(limit)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return slice.compactMap { line in
            try? dec.decode(Entry.self, from: Data(line.utf8))
        }
    }
}
