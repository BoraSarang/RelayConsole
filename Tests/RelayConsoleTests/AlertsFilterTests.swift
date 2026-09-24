import Foundation
import Testing
@testable import RelayConsole

@MainActor
struct AlertsFilterTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func e(
        kind: WatchKind = .throttling,
        sev: WatchSeverity = .warning,
        serial: String = "S1",
        title: String = "t",
        detail: String = "d",
        at: Date? = nil,
        isClear: Bool = false,
        source: WatchSource? = nil,
        ackAt: Date? = nil,
        note: String? = nil,
        mutedUntil: Date? = nil
    ) -> WatchEvent {
        var ev = WatchEvent(
            kind: kind,
            severity: sev,
            serial: serial,
            title: title,
            detail: detail,
            at: at ?? t0,
            isClear: isClear,
            source: source
        )
        if let ackAt { ev.ackAt = ackAt }
        if let note { ev.note = note }
        if let mutedUntil { ev.mutedUntil = mutedUntil }
        return ev
    }

    // MARK: - 상태 파생

    @Test func stateActiveWhenNotClearAndNotMuted() {
        #expect(e().state(now: t0) == .active)
    }

    @Test func stateClearedWhenIsClear() {
        #expect(e(isClear: true, mutedUntil: t0.addingTimeInterval(3600)).state(now: t0) == .cleared)
    }

    @Test func stateMutedWhenMuteInFuture() {
        #expect(e(mutedUntil: t0.addingTimeInterval(60)).state(now: t0) == .muted)
    }

    @Test func stateActiveWhenMuteExpired() {
        #expect(e(mutedUntil: t0.addingTimeInterval(-1)).state(now: t0) == .active)
    }

    // MARK: - 하위호환

    @Test func sourceDefaultsToAndroidWhenNil() {
        #expect(e().sourceOrDefault == .android)
        #expect(e(source: .apple).sourceOrDefault == .apple)
    }

    @Test func legacyJSONWithoutNewFieldsDecodes() throws {
        let json = """
        {"id":"E5A0C1D2-0000-0000-0000-000000000001","kind":"throttling","severity":"critical","serial":"R5C1","title":"T","detail":"D","at":"2026-09-24T00:00:00Z","isClear":false}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let dec = try decoder.decode(WatchEvent.self, from: Data(json.utf8))
        #expect(dec.source == nil)
        #expect(dec.ackAt == nil)
        #expect(dec.note == nil)
        #expect(dec.mutedUntil == nil)
        #expect(dec.sourceOrDefault == .android)
    }

    @Test func codableRoundTripIncludesNewFields() throws {
        let original = e(
            source: .apple,
            ackAt: t0.addingTimeInterval(10),
            note: "handled",
            mutedUntil: t0.addingTimeInterval(3600)
        )
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(original)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let decoded = try dec.decode(WatchEvent.self, from: data)
        #expect(decoded.source == .apple)
        #expect(decoded.ackAt != nil)
        #expect(decoded.note == "handled")
        #expect(decoded.mutedUntil != nil)
    }

    // MARK: - 필터

    @Test func filterByStateActiveExcludesMutedAndCleared() {
        let active = e(serial: "A")
        let muted = e(serial: "M", mutedUntil: t0.addingTimeInterval(60))
        let cleared = e(serial: "C", isClear: true)
        let f = AlertsFilter(state: .active)
        let out = WatchEventAlerts.filter([active, muted, cleared], by: f, now: t0)
        #expect(out.map(\.serial) == ["A"])
    }

    @Test func filterBySeverityMulti() {
        let info = e(sev: .info)
        let warn = e(sev: .warning)
        let crit = e(sev: .critical)
        let f = AlertsFilter(severities: [.warning, .critical])
        let out = WatchEventAlerts.filter([info, warn, crit], by: f, now: t0)
        #expect(out.count == 2)
    }

    @Test func filterBySourceAppleOnly() {
        let and = e(serial: "A", source: .android)
        let apl = e(serial: "P", source: .apple)
        let f = AlertsFilter(sources: [.apple])
        let out = WatchEventAlerts.filter([and, apl], by: f, now: t0)
        #expect(out.map(\.serial) == ["P"])
    }

    @Test func filterBySinceUntil() {
        let old = e(at: t0)
        let mid = e(serial: "M", at: t0.addingTimeInterval(3600))
        let recent = e(serial: "R", at: t0.addingTimeInterval(7200))
        var f = AlertsFilter()
        f.since = t0.addingTimeInterval(1800)
        f.until = t0.addingTimeInterval(5400)
        let out = WatchEventAlerts.filter([old, mid, recent], by: f, now: t0)
        #expect(out.map(\.serial) == ["M"])
    }

    @Test func filterBySearchTitleDetailSerial() {
        let a = e(serial: "R5C1", title: "스로틀링", detail: "Status 3")
        let b = e(serial: "X9", title: "충전", detail: "AC")
        #expect(WatchEventAlerts.filter([a, b], by: AlertsFilter(search: "스로틀"), now: t0).count == 1)
        #expect(WatchEventAlerts.filter([a, b], by: AlertsFilter(search: "X9"), now: t0).count == 1)
        #expect(WatchEventAlerts.filter([a, b], by: AlertsFilter(search: "Status"), now: t0).count == 1)
    }

    @Test func filterBySerialExact() {
        let a = e(serial: "S1")
        let b = e(serial: "S2")
        let out = WatchEventAlerts.filter([a, b], by: AlertsFilter(serial: "S1"), now: t0)
        #expect(out.count == 1)
    }

    // MARK: - 카운트

    @Test func countsSplitActiveMutedCleared() {
        let events = [
            e(serial: "1"),
            e(serial: "2", mutedUntil: t0.addingTimeInterval(60)),
            e(serial: "3", isClear: true)
        ]
        let counts = WatchEventAlerts.counts(events, filteredBy: AlertsFilter(), now: t0)
        #expect(counts[.active] == 1)
        #expect(counts[.muted] == 1)
        #expect(counts[.cleared] == 1)
    }

    // MARK: - 그룹핑

    @Test func groupByDevicePreservesOrderAndSource() {
        let a1 = e(serial: "A", source: .android)
        let p1 = e(serial: "P", source: .apple)
        let a2 = e(kind: .chargeChanged, serial: "A", source: .android)
        let groups = WatchEventAlerts.groupByDevice([a1, p1, a2])
        #expect(groups.count == 2)
        #expect(groups[0].key == "A")
        #expect(groups[0].events.count == 2)
        #expect(groups[1].source == .apple)
    }

    // MARK: - 업데이트

    @Test func updatingAckNoteMuteIndependently() {
        var ev = e()
        ev = ev.updating(ackAt: t0, setAck: true)
        #expect(ev.ackAt != nil)
        #expect(ev.note == nil)
        ev = ev.updating(note: "메모", setNote: true)
        #expect(ev.ackAt != nil)
        #expect(ev.note == "메모")
        ev = ev.updating(mutedUntil: t0.addingTimeInterval(60), setMute: true)
        #expect(ev.state(now: t0) == .muted)
        ev = ev.updating(mutedUntil: nil, setMute: true)
        #expect(ev.state(now: t0) == .active)
        #expect(ev.ackAt != nil)
    }

    // MARK: - export

    @Test func exportCSVHeaderAndEscape() throws {
        let ev = e(title: "제목, 포함", detail: "line\nbreak", source: .apple, note: "quote\"x")
        let csv = WatchEventAlerts.exportCSV([ev], now: t0)
        let lines = csv.split(separator: "\n")
        #expect(lines.first == "at,source,serial,kind,severity,state,title,detail,ackAt,note,mutedUntil")
        #expect(csv.contains("\"제목, 포함\""))
        #expect(csv.contains("\"quote\"\"x\""))
        #expect(csv.contains(",apple,"))
        #expect(csv.contains(",active,"))
    }

    @Test func exportJSONDecodesBack() throws {
        let events = [e(source: .apple), e(serial: "B")]
        let data = try #require(WatchEventAlerts.exportJSON(events))
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let back = try dec.decode([WatchEvent].self, from: data)
        #expect(back.count == 2)
        #expect(back.contains { $0.sourceOrDefault == .apple })
    }

    // MARK: - ConsoleStore 업데이트

    @Test func storeAckAndMutePersistInMemory() {
        let store = ConsoleStore.shared
        let before = store.recentWatchEvents.count
        let id = UUID()
        var injected = WatchEvent(
            kind: .throttling,
            severity: .critical,
            serial: "DEBUG-ALERTS",
            title: "ALERTS-TEST",
            detail: "ack/mute",
            at: t0
        )
        // id 고정 비교용 — debugIngestWatchQuietly는 새 UUID 유지
        store.debugIngestWatchQuietly(injected)
        #expect(store.recentWatchEvents.count == before + 1)
        let storedId = store.recentWatchEvents[0].id
        _ = id
        _ = injected
        store.ackWatchEvent(id: storedId, at: t0)
        #expect(store.recentWatchEvents[0].ackAt == t0)
        store.muteWatchEvent(id: storedId, until: t0.addingTimeInterval(3600))
        #expect(store.recentWatchEvents[0].state(now: t0) == .muted)
        store.setWatchNote(id: storedId, note: "n")
        #expect(store.recentWatchEvents[0].note == "n")
        store.muteWatchEvent(id: storedId, until: nil)
        #expect(store.recentWatchEvents[0].state(now: t0) == .active)
    }
}
