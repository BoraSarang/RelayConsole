import XCTest
@testable import RelayConsole

/// 기기 온라인 판정 — **"연결이 끝났는데 상세가 보인다"** 의 근본을 막는다 (2026-09-28)
///
/// 종전엔 `isOnline` 이 `true` 로 하드코딩돼 있어서, 끊겨도 온라인으로 보였고
/// `markOffline` 을 즉시 되돌렸다. 여기서는 **판정 규칙만** 고정한다.
final class DeviceOnlineJudgementTests: XCTestCase {

    /// 지금 adb 가 응답했다 = 온라인이다 (가장 강한 증거)
    func testResponseMeansOnline() {
        XCTAssertTrue(DeviceMonitor.isOnline(gotAnyResponse: true, failureStreak: 0))
    }

    /// 한 번 실패는 **떨림**일 수 있다 — 오프라인으로 말하지 않는다 (핑퐁 방지)
    func testSingleFailureIsNotOfflineYet() {
        XCTAssertTrue(
            DeviceMonitor.isOnline(gotAnyResponse: false, failureStreak: 1),
            "한 번의 실패만으로 '끊겼다' 고 말하면 떨림에 흔들린다"
        )
    }

    /// 연속 실패가 임계에 도달하면 오프라인이다
    func testStreakReachingThresholdIsOffline() {
        XCTAssertFalse(DeviceMonitor.isOnline(gotAnyResponse: false, failureStreak: 2))
        XCTAssertFalse(DeviceMonitor.isOnline(gotAnyResponse: false, failureStreak: 9))
    }

    /// ★ 종전 결함의 재현 — adb 서버가 transport 를 캐시한 채 응답이 없던 구간
    func testCachedTransportDoesNotCountAsOnline() {
        // adb devices 목록에는 남아 있지만(캐시) 실제 응답은 없다
        XCTAssertFalse(
            DeviceMonitor.isOnline(gotAnyResponse: false, failureStreak: 2),
            "목록에 남아 있다는 이유로 온라인이면 안 된다 — 실측에서 1→0→1 진동이 났다"
        )
    }

    /// 응답이 돌아오면 **즉시** 온라인으로 복귀한다 (확실하니 기다릴 이유가 없다)
    func testRecoveryIsImmediate() {
        XCTAssertTrue(
            DeviceMonitor.isOnline(gotAnyResponse: true, failureStreak: 0),
            "한 번이라도 응답하면 바로 온라인"
        )
    }

    /// 임계는 2다 — 1이 아니고 0도 아니다
    func testThresholdIsTwo() {
        XCTAssertEqual(DeviceMonitor.offlineAfterFailures, 2)
    }
}
