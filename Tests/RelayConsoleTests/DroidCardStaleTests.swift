import XCTest
@testable import RelayConsole

/// 오프라인일 때 카드가 "오래된 값" 임을 보이는지 — **배너로는 부족했다** (2026-09-28)
///
/// 종전에는 상단 배너에 "측정 실패 — 아래 값은 마지막 정상 수집값입니다" 가 떴다.
/// 그런데 카드는 **아무것도 달라지지 않았다.** CPU 14% 가 살아있는 기기처럼 보였다.
/// 사용자는 배너를 읽지 않고 **숫자를 본다.**
final class DroidCardStaleTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func device(online: Bool, measuredAt: Date?) -> DeviceSnapshot {
        var d = DeviceSnapshot()
        d.serial = "S1"
        d.isOnline = online
        d.measuredAt = measuredAt
        return d
    }

    /// 온라인이면 표시하지 않는다 — 정상 상태에서 흐리면 안 된다
    func testOnlineHasNoStaleBadge() {
        XCTAssertNil(DroidCards.staleInfo(for: device(online: true, measuredAt: now), now: now))
    }

    /// 오프라인 + 측정 시각 있음 → 표시
    func testOfflineWithTimestampShowsStale() {
        let info = DroidCards.staleInfo(for: device(online: false, measuredAt: now.addingTimeInterval(-600)), now: now)
        XCTAssertNotNil(info)
    }

    /// ★ 오프라인이지만 **측정 시각이 없으면 표시하지 않는다**
    ///
    /// "언젠지 모르는 값" 을 "오래된 값" 처럼 말하면 그것도 **거짓말**이다.
    func testOfflineWithoutTimestampShowsNothing() {
        XCTAssertNil(
            DroidCards.staleInfo(for: device(online: false, measuredAt: nil), now: now),
            "모르는 시각을 '마지막 측정' 이라고 하면 안 된다"
        )
    }

    /// 기기가 아예 없으면 표시하지 않는다 (빈 슬롯과 "오래됨" 은 다르다)
    func testNoDeviceShowsNothing() {
        XCTAssertNil(DroidCards.staleInfo(for: nil, now: now))
    }

    /// 측정 시각이 **미래**면 표시하지 않는다 — 시계 어긋남일 뿐 "오래된 것" 이 아니다
    func testFutureTimestampShowsNothing() {
        XCTAssertNil(
            DroidCards.staleInfo(for: device(online: false, measuredAt: now.addingTimeInterval(60)), now: now),
            "미래 시각은 '오래됨' 이 아니다"
        )
    }

    /// 표시할 때 **그 시각을 그대로** 담는다 — 몇 초 지났는지가 아니라 "언제 것인가" 를 말해야 한다
    func testStaleCarriesExactTimestamp() {
        let at = now.addingTimeInterval(-3600)
        let info = DroidCards.staleInfo(for: device(online: false, measuredAt: at), now: now)
        XCTAssertEqual(info?.at, at)
    }
}

/// 충전 방치 카드 — 트래커는 끝났고 카드 표시만 없었다 (PR #62 잔여)
///
/// 방치 중이 아니면(충전 중·임계 초과·오프라인·0초) **배너가 없다**.
/// "0초 방치" 는 /metrics 행 없음과 같은 모순이다.
final class DroidCardNeglectTests: XCTestCase {

    private func device(online: Bool, neglectSeconds: Int?) -> DeviceSnapshot {
        var d = DeviceSnapshot()
        d.serial = "S1"
        d.isOnline = online
        d.neglectSeconds = neglectSeconds
        return d
    }

    func testNoBannerWhenNotNeglected() {
        XCTAssertNil(DroidCards.neglectBanner(device(online: true, neglectSeconds: nil)))
        XCTAssertNil(DroidCards.neglectBanner(device(online: true, neglectSeconds: 0)))
        XCTAssertNil(DroidCards.neglectBanner(nil))
    }

    /// 오프라인 기기의 묵은 방치값은 말하지 않는다 — "지금" 이 아닌 것을 지금처럼 보이면 안 된다
    func testNoBannerWhenOffline() {
        XCTAssertNil(DroidCards.neglectBanner(device(online: false, neglectSeconds: 3600)))
    }

    func testBannerShowsDuration() {
        let banner = DroidCards.neglectBanner(device(online: true, neglectSeconds: 3720))
        XCTAssertNotNil(banner)
        XCTAssertTrue(banner?.contains("1") == true, "지속 시간이 보여야 한다: \(banner ?? "")")
    }

    func testDurationUnits() {
        // %d 자리 — %@ 로 되돌리면 L10nFormatTests 전수 스캔이 잡는다
        XCTAssertTrue(DroidCards.neglectDuration(3720).contains("1"))
        XCTAssertTrue(DroidCards.neglectDuration(2700).contains("45"))
        XCTAssertFalse(DroidCards.neglectDuration(30).contains("0분"), "30초를 0분이라 하면 거짓말: \(DroidCards.neglectDuration(30))")
    }

    /// 스냅샷 기본값은 방치 아님 — 폴링이 값을 못 채우면 배너가 나면 안 된다
    func testSnapshotDefaultsToNotNeglected() {
        XCTAssertNil(DeviceSnapshot().neglectSeconds)
    }
}
