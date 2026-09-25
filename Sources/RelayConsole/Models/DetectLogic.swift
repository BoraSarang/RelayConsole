import Foundation

/// 설정 변경·logcat 탐지 이벤트 집계 — 대시보드 타임라인·건수 (AGENTS.local §4 [표시②])
enum DetectLogic {
    /// 오늘 · 해당 기기의 탐지 이벤트 (신순 유지)
    static func today(
        events: [WatchEvent],
        serial: String,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [WatchEvent] {
        guard !serial.isEmpty else { return [] }
        let day = InsightLogic.dayKey(for: now, calendar: calendar)
        return events.filter {
            $0.serial == serial && $0.kind.isDetectKind
                && InsightLogic.dayKey(for: $0.at, calendar: calendar) == day
        }
    }

    /// kind별 건수 (오늘 · 해당 기기)
    static func counts(_ events: [WatchEvent]) -> (settings: Int, logcat: Int) {
        (
            settings: events.filter { $0.kind == .settingsChanged }.count,
            logcat: events.filter { $0.kind == .logcatHits }.count
        )
    }

    /// 타임라인 노출 건수
    static let listLimit = 5
}
