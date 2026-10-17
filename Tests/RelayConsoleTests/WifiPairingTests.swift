import Testing
@testable import RelayConsole

/// Android 11+ 무선 디버깅 페어링 (2026-10-17 · PLAN_wifi_pairing)
///
/// 여기서 고정하는 것은 **adb 출력 형식**이다. 파서·판정이 순수 함수라서
/// 실기기 없이도 형식 회귀를 잡을 수 있다(실측 출력을 그대로 픽스처로 쓴다).
struct WifiPairingTests {

    /// AOSP 문서의 `adb mdns services` 실제 형식 — 열 구분이 공백/탭 가변
    private let sample = """
    List of discovered mdns services
    adb-14141FDF600081         _adb._tcp          192.168.86.38:5555
    adb-14141FDF600081-QXjCrW  _adb-tls-pairing._tcp  192.168.86.38:33861
    adb-14141FDF600081-TnSdi9  _adb-tls-connect._tcp  192.168.86.38:33015
    studio-g@<xeYnap/    _adb-tls-pairing._tcp\t192.168.86.39:55861
    """

    // MARK: - 파싱

    @Test func parsesAllRowsAndSkipsHeader() {
        let services = WifiAdbLogic.parseMdnsServices(sample)
        #expect(services.count == 4)
        #expect(services[0].instance == "adb-14141FDF600081")
        #expect(services[0].type == "_adb._tcp")
        #expect(services[0].host == "192.168.86.38")
        #expect(services[0].port == 5555)
    }

    @Test func parsesTabSeparatedRow() {
        let services = WifiAdbLogic.parseMdnsServices(sample)
        #expect(services.contains { $0.instance == "studio-g@<xeYnap/" && $0.endpoint == "192.168.86.39:55861" })
    }

    @Test func skipsMalformedRows() {
        let text = """
        List of discovered mdns services
        adb-x  _adb._tcp  not-an-ip:5555
        adb-y  _adb._tcp
        adb-z  _other._tcp  192.168.0.9:5555
        adb-ok  _adb-tls-connect._tcp  192.168.0.7:37000
        """
        let services = WifiAdbLogic.parseMdnsServices(text)
        #expect(services.count == 1)
        #expect(services[0].endpoint == "192.168.0.7:37000")
    }

    @Test func emptyOutputYieldsNoServices() {
        #expect(WifiAdbLogic.parseMdnsServices("List of discovered mdns services").isEmpty)
    }

    // MARK: - 종류별 필터

    @Test func splitsPairingEndpoints() {
        let services = WifiAdbLogic.parseMdnsServices(sample)
        #expect(WifiAdbLogic.pairingEndpoints(services) == ["192.168.86.38:33861", "192.168.86.39:55861"])
    }

    // MARK: - 우리 기기 고르기

    @Test func matchesBySerialPrefix() {
        let services = WifiAdbLogic.parseMdnsServices(sample)
        let hit = WifiAdbLogic.matchingConnectEndpoints(
            services: services,
            physicalId: "14141FDF600081",
            knownHosts: []
        )
        #expect(hit == ["192.168.86.38:33015"])
    }

    @Test func serialPrefixDoesNotSwallowLongerSerial() {
        let service = WifiAdbLogic.MdnsService(
            instance: "adb-R0QKSX2-TnSdi9",
            type: WifiAdbLogic.MdnsService.typeConnect,
            host: "192.168.0.5",
            port: 37000
        )
        #expect(service.belongs(to: "R0QKSX2"))
        #expect(!service.belongs(to: "R0QKSX"))
    }

    @Test func fallsBackToKnownHostWhenSerialUnknown() {
        let services = WifiAdbLogic.parseMdnsServices(sample)
        let hit = WifiAdbLogic.matchingConnectEndpoints(
            services: services,
            physicalId: nil,
            knownHosts: ["192.168.86.38"]
        )
        #expect(hit == ["192.168.86.38:33015"])
    }

