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

    /// **판정에 무관한 것만** 고정한다 — 실기 IP/연결 여부에 의존하면
    /// 핫스팟을 끄는 순간 테스트가 깨진다(2026-09-27 실제로 그랬다).
    ///
    /// 실측 근거(문서화용): 맥 → 폰 ping 100% loss · 폰 → 자기 ping 0.142ms ·
    /// `nc 5555` succeeded. 즉 이 기기는 ICMP 를 막고 adb 포트는 연다.
    /// 그래서 기준을 `nc -z` 로 잡았다 — ping 이면 "연결 가능한 기기" 를
    /// "닿지 않음" 으로 오판해 tcpip 을 건너뛴다.
    @Test func reachabilityRejectsInvalidInputWithoutTouchingNetwork() {
        // 잘못된 입력 / 루프백은 네트워크를 건드리지 않고 즉시 false 여야 한다
        #expect(!PingProbe.reachable(ip: "not-an-ip"))
        #expect(!PingProbe.reachable(ip: "999.1.1.1"))
        #expect(!PingProbe.reachable(ip: "127.0.0.1"), "루프백은 검사 대상이 아니다")
        #expect(!PingProbe.reachable(ip: ""))
    }

    /// 닫혀 있는 포트(로컬 listen 없는 고포트) 는 false — 도달 불가의 기본 동작
    @Test func closedPortIsUnreachable() {
        #expect(!PingProbe.reachable(ip: "127.0.0.1", port: 9))
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

/// 옛 TCP 엔드포인트 정리 — 2026-09-27 자동 모드 실기 검증 중 발견
///
/// ## 무엇을 고치는가
/// Wi-Fi IP 는 바뀐다(같은 폰이 하루에 세 번 바뀐 것을 관측). `adb devices` 의 TCP 키는
/// IP 그 자체라 **옛 항목이 계속 살아남고**, 같은 폰이 2개 기기로 잡혀 **폴링이 2배**다.
///
/// ## 판별 근거
/// IP 로는 알 수 없다. `ro.boot.serialno` 로 판별한다 — IP 가 바뀌어도 고정이고
/// TCP 로도 읽힌다(실측: 같은 폰의 세 IP 모두 `R5CT215F4QK`).
///
/// ## 위험
/// **잘못 끊으면 사용자의 다른 기기가 죽는다.** 그래서 아래 테스트는
/// "끊어야 하는 것만 끊고, 애매하면 아무것도 안 끊는다" 를 고정한다.
struct WifiStaleTests {
    /// 실측 `adb devices` 출력 형식
    private let devicesSample = """
    List of devices attached
    R5CT215F4QK	device
    10.38.120.211:5555	device
    172.30.102.182:5555	offline
    emulator-5554	device
    """

    @Test func parseDeviceListKeepsOnlyHealthyDevices() {
        let parsed = WifiAdbController.parseDeviceList(devicesSample)
        #expect(parsed.contains("R5CT215F4QK"))
        #expect(parsed.contains("10.38.120.211:5555"))
        #expect(parsed.contains("emulator-5554"))
        #expect(!parsed.contains("172.30.102.182:5555"), "offline 은 살아있지 않다")
        #expect(!parsed.contains("List of devices attached"))
    }

    @Test func parseDeviceListEmptyOnGarbage() {
        #expect(WifiAdbController.parseDeviceList("").isEmpty)
        #expect(WifiAdbController.parseDeviceList("adb server version (41) doesn't match").isEmpty)
    }

    @Test func networkEndpointDetection() {
        #expect(WifiAdbLogic.isNetworkEndpoint("10.38.120.211:5555"))
        #expect(WifiAdbLogic.isNetworkEndpoint("192.168.1.5:5037"))
        // USB 시리얼에는 콜론이 없다 — 이 구분이 TCP/USB 판별의 전부
        #expect(!WifiAdbLogic.isNetworkEndpoint("R5CT215F4QK"))
        #expect(!WifiAdbLogic.isNetworkEndpoint("emulator-5554"))
    }

    // MARK: - stale 판별 (이것이 핵심)

    @Test func samePhysicalDeviceDifferentIpsAreStale() {
        // 실측 관측 이력 — 같은 폰, IP 만 변경
        let ids = [
            "10.38.120.211:5555": "R5CT215F4QK",   // 지금
            "172.30.102.182:5555": "R5CT215F4QK",  // 저녁
            "10.233.247.205:5555": "R5CT215F4QK"    // 오전
        ]
        let stale = WifiAdbLogic.staleNetworkEndpoints(
            physicalIdsByEndpoint: ids, physicalId: "R5CT215F4QK", keep: "10.38.120.211:5555"
        )
        #expect(stale == ["10.233.247.205:5555", "172.30.102.182:5555"].sorted())
    }

    @Test func otherDevicesAreNeverDisconnected() {
        // **가장 위험한 실패 모드** — 다른 폰을 끊으면 안 된다
        let ids = [
            "10.38.120.211:5555": "R5CT215F4QK",   // 이 폰
            "192.168.1.99:5555": "OTHER-DEVICE-ID"  // 다른 폰
        ]
        let stale = WifiAdbLogic.staleNetworkEndpoints(
            physicalIdsByEndpoint: ids, physicalId: "R5CT215F4QK", keep: "10.38.120.211:5555"
        )
        #expect(stale.isEmpty, "다른 기기의 엔드포인트는 절대 끊지 않는다")
    }

    @Test func keepEndpointIsNeverDisconnected() {
        let ids = ["10.38.120.211:5555": "R5CT215F4QK"]
        #expect(WifiAdbLogic.staleNetworkEndpoints(
            physicalIdsByEndpoint: ids, physicalId: "R5CT215F4QK", keep: "10.38.120.211:5555"
        ).isEmpty)
    }

    @Test func ambiguousIdentityDisconnectsNothing() {
        // 물리 식별을 못 한 후보는 **제외**된다 — 애매하면 남겨두는 게 옳다
        let ids = [
            "10.38.120.211:5555": "R5CT215F4QK",
            "172.30.102.182:5555": ""              // getprop 실패 → 빈 값
        ]
        let stale = WifiAdbLogic.staleNetworkEndpoints(
            physicalIdsByEndpoint: ids, physicalId: "R5CT215F4QK", keep: "10.38.120.211:5555"
        )
        #expect(stale.isEmpty, "식별 불가 항목은 끊지 않는다")
    }

    @Test func noNetworkDuplicatesMeansNothingToDo() {
        // TCP 가 하나뿐이면 정리 대상이 없다 — 불필요한 adb 호출을 하지 않는다
        let ids = ["10.38.120.211:5555": "R5CT215F4QK"]
        #expect(WifiAdbLogic.staleNetworkEndpoints(
            physicalIdsByEndpoint: ids, physicalId: "R5CT215F4QK", keep: "10.38.120.211:5555"
        ).isEmpty)
    }

    @Test func physicalIdPropIsStable() {
        // 이 값이 바뀌면 판별이 무너진다 — 프로퍼티 이름을 고정한다
        #expect(WifiAdbLogic.physicalIdProp == "ro.boot.serialno")
    }
}

