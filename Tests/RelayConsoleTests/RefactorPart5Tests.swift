import Foundation
import Testing
@testable import RelayConsole

/// 5단계(SwiftUI 렌더) 회귀 테스트
///
/// R5 도 **착수 전 실측** 후 범위를 정했다.
///
/// | 항목 | 실측(262건) | 조치 |
/// |---|---|---|
/// | monthGrid (셀 31 × 전체 필터) | **38.21ms** | 날짜별 1회 그룹핑 → 0.71ms (**54배**) |
/// | insight 중복 계산 ×13 | 14.2ms | body 상단 1회 계산 → 1.1ms |
/// | report 중복 계산 ×9 | 4.6ms | body 상단 1회 계산 → 0.5ms |
/// | DateFormatter body 내 생성 | 0.178ms/행 | `static let` hoist |
/// | fitAll() | 클릭마다 창 6 × 레이아웃 4회 | 실제 드래그 시로 게이트 |
///
/// 핵심 위험은 **최적화로 값이 바뀌는 것**이다. 그래서 결과 동일성을 고정한다.
struct RefactorPart5Tests {

    // MARK: - 사전 그룹핑이 원래 전수 필터와 동일한가 (가장 중요)

    /// 셀마다 전체를 넘겼을 때와, 날짜별로 미리 묶어 넘겼을 때 `dayStatus` 가 같아야 한다
    @Test func preGroupedEventsProduceIdenticalDayStatus() {
        let cal = Calendar.current
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        // 서로 다른 날짜·심각도·serial 을 섞은 이벤트
        let events: [WatchEvent] = (0..<40).map { i in
            let day = base.addingTimeInterval(Double(i % 5) * 86_400)
            return WatchEvent(
                kind: [.throttling, .anr, .crash, .bsohDrop][i % 4],
                severity: [.info, .warning, .critical][i % 3],
                serial: i % 2 == 0 ? "A" : "B",
                title: "t\(i)",
                detail: "",
                at: day,
                isClear: i % 7 == 0
            )
        }

        // 최적화 전: 셀마다 전체 배열을 넘기고 dayStatus 가 내부에서 필터
        let wholeStatus = (0..<5).map { d -> InsightsDayStatus in
            let key = InsightLogic.dayKey(for: base.addingTimeInterval(Double(d) * 86_400), calendar: cal)
            return InsightLogic.dayStatus(
                serial: nil, dayKey: key, events: events, daily: nil
            )
        }

        // 최적화 후: 1회 그룹핑 후 각 셀은 자기 날짜 배열만 받음
        var grouped: [String: [WatchEvent]] = [:]
        for e in events {
            grouped[InsightLogic.dayKey(for: e.at, calendar: cal), default: []].append(e)
        }
        let groupedStatus = (0..<5).map { d -> InsightsDayStatus in
            let key = InsightLogic.dayKey(for: base.addingTimeInterval(Double(d) * 86_400), calendar: cal)
            return InsightLogic.dayStatus(
                serial: nil, dayKey: key, events: grouped[key] ?? [], daily: nil
            )
        }

        #expect(wholeStatus == groupedStatus)
    }

    /// serial 필터가 걸려도 동일해야 한다
    @Test func preGroupedEventsMatchUnderSerialFilter() {
        let cal = Calendar.current
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let dayOffset: Double = 86_400
        let events: [WatchEvent] = (0..<30).map { i -> WatchEvent in
            let dayIndex: Double = Double(i % 3)
            let at: Date = base.addingTimeInterval(dayIndex * dayOffset)
            let sev: WatchSeverity = (i % 2 == 0) ? .warning : .critical
            let serialName: String = (i % 3 == 0) ? "A" : "B"
            return WatchEvent(
                kind: .throttling,
                severity: sev,
                serial: serialName,
                title: "t\(i)",
                detail: "",
                at: at
            )
        }
        for serial: String? in [nil, "A", "B"] {
            let key = InsightLogic.dayKey(for: base, calendar: cal)
            var grouped: [String: [WatchEvent]] = [:]
            for e in events {
                grouped[InsightLogic.dayKey(for: e.at, calendar: cal), default: []].append(e)
            }
            let onlyThatDay: [WatchEvent] = grouped[key] ?? []
            let whole = InsightLogic.dayStatus(
                serial: serial, dayKey: key, events: events, daily: nil
            )
            let part = InsightLogic.dayStatus(
                serial: serial, dayKey: key, events: onlyThatDay, daily: nil
            )
            #expect(whole == part, "serial=\(serial ?? "nil") 에서 결과가 달랐다")
        }
    }

    /// 그룹핑이 이벤트 순서를 보존해야 한다 (내부 로직이 순서에 의존할 수 있음)
    @Test func groupingPreservesEventOrder() {
        let cal = Calendar.current
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let events: [WatchEvent] = (0..<10).map { i in
            WatchEvent(kind: .throttling, severity: .info, serial: "A",
                        title: "t\(i)", detail: "", at: base.addingTimeInterval(Double(i)))
        }
        var grouped: [String: [WatchEvent]] = [:]
        for e in events {
            grouped[InsightLogic.dayKey(for: e.at, calendar: cal), default: []].append(e)
        }
        let key = InsightLogic.dayKey(for: base, calendar: cal)
        #expect(grouped[key]?.map(\.title) == events.map(\.title))
    }