    @Test func neverPicksAnotherPhone() {
        let services = WifiAdbLogic.parseMdnsServices(sample)
        // 시리얼이 다르고 호스트도 모른다 — 남의 폰에 붙으면 안 된다
        let hit = WifiAdbLogic.matchingConnectEndpoints(
            services: services,
            physicalId: "ZZZZZZZZ",
            knownHosts: ["192.168.99.99"]
        )
        #expect(hit.isEmpty)
    }

    // MARK: - 후보 병합 (재부팅 내구성)

    @Test func discoveredGoesFirstAndOldPortForSameHostIsDropped() {
        let merged = WifiAdbLogic.mergeDiscovered(
            discovered: ["192.168.0.7:37000"],
            base: ["192.168.0.7:5555", "192.168.0.9:5555"]
        )
        // 같은 호스트의 옛 후보(5555)는 버린다 — 페어링·재부팅 뒤 그 포트는 닫혀 있다
        #expect(merged == ["192.168.0.7:37000", "192.168.0.9:5555"])
    }

    @Test func keepsBaseOrderWhenNothingDiscovered() {
        let base = ["192.168.0.7:5555", "192.168.0.9:5555"]
        #expect(WifiAdbLogic.mergeDiscovered(discovered: [], base: base) == base)
    }

    @Test func mergeDoesNotDuplicate() {
        let merged = WifiAdbLogic.mergeDiscovered(
            discovered: ["192.168.0.7:37000", "192.168.0.9:33015"],
            base: ["192.168.0.9:33015"]
        )
        #expect(merged == ["192.168.0.7:37000", "192.168.0.9:33015"])
    }

    // MARK: - 코드·인자

    @Test func normalizesCodeTypedWithNoise() {
        #expect(WifiAdbLogic.normalizePairingCode(" 515 109 ") == "515109")
        #expect(WifiAdbLogic.normalizePairingCode("515-109") == "515109")
        #expect(WifiAdbLogic.isValidPairingCode("515109"))
        #expect(!WifiAdbLogic.isValidPairingCode("51510"))
        #expect(!WifiAdbLogic.isValidPairingCode("abcdef"))
    }

