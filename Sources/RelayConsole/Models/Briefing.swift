import Foundation

/// 아침 브리핑 스냅숏 — 팝오버 헤더 한 줄 데이터 (PLAN_briefing · RESEARCH S1)
struct BriefingSnapshot: Equatable, Sendable {
    let upSites: Int
    let downSites: Int
    let totalSites: Int
    let overdueJobs: Int
    let onlinePhones: Int
    let totalPhones: Int
    let activeCriticals: Int

    /// critical > down/overdue > 정상
    enum Tone: Equatable, Sendable {
        case ok, warn, bad
    }

    var tone: Tone {
        if activeCriticals > 0 { return .bad }
        if downSites > 0 || overdueJobs > 0 || onlinePhones < totalPhones { return .warn }
        return .ok
    }

    /// L10n.format("briefing.line", …) 인자 — 순서 고정
    var formatArgs: [CVarArg] {
        [upSites, totalSites, overdueJobs, onlinePhones, totalPhones, activeCriticals]
    }
}

/// 순수 브리핑 계산 — 단위 테스트 대상
enum BriefingLogic {
    static func snapshot(
        sites: [Site],
        jobs: [Job],
        androidOnline: Int,
        androidTotal: Int,
        appleOnline: Int,
        appleTotal: Int,
        events: [WatchEvent],
        now: Date = .now
    ) -> BriefingSnapshot {
        let enabledSites = sites.filter(\.enabled)
        let up = enabledSites.filter { $0.effectiveUp() == true }.count
        let down = enabledSites.filter { $0.effectiveUp() == false }.count
        let overdue = jobs.filter { $0.enabled && $0.isOverdue(now: now) == true }.count
        let online = androidOnline + appleOnline
        let total = androidTotal + appleTotal
        return BriefingSnapshot(
            upSites: up,
            downSites: down,
            totalSites: enabledSites.count,
            overdueJobs: overdue,
            onlinePhones: online,
            totalPhones: total,
            activeCriticals: activeCriticalCount(events)
        )
    }

    /// `ConsoleStore.hasActiveCritical` count 버전 — 최신 clear가 더 위(인덱스 작음)면 해제
    static func activeCriticalCount(_ events: [WatchEvent]) -> Int {
        var count = 0
        for (i, e) in events.enumerated() {
            guard e.severity == .critical, !e.isClear else { continue }
            let fp = e.fingerprint
            let cleared = events[..<i].contains { $0.fingerprint == fp && $0.isClear }
            if !cleared { count += 1 }
        }
        return count
    }
}
