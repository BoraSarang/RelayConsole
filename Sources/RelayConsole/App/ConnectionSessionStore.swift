import Foundation

/// 연결 세션 JSON 영구화 — Application Support/RelayConsole/connection-sessions.json
@MainActor
final class ConnectionSessionStore {
    static let shared = ConnectionSessionStore()

    private let url: URL
    private let queue = DispatchQueue(label: "relay.connectionstore", qos: .utility)
    private(set) var sessions: [ConnectionSession] = []

    private init() {
        self.url = Self.defaultURL()
        sessions = loadFromDisk()
    }

    /// 테스트 전용 — 실제 사용자 데이터를 건드리지 않도록 파일 위치를 주입한다
    init(url: URL) {
        self.url = url
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        sessions = loadFromDisk()
    }

    static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("RelayConsole", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("connection-sessions.json")
    }

    /// 저장 위치 (테스트에서 읽기 검증용)
    var fileURL: URL { url }

    private func loadFromDisk() -> [ConnectionSession] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ConnectionSession].self, from: data)) ?? []
    }

    func save() {
        guard let data = encode() else { return }
        let target = url
        queue.async {
            try? data.write(to: target, options: .atomic)
        }
    }

    private func encode() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(sessions)
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
    ///
    /// `save()`는 비동기 큐에 쓰기를 미루므로, 종료 시점에 호출되면 큐가 배출되기 전에
    /// 프로세스가 끝나 마지막 상태가 유실될 수 있다. 그래서 flush는 **동기**로 기록한다.
    /// `queue.sync`로 먼저 쌓여 있던 쓰기를 배출한 뒤 이어 쓰므로 순서도 보장된다.
    /// (주 호출부가 @MainActor 이므로 이 구간에 save()가 끼어들 수 없다)
    func flush() {
        guard let data = encode() else { return }
        let target = url
        queue.sync {
            try? data.write(to: target, options: .atomic)
        }
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
