import Foundation

/// 연결 세션 JSON 영구화 — Application Support/RelayConsole/connection-sessions.json
@MainActor
final class ConnectionSessionStore {
    static let shared = ConnectionSessionStore()

    private let url: URL
    private let queue = DispatchQueue(label: "relay.connectionstore", qos: .utility)
    private(set) var sessions: [ConnectionSession] = []
    private var dirty = false

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("RelayConsole", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("connection-sessions.json")
        sessions = loadFromDisk()
    }

    private func loadFromDisk() -> [ConnectionSession] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ConnectionSession].self, from: data)) ?? []
    }

    func save() {
        dirty = false
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(sessions) else { return }
        let target = url
        queue.async {
            try? data.write(to: target, options: .atomic)
        }
    }

    // MARK: - API

    func open(serial: String, kind: ConnectionKind, at: Date = .now) {
        ConnectionSessionLogic.open(sessions: &sessions, serial: serial, kind: kind, at: at)
        save()
    }

    @discardableResult
    func close(serial: String, at: Date = .now) -> Bool {
        let ok = ConnectionSessionLogic.close(sessions: &sessions, serial: serial, at: at)
        if ok { save() }
        return ok
    }

    /// 앱 종료 시 미닫힌 세션 유지 (isOngoing으로 표시)
    func flush() {
        if dirty { save() }
    }

    func daySummary(dayKey: String, serial: String? = nil, now: Date = .now) -> ConnectionDaySummary {
        ConnectionSessionLogic.dailySummary(sessions, dayKey: dayKey, serial: serial, now: now)
    }

    func prune(retentionDays: Int, now: Date = .now) {
        if ConnectionSessionLogic.prune(&sessions, retentionDays: retentionDays, now: now) > 0 {
            save()
        }
    }

    /// 전체 교환 (테스트/디버그)
    func replaceAll(_ list: [ConnectionSession]) {
        sessions = list
        save()
    }

    func clear() {
        sessions = []
        save()
    }
}
