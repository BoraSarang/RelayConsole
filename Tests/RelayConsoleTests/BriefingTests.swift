import XCTest
@testable import RelayConsole

final class BriefingTests: XCTestCase {
    private func site(
        name: String = "api",
        enabled: Bool = true,
        failThreshold: Int = 1,
        history: [SiteCheck] = [SiteCheck(ok: true)]
    ) -> Site {
        var s = Site(name: name, target: "https://example.com", probe: .http, failThreshold: failThreshold)
        s.enabled = enabled
        s.history = history
        return s
    }

    private func job(
        name: String = "backup",
        enabled: Bool = true,
        lastBeatAt: Date? = nil,
        expectEverySec: Int = 60,
        createdAt: Date = Date().addingTimeInterval(-600)
    ) -> Job {
        Job(
            name: name,
            expectEverySec: expectEverySec,
            lastBeatAt: lastBeatAt,
            lastBeatOk: lastBeatAt != nil,
            enabled: enabled,
            createdAt: createdAt
        )
    }

    private func crit(
        serial: String = "S1",
        kind: WatchKind = .throttling,
        isClear: Bool = false,
        at: Date = Date()
    ) -> WatchEvent {
        WatchEvent(
            kind: kind,
            severity: .critical,
            serial: serial,
            title: "T",
            detail: "D",
            at: at,
            isClear: isClear
        )
    }

    func testSnapshotCountsUpAndDownSites() {
        let up = site(name: "a", history: [SiteCheck(ok: true)])
        var down = site(name: "b", history: [SiteCheck(ok: false)])
        down.failThreshold = 1
        let disabled = site(name: "c", enabled: false, history: [SiteCheck(ok: false)])

        let snap = BriefingLogic.snapshot(
            sites: [up, down, disabled],
            jobs: [],
            androidOnline: 0,
            androidTotal: 0,
            appleOnline: 0,
            appleTotal: 0,
            events: []
        )
        XCTAssertEqual(snap.upSites, 1)
        XCTAssertEqual(snap.downSites, 1)
        XCTAssertEqual(snap.totalSites, 2)
        XCTAssertEqual(snap.tone, .warn)
    }

    func testSnapshotOverdueJobCounts() {
        let overdue = job(name: "late", lastBeatAt: Date().addingTimeInterval(-300), expectEverySec: 60)
        let ok = job(name: "ok", lastBeatAt: Date(), expectEverySec: 60)

        let snap = BriefingLogic.snapshot(
            sites: [],
            jobs: [overdue, ok],
            androidOnline: 1,
            androidTotal: 1,
            appleOnline: 0,
            appleTotal: 0,
            events: []
        )
        XCTAssertEqual(snap.overdueJobs, 1)
        XCTAssertEqual(snap.onlinePhones, 1)
        XCTAssertEqual(snap.totalPhones, 1)
        XCTAssertEqual(snap.tone, .warn)
    }

    func testSnapshotAllHealthyIsOk() {
        let snap = BriefingLogic.snapshot(
            sites: [site()],
            jobs: [job(lastBeatAt: Date())],
            androidOnline: 2,
            androidTotal: 2,
            appleOnline: 1,
            appleTotal: 1,
            events: []
        )
        XCTAssertEqual(snap.tone, .ok)
        XCTAssertEqual(snap.activeCriticals, 0)
        XCTAssertEqual(snap.formatArgs as? [Int], [1, 1, 0, 3, 3, 0])
    }

    /// ★ 이 테스트는 **의도적으로 정정**했다 (2026-09-28)
    ///
    /// 예전엔 **입력 배열의 순서**로 판단했다 (`[enter, clear]` → 1, `[clear, enter]` → 0).
    /// 그런데 이벤트 `at`(시각)이 이미 순서를 담고 있고, 저장 포맷은 **최신 우선**이라
    /// **순서만 보고 판단하면 특정 배열에서 오답**이 났다. 실제로 같은 지문의 반복 enter 를
    /// N건으로 세어 "미해소 알림 76" 같은 **거짓 수**를 만들었다.
    /// → 이제 **시각**으로 판단하고, **입력 순서와 무관**하게 답한다.
    func testActiveCriticalCountIgnoresClearedFingerprint() {
        let clear = crit(serial: "S1", isClear: true, at: Date())
        let enter = crit(serial: "S1", at: Date().addingTimeInterval(10))  // clear 이후 진입 → 미해소
        // 어떤 순서로 줘도 시각 기준 답은 같다 — 최신 enter, 이전 clear
        XCTAssertEqual(BriefingLogic.activeCriticalCount([enter, clear]), 1)
        XCTAssertEqual(BriefingLogic.activeCriticalCount([clear, enter]), 1, "입력 순서가 답을 바꾸지 않는다")

        // clear 가 enter 보다 **나중**이면 해소
        let lateClear = crit(serial: "S1", isClear: true, at: Date().addingTimeInterval(20))
        let earlyEnter = crit(serial: "S1", at: Date())
        XCTAssertEqual(BriefingLogic.activeCriticalCount([lateClear, earlyEnter]), 0,
                       "해소 시각이 진입 시각보다 늦으면 미해소가 아니다")
    }

    func testActiveCriticalCountSeparatesSerials() {
        let a = crit(serial: "A")
        let b = crit(serial: "B")
        XCTAssertEqual(BriefingLogic.activeCriticalCount([a, b]), 2)
        // 최신 first — A clear가 더 위(인덱스 작음)면 A만 해제, B 유지
        XCTAssertEqual(
            BriefingLogic.activeCriticalCount([crit(serial: "A", isClear: true), a, b]),
            1
        )
    }

    func testCriticalToneBeatsWarn() {
        let snap = BriefingLogic.snapshot(
            sites: [],
            jobs: [],
            androidOnline: 0,
            androidTotal: 1,
            appleOnline: 0,
            appleTotal: 0,
            events: [crit()]
        )
        XCTAssertEqual(snap.tone, .bad)
        XCTAssertEqual(snap.activeCriticals, 1)
    }

    func testDisabledJobNotOverdue() {
        let disabled = job(name: "off", enabled: false, lastBeatAt: Date().addingTimeInterval(-9999))
        let snap = BriefingLogic.snapshot(
            sites: [],
            jobs: [disabled],
            androidOnline: 0,
            androidTotal: 0,
            appleOnline: 0,
            appleTotal: 0,
            events: []
        )
        XCTAssertEqual(snap.overdueJobs, 0)
    }
}
