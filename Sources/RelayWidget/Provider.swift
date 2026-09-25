import WidgetKit
import Foundation

struct RelayWidgetEntry: TimelineEntry {
    let date: Date
    /// nil = 아직 스냅샷 없음 (앱 미기록) — 빈 상태 문구 노출
    let snapshot: WidgetSnapshot?
}

struct RelayWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> RelayWidgetEntry {
        RelayWidgetEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (RelayWidgetEntry) -> Void) {
        completion(RelayWidgetEntry(date: .now, snapshot: WidgetSnapshotStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RelayWidgetEntry>) -> Void) {
        // 실시간 갱신은 앱이 reloadTimelines로 유도 — 여기는 예비 주기 (15분)
        let entry = RelayWidgetEntry(date: .now, snapshot: WidgetSnapshotStore.read())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}
