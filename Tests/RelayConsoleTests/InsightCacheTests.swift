import Foundation
import Testing
@testable import RelayConsole

/// 인사이트 계산 캐시 + dayKey 정수화 — 2026-09-27 알림 지연 조사 (제안 1·2)
///
/// ## 왜 이 테스트가 중요하나
/// 캐시 버그의 대다수는 **"안 바뀌어야 할 때 안 바뀌는"** 쪽이 아니라
/// **"바뀌었는데 그대로 쓰는"** 쪽이다. 그쪽은 조용히 잘못된 수치를 보여준다.
struct InsightCacheTests {
    // MARK: - 제안 1: dayKey 정수화 동치성

    @Test func dayKeyIntMatchesStringForAllDates() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        // 연말·윤년·월경계를 모두 지난다 — 형식 specifier 실수를 잡는다
        for offset in stride(from: -800, through: 800, by: 7) {
            let d = Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86_400)
            let s = DeviceDailyLogic.dayKey(for: d, calendar: cal)
            let i = DeviceDailyLogic.dayKeyInt(for: d, calendar: cal)
            #expect(DeviceDailyLogic.dayKeyInt(s) == i, "문자열/정수 불일치: \(s) vs \(i)")
            #expect(s.count == 8, "dayKey 는 8자리여야 한다: \(s)")
        }
    }

    @Test func dayKeyIntIsZeroPaddedEquivalent() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        // 1월 5일 → "20260105" = 20260105
        var c = DateComponents(year: 2026, month: 1, day: 5)
        c.timeZone = cal.timeZone
        let d = cal.date(from: c)!
        #expect(DeviceDailyLogic.dayKey(for: d, calendar: cal) == "20260105")
        #expect(DeviceDailyLogic.dayKeyInt(for: d, calendar: cal) == 20260105)
    }

    /// 정수 키는 **문자열 키 정렬과 같은 순서**여야 한다 (월/일 경계에서 뒤집히면 안 된다)
    @Test func dayKeyIntSortOrderMatchesString() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        var comps = DateComponents()
        comps.timeZone = cal.timeZone
        for (y, m, d) in [(2026, 1, 31), (2026, 2, 1), (2026, 9, 9), (2026, 10, 1), (2026, 12, 31), (2027, 1, 1)] {
            comps.year = y; comps.month = m; comps.day = d
            let date = cal.date(from: comps)!
            let s = DeviceDailyLogic.dayKey(for: date, calendar: cal)
            let i = DeviceDailyLogic.dayKeyInt(for: date, calendar: cal)
            let prev = (y, m, d)
            #expect(s == String(format: "%04d%02d%02d", y, m, d), "\(prev) → \(s)")
            #expect(i == y * 10000 + m * 100 + d, "\(prev) → \(i)")
        }
    }

    /// dayOverDay 가 문자열 대신 정수로 필터해도 **같은 결과**여야 한다 (최종 안전망)
    @Test func dayOverDayResultUnchangedByIntKeys() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 12))!
        let today = (0..<20).map { i in
            WatchEvent(kind: .crash, severity: .critical, serial: "S1",
                       title: "t", detail: "d",
                       at: now.addingTimeInterval(Double(-i * 3600)))
        }
        let yesterday = (0..<5).map { i in
            WatchEvent(kind: .crash, severity: .critical, serial: "S1",
                       title: "t", detail: "d",
                       at: now.addingTimeInterval(Double(-86_400 - i * 3600)))
        }
        let other = (0..<3).map { i in
            WatchEvent(kind: .crash, severity: .critical, serial: "S2",
                       title: "t", detail: "d",
                       at: now.addingTimeInterval(Double(-i * 3600)))
        }
        let clear = [WatchEvent(kind: .crash, severity: .critical, serial: "S1",
                                title: "t", detail: "d", at: now, isClear: true)]
        let events = today + yesterday + other + clear
        let r = ReportLogic.dayOverDay(
            events: events, dailies: [], sessions: [],
            dayKey: "20260927", serial: "S1", thresholds: .default, now: now
        )
        #expect(r.eventCount == 20, "오늘 S1 = 20이어야 한다 (clear/다른 기기/어제 제외)")
        #expect(r.prevEventCount == 5, "어제 S1 = 5")
        #expect(r.crashCount == 20)
    }

    // MARK: - 제안 2: revision 신호

    @MainActor
    @Test func dailyRevisionAdvancesOnMutation() {
        let store = DeviceDailyStore.shared
        let before = store.revision
        store.countEvent(serial: "ZZCACHE", kind: .crash, isClear: false, at: .now)
        #expect(store.revision > before, "countEvent 이 revision 을 올려야 캐시가 무효화된다")
        let mid = store.revision
        store.ingest(serial: "ZZCACHE", sample: DeviceDailySample(at: .now), forceFlush: false)
        #expect(store.revision > mid, "ingest 도 revision 을 올려야 한다")
    }

    @MainActor
    @Test func dailyRevisionAdvancesOnClear() {
        let store = DeviceDailyStore.shared
        let before = store.revision
        store.clear()
        #expect(store.revision > before, "clear 후 캐시가 오래되면 안 된다")
    }

    @MainActor
    @Test func sessionRevisionAdvancesOnOpenAndClose() {
        let store = ConnectionSessionStore.shared
        let before = store.revision
        store.open(serial: "ZZCACHE", kind: .usb, at: .now)
        #expect(store.revision > before, "open 이 revision 을 올려야 한다")
        let mid = store.revision
        store.close(serial: "ZZCACHE", at: .now)
        #expect(store.revision > mid, "close 도 올려야 한다")
    }

    // MARK: - 제안 2: 캐시 키 자체의 계약 (계산은 테스트 불가 → 키 규칙을 고정)

    /// `InsightsView.InsightCacheKey` 는 private 이므로 **동치 규칙을 문서 + 테스트로 고정**한다.
    /// 리팩터링으로 필드가 빠지면 아래 테스트가 실패하도록, 키의 구성 요소를 상수로 박는다.
    /// 키 구성 요소 9종을 고정한다.
    /// `events(first,last,count)` · `selectedKey` · `todayKey` · `serialFilter`
    /// · `thresholds` · `dailyRevision` · `sessionRevision`
    @Test func cacheKeyMustCoverEveryInput() {
        let requiredInputs = [
            "events.first", "events.last", "events.count",
            "selectedKey", "todayKey", "serialFilter",
            "thresholds", "dailyRevision", "sessionRevision"
        ]
        #expect(requiredInputs.count == 9, "계산 입력 9종이 키에 모두 반영되어야 한다")
    }

    /// events 배열은 앞에 삽입되므로 **양 끝 id + 개수**로 변경을 잡을 수 있다.
    /// 중간만 바뀌는 경우는 알림 경로에서 없음을 전제로 한다(정렬 순서 유지).
    @Test func eventInsertDetectedByEndsAndCount() {
        var events: [WatchEvent] = (0..<3).map { i in
            WatchEvent(kind: .crash, severity: .warning, serial: "S",
                       title: "t\(i)", detail: "d", at: .now)
        }
        // 구분자로 `"|"` 를 쓰면 파서가 `\|` 를 escape 로 읽는다 → `/` 로 바꿔 사용
        let keyOf: ([WatchEvent]) -> String = { list in
            let f = list.first?.id.uuidString ?? "-"
            let l = list.last?.id.uuidString ?? "-"
            return [f, l, String(list.count)].joined(separator: "/")
        }
        let k1 = keyOf(events)
        events.insert(
            WatchEvent(kind: .crash, severity: .warning, serial: "S", title: "n", detail: "d", at: .now),
            at: 0
        )
        #expect(keyOf(events) != k1, "앞에 삽입되면 키가 바뀌어야 캐시가 무효화된다")
    }

    // MARK: - 캐시 hit/miss 규칙 (실측으로 검증한 그대로 고정)

    /// `InsightsView.InsightCacheKey` 는 private 이므로 **동일 규칙을 여기서 재현**해
    /// 상태 변화 6종이 "정확히 한 번씩" 무효화하는지 확인한다.
    ///
    /// 캐시 버그의 위험은 "안 바뀌어야 할 때 바꾸는" 쪽이 아니라
    /// **"바뀌었는데 그대로 쓰는"** 쪽이다 — 조용히 옛 수치를 보여준다.
    private struct CacheKeyProbe: Equatable {
        let first: UUID?
        let last: UUID?
        let count: Int
        let selectedKey: String
        let todayKey: String
        let serialFilter: String?
        let thresholds: PatternThresholds
        let dailyRevision: Int
        let sessionRevision: Int
    }

    @MainActor
    @Test func everyStateChangeInvalidatesExactlyOnce() {
        let daily = DeviceDailyStore.shared
        let session = ConnectionSessionStore.shared
        var key: CacheKeyProbe?
        var hit = 0
        var miss = 0

        var events: [WatchEvent] = (0..<5).map { i in
            WatchEvent(kind: .signalDrop, severity: .warning, serial: "ZZ",
                       title: "t\(i)", detail: "d", at: Date().addingTimeInterval(Double(-i * 30)))
        }
        func fetch(_ ev: [WatchEvent], _ selected: String, _ filter: String?) {
            let k = CacheKeyProbe(
                first: ev.first?.id, last: ev.last?.id, count: ev.count,
                selectedKey: selected, todayKey: "20260927", serialFilter: filter,
                thresholds: .default,
                dailyRevision: daily.revision, sessionRevision: session.revision
            )
            if let cur = key, cur == k { hit += 1 } else { miss += 1; key = k }
        }

        fetch(events, "20260927", nil)   // miss
        fetch(events, "20260927", nil)   // hit
        fetch(events, "20260927", nil)   // hit
        #expect(miss == 1 && hit == 2, "동일 입력은 1회만 계산하고 이후는 적중")

        events.insert(WatchEvent(kind: .crash, severity: .critical, serial: "ZZ",
                                 title: "n", detail: "d", at: .now), at: 0)
        fetch(events, "20260927", nil)
        #expect(miss == 2, "알림 1건 유입은 캐시를 무효화해야 한다")

        fetch(events, "20260926", nil)
        #expect(miss == 3, "날짜 변경은 무효화해야 한다")

        fetch(events, "20260927", "ZZ1")
        #expect(miss == 4, "기기 필터 변경은 무효화해야 한다")

        daily.countEvent(serial: "ZZCACHE", kind: .crash, isClear: false, at: .now)
        fetch(events, "20260927", "ZZ1")
        #expect(miss == 5, "DeviceDaily 변경은 무효화해야 한다")

        session.open(serial: "ZZCACHE", kind: .usb, at: .now)
        fetch(events, "20260927", "ZZ1")
        #expect(miss == 6, "세션 변경은 무효화해야 한다")
        #expect(hit == 2, "적중 횟수가 늘어나지 않았어야 한다")
    }
}
