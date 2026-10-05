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
        events: [WatchEvent] = []
    ) -> MetricsSnapshot {
        MetricsSnapshotBuilder.make(
            devices: devices, events: events,
            now: now, version: "9.9.9"
        )
    }

    // MARK: - 스냅숏 규칙

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

    func testVersionIsCarriedThrough() {
        XCTAssertEqual(make().version, "9.9.9")
        XCTAssertTrue(MetricsTextBuilder.render(make()).contains(#"relay_build_info{build="9.9.9",version="9.9.9"} 1"#))
    }

    func testRenderProducesValidExpositionEnding() {
        let text = MetricsTextBuilder.render(make())
        XCTAssertTrue(text.hasSuffix("\n"))
        XCTAssertFalse(text.contains("\n\n"))
        XCTAssertTrue(text.contains("relay_alert_active_critical 0"))
    }
}
