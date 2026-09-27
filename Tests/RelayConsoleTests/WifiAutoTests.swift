import Foundation
import Testing
@testable import RelayConsole

/// USB → Wi-Fi ADB 자동 개방 — 2026-09-27 · `PLAN_wifi_auto_tcpip`
///
/// ## 이 테스트가 지키는 것
/// IP 판별 **순서**가 곧 정확도다. 실측(SM-S901N · 핫스팟 + 셀룰러 동시):
/// - 맥 게이트웨이 = `10.233.247.205` ← **정답** (swlan0)
/// - `ip route get 1.1.1.1` 의 src = `10.148.183.154` ← **셀룰러** (rmnet_data1)
/// - `ip addr show wlan0` = **빈 값** (이 기기에 wlan0 없음)
///
/// 종전 순서(route get 1순위)는 이 기기에서 **잘못된 IP** 를 골랐고,
/// 게다가 **빈 값이 아니라 값을 반환**해서 올바른 후보에 도달하지 못했다.
struct WifiAutoTests {
    /// 실측 샘플 그대로 — 삼중 출력
    private let ifAddrSample = """
    1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536
        inet 127.0.0.1/8 scope host lo
    32: rmnet_data1@rmnet_ipa0: <UP,LOWER_UP> mtu 1450
        inet 10.148.183.154/30 brd 10.148.183.155 scope global rmnet_data1
    60: swlan0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500
        inet 10.233.247.205/24 brd 10.233.247.255 scope global swlan0
    """

    private let routeSample = """
    1.1.1.1 via 10.148.183.153 dev rmnet_data1 table 1032 src 10.148.183.154 uid 2000
        cache mtu 1450
    """

    // MARK: - 인터페이스 판별

    @Test func wifiInterfaceNamesIncludeSamsung() {
        // 이 기기가 swlan0 — wlan0 만 보면 빈 값이 돌아온다
        #expect(WifiAdbLogic.isWifiInterface("swlan0"))
        #expect(WifiAdbLogic.isWifiInterface("wlan0"))
        #expect(WifiAdbLogic.isWifiInterface("wlp2s0"))
        #expect(WifiAdbLogic.isWifiInterface("60: swlan0:"))
        #expect(WifiAdbLogic.isWifiInterface("swlan0@if12"))
    }

    @Test func nonWifiInterfacesRejected() {
        // 셀룰러·루프백·핫스팟 인터페이스는 Wi-Fi IP 가 아니다
        for name in ["rmnet_data1", "rmnet_ipa0", "lo", "ap0", "eth0", "tun0", ""] {
            #expect(!WifiAdbLogic.isWifiInterface(name), "Wi-Fi 가 아님: \(name)")
        }
    }

    // MARK: - IP 판별 (실측 회귀)

    @Test func parseWifiIpSkipsCellularAndLoopback() {
        #expect(WifiAdbLogic.parseWifiIp(fromIfAddr: ifAddrSample) == "10.233.247.205")
    }

    @Test func resolveIpPrefersGatewayOverCellularRoute() {
        let ip = WifiAdbLogic.resolveIp(
            gateway: "10.233.247.205",
            ifAddrText: ifAddrSample,
            ifconfigText: nil,
            routeText: routeSample
        )
        #expect(ip == "10.233.247.205", "핫스팟이면 게이트웨이가 곧 폰 IP 다")
    }

    /// 핵심 회귀 — 종전 순서였으면 **셀룰러 주소**를 골랐다
    @Test func routeTextIsNeverPreferredOverIfAddr() {
        // 게이트웨이가 없는 환경( 공유기 라우터 아래 폰 )에서도 기기 Wi-Fi 를 우선한다
        let ip = WifiAdbLogic.resolveIp(
            gateway: nil,
            ifAddrText: ifAddrSample,
            ifconfigText: nil,
            routeText: routeSample
        )
        #expect(ip == "10.233.247.205")
        #expect(ip != "10.148.183.154", "셀룰러 IP 를 Wi-Fi IP 로 쓰면 안 된다")
    }