/// TCP 유실 시 자동 재연결 — 2026-09-27 · `PLAN_wifi_reconnect`
///
/// ## 왜 필요한가
/// "USB 를 뽑아도 IP 로 계속" 의 목표는 **IP 가 바뀌어도** 성립해야 한다.
/// 핫스팟 이동·Wi-Fi 재연결로 IP 가 바뀌면 기존 엔드포인트가 죽고,
/// USB 를 다시 꽂지 않으면 아무도 새 IP 로 붙지 않는다.
///
/// ## 최대 위험 = 무한 재시도
/// 폴링이 5초 주기이므로 쿨다운이 없으면 **분당 12회** connect 시도 = adb 폭주 + 배터리.
/// 그래서 쿨다운 판정을 테스트로 고정한다.
struct WifiReconnectTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func networkLossTriggersReconnect() {
        #expect(WifiAdbLogic.shouldReconnect(
            autoEnabled: true, lostSerial: "10.38.120.211:5555",
            now: t0, lastAttemptAt: nil, failures: 0
        ))
    }

    @Test func usbLossDoesNotTriggerThisPath() {
        // USB 유실은 `autoEnableIfEnabled`(tcpip) 경로가 처리한다 — 여기로 오면 안 된다
        #expect(!WifiAdbLogic.shouldReconnect(
            autoEnabled: true, lostSerial: "R5CT215F4QK",
            now: t0, lastAttemptAt: nil, failures: 0
        ))
    }

    @Test func autoModeOffBlocksReconnect() {
        // 사용자가 Wi-Fi ADB 를 끄고 싶은데 계속 붙으면 안 된다
        #expect(!WifiAdbLogic.shouldReconnect(
            autoEnabled: false, lostSerial: "10.38.120.211:5555",
            now: t0, lastAttemptAt: nil, failures: 0
        ))
    }

    /// ★ 핵심 — 쿨다운 안 지났으면 즉시 재시도 금지
    @Test func cooldownBlocksImmediateRetry() {
        let last = t0.addingTimeInterval(-10)  // 10초 전
        #expect(!WifiAdbLogic.shouldReconnect(
            autoEnabled: true, lostSerial: "10.38.120.211:5555",
            now: t0, lastAttemptAt: last, failures: 0
        ))
    }

    @Test func cooldownElapsedAllowsRetry() {
        let last = t0.addingTimeInterval(-61)  // 61초 전 (기본 쿨다운 60초)
        #expect(WifiAdbLogic.shouldReconnect(
            autoEnabled: true, lostSerial: "10.38.120.211:5555",
            now: t0, lastAttemptAt: last, failures: 0
        ))
    }

    /// 연속 실패 시 간격이 2배씩 늘어나야 한다 — 확실히 없는 기기면 오래 시도하지 않는다
    @Test func delayGrowsExponentiallyAndIsCapped() {
        #expect(WifiAdbLogic.reconnectDelay(failures: 0) == 60)
        #expect(WifiAdbLogic.reconnectDelay(failures: 1) == 120)
        #expect(WifiAdbLogic.reconnectDelay(failures: 2) == 240)
        // 상한 — 15분을 넘지 않는다
        #expect(WifiAdbLogic.reconnectDelay(failures: 10) == 900)
        #expect(WifiAdbLogic.reconnectDelay(failures: 100) == 900)
        #expect(WifiAdbLogic.reconnectDelay(failures: -5) == 60, "음수 실패 횟수는 0 으로")
    }

    /// 실패가 쌓이면 쿨다운이 늘어나 **재시도 빈도도 떨어져야** 한다
    @Test func manyFailuresReduceRetryFrequency() {
        let last = t0.addingTimeInterval(-300)  // 5분 전
        // 연속 2회 실패 → 지연 240초 → 5분 지났으니 재시도 가능
        #expect(WifiAdbLogic.shouldReconnect(
            autoEnabled: true, lostSerial: "10.38.120.211:5555",
            now: t0, lastAttemptAt: last, failures: 2
        ))
        // 연속 10회 실패 → 지연 900초(15분) → 5분 지났으니 **아직 금지**
        #expect(!WifiAdbLogic.shouldReconnect(
            autoEnabled: true, lostSerial: "10.38.120.211:5555",
            now: t0, lastAttemptAt: last, failures: 10
        ))
    }

    /// 15분 지났다면 어떤 실패 횟수라도 다시 시도한다 — 영구 포기하면 안 된다
    @Test func longElapsedAlwaysRetries() {
        let last = t0.addingTimeInterval(-1000)  // 약 16분 전
        for failures in [0, 1, 5, 20] {
            #expect(WifiAdbLogic.shouldReconnect(
                autoEnabled: true, lostSerial: "10.38.120.211:5555",
                now: t0, lastAttemptAt: last, failures: failures
            ), "실패 \(failures)회여도 15분 지나면 재시도해야 한다")
        }
    }
}
