import XCTest
@testable import RelayConsole

/// 재연결 후보에서 **서브넷 이웃**을 쓰는 근거와 한계 (2026-09-28)
///
/// 사용자 지적: "전에 연결되었던 IP — 게이트웨이가 연결 상태면 adb wifi 다시 연결 시도 안하니?"
/// → 맞아, **이전 IP 를 첫 후보로** 넣어야 한다. 게이트웨이 하나로 서달라고 하면
/// SoftAP 아닌 네트워크에서 반드시 실패한다.
final class WifiReconnectNeighborTests: XCTestCase {

    // MARK: - 서브넷 접두사

    func testSubnetPrefixOfIPv4() {
        XCTAssertEqual(WifiAdbLogic.subnetPrefix(ip: "10.38.120.211"), "10.38.120")
    }

    /// IPv4 가 아니면 접두사를 만들지 않는다 — 잘못된 후보를 만들지 않는다
    func testSubnetPrefixRejectsNonIPv4() {
        XCTAssertNil(WifiAdbLogic.subnetPrefix(ip: "10.38.120"))
        XCTAssertNil(WifiAdbLogic.subnetPrefix(ip: "notanip"))
        XCTAssertNil(WifiAdbLogic.subnetPrefix(ip: "10.38.120.211.5"))
    }

    // MARK: - ARP 파싱 — 실제 `arp -an` 출력 형태

    private let arpSample = """
    ? (10.38.120.146) at 56:e2:8e:4e:98:e6 on en0 ifscope [ethernet]
    ? (10.38.120.193) at 8a:3f:1b:f8:3c:a9 on en0 ifscope permanent [ethernet]
    ? (10.38.120.211) at e6:82:5d:b7:32:b4 on en0 ifscope [ethernet]
    ? (10.38.120.255) at ff:ff:ff:ff:ff:ff on en0 ifscope [ethernet]
    ? (224.0.0.251) at 1:0:5e:0:0:fb on en0 ifscope permanent [ethernet]
    """

    /// **같은 서브넷만** — 다른 네트워크의 이웃이 후보가 되면 안 된다
    func testArpParsesOnlySameSubnet() {
        let out = WifiAdbLogic.parseArpIPs(arpSample, onSubnet: "10.38.120")
        XCTAssertTrue(out.contains("10.38.120.211"))
        XCTAssertFalse(out.contains("224.0.0.251"), "멀티캐스트는 이웃이 아니다")
    }

    /// 브로드캐스트는 후보가 아니다 — 붙을 대상이 없다
    func testBroadcastIsExcluded() {
        let out = WifiAdbLogic.parseArpIPs(arpSample, onSubnet: "10.38.120")
        XCTAssertFalse(out.contains("10.38.120.255"), "브로드캐스트 주소에 붙으려 하면 안 된다")
    }

    /// 접두사만 같으면 넣지 않는다 — `10.38.1201.x` 같은 것을 막는다
    func testPrefixMatchIsNotSubstringMatch() {
        let text = "? (10.38.1201.7) at aa:bb:cc:dd:ee:ff on en0 [ethernet]"
        let out = WifiAdbLogic.parseArpIPs(text, onSubnet: "10.38.120")
        XCTAssertTrue(out.isEmpty, "부분 문자열 일치로 후보가 되면 안 된다")
    }

    func testEmptyArpGivesEmptyResult() {
        XCTAssertTrue(WifiAdbLogic.parseArpIPs("", onSubnet: "10.38.120").isEmpty)
    }

    // MARK: - 엔드포인트

    func testHostOfEndpoint() {
        XCTAssertEqual(WifiAdbLogic.host(ofEndpoint: "10.38.120.211:5555"), "10.38.120.211")
    }

    /// 포트만 있거나 형식이 이상하면 nil
    func testHostOfMalformedEndpoint() {
        XCTAssertNil(WifiAdbLogic.host(ofEndpoint: "5555"))
        XCTAssertNil(WifiAdbLogic.host(ofEndpoint: "notanip:5555"))
    }

    // MARK: - ★ 후보 순서 (사용자 지적이 가리킨 것)

    /// 게이트웨이보다 **이전 IP** 가 먼저여야 한다
    /// — SoftAP 아닌 네트워크에서 게이트웨이만으로는 반드시 실패한다
    func testPreviousEndpointComesBeforeGateway() {
        let order = WifiAdbLogic.reconnectCandidateOrder(
            lastEndpoint: "10.38.120.211:5555",
            lostSerial: "10.38.120.211:5555",
            deviceReported: [],
            gateway: "192.168.0.1",
            arpNeighbours: []
        )
        XCTAssertEqual(order.first, "10.38.120.211",
                       "전에 붙었던 IP 가 게이트웨이보다 먼저여야 한다")
        XCTAssertEqual(order.last, "192.168.0.1", "게이트웨이는 후순위")
    }

    /// 기기가 USB 로 살아 있으면 그 답이 **게이트웨이보다 정확**하다
    func testDeviceReportedBeatsGateway() {
        let order = WifiAdbLogic.reconnectCandidateOrder(
            lastEndpoint: nil,
            lostSerial: "10.0.0.5:5555",
            deviceReported: ["192.168.1.77"],
            gateway: "192.168.0.1",
            arpNeighbours: []
        )
        XCTAssertTrue(order.contains("192.168.1.77"))
        XCTAssertLessThan(
            try XCTUnwrap(order.firstIndex(of: "192.168.1.77")),
            try XCTUnwrap(order.firstIndex(of: "192.168.0.1")),
            "기기가 말한 주소가 라우터보다 먼저여야 한다"
        )
    }

    /// 중복은 한 번만 — 옛 IP 와 lost IP 가 같을 수 있다
    func testDuplicatesAreRemoved() {
        let order = WifiAdbLogic.reconnectCandidateOrder(
            lastEndpoint: "10.0.0.5:5555",
            lostSerial: "10.0.0.5:5555",
            deviceReported: ["10.0.0.5"],
            gateway: "10.0.0.5",
            arpNeighbours: ["10.0.0.5"]
        )
        XCTAssertEqual(order, ["10.0.0.5"])
    }
}