    @Test func pairArgsPassCodeAsArgument() {
        // 인자 없이 실행하면 `Enter pairing code:` 로 **멈춘다**(실측) — 항상 코드를 넘긴다
        #expect(WifiAdbLogic.pairArgs(endpoint: " 192.168.0.7:43811 ", code: "515-109")
            == ["pair", "192.168.0.7:43811", "515109"])
    }

    // MARK: - 성공·실패 판정

    @Test func successIsDetectedFromOutput() {
        let real = "Successfully paired to 192.168.86.38:43811 [guid=adb-14141FDF600081-QXjCrW]"
        #expect(WifiAdbLogic.isPairSuccess(output: real))
        // adb는 실패해도 exit 0 인 경우가 있다 — 종료코드만 믿으면 실패를 성공으로 오판한다
        #expect(!WifiAdbLogic.isPairSuccess(output: "failed to connect to 192.168.0.7:43811"))
    }

    @Test func failureKeyMapsKnownCauses() {
        #expect(WifiAdbLogic.pairFailureKey(output: "Failed: Wrong password") == "wifi.pair.error.code")
        #expect(WifiAdbLogic.pairFailureKey(output: "Already paired to 192.168.0.7:43811")
            == "wifi.pair.error.already")
        #expect(WifiAdbLogic.pairFailureKey(output: "adb: pairing timed out") == "wifi.pair.error.timeout")
        #expect(WifiAdbLogic.pairFailureKey(output: "failed to connect to 192.168.0.7:43811")
            == "wifi.pair.error.unreachable")
        #expect(WifiAdbLogic.pairFailureKey(output: "error: protocol fault (couldn't read status message)")
            == "wifi.pair.error.unreachable")
        #expect(WifiAdbLogic.pairFailureKey(output: "something else") == "wifi.pair.error.failed")
    }

    @Test func endpointValidationIsReusedForPairing() {
        #expect(WifiAdbLogic.validateEndpoint("192.168.0.7:43811") == nil)
        #expect(WifiAdbLogic.validateEndpoint("192.168.0.7") != nil)
    }

    // MARK: - 같은 인스턴스 이름 (2026-10-17 실측)

    /// S22(192.168.86.49) 실측 출력 — 한 폰이 connect·pairing 을 **같은 인스턴스 이름**으로 광고한다.
    /// 이걸 `id: \.instance` 로 그리면 SwiftUI 가 id 중복으로 connect 줄을 두 번 그리고
    /// **페어링 줄은 사라진다**(사용자가 겪은 "페어링 주소가 안 보인다" 증상).
    private let realS22 = """
    List of discovered mdns services
    adb-R5CT215F4QK-iL8Q9e\t_adb-tls-connect._tcp\t192.168.86.49:45325
    adb-R5CT215F4QK-iL8Q9e\t_adb-tls-pairing._tcp\t192.168.86.49:45673
    """

    @Test func sameInstanceNameStillYieldsTwoDistinctRows() {
        let services = WifiAdbLogic.parseMdnsServices(realS22)
        #expect(services.count == 2)
        #expect(Set(services.map(\.id)).count == 2)
    }

    @Test func idIsUniqueEvenForSameTypeAndDifferentPort() {
        let a = WifiAdbLogic.MdnsService(
            instance: "adb-R5CT215F4QK-iL8Q9e",
            type: WifiAdbLogic.MdnsService.typeConnect,
            host: "192.168.86.49",
            port: 45325
        )
        let b = WifiAdbLogic.MdnsService(
            instance: "adb-R5CT215F4QK-iL8Q9e",
            type: WifiAdbLogic.MdnsService.typeConnect,
            host: "192.168.86.49",
            port: 45673
        )
        #expect(a.id != b.id)
    }

    @Test func pairingRowIsShownFirst() {
        let ordered = WifiAdbLogic.displayOrdered(WifiAdbLogic.parseMdnsServices(realS22))
        #expect(ordered.first?.isPairing == true)
        #expect(ordered.map(\.endpoint) == ["192.168.86.49:45673", "192.168.86.49:45325"])
    }

    @Test func displayOrderIsStableAcrossHosts() {
        let a = WifiAdbLogic.MdnsService(
            instance: "adb-X-1",
            type: WifiAdbLogic.MdnsService.typeConnect,
            host: "192.168.0.9",
            port: 37000
        )
        let b = WifiAdbLogic.MdnsService(
            instance: "adb-X-2",
            type: WifiAdbLogic.MdnsService.typeConnect,
            host: "192.168.0.7",
            port: 5555
        )
        #expect(WifiAdbLogic.displayOrdered([a, b]).map(\.host) == ["192.168.0.7", "192.168.0.9"])
    }

    // MARK: - 포트 혼동 가드 (페어링 ≠ connect)

    @Test func connectPortIsRejectedAsPairingAddress() {
        let services = WifiAdbLogic.parseMdnsServices(realS22)
        #expect(WifiAdbLogic.isConnectEndpoint("192.168.86.49:45325", services: services))
        #expect(WifiAdbLogic.isConnectEndpoint(" 192.168.86.49:45325 ", services: services))
        #expect(!WifiAdbLogic.isConnectEndpoint("192.168.86.49:45673", services: services))
    }

    @Test func pairingAddressIsOfferedWhenConnectPortWasUsed() {
        let services = WifiAdbLogic.parseMdnsServices(realS22)
        #expect(WifiAdbLogic.pairingEndpoint(host: "192.168.86.49", services: services) == "192.168.86.49:45673")
        // 페어링 창이 닫혀 있으면 대신 줄 주소가 없다 — 문구 분기에 쓴다
        #expect(WifiAdbLogic.pairingEndpoint(host: "192.168.86.50", services: services) == nil)
    }

    // MARK: - 재연결 후보의 포트 (2026-10-17 · 49 실측 전 코드 검토)

    @Test func probePortUsesTheCandidatesOwnPort() {
        // 재부팅 뒤 폰은 5555(레거시 tcpip)를 닫고 무선 디버깅 포트만 연다 —
        // 게이트가 5555 를 보면 무선 후보를 통째로 걸러 자동 재연결이 영영 안 붙는다
        #expect(WifiAdbLogic.probePort(forEndpoint: "192.168.86.49:45325") == 45325)
        #expect(WifiAdbLogic.probePort(forEndpoint: "192.168.86.49:5555") == 5555)
        // 포트 없는 후보(IP만)는 기본 5555 로 확인한다
        #expect(WifiAdbLogic.probePort(forEndpoint: "192.168.86.49") == WifiAdbLogic.defaultPort)
    }

    @Test func discoveredWirelessCandidateIsTheOnlyOneLeftForItsHost() {
        // mDNS 로 찾은 무선 후보가 앞에 서고, 같은 호스트의 옛 5555 후보는 버려진다.
        // → 그 호스트에 남는 후보의 포트는 5555 가 아니다(게이트가 그 후보를 버리면 안 된다)
        let merged = WifiAdbLogic.mergeDiscovered(
            discovered: ["192.168.86.49:45325"],
            base: ["192.168.86.49:5555", "192.168.86.30:5555"]
        )
        #expect(merged.first == "192.168.86.49:45325")
        #expect(!merged.contains("192.168.86.49:5555"))
        #expect(merged.contains("192.168.86.30:5555"))   // 다른 폰은 그대로 남는다
        #expect(WifiAdbLogic.probePort(forEndpoint: merged[0]) == 45325)
    }

    // MARK: - 새 광고 → 쿨다운 건너뛰기 (2026-10-18 · 폰이 돌아온 순간을 잡는다)

    @Test func newAdvertisementSkipsCooldown() {
        // 처음 보는 광고 = 폰이 돌아왔다 → 백오프를 기다리지 않는다
        #expect(WifiAdbLogic.bypassCooldownOnNewAdvertisement(
            discovered: ["192.168.86.49:37841"], lastSeen: nil))
        // 포트가 바뀐 새 광고도 새 광고다 (재부팅·재토글 때마다 포트가 바뀐다)
        #expect(WifiAdbLogic.bypassCooldownOnNewAdvertisement(
            discovered: ["192.168.86.49:37841"], lastSeen: "192.168.86.49:37311"))
    }

    @Test func sameAdvertisementKeepsTheBackoff() {
        // 같은 광고를 계속 보고 있으면 평소 백오프 — 매 틱(5초) 다시 붙으려 들지 않는다
        let seen = WifiAdbLogic.advertisedKey(["192.168.86.49:37841"])
        #expect(!WifiAdbLogic.bypassCooldownOnNewAdvertisement(
            discovered: ["192.168.86.49:37841"], lastSeen: seen))
    }

    @Test func noAdvertisementKeepsTheBackoff() {
        // 광고가 없으면(=폰이 없다) 백오프가 제 역할을 한다 — 서브넷 스윕을 자주 돌리지 않는다
        #expect(!WifiAdbLogic.bypassCooldownOnNewAdvertisement(discovered: [], lastSeen: nil))
        #expect(!WifiAdbLogic.bypassCooldownOnNewAdvertisement(discovered: [], lastSeen: "192.168.86.49:37311"))
    }

    @Test func advertisementKeyIgnoresOrder() {
        // 광고 순서는 조회마다 흔들린다 — 순서 때문에 "새 광고"로 오판하지 않는다
        #expect(WifiAdbLogic.advertisedKey(["192.168.86.49:37841", "192.168.86.49:45673"])
            == WifiAdbLogic.advertisedKey(["192.168.86.49:45673", "192.168.86.49:37841"]))
    }
}
