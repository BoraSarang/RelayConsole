import Foundation

/// 신호·배터리 환경 패턴 요약 — 순수 함수 (PLAN_auto_diagnose Phase 3)
///
/// "빈번한가"에 답한다. 원인은 모르면 적지 않는다 ([표시②]).
/// 셀 변경 = 핸드오버 정황 (실측 2026-10-05: 345↔93 변경 확인).
struct EnvSummary: Equatable, Sendable {
    /// 7일 셀 변경(전이) 횟수
    var cellChanges7d: Int
    /// 7일 서로 다른 셀 수
    var distinctCells7d: Int
    /// 7일 신호 급락(signalDrop enter) 횟수
    var drops7d: Int
    /// 방전 속도 (%/h, 양수) — 충전 중이거나 자료 부족이면 nil
    var drainPctPerHour: Double?
    /// 아무 자료도 없음 — 카드는 빈 힌트를 낸다
    var isEmpty: Bool {
        cellChanges7d == 0 && distinctCells7d == 0 && drops7d == 0 && drainPctPerHour == nil
    }
}

enum EnvPatterns {
    /// 방전 속도 — (첫값-끝값)/창시간. 충전 중(올라감)·자료 부족이면 nil.
    /// 링 버퍼라 중간 결측은 무시하고 양 끝만 본다 (근사 — 주석에 명시).
    static func drainRatePctPerHour(
        levels: [Double],
        windowSeconds: TimeInterval?
    ) -> Double? {
        guard levels.count >= 2,
              let span = windowSeconds, span >= 300 else { return nil }
        let drop = levels.first! - levels.last!
        guard drop > 0 else { return nil }
        return drop / (span / 3600)
    }

    static func summarize(
        cells: [CellSample],
        dropEvents: [WatchEvent],
        levels: [Double],
        windowSeconds: TimeInterval?,
        serial: String,
        now: Date = .now
    ) -> EnvSummary {
        let weekAgo = now.addingTimeInterval(-7 * 24 * 3600)
        let recent = cells.filter { $0.at >= weekAgo }
        let changes = recent.count > 0 ? recent.count - 1 : 0
        let distinct = Set(recent.map { "\($0.ci)/\($0.pci)" }).count
        let drops = dropEvents.filter {
            $0.kind == .signalDrop && !$0.isClear && $0.serial == serial && $0.at >= weekAgo
        }.count
        return EnvSummary(
            cellChanges7d: changes,
            distinctCells7d: distinct,
            drops7d: drops,
            drainPctPerHour: drainRatePctPerHour(levels: levels, windowSeconds: windowSeconds)
        )
    }
}
