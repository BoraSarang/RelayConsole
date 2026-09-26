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

    /// **로드** 실패 여부 — 파일이 있는데 읽기/디코딩이 실패한 경우에만 true.
    /// (파일 없음은 최초 실행으로 정상) 다음 저장에서 기존 데이터를 덮어씌우므로
    /// 사용자가 알아야 한다([표시②]).
    private(set) var loadFailed = false

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

    /// 저장된 이력 로드 — 실패 시 `loadFailed` 로 알린다 (빈 배열로 조용히 대체하지 않음)
    func load() -> [WatchEvent] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            loadFailed = false          // 아직 없음 = 최초 실행 = 정상
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let events = try decoder.decode([WatchEvent].self, from: data)
            loadFailed = false
            return events
        } catch {
            // 파일은 있으나 읽기/디코딩 실패 → 조용히 덮어쓰면 복구 불가
            loadFailed = true
            DebugLogger.shared.error(
                "Store",
                "[ERROR] \(ErrorCode.storeReadFailed.rawValue) 이벤트 이력 읽기 실패: \(error.localizedDescription)"
            )
            return []
        }
    }

    /// 이력 저장 (최대 maxEvents건, 최신 우선) — 인코딩·쓰기 모두 백그라운드
    func save(_ events: [WatchEvent]) {
        preserveCorruptOriginal()
        writer.submit(events)
    }

    /// 로드 실패로 빈 배열이 된 상태에서 저장하면 기존 파일이 통째로 덮어써진다.
    /// 손상된 원본을 `.corrupt-<ts>` 로 먼저 보존한다(파괴적 자동 복구는 하지 않는다).
    private func preserveCorruptOriginal() {
        guard loadFailed else { return }
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).corrupt-\(f.string(from: .now))")
        try? FileManager.default.copyItem(at: url, to: backup)
        DebugLogger.shared.warn("Store", "[WARN] 손상된 원본 보존: \(backup.lastPathComponent)")
        loadFailed = false    // 1회만 보존
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
