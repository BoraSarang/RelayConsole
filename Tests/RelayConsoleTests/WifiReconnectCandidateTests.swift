import XCTest
@testable import RelayConsole

/// Wi-Fi ADB 재연결 IP 판별 — **"게이트웨이 = 기기 IP" 는 SoftAP 일 때만 성립** (2026-09-28)
///
/// 종전에는 게이트웨이를 **최우선 반환**했다. 그건 SoftAP 가 아닐 수 있음에도
/// 성립하지 않으며, 집 Wi-Fi 에서 같은 로직이 **라우터로 붙으러 가** 결과적으로
/// "USB 로는 연결되는데 인터넷으로 넘어가면 못 찾는다" 가 된다.
final class WifiReconnectCandidateTests: XCTestCase {

    /// 실제 `ip -f inet addr` 원문 — **축약하면 파서가 못 읽는다**
    private let ifAddrSample = """
    1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536
        inet 127.0.0.1/8 scope host lo
    60: swlan0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500
        inet 192.168.0.55/24 brd 192.168.0.255 scope global swlan0
    """

    /// ★ 종전의 함정 — 게이트웨이가 **앞에** 나온다 (라우터로 붙으러 간다)
    func testGatewayIsNotFirstWhenDeviceIpIsKnown() {
        let c = WifiAdbLogic.resolveIpCandidates(
            gateway: "192.168.0.1",        // 라우터
            ifAddrText: ifAddrSample,       // **기기**
            ifconfigText: nil,
            routeText: nil
        )
        XCTAssertEqual(c.first, "192.168.0.55",
                       "기기가 말한 주소가 라우터보다 먼저여야 한다")
    }

    /// 게이트웨이는 **뒤에** 있다 (SoftAP 전용 가정이라 후순위)
    func testGatewayComesAfterDeviceIp() {
        let c = WifiAdbLogic.resolveIpCandidates(
            gateway: "10.0.0.1",
            ifAddrText: """
            60: swlan0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500
                inet 10.0.0.9/24 brd 10.0.0.255 scope global swlan0
            """,
            ifconfigText: nil,
            routeText: nil
        )
        XCTAssertEqual(c.last, "10.0.0.1", "게이트웨이는 후순위")
        XCTAssertEqual(c.count, 2, "후보 2개")
    }

    /// 기기에게 아무것도 못 물어봤을 때만 게이트웨이가 답이 된다 (SoftAP 케이스)
    func testGatewayOnlyWhenNothingElseKnown() {
        let c = WifiAdbLogic.resolveIpCandidates(
            gateway: "10.38.120.211",
            ifAddrText: nil, ifconfigText: nil, routeText: nil
        )
        XCTAssertEqual(c, ["10.38.120.211"], "SoftAP 라면 이것이 정답")
    }

    /// 중복 제거 — 같은 IP 가 여러 경로에서 나와도 한 번만 시도
    func testNoDuplicateCandidates() {
        let c = WifiAdbLogic.resolveIpCandidates(
            gateway: "10.0.0.5",
            ifAddrText: """
            60: swlan0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500
                inet 10.0.0.5/24 brd 10.0.0.255 scope global swlan0
            """,
            ifconfigText: "wlan0     Link encap:Ethernet  inet 10.0.0.5",
            routeText: nil
        )
        XCTAssertEqual(c, ["10.0.0.5"], "같은 주소는 한 번만")
    }

    /// loopback·비 IPv4 는 제외 (명령을 망가뜨리는 값)
    func testLoopbackAndNonIPv4Excluded() {
        let c = WifiAdbLogic.resolveIpCandidates(
            gateway: "127.0.0.1",
            ifAddrText: "swlan0: inet notanip/24",
            ifconfigText: nil,
            routeText: nil
        )
        XCTAssertTrue(c.isEmpty, "루프백·비 IP 는 후보가 아니다")
    }

    /// 기존 `resolveIp` 편의 함수는 첫 후보를 반환 (호환)
    func testResolveIpReturnsFirst() {
        let ip = WifiAdbLogic.resolveIp(
            gateway: "192.168.0.1",
            ifAddrText: """
            60: swlan0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500
                inet 192.168.0.55/24 brd 192.168.0.255 scope global swlan0
            """,
            ifconfigText: nil, routeText: nil
        )
        XCTAssertEqual(ip, "192.168.0.55")
    }

    /// 스윕 대상은 /24 전체 (.0·.255 제외, 254개) — 게이트웨이 본인도 포함
    /// (핫스팟이면 폰이 게이트웨이다)
    func testSweepTargetsFullSubnet() {
        let t = WifiAdbLogic.sweepTargets(prefix: "10.166.169")
        XCTAssertEqual(t.count, 254)
        XCTAssertEqual(t.first, "10.166.169.1")
        XCTAssertEqual(t.last, "10.166.169.254")
        XCTAssertFalse(t.contains("10.166.169.0"))
        XCTAssertFalse(t.contains("10.166.169.255"))
    }

    /// 접두사가 깨졌으면 빈 목록 — 이상한 값으로 nc 를 돌리지 않는다
    func testSweepTargetsRejectsBadPrefix() {
        XCTAssertTrue(WifiAdbLogic.sweepTargets(prefix: "").isEmpty)
        XCTAssertTrue(WifiAdbLogic.sweepTargets(prefix: "10.166").isEmpty)
        XCTAssertTrue(WifiAdbLogic.sweepTargets(prefix: "a.b.c").isEmpty)
    }

    /// 스윕 결과는 맨 뒤 (최후) — 앞에 알려진 후보가 있으면 거기서 끝나야 한다
    func testSweptSubnetComesLast() {
        let c = WifiAdbLogic.reconnectCandidateOrder(
            lastEndpoint: "10.166.169.252:5555",
            lostSerial: "10.166.169.252:5555",
            deviceReported: [],
            gateway: "10.166.169.1",
            arpNeighbours: ["10.166.169.5"],
            sweptSubnet: ["10.166.169.242", "10.166.169.252"]
        )
        XCTAssertEqual(c.last, "10.166.169.242", "스윕 신규 IP 는 맨 뒤")
        XCTAssertEqual(c.first, "10.166.169.252", "알려진 IP 가 먼저")
        XCTAssertEqual(c.filter { $0 == "10.166.169.252" }.count, 1, "중복 제거")
    }
}
