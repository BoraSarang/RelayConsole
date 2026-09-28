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
