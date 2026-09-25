import Foundation
import Testing
@testable import RelayConsole

/// 대시보드 정리 — 카드 순서 / 행 동기화 / 탐지(설정 변경·logcat) 구조화 (2026-09-25)
struct DashboardLayoutTests {
    // MARK: - 순서 (우선순위)

    @Test func rowsFollowOpsPriority() {
        #expect(DashboardCard.rows == [
            [.cpu, .thermal],
            [.memory, .network],
            [.battery, .health],
            [.gpu, .storage]
        ])
        #expect(DashboardCard.wideCards == [.sensors])
    }

    @Test func orderedCoversEveryCardExactlyOnce() {
        let ordered = DashboardCard.ordered
        #expect(ordered.count == DashboardCard.allCases.count)
        #expect(Set(ordered) == Set(DashboardCard.allCases))
        #expect(ordered.first == .cpu)
        #expect(ordered.last == .sensors)
    }

    @Test func settingsLabelKeysResolve() {
        for card in DashboardCard.allCases {
            let key = card.settingsLabelKey
            #expect(L10n.string(key) != key, "missing L10n key: \(key)")
        }
    }

    // MARK: - 탐지 L10n 키

    @Test func detectKeysResolve() {
        let keys = [
            "droid.detect.title",
            "droid.detect.settings",
            "droid.detect.logcat",
            "droid.detect.logs",
            "droid.detect.empty",
            "kind.settingsChanged",
            "kind.logcatHits",
            "event.settingsChanged.src",
            "event.logcatHits.window"
        ]
        for key in keys {
            #expect(L10n.string(key) != key, "missing L10n key: \(key)")
        }
        // en/ko 1:1 — 포맷 인자 보존
        #expect(L10n.string("event.logcatHits.window").contains("%@"))
        #expect(L10n.string("event.logcatHits.window").contains("%d"))
    }

    // MARK: - 탐지 이벤트

    @Test func detectEventSeverityIsInfo() {
        let e = WatchEvent.detect(
            kind: .settingsChanged,
            serial: "R5CR10ABCDE",
            title: "설정 변경 accelerometer_rotation 0→1",
            detail: "settings get system"
        )
        #expect(e.severity == .info)
        #expect(e.kind.isDetectKind)
        #expect(WatchKind.logcatHits.isDetectKind)
        #expect(!WatchKind.crash.isDetectKind)
    }

    @Test func detectEventsDoNotInflateDailyCounts() {
        var daily = DeviceDaily(serial: "S1", dayKey: "20260925")
        DeviceDailyLogic.countEvent(into: &daily, kind: .settingsChanged, isClear: false)
        DeviceDailyLogic.countEvent(into: &daily, kind: .logcatHits, isClear: false)
        #expect(daily.warnEvents == 0)
        #expect(daily.criticalEvents == 0)
        #expect(daily.crashEvents == 0)
        #expect(daily.anrEvents == 0)
    }

    // MARK: - 오늘 집계

    @Test func todayFiltersBySerialKindAndDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let settings = WatchEvent.detect(
            kind: .settingsChanged, serial: "S1", title: "t1", detail: "d1", at: now
        )
        let logcat = WatchEvent.detect(
            kind: .logcatHits, serial: "S1", title: "t2", detail: "d2", at: now
        )
        let otherDevice = WatchEvent.detect(
            kind: .settingsChanged, serial: "S2", title: "t3", detail: "d3", at: now
        )
        let yesterday = WatchEvent.detect(
            kind: .settingsChanged,
            serial: "S1",
            title: "t4",
            detail: "d4",
            at: now.addingTimeInterval(-86_400)
        )
        let notDetect = WatchEvent(
            kind: .throttling, severity: .warning, serial: "S1",
            title: "t5", detail: "d5", at: now
        )

        let events = [settings, logcat, otherDevice, yesterday, notDetect]
        let today = DetectLogic.today(events: events, serial: "S1", now: now, calendar: cal)

        #expect(today.map(\.id) == [settings.id, logcat.id])
        let counts = DetectLogic.counts(today)
        #expect(counts.settings == 1)
        #expect(counts.logcat == 1)
        #expect(DetectLogic.today(events: events, serial: "", now: now, calendar: cal).isEmpty)
    }

    // MARK: - logcat 키워드 분해

    @Test func logcatHitBreakdownMatchesCount() {
        let sample = """
        09-23 19:30:04.962  1235  1235 I WindowManager: accelerometer_rotation set to 1
        09-23 19:30:05.100  1235  1235 I wm: wm_user_rotation_changed rotation=0
        09-23 19:30:05.200  1235  1235 I ThermalEngine: thermal level changed
        09-23 19:30:05.300  1235  1235 I unrelated: hello world
        """
        let breakdown = AdbClient.logcatHitBreakdown(sample)
        #expect(breakdown.reduce(0) { $0 + $1.count } == AdbClient.countLogcatHits(sample))
        #expect(breakdown.first { $0.keyword == "accelerometer_rotation" }?.count == 1)
        #expect(breakdown.first { $0.keyword == "wm_user_rotation_changed" }?.count == 1)
        #expect(breakdown.first { $0.keyword == "thermal" }?.count == 1)
        #expect(breakdown.count == 3)
        #expect(AdbClient.logcatHitBreakdown("", keywords: []).isEmpty)
    }

    @Test func logcatHitBreakdownCountsLineOnce() {
        // 한 줄이 여러 키워드에 걸려도 1줄 = 1건 (첫 매칭 키워드에 귀속)
        let multi = "09-23 19:30:04.962 I T: thermal accelerometer_rotation"
        let breakdown = AdbClient.logcatHitBreakdown(multi)
        #expect(breakdown.reduce(0) { $0 + $1.count } == 1)
        #expect(breakdown.first?.keyword == "accelerometer_rotation")
    }
}