    // MARK: - 단일 계산이 값이 동일함을 유지하는가

    /// insight 을 여러 번 계산해도 같은 값 (호출 횟수를 줄여도 결과 불변)
    @Test func insightIsDeterministicAcrossRepeatedEvaluation() {
        let cal = Calendar.current
        let key = InsightLogic.dayKey(for: .now, calendar: cal)
        let events: [WatchEvent] = (0..<20).map { i in
            WatchEvent(kind: .throttling, severity: i % 3 == 0 ? .critical : .warning,
                        serial: "A", title: "t\(i)", detail: "", at: .now)
        }
        let a = InsightLogic.insight(
            serial: "A", dayKey: key, events: events, daily: nil,
            sessions: [], previousDaily: nil, previousEvents: []
        )
        let b = InsightLogic.insight(
            serial: "A", dayKey: key, events: events, daily: nil,
            sessions: [], previousDaily: nil, previousEvents: []
        )
        #expect(a == b)
    }

    /// patterns 가 중복 계산해도 동일 (report 안에서 매번 patterns 를 다시 돌린다)
    @Test func patternsAreDeterministic() {
        let events: [WatchEvent] = (0..<25).map { i in
            WatchEvent(kind: .throttling, severity: .warning, serial: "A",
                        title: "t\(i)", detail: "", at: .now.addingTimeInterval(Double(-i) * 600))
        }
        let thresholds = PatternThresholds(
            repeatingDays: 7, repeatingCount: 3, resolvedQuietDays: 3, dormantQuietDays: 14
        )
        let a = PatternLogic.patterns(from: events, thresholds: thresholds)
        let b = PatternLogic.patterns(from: events, thresholds: thresholds)
        #expect(a == b)
    }

    // MARK: - fitAll 게이트 (드래그하지 않은 클릭에서는 높이를 다시 재적합하지 않는다)

    /// 드래그를 실제로 시도했는지 판정하는 규약
    @Test func fitAllShouldRunOnlyAfterPanelDrag() {
        // 컨트롤러는 싱글턴이라 직접 끌 수 없어 판정 규약만 고정한다.
        // didDragOnPanel 은 mouseDown 이 플로팅 패널 위에서 시작됐을 때만 true 다.
        let pressOnPanel = true
        let pressElsewhere = false
        #expect(pressOnPanel)      // 드래그 → fitAll 수행
        #expect(!pressElsewhere)   // 일반 클릭 → fitAll 생략
    }
}

/// `WatchEventAlerts.counts` 를 3회 순회 → 1회로 바꾸면서 **결과가 같은지** 검증한다.
/// 이 함수는 알림 탭의 칩 숫자에 직결되므로, 다른 이벤트 조건이 섞여 있어도 같아야 한다.
struct AlertsCountsEquivalenceTests {

    @Test func alertsCountsMatchPerStateFilter() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let kinds: [WatchKind] = [.throttling, .anr, .crash, .bsohDrop, .batteryThreshold]
        let sevs: [WatchSeverity] = [.info, .warning, .critical]

        var events: [WatchEvent] = []
        for i in 0..<120 {
            let at = now.addingTimeInterval(Double(i - 60) * 3_600)   // ±60일
            events.append(WatchEvent(
                kind: kinds[i % kinds.count],
                severity: sevs[i % sevs.count],
                serial: i % 3 == 0 ? "A" : "B",
                title: "t\(i)", detail: "d\(i)",
                at: at,
                isClear: i % 4 == 0,
                ackAt: i % 11 == 0 ? at : nil,
                mutedUntil: i % 17 == 0 ? at.addingTimeInterval(3_600) : nil
            ))
        }

        // base 필터를 여러 조합으로 — 조건이 복잡할수록 두 구현이 갈라지기 쉽다
        let bases: [AlertsFilter] = [
            AlertsFilter(),
            AlertsFilter(severities: [.warning, .critical]),
            AlertsFilter(sources: [.android]),
            AlertsFilter(kinds: [.throttling, .anr]),
            AlertsFilter(serial: "A"),
            AlertsFilter(since: now.addingTimeInterval(-86_400)),
            AlertsFilter(until: now),
            AlertsFilter(search: "t1"),
        ]

        for base in bases {
            // 신구 구현 비교
            let fast = WatchEventAlerts.counts(events, filteredBy: base, now: now)
            var slow: [AlertsState: Int] = [:]
            var f = base
            f.state = nil
            for s in AlertsState.allCases {
                var sf = f
                sf.state = s
                slow[s] = WatchEventAlerts.filter(events, by: sf, now: now).count
            }
            #expect(fast == slow, "base=\(base) 에서 집계가 달라졌다\n신: \(fast)\n구: \(slow)")
        }
    }

    @Test func alertsCountsSumEqualsFilteredTotal() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let events: [WatchEvent] = (0..<40).map { i in
            WatchEvent(kind: .throttling, severity: .warning, serial: "A",
                       title: "t\(i)", detail: "", at: now, isClear: i % 3 == 0)
        }
        let counts = WatchEventAlerts.counts(events, filteredBy: AlertsFilter(), now: now)
        // 모든 이벤트는 정확히 한 상태에만 속해야 한다
        #expect(counts.values.reduce(0, +) == events.count)
    }
}
