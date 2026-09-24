import Foundation

/// 감시 이벤트 JSON 영구화 (EventStore 1차 — GRDB 없이 Foundation만 사용)
/// Application Support/RelayConsole/watch-events.json · 최대 500건 유지
@MainActor
final class EventStore {
    static let shared = EventStore()

    static let maxEvents = 500

    private let url: URL
    private let queue = DispatchQueue(label: "relay.eventstore", qos: .utility)

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("RelayConsole", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("watch-events.json")
    }

    /// 저장된 이력 로드 — 실패/없으면 빈 배열 (신규 필드 없는 기존 JSON도 OK)
    func load() -> [WatchEvent] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([WatchEvent].self, from: data)) ?? []
    }

    /// 이력 저장 (최대 maxEvents건, 최신 우선) — 비동기 큐에서 쓰기
    func save(_ events: [WatchEvent]) {
        let trimmed = Array(events.prefix(Self.maxEvents))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(trimmed) else { return }
        let target = url
        queue.async {
            try? data.write(to: target, options: .atomic)
        }
    }

    /// 필터 조회 — 인자 배열 기준 (ConsoleStore.recentWatchEvents 권장)
    func filtered(
        from events: [WatchEvent],
        by filter: AlertsFilter,
        now: Date = .now
    ) -> [WatchEvent] {
        WatchEventAlerts.filter(events, by: filter, now: now)
    }
}
