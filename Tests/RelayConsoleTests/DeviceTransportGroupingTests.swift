import Testing
@testable import RelayConsole

/// 같은 폰이 여러 전송으로 잡힐 때의 화면 묶음 (2026-10-17 · T-2026-10-17-10)
///
/// 실측: S22 하나가 레거시 tcpip(`:5555`)와 무선 디버깅(`:45325`)으로 **동시에** `device` 였고,
/// USB 까지 꽂으면 세 줄이 된다. adb 의 기기 키는 전송이라 그대로 그리면 사용자가
/// 어느 줄을 눌러야 하는지 알 수 없다. **표시만** 합치는 규칙을 여기서 고정한다.
struct DeviceTransportGroupingTests {

    private func snap(
        _ serial: String,
        kind: ConnectionKind?,
        physicalId: String?,
        online: Bool = true,
        name: String = "S22"
    ) -> DeviceSnapshot {
        var d = DeviceSnapshot()
        d.serial = serial
        d.connectionKind = kind
        d.physicalId = physicalId
        d.isOnline = online
        d.deviceName = name
        return d
    }

    private var legacy: DeviceSnapshot {
        snap("192.168.86.49:5555", kind: .network, physicalId: "R5CT215F4QK")
    }
    private var wireless: DeviceSnapshot {
        snap("192.168.86.49:45325", kind: .network, physicalId: "R5CT215F4QK")
    }
    private var usb: DeviceSnapshot {
        snap("R5CT215F4QK", kind: .usb, physicalId: "R5CT215F4QK")
    }

    // MARK: - 전송 구분

    @Test func legacyTcpipAndWirelessAreToldApart() {
        #expect(legacy.isLegacyTcpipEndpoint)
        #expect(!wireless.isLegacyTcpipEndpoint)
        #expect(!usb.isLegacyTcpipEndpoint)
    }

    @Test func transportRankPrefersUSBThenWireless() {
        #expect(usb.transportRank < wireless.transportRank)
        #expect(wireless.transportRank < legacy.transportRank)
    }

    @Test func badgeIsFilledForKnownTransports() {
        #expect(!usb.transportBadge.isEmpty)
        #expect(!wireless.transportBadge.isEmpty)
        #expect(!legacy.transportBadge.isEmpty)
        // 무선과 레거시는 다른 문구여야 한다 — 재부팅 내구성이 정반대다
        #expect(wireless.transportBadge != legacy.transportBadge)
    }

    // MARK: - 묶기

    @Test func twoNetworkTransportsOfOnePhoneBecomeOneRow() {
        let groups = DeviceInventory.group([legacy, wireless])
        #expect(groups.count == 1)
        #expect(groups[0].hasMultipleTransports)
        // 대표는 재부팅 후에도 살아남는 무선 디버깅
        #expect(groups[0].primary.serial == "192.168.86.49:45325")
        #expect(groups[0].others.map(\.serial) == ["192.168.86.49:5555"])
    }

    @Test func usbPlusWirelessPlusLegacyBecomeOneRow() {
        let groups = DeviceInventory.group([wireless, legacy, usb])
        #expect(groups.count == 1)
        #expect(groups[0].primary.serial == "R5CT215F4QK")
        #expect(groups[0].others.count == 2)
    }

    @Test func differentPhonesStaySeparate() {
        let other = snap("192.168.86.30:5555", kind: .network, physicalId: "RQCT1234ABC", name: "Router")
        let groups = DeviceInventory.group([legacy, other])
        #expect(groups.count == 2)
        #expect(groups.allSatisfy { !$0.hasMultipleTransports })
    }

    @Test func unknownPhysicalIdIsNotMerged() {
        // 물리 고유값을 모르면 묶지 않는다 — 추측으로 남의 폰을 합치면 안 된다
        let a = snap("192.168.86.49:5555", kind: .network, physicalId: nil)
        let b = snap("192.168.86.49:45325", kind: .network, physicalId: nil)
        #expect(DeviceInventory.group([a, b]).count == 2)
    }

    @Test func selectedTransportBecomesPrimary() {
        // 5555 를 쓰고 있으면 그 줄이 대표로 보여야 화면 선택 표시와 어긋나지 않는다
        let groups = DeviceInventory.group([legacy, wireless], selected: "192.168.86.49:5555")
        #expect(groups[0].primary.serial == "192.168.86.49:5555")
        #expect(groups[0].contains("192.168.86.49:45325"))
    }

    @Test func selectedButOfflineTransportDoesNotBecomePrimary() {
        // 선택이 아직 따라오지 않은 순간: 죽은 5555 를 활성인 것처럼 보여주면 안 된다
        let deadLegacy = snap("192.168.86.49:5555", kind: .network, physicalId: "R5CT215F4QK", online: false)
        let groups = DeviceInventory.group([deadLegacy, wireless], selected: "192.168.86.49:5555")
        #expect(groups[0].primary.serial == "192.168.86.49:45325")
        #expect(groups[0].others.map(\.serial) == ["192.168.86.49:5555"])
    }

    @Test func onlineTransportBeatsOfflineOne() {
        let offlineUSB = snap("R5CT215F4QK", kind: .usb, physicalId: "R5CT215F4QK", online: false)
        let groups = DeviceInventory.group([offlineUSB, wireless])
        #expect(groups[0].primary.serial == "192.168.86.49:45325")
    }

    @Test func groupOrderFollowsFirstAppearance() {
        let other = snap("192.168.86.30:5555", kind: .network, physicalId: "RQCT1234ABC", name: "Router")
        let groups = DeviceInventory.group([other, wireless, legacy])
        #expect(groups.map(\.primary.displayName) == ["Router", "S22"])
        #expect(groups[1].others.count == 1)
    }

    @Test func groupKeyUsesPhysicalIdWhenKnown() {
        #expect(DeviceInventory.groupKey(wireless) == DeviceInventory.groupKey(legacy))
        #expect(DeviceInventory.groupKey(usb) == DeviceInventory.groupKey(legacy))
        let unknown = snap("192.168.86.49:5555", kind: .network, physicalId: nil)
        #expect(DeviceInventory.groupKey(unknown) == "serial:192.168.86.49:5555")
    }

    @Test func emptyListYieldsNoGroups() {
        #expect(DeviceInventory.group([]).isEmpty)
    }
}