    @Test func resolveIpFallbackOrder() {
        // ifconfig 만 있는 경우
        let ifconfig = """
        rmnet_data1: flags=4099<UP>  mtu 1450
            inet 10.148.183.154  netmask 255.255.255.252
        wlan0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
            inet 192.168.0.42  netmask 255.255.255.0
        """
        #expect(WifiAdbLogic.resolveIp(
            gateway: nil, ifAddrText: nil, ifconfigText: ifconfig, routeText: nil
        ) == "192.168.0.42")
        // route 만 남으면 마지막 수단으로라도 쓴다 (빈 값이면 nil)
        #expect(WifiAdbLogic.resolveIp(
            gateway: nil, ifAddrText: nil, ifconfigText: nil, routeText: routeSample
        ) == "10.148.183.154")
        #expect(WifiAdbLogic.resolveIp(
            gateway: nil, ifAddrText: nil, ifconfigText: nil, routeText: ""
        ) == nil)
    }

    @Test func resolveIpRejectsBadGateway() {
        let ip = WifiAdbLogic.resolveIp(
            gateway: "127.0.0.1",
            ifAddrText: ifAddrSample,
            ifconfigText: nil,
            routeText: nil
        )
        #expect(ip == "10.233.247.205", "루프백 게이트웨이는 무시한다")
    }

    // MARK: - 멱등 (adbd 재시작 방지)

    @Test func tcpipSkippedWhenNetworkAlreadyOpen() {
        // tcpip 은 adbd 를 재시작해 USB 가 잠깐 사라진다 — 이미 열려 있으면 건드리지 않는다
        #expect(WifiAdbLogic.needsTcpip(isNetworkSerialPresent: true) == false)
        #expect(WifiAdbLogic.needsTcpip(isNetworkSerialPresent: false) == true)
    }

    @Test func connectRetryBudgetIsBounded() {
        // 무한 재시도는 안 된다 — 3회면 충분 (스크립트 주석: "adbd 아직 준비중일 수 있음")
        #expect(WifiAdbLogic.connectAttempts == 3)
        #expect(WifiAdbLogic.connectRetryInterval >= 1)
    }

    // MARK: - 게이트웨이 파싱

    @Test func parseGatewayFromRouteOutput() {
        let sample = """
           route to: default
        destination: default
             mask: default
          gateway: 10.233.247.205
        interface: en0
        """
        #expect(MacRoute.parseGateway(sample) == "10.233.247.205")
    }

    // MARK: - 도달 확인 기준 (ping 아닌 포트)

    /// 실측: 맥 → 폰 ping 은 100% loss, 같은 주소에 `nc 5555` 는 succeeded.
    /// ping 을 유일한 기준으로 삼으면 **연결 가능한 기기를 "닿지 않음" 으로 오판**한다.
    @Test func reachabilityUsesAdbPortNotPing() {
        #expect(PingProbe.reachable(ip: "10.233.247.205", port: 5555))
    }

    @Test func unreachableAndInvalidAddresses() {
        // 192.0.2.0/24 은 TEST-NET — RFC5737 문서용이라 절대 응답하지 않는다
        #expect(!PingProbe.reachable(ip: "192.0.2.1", port: 5555))
        #expect(!PingProbe.reachable(ip: "not-an-ip"))
        #expect(!PingProbe.reachable(ip: "127.0.0.1"), "루프백은 검사 대상이 아니다")
    }

    @Test func parseGatewayNilWhenAbsent() {
        #expect(MacRoute.parseGateway("") == nil)
        #expect(MacRoute.parseGateway("destination: default\ninterface: en0") == nil)
        #expect(MacRoute.parseGateway("  gateway: not-an-ip  ") == nil)
    }

    // MARK: - 기존 회귀 (parseWlanIp · args)

    @Test func legacyParseWlanIpStillWorks() {
        #expect(WifiAdbLogic.parseWlanIp(from: """
        1.1.1.1 via 192.168.0.1 dev wlan0 src 192.168.0.5 uid 1000
            cache
        """) == "192.168.0.5")
        #expect(WifiAdbLogic.parseWlanIp(from: """
        wlan0: flags=4163<UP>  mtu 1500
            inet 10.0.0.42  netmask 255.255.255.0
        """) == "10.0.0.42")
        #expect(WifiAdbLogic.parseWlanIp(from: "") == nil)
    }

    @Test func legacyArgsUnchanged() {
        #expect(WifiAdbLogic.tcpipArgs(serial: "ABC123") == ["-s", "ABC123", "tcpip", "5555"])
        #expect(WifiAdbLogic.connectArgs(endpoint: " 10.0.0.2:5555 ") == ["connect", "10.0.0.2:5555"])
        #expect(WifiAdbLogic.disconnectArgs(endpoint: "10.0.0.2:5555") == ["disconnect", "10.0.0.2:5555"])
        #expect(WifiAdbLogic.defaultEndpoint(ip: "192.168.0.9") == "192.168.0.9:5555")
    }

    // MARK: - 설정 기본값

    @Test func autoModeKeyIsStable() {
        // 설정 키가 바뀌면 사용자 설정이 조용히 초기화된다 — 고정값 테스트
        #expect(WifiAdbLogic.autoModeKey == "relay.wifiAutoTcpip")
    }
}
