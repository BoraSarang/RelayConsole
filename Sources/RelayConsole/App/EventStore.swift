import Foundation

/// 감시 이벤트 JSON 영구화 (EventStore 1차 — GRDB 없이 Foundation만 사용)
/// Application Support/RelayConsole/watch-events.json · 최대 500건 유지
@MainActor
final class EventStore {
    static let shared = EventStore()

    /// 보관 상한 — writer 의 백그라운드 인코딩 클로저에서 참조하므로 actor 격리를 두지 않는다
    nonisolated static let maxEvents = 500

    private let url: URL
    private let writer: CoalescingWriter<[WatchEvent]>

    /// 저장 실패 사유 (nil 이면 정상) — 조용한 실패를 막기 위한 조회점
    var lastSaveError: String? { writer.lastError }

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("RelayConsole", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent("watch-events.json")
        url = target
        // 인코딩을 writer 큐로 옮겨 MainActor 비용을 없앤다.
        // 대기 중인 쓰기는 최신 값으로 대체하므로 이벤트 20건 연속 유입 시
        // 20회 전량 재기록(1.12MB)이 아니라 1회로 합쳐진다.
        writer = CoalescingWriter(url: target, name: "EventStore", queueLabel: "relay.eventstore") { events in
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            return try encoder.encode(Array(events.prefix(EventStore.maxEvents)))
        }
    }

    /// 저장된 이력 로드 — 실패/없으면 빈 배열 (신규 필드 없는 기존 JSON도 OK)
    func load() -> [WatchEvent] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([WatchEvent].self, from: data)) ?? []
    }

    /// 이력 저장 (최대 maxEvents건, 최신 우선) — 인코딩·쓰기 모두 백그라운드
    func save(_ events: [WatchEvent]) {
        writer.submit(events)
    }

    /// 진행 중 쓰기 + 대기 값을 **동기** 기록 — 앱 종료 전에 호출
    func flushSync() {
        writer.flushSync()
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
