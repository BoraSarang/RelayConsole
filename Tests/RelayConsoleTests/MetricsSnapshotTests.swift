import XCTest
@testable import RelayConsole

/// 도메인 → 지표 변환 — **기존 판정 로직과 어긋나면 안 된다**
///
/// 지표는 "값을 보여주기" 다. 값이 **거짓**이면 사용자는 대시보드를 보고도 모른다.
/// 그래서 이 변환도 테스트한다 (store 는 `private init` 싱글턴이라 쓸 수 없다 —
/// 그래서 변환을 `MetricsSnapshotBuilder` 로 꺼냈다).
final class MetricsSnapshotTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func make(
        devices: [DeviceSnapshot] = [],
        sites: [Site] = [],
        jobs: [Job] = [],
        events: [WatchEvent] = []
    ) -> MetricsSnapshot {
        MetricsSnapshotBuilder.make(
            devices: devices, sites: sites, jobs: jobs, events: events,
            now: now, version: "9.9.9"
        )
    }

    // MARK: - 잡 지연 초

    func testOverdueSecondsIsNilAtGraceBoundary() {
        // 주기 60초 · 마지막 수신이 정확히 60초 전 → isOverdue 는 아직 false(1.5배 미달)
        let job = Job(name: "j", expectEverySec: 60,
                      lastBeatAt: now.addingTimeInterval(-60),
                      createdAt: now.addingTimeInterval(-600))
        XCTAssertNil(MetricsSnapshotBuilder.overdueSeconds(job, now: now))
    }

    func testOverdueSecondsCountsPastDeadline() {
        // 주기 60초인데 180초 전 수신 → 기한(60초 전)을 120초 넘겼다
        let job = Job(name: "j", expectEverySec: 60,
                      lastBeatAt: now.addingTimeInterval(-180),
                      createdAt: now.addingTimeInterval(-1000))
        XCTAssertEqual(MetricsSnapshotBuilder.overdueSeconds(job, now: now) ?? 0, 120, accuracy: 1)
    }

    func testOverdueSecondsForNeverReceivedBeat() {
        // 미수신 + grace 경과 → 기한은 createdAt + 주기 = 240초 전
        let job = Job(name: "j", expectEverySec: 60, lastBeatAt: nil,
                      createdAt: now.addingTimeInterval(-300))
        XCTAssertEqual(MetricsSnapshotBuilder.overdueSeconds(job, now: now) ?? 0, 240, accuracy: 1)
    }

    func testOverdueSecondsIsNilWhileGraceNotOver() {
        // 방금 만들어진 잡 → grace 유보 (isOverdue 가 nil)
        let job = Job(name: "j", expectEverySec: 60, lastBeatAt: nil, createdAt: now)
        XCTAssertNil(MetricsSnapshotBuilder.overdueSeconds(job, now: now))
    }

    func testOverdueSecondsNeverNegative() {
        let job = Job(name: "j", expectEverySec: 30,
                      lastBeatAt: now.addingTimeInterval(-1000),
                      createdAt: now.addingTimeInterval(-1000))
        let v = MetricsSnapshotBuilder.overdueSeconds(job, now: now)
        XCTAssertNotNil(v)
        XCTAssertGreaterThanOrEqual(v ?? -1, 0)
    }

    func testDisabledJobHasNoOverdue() {
        var job = Job(name: "j", expectEverySec: 60,
                      lastBeatAt: now.addingTimeInterval(-9999),
                      createdAt: now.addingTimeInterval(-9999))
        job.enabled = false
        XCTAssertNil(MetricsSnapshotBuilder.overdueSeconds(job, now: now))
    }

    // MARK: - 스냅숏 규칙

    func testDisabledSiteAndJobProduceNoRows() {
        var site = Site(name: "off", target: "https://off.example.com", probe: .http)
        site.enabled = false
        var job = Job(name: "off", expectEverySec: 60)
        job.enabled = false

        let snap = make(sites: [site], jobs: [job])
        XCTAssertTrue(snap.sites.isEmpty, "비활성 사이트는 행을 내지 않는다")
        XCTAssertTrue(snap.jobs.isEmpty, "비활성 잡은 행을 내지 않는다")
    }

    func testSiteNeverCheckedIsUndecidedNotDown() {
        // history 가 비면 effectiveUp() 이 nil → "죽었다" 고 말하지 않는다
        let snap = make(sites: [Site(name: "fresh", target: "https://fresh.example.com", probe: .http)])
        XCTAssertEqual(snap.sites.count, 1)
        XCTAssertNil(snap.sites[0].isUp, "판정 유보(nil) 여야 한다")

        let text = MetricsTextBuilder.render(snap)
        XCTAssertFalse(text.contains("relay_site_up{name=\"fresh\""))
    }

    func testSiteWithOkCheckIsUp() {
        let site = Site(
            name: "api", target: "https://api.example.com", probe: .http,
            history: [SiteCheck(ok: true, latencyMs: 120)]
        )
        XCTAssertEqual(make(sites: [site]).sites[0].isUp, true)
    }

    func testSiteFailingBelowThresholdIsStillUp() {
        // 연속 실패가 failThreshold 미만 → flapping 보호로 여전히 up
        let site = Site(
            name: "flap", target: "https://f.example.com", probe: .http, failThreshold: 2,
            history: [SiteCheck(ok: true, latencyMs: 10), SiteCheck(ok: false)]
        )
        XCTAssertEqual(make(sites: [site]).sites[0].isUp, true)
    }

    func testSiteFailingPastThresholdIsDown() {
        let site = Site(
            name: "dead", target: "https://d.example.com", probe: .http, failThreshold: 2,
            history: [SiteCheck(ok: true, latencyMs: 10), SiteCheck(ok: false), SiteCheck(ok: false)]
        )
        XCTAssertEqual(make(sites: [site]).sites[0].isUp, false)
    }

    func testOfflineDeviceHasNoBatteryValue() {
        var d = DeviceSnapshot()
        d.serial = "OFF1"
        d.model = "Pixel"
        d.isOnline = false
        d.batteryLevel = 42
        let snap = make(devices: [d])
        // 오프라인 기기의 배터리는 "확인하지 못했다" — 저장값이 있어도 내지 않는다
        XCTAssertNil(snap.devices[0].batteryPercent)
        let text = MetricsTextBuilder.render(snap)
        XCTAssertTrue(text.contains("serial=\"OFF1\""), "오프라인 기기는 행이 있다 (사라지면 구분 불가)")
        XCTAssertFalse(text.contains("relay_device_battery_percent{serial=\"OFF1\""))
    }

    func testOnlineDeviceKeepsBattery() {
        var d = DeviceSnapshot()
        d.serial = "ON1"
        d.model = "SM-S901N"
        d.isOnline = true
        d.batteryLevel = 87
        d.connectionKind = .network
        let snap = make(devices: [d])
        XCTAssertEqual(snap.devices[0].batteryPercent, 87)
        XCTAssertEqual(snap.devices[0].connectionKind, "network")
    }

    func testSSLRemainingIsNegativeWhenAlreadyExpired() {
        var site = Site(name: "old", target: "https://o.example.com", probe: .http)
        site.sslExpiresAt = now.addingTimeInterval(-86400)
        let snap = make(sites: [site])
        // 만료가 지나면 **음수**가 정직하다 — 0 으로 접으면 "오늘 만료" 와 구분되지 않는다
        XCTAssertEqual(snap.sites[0].sslExpiresInSeconds ?? 0, -86400, accuracy: 1)
    }

    func testVersionIsCarriedThrough() {
        XCTAssertEqual(make().version, "9.9.9")
        XCTAssertTrue(MetricsTextBuilder.render(make()).contains(#"relay_build_info{build="9.9.9",version="9.9.9"} 1"#))
    }

    func testRenderProducesValidExpositionEnding() {
        let text = MetricsTextBuilder.render(make())
        XCTAssertTrue(text.hasSuffix("\n"))
        XCTAssertFalse(text.contains("\n\n"))
        XCTAssertTrue(text.contains("relay_heartbeat_up 1"))
        XCTAssertTrue(text.contains("relay_alert_active_critical 0"))
    }
}
