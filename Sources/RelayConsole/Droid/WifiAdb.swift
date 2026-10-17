import Foundation
import Combine

// MARK: - 순수 로직 (테스트)

enum WifiAdbLogic {
    static let defaultPort = 5555

    // MARK: - IP 판별 (2026-09-27 순서 개편 — 계측 근거는 PLAN_wifi_auto_tcpip)

    /// Wi-Fi 인터페이스 이름인가 — **Samsung 은 `wlan0` 이 아니라 `swlan0`** (실측).
    /// `wlan0` 만 하드코딩하면 빈 값이 돌아와 다음 후보로 넘어가지 못한다.
    static func isWifiInterface(_ raw: String) -> Bool {
        // `swlan0:`, `wlan0@if2`, `rmnet_data1@rmnet_ipa0` 같은 형태에서 이름만 떼어낸다
        var name = raw.trimmingCharacters(in: .whitespaces)
        if let at = name.firstIndex(of: "@") { name = String(name[name.startIndex..<at]) }
        while let last = name.last, last == ":" || last.isWhitespace { name.removeLast() }
        // `ip addr` 헤더는 "60: swlan0:" 처럼 번호가 붙어 온다
        if let colon = name.firstIndex(of: ":"), name[name.startIndex..<colon].allSatisfy(\.isNumber) {
            name = String(name[name.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        let n = name.lowercased()
        return n.hasPrefix("wlan") || n.hasPrefix("swlan") || n.hasPrefix("wlp") || n.hasPrefix("wl")
    }

    /// `ip -f inet addr` 다중 블록 텍스트 → **Wi-Fi 인터페이스만** 골라 IPv4
    static func parseWifiIp(fromIfAddr text: String) -> String? {
        var currentIsWifi = false
        for raw in text.split(separator: "\n") {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            // 인터페이스 헤더: "60: swlan0:" 또는 "swlan0: flags=…"
            let isHeader = line.contains(":") && {
                let head = line.prefix { $0 != ":" }.trimmingCharacters(in: .whitespaces)
                let afterColon = line.split(separator: ":", maxSplits: 1).last.map(String.init) ?? ""
                return head.isEmpty || head.allSatisfy(\.isNumber) || afterColon.contains("flags=")
            }()
            if isHeader {
                currentIsWifi = isWifiInterface(line)
                continue
            }
            guard currentIsWifi, let ip = firstIPv4(inLines: [line], interfaceHints: nil) else { continue }
            return ip
        }
        return nil
    }

    /// IP 후보 결정 — **순서가 곧 정확도다.**
    ///
    /// ## ★ 2026-09-28 개편 — 게이트웨이를 "정답" 으로 두지 않는다
    /// 종전엔 **맥의 게이트웨이를 최우선**으로 반환했다. 근거는 "폰이 핫스팟이면
    /// 게이트웨이가 곧 폰 IP" 였다. 그런데:
    ///
    /// - 그 전제는 **SoftAP 일 때만** 성립한다. `dumpsys wifi` 로 확인한 결과
    ///   이 기기는 `SoftApManagers:0` — **SoftAP 가 아니었다.** 같은 IP 가 나올 뿐,
    ///   근거가 아니라 **우연**이었다.
    /// - 집 Wi-Fi 에서 같은 로직이 **라우터로 붙으러 간다** → "USB 로는 연결되는데
    ///   인터넷으로 넘어가면 감지를 못 한다" 의 근본
    /// - 게다가 게이트웨이는 **빈 값이 아니라 값을 반환해서** 뒤 후보에 도달하지 못한다
    ///
    /// → **후보들을 순서대로 돌려 실제로 붙는 것을 시도**한다
    ///   (`autoReconnect` 가 `connect` 를 시도하고 실패하면 다음 후보로 넘어간다).
    ///   순서는 **기기에게 직접 물은 값**을 앞에 둔다.
    ///
    /// ① 기기 `ip addr` 의 Wi-Fi 인터페이스 (`swlan0` 등) — **기기 자신의 주소. 가장 정확**
    /// ② 기기 `ifconfig` 전체
    /// ③ 맥 게이트웨이 — SoftAP 일 때만 정답이라 **뒤로** 내린다
    /// ④ `ip route get` 의 `src` — **마지막**. 인터넷으로 나가는 쪽이라
    ///    핫스팟 + 셀룰러 동시 켜진 기기에서는 **셀룰러 IP** 가 나온다 (실측 `10.148.183.154`)
    static func resolveIpCandidates(
        gateway: String?,
        ifAddrText: String?,
        ifconfigText: String?,
        routeText: String?
    ) -> [String] {
        var out: [String] = []
        func add(_ ip: String?) {
            guard let ip else { return }
            let v = ip.trimmingCharacters(in: .whitespaces)
            guard isIPv4(v), !isLoopback(v), !out.contains(v) else { return }
            out.append(v)
        }
        add(ifAddrText.flatMap(parseWifiIp(fromIfAddr:)))
        add(ifconfigText.flatMap(parseWlanIp(from:)))
        // 게이트웨이는 **뒤로** — SoftAP 가 아닐 수 있다 (2026-09-28)
        add(gateway)
        add(routeText.flatMap(parseWlanIp(from:)))
        return out
    }

    /// `arp -an` 출력에서 **해당 서브넷의 IPv4 만** 뽑는다 — 순수
    ///
    /// 실제 출력 한 줄:
    /// `? (10.38.120.211) at e6:82:5d:b7:32:b4 on en0 ifscope [ethernet]`
    static func parseArpIPs(_ text: String, onSubnet prefix: String) -> [String] {
        var out: [String] = []
        for line in text.split(separator: "\n") {
            guard let open = line.firstIndex(of: "(") else { continue }
            let after = line[line.index(after: open)...]
            guard let close = after.firstIndex(of: ")") else { continue }
            let ip = String(after[after.startIndex..<close])
            guard isIPv4(ip), ip.hasPrefix(prefix + "."), !out.contains(ip) else { continue }
            // ★ 브로드캐스트/멀티캐스트는 **붙을 대상이 아니다** (2026-09-28 테스트가 잡음)
            //   `adb connect 10.38.120.255:5555` 는 무의미하다 — 게다가 오염을 남긴다
            guard !isBroadcastOrMulticast(ip) else { continue }
            out.append(ip)
        }
        return out
    }

    /// 브로드캐스트(`x.x.x.255`)·멀티캐스트(`224.0.0.0/4`) 주소인가
    static func isBroadcastOrMulticast(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        if parts[0] >= 224 && parts[0] <= 239 { return true }   // 멀티캐스트
        return parts[3] == 255                                  // /24 브로드캐스트
    }

    /// `/24` 기준 서브넷 접두사 — `"10.38.120.211"` → `"10.38.120"`
    ///
    /// 게이트웨이가 같은 서브넷인지 확인할 때 쓴다. `/24` 만 다룬다
    /// (그 이상 세분화하면 후보가 폭발하고, 그보다 넓으면 이웃이 오염된다).
    static func subnetPrefix(ip: String) -> String? {
        let parts = ip.split(separator: ".").map(String.init)
        guard parts.count == 4, parts.allSatisfy({ Int($0) != nil }) else { return nil }
        return "\(parts[0]).\(parts[1]).\(parts[2])"
    }

    /// 같은 대역 5555 스윕 대상 — `/24` 호스트 전체 (`.0`·`.255` 제외, 254개)
    ///
    /// DHCP 로 IP 가 바뀐 기기는 ARP 에 없다 (아직 통신한 적이 없으므로).
    /// 포트 스윕은 `adb connect` 를 날리지 않고 찾는다 — 서버 오염 없음.
    /// 게이트웨이 본인도 포함한다 — 핫스팟이면 폰이 게이트웨이다.
    static func sweepTargets(prefix: String) -> [String] {
        let parts = prefix.split(separator: ".")
        guard parts.count == 3, parts.allSatisfy({ Int($0) != nil }) else { return [] }
        return (1...254).map { "\(prefix).\($0)" }
    }

    /// `host:port` 에서 IP 만 — 후보 정리에 쓴다
    static func host(ofEndpoint endpoint: String) -> String? {
        guard let h = endpoint.split(separator: ":").first.map(String.init), isIPv4(h) else { return nil }
        return h
    }

    /// ★ 재연결 후보의 **순서** — 순수 (2026-09-28 · 사용자 지적으로 보강)
    ///
    /// ## 왜 이 순서인가
    /// 사용자 지적: *"전에 연결되었던 IP — 게이트웨이가 연결 상태면 adb wifi 다시 연결 시도 안하니?"*
    /// 맞다. 종전엔 **게이트웨이 하나만** 보고 그것으로 서달랐다.
    /// 게이트웨이 = 기기 IP 는 **SoftAP 일 때만** 성립하므로
    /// (실측 `SoftApManagers:0` — 이 기기는 SoftAP 아님) 집 Wi-Fi 에서 **반드시 실패**했다.
    ///
    /// 순서:
    /// ① **전에 붙었던 IP** — DHCP 가 IP 를 그대로 줬을 때 이것 하나로 복구된다 (가장 빠름)
    /// ② 방금 잃어버린 serial 의 IP — 위와 같을 수 있지만 **정리 후 연결**된 경우
    /// ③ **기기가 살아 있으면(USB) 직접 물어본 값** — 가장 정확
    /// ④ 게이트웨이 — SoftAP 전용 가정이라 뒤쪽 (단, 핫스팟이면 폰이 게이트웨이다)
    /// ⑤ ARP 이웃 — 라우터가 살아있을 때 넓이를 늘린다 (아래 한계)
    /// ⑥ 같은 대역 5555 스윕 — DHCP 로 IP 가 바뀐 기기 (ARP 에 없음, 최후)
    ///
    /// ## ⑤ 의 한계 — 감수한다
    /// **새 IP 로 바뀐 기기는 ARP 에 없다** (아직 통신한 적이 없으므로).
    /// ⑤ 는 "DHCP 가 이전에 쓰던 IP 를 다시 준 경우"에만 도움이 된다.
    /// 정말 모르면 — **사용자에게 사유를 보여주는 것**이 정보다.
    static func reconnectCandidateOrder(
        lastEndpoint: String?,
        lostSerial: String,
        deviceReported: [String],
        gateway: String?,
        arpNeighbours: [String],
        sweptSubnet: [String] = []
    ) -> [String] {
        var out: [String] = []
        func add(_ ip: String?) {
            guard let ip else { return }
            let v = ip.trimmingCharacters(in: .whitespaces)
            guard isIPv4(v), !isLoopback(v), !out.contains(v) else { return }
            out.append(v)
        }
        add(lastEndpoint.flatMap { host(ofEndpoint: $0) })
        add(host(ofEndpoint: lostSerial))
        deviceReported.forEach { add($0) }
        add(gateway)
        arpNeighbours.forEach { add($0) }
        sweptSubnet.forEach { add($0) }
        return out
    }

    /// 첫 후보 — 후보가 하나일 때 쓰는 편의 (기존 호출부 호환)
    static func resolveIp(
        gateway: String?,
        ifAddrText: String?,
        ifconfigText: String?,
        routeText: String?
    ) -> String? {
        resolveIpCandidates(
            gateway: gateway,
            ifAddrText: ifAddrText,
            ifconfigText: ifconfigText,
            routeText: routeText
        ).first
    }

    /// 이미 해당 엔드포인트가 열려 있으면 tcpip 을 다시 걸지 않는다.
    /// 이유: `adb tcpip` 은 **adbd 를 재시작**해서 그 순간 USB 연결이 잠깐 사라진다.
    /// 이미 TCP 로 열려 있다면 기기는 재부팅된 적이 없으니 다시 걸 이유가 없다.
    static func needsTcpip(isNetworkSerialPresent: Bool) -> Bool { !isNetworkSerialPresent }

    /// 저장된 엔드포인트에서 실제 확인할 IP — 접미사 일치 + IPv4 추출 (순수)
    ///
    /// 포트 개방 여부(`nc`)는 IO라 컨트롤러에서 확인하고, 여기서는 문자열 판정만 한다.
    /// 접미사만 보고 "열려 있음"으로 단정하면 재부팅 직후 stale에 스킵된다 (2026-10-10 실측).
    static func openEndpointHost(lastEndpoint: String?, port: Int) -> String? {
        guard let ep = lastEndpoint, ep.hasSuffix(":\(port)") else { return nil }
        return host(ofEndpoint: ep)
    }

    /// 실패 문장 조립 — `%@` 포함 키는 치환, 없으면 원인 병기 (AGENTS.local §4 [표시②])
    ///
    /// `%@` 키에 detail을 뒤에 붙이면 `%@` 원문이 화면에 노출된다 (2026-10-10 실측:
    /// `%@ 에 닿지 않습니다 — ... — 10.164.172.249:5555`). 포함 여부로 분기한다.
    static func failText(key: String, detail: String?) -> String {
        let base = L10n.string(key)
        guard let detail, !detail.isEmpty else { return base }
        if base.contains("%@") { return L10n.format(key, detail) }
        return "\(base) — \(detail)"
    }

    /// `ro.boot.serialno` 로 읽는 **물리 기기 고유값** — TCP 엔드포인트의 정체
    ///
    /// ## 왜 이게 정답인가 (2026-09-27 실측)
    ///
    /// `adb devices` 의 키는 TCP 라 `10.38.120.211:5555` 처럼 **IP 라 IP 가 바뀐다.**
    /// 그러면 옛 엔드포인트와 새 엔드포인트가 같은 폰인지 알 수 없어
    /// stale 항목이 계속 남고, 같은 폰이 2개 기기로 잡혀 **폴링이 두 배**로 돌아간다.
    ///
    /// 실측 — 같은 폰이 하루에 세 번 IP 를 바꿨는데 `ro.boot.serialno` 는 고정:
    /// ```
    /// 10.233.247.205:5555 (오전)  ─┐
    /// 172.30.102.182:5555 (저녁)  ─┼─ 전부 ro.boot.serialno = R5CT215F4QK
    /// 10.38.120.211:5555 (지금)   ─┘
    /// ```
    /// **TCP 로도 읽힌다** — 별도 인증 없이 `shell getprop` 한 번이다.
    static let physicalIdProp = "ro.boot.serialno"

    /// TCP 엔드포인트인가 (`:5555` 형태 — USB 시리얼은 콜론이 없다)
    static func isNetworkEndpoint(_ serial: String) -> Bool {
        serial.contains(":")
    }

    /// [USB → Wi-Fi 전환] 의 대상이 될 수 있는가 — **USB 로 붙은 기기만** (판정만 · 테스트 고정)
    ///
    /// 이 버튼은 `adb tcpip 5555` 를 실행한다 = **adbd 재시작**. 무선 기기에 눌리면
    /// 지금 붙어 있는 무선 연결을 끊는다. 종전엔 시트를 무선 기기에서 열면 그 기기가
    /// 이 섹션의 대상으로 보였다(2026-10-18) — 종류를 모르는(`nil`) USB 기기는 허용한다.
    static func canEnableTcpip(connectionKind: ConnectionKind?) -> Bool {
        connectionKind == .usb || connectionKind == nil
    }

    /// stale 판정 — **물리 고유값이 같은데 엔드포인트가 다른** TCP 항목을 찾는다.
    ///
    /// - Parameters:
    ///   - physicalIdsByEndpoint: 엔드포인트 → 그 기기의 `ro.boot.serialno`.
    ///     **판별의 근거는 오직 이 값이다** — IP 로는 같은 폰인지 알 수 없다.
    ///   - keep: 이번에 열었던 엔드포인트. 이건 명백히 살아 있으므로 건드리지 않는다.
    static func staleNetworkEndpoints(
        physicalIdsByEndpoint: [String: String],
        physicalId: String,
        keep: String
    ) -> [String] {
        physicalIdsByEndpoint.compactMap { endpoint, id in
            guard endpoint != keep, id == physicalId else { return nil }
            return endpoint
        }.sorted()
    }

    static let autoModeKey = "relay.wifiAutoTcpip"

    // MARK: - 재연결 (2026-09-27 · PLAN_wifi_reconnect)

    /// 재연결 최소 간격 — **무한 재시도 방지**
    ///
    /// 폴링이 5초 주기이므로 쿨다운이 없으면 분당 **12회** connect 시도가 된다.
    /// adb 폭주 + 배터리. 쿨다운은 선택이 아니라 필수다.
    static let reconnectCooldown: TimeInterval = 60
    /// 연속 실패 시 간격을 2배씩 늘린다 (최대 15분) — 확실히 없는 기기면 오래 시도하지 않는다
    static let reconnectCooldownMax: TimeInterval = 900

    /// 재연결 간격 계산 — 연속 실패 `failures` 회 기준
    static func reconnectDelay(failures: Int) -> TimeInterval {
        let factor = pow(2.0, Double(max(0, failures)))
        return min(reconnectCooldown * factor, reconnectCooldownMax)
    }

    /// 재연결을 시도해야 하는가 — **판정만** (IO 없음, 테스트 가능)
    ///
    /// - TCP 엔드포인트가 유실된 경우만 대상 (USB 유실은 tcpip 경로가 따로 있다)
    /// - 자동 모드가 켜져 있어야 하고
    /// - 쿨다운이 지났어야 한다
    static func shouldReconnect(
        autoEnabled: Bool,
        lostSerial: String,
        now: Date,
        lastAttemptAt: Date?,
        failures: Int
    ) -> Bool {
        guard autoEnabled else { return false }
        // TCP 엔드포인트만 — USB 는 autoEnableIfEnabled 경로가 처리한다
        guard isNetworkEndpoint(lostSerial) else { return false }
        if let last = lastAttemptAt {
            let elapsed = now.timeIntervalSince(last)
            guard elapsed >= reconnectDelay(failures: failures) else { return false }
        }
        return true
    }

    /// 유실을 알리는 문구 키 — **판정만** (IO 없음 · 테스트 고정)
    ///
    /// 끊긴 순간 상태 줄을 바꾸지 않으면 직전의 "다시 연결했습니다"(성공)가 그대로 남아
    /// **"지금 연결됨"처럼 보인다** (2026-10-18 실측 — 사용자가 "안 없어지네").
    /// 자동모드가 꺼져 있으면 "다시 찾는 중"은 거짓말이므로 다른 문구를 쓴다.
    static func lostStatusKey(autoEnabled: Bool) -> String {
        autoEnabled ? "wifi.lost.searching" : "wifi.lost.autoOff"
    }

    /// 새 mDNS 광고를 봤을 때 **쿨다운만** 건너뛸지 — 순수 판정 (IO 없음 · 테스트 고정)
    ///
    /// 재시도 백오프(60초→2분→4분→8분→15분)는 **정말 없는 기기**를 두드리지 않으려는 장치다.
    /// 그런데 폰이 **돌아오는 순간**(재부팅·무선 디버깅 재토글)은 그 신호가 아니다 — 새 포트가
    /// 광고되면 곧바로 붙어야 한다. 실측(2026-10-18): 폰을 10분 만에 다시 켜면 백오프 때문에
    /// 최대 15분을 더 기다렸다(이번 사이클은 초기 단계라 51초).
    ///
    /// 광고가 **새로 보였을 때만** `true` 이므로 같은 광고로는 한 번만 건너뛴다 = 폭주하지 않는다.
    static func bypassCooldownOnNewAdvertisement(discovered: [String], lastSeen: String?) -> Bool {
        guard !discovered.isEmpty else { return false }
        return advertisedKey(discovered) != lastSeen
    }

    /// 광고 묶음의 지문 — 순서에 흔들리지 않게 정렬해 고정한다
    static func advertisedKey(_ discovered: [String]) -> String {
        discovered.sorted().joined(separator: ",")
    }

    /// adb connect 성공 판정 — 순수 함수 (테스트 고정)
    /// adb는 실패해도 exit 0을 반환하므로("failed to connect ..." + 0) 출력으로 판별한다.
    /// 스크립트의 `grep -qE "^(already )?connected to"` 와 동일 기준.
    /// exit 코드만 믿으면 실패를 성공으로 오판해 kill-server 폴백이 영원히 안 탄다 (2026-10-05 실측).
    static func isConnectSuccess(output: String) -> Bool {
        output.split(separator: "\n").contains { raw in
            let line = raw.trimmingCharacters(in: .whitespaces).lowercased()
            return line.hasPrefix("connected to") || line.hasPrefix("already connected to")
        }
    }

    /// adb 서버 stuck 판정 — 순수 함수 (테스트 고정)
    /// "No route to host"는 서버가 로컬 네트워크에 못 나가는 상태로 떠 있다는 신호다.
    /// 이 상태에선 connect 재시도가 전부 실패하므로 kill-server → start-server 1회가 정답이다
    /// (scrcpy_run.sh의 동일 단계 · USB 경로 connectWithRetry 선례).
    static func shouldRestartAdbServer(cause: String) -> Bool {
        cause.localizedCaseInsensitiveContains("no route to host")
    }

    /// 마지막 연결 엔드포인트 영속 키 — 재시작 기억상실 방지 (2026-10-05)
    /// lastEndpoint·유실목록은 메모리-only라 재시작하면 "붙어 있어야 할 기기"를 잊고 영원히 조용했다.
    static let lastEndpointKey = "relay.wifi.lastEndpoint"

    /// 기기별 기억 영속 키 — 물리 ID(`ro.boot.serialno`) → 마지막 TCP 엔드포인트 (2026-10-11)
    ///
    /// 단일 `lastEndpoint`만으로는 2대 운용이 안 된다: S22 IP가 기억돼 있으면
    /// Router USB 감지 시 "이미 Wi-Fi 연결됨"으로 스킵돼 Router는 영원히 자동으로 안 붙었다.
    /// IP는 바뀌어도 물리 ID는 고정이므로 키로 쓴다.
    static let endpointsByDeviceKey = "relay.wifi.endpointsByDevice"

    /// 기기별 기억 디코딩 — 깨지면 빈 dict (하나 오염으로 전체를 버리지 않음)
    static func decodeEndpointsByDevice(_ raw: String?) -> [String: String] {
        guard let raw, let data = raw.data(using: .utf8),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return map.filter { !$0.key.isEmpty && isNetworkEndpoint($0.value) }
    }

    static func encodeEndpointsByDevice(_ map: [String: String]) -> String {
        guard let data = try? JSONEncoder().encode(map),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }

    /// 엔드포인트 → 물리 ID 역조회 — 재연결 후보 ①번(전에 붙었던 IP)을 기기별로 고르기 위함
    static func physicalIdForEndpoint(_ endpoint: String, in map: [String: String]) -> String? {
        map.first { $0.value == endpoint }?.key
    }

    /// 기기별 기억 시드 — 이미 발견된(found)·대기 중(pending)·**사용자가 끊은** 기억은 올리지 않는다 (2026-10-11 · 2026-10-18)
    ///
    /// 종전 `seedLostEndpoint`는 "아무것도 안 보일 때"만 단일 슬롯을 살렸다.
    /// S22가 살아 있으면 Router 기억은 영원히 시드되지 않았다.
    /// `userDisconnected` 가 없으면 **[끊기] 로 끊은 기기가 다음 틱에 되살아난다**(실측 결함).
    static func seedLostEndpoints(
        remembered: [String: String],
        found: Set<String>,
        pending: Set<String>,
        userDisconnected: Set<String> = []
    ) -> [String] {
        remembered.values.filter {
            !found.contains($0) && !pending.contains($0) && !userDisconnected.contains($0)
        }.sorted()
    }

    /// 기억에서 엔드포인트를 지운다 — **[끊기] 는 "다시 잇지 마" 라는 뜻**이다 (판정만: 새 맵 반환)
    ///
    /// 이 기억(`endpointsByDevice`)은 자동 재연결의 씨앗이라, 남겨 두면 사용자가 끊은 기기를
    /// 앱이 1분 뒤 스스로 되살린다. 같은 물리 기기의 다른 엔드포인트는 그대로 둔다.
    static func forgetEndpoint(_ endpoint: String, in remembered: [String: String]) -> [String: String] {
        remembered.filter { $0.value != endpoint }
    }

    /// 시작 시 유실 후보 선등록 판정 — 순수 함수 (테스트 고정)
    /// adb 목록이 비어 시작했는데(재시작 직후) 저장된 엔드포인트가 있으면 그것을 잊지 않고 다시 찾는다.
    /// 대기 중인 유실이 이미 있으면 그것을 우선한다.
    static func seedLostEndpoint(savedLastEndpoint: String?, foundEmpty: Bool, hasPending: Bool) -> String? {
        guard foundEmpty, !hasPending,
              let saved = savedLastEndpoint, isNetworkEndpoint(saved) else { return nil }
        return saved
    }

    /// adbd 재기동 대기 — 고정 대기 대신 재시도로 판정한다 (스크립트는 4초 고정 대기)
    static let connectAttempts = 3
    static let connectRetryInterval: TimeInterval = 2
    /// 서버 재시작 뒤 추가 시도 — 재시작 직후 목록 반영이 늦어 1회로 끊으면 조용히 죽는다 (2026-10-10)
    static let postRestartAttempts = 2

    /// adb 오류에서 사람이 읽을 수 있는 원문을 뽑는다 (안쪽에 이미 `cause` 가 있다)
    static func cause(_ error: Error) -> String { (error as? WifiAdbError)?.cause ?? "" }

    /// `ip route` / `ip -f inet addr` / ifconfig 텍스트에서 wlan IPv4 추출
    /// 우선: Wi-Fi 인터페이스 · 그 외 default src
    static func parseWlanIp(from text: String) -> String? {
        // 1) Wi-Fi 인터페이스 블록의 inet (wlan0 / swlan0 / wlp…)
        //    블록 헤더를 보고 **Wi-Fi 인 것만** 넘긴다 — rmnet(셀룰러) 블록을 먼저 읽으면
        //    cellular 주소가 답이 된다 (실측 `10.148.183.154`)
        let wifiBlocks = blocks(of: text).filter { block in
            block.split(separator: "\n").contains { isWifiInterface(String($0)) }
        }
        if let ip = firstIPv4(inLines: wifiBlocks, interfaceHints: nil) {
            return ip
        }
        // 2) `ip route` → "src 192.168.x.y"
        for line in text.split(separator: "\n") {
            if let r = line.range(of: #"\bsrc\s+([0-9.]+)"#, options: .regularExpression) {
                let m = line[r]
                if let ip = ipv4(fromToken: String(m.split(separator: " ").last ?? "")) {
                    return ip
                }
            }
        }
        // 3) 전체 텍스트 첫 IPv4 (127. 제외)
        return firstIPv4(inLines: text.split(separator: "\n").map(String.init), interfaceHints: nil)
    }

    /// 엔드포인트 검증 — nil이면 OK, 아니면 i18n 키
    static func validateEndpoint(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "wifi.error.endpoint.empty" }
        guard let hostPort = splitHostPort(t) else { return "wifi.error.endpoint.format" }
        let (host, port) = hostPort
        guard isIPv4(host), (1...65535).contains(port) else {
            return "wifi.error.endpoint.format"
        }
        return nil
    }

    static func tcpipArgs(serial: String, port: Int = defaultPort) -> [String] {
        ["-s", serial, "tcpip", String(port)]
    }

    static func connectArgs(endpoint: String) -> [String] {
        ["connect", endpoint.trimmingCharacters(in: .whitespacesAndNewlines)]
    }

    static func disconnectArgs(endpoint: String) -> [String] {
        ["disconnect", endpoint.trimmingCharacters(in: .whitespacesAndNewlines)]
    }

    static func defaultEndpoint(ip: String, port: Int = defaultPort) -> String {
        "\(ip):\(port)"
    }

    /// 후보 엔드포인트를 확인할 때 **볼 포트** — 후보의 자기 포트(없으면 기본 5555)
    ///
    /// ★ 2026-10-17: 종전엔 재연결 게이트가 **5555 를 하드코딩**했다. 재부팅 뒤 폰은
    ///   5555(레거시 tcpip)를 닫고 무선 디버깅 포트만 연다. 게다가 `mergeDiscovered` 가
    ///   같은 호스트의 옛 5555 후보를 버리므로, 그 순간 후보는 무선 포트 **하나뿐**인데
    ///   게이트가 5555 를 보며 **그 하나를 걸러냈다** — mDNS 로 찾아 놓고도 못 붙는 경로다.
    ///   (49 실측 전 코드 검토에서 발견 · 실기기에서 재현하기 전에 고침)
    static func probePort(forEndpoint endpoint: String) -> Int {
        splitHostPort(endpoint)?.port ?? defaultPort
    }

    /// `host:port` 분리 — 포트 없으면 nil (기본 포트는 호출부에서 붙임)
    static func splitHostPort(_ t: String) -> (host: String, port: Int)? {
        let parts = t.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, let p = Int(parts[1]), !parts[1].isEmpty else {
            return nil
        }
        return (String(parts[0]), p)
    }

    static func isIPv4(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        for p in parts {
            guard !p.isEmpty, p.allSatisfy(\.isNumber), let n = Int(p), (0...255).contains(n) else {
                return false
            }
        }
        return true
    }

    // MARK: - 무선 디버깅 페어링 (Android 11+ · 2026-10-17 · PLAN_wifi_pairing)

    /// mDNS 광고 한 건 — `adb mdns services` 한 줄
    ///
    /// AOSP 설계(adbd_wifi)상 광고는 **폰이** 한다. 페어링 서비스는 "페어링 코드로 기기 페어링"
    /// 창이 열려 있는 동안만, connect 서비스는 무선 디버깅이 켜져 있는 동안 뜬다.
    /// 그래서 connect 광고는 **포트가 바뀌어도 우리에게 새 주소를 알려주는 유일한 단서**다.
    ///
    /// ## 인스턴스 이름은 서비스마다 겹친다 (2026-10-17 실측)
    ///
    /// 한 폰이 connect 와 pairing 을 **같은 인스턴스 이름**으로 광고한다:
    /// ```
    /// adb-R5CT215F4QK-iL8Q9e  _adb-tls-connect._tcp   192.168.86.49:45325
    /// adb-R5CT215F4QK-iL8Q9e  _adb-tls-pairing._tcp   192.168.86.49:45673
    /// ```
    /// 그래서 `instance` 만으로는 목록 항목을 구분할 수 없다 — SwiftUI `ForEach` 에
    /// 그대로 쓰면 **id 중복으로 페어링 줄이 사라지고 connect 줄이 두 번 그려진다**(실측 버그).
    /// 행 정체성은 `id`(인스턴스+종류+주소)를 쓴다.
    struct MdnsService: Identifiable, Hashable, Sendable {
        /// `adb-R0QKSX…-QXjCrW` (QR 페어링은 `studio-…`)
        let instance: String
        /// `_adb-tls-connect._tcp`
        let type: String
        let host: String
        let port: Int

        /// 행 정체성 — 같은 인스턴스가 종류별로 여러 줄 나오므로 셋을 모두 묶는다
        var id: String { "\(instance)|\(type)|\(endpoint)" }

        static let typePairing = "_adb-tls-pairing._tcp"
        static let typeConnect = "_adb-tls-connect._tcp"

        var endpoint: String { "\(host):\(port)" }
        var isPairing: Bool { type == Self.typePairing }
        var isConnect: Bool { type == Self.typeConnect }

        /// 인스턴스 이름의 시리얼이 이 기기 것인가 — `adb-<serial>[-<random>]`
        ///
        /// 접두 일치만 보면 `R0QKSX` 가 `R0QKSX2` 를 삼킨다 — 뒤가 끝이거나 `-` 여야 한다.
        func belongs(to serial: String) -> Bool {
            let prefix = "adb-\(serial)"
            guard instance.hasPrefix(prefix) else { return false }
            let rest = instance.dropFirst(prefix.count)
            return rest.isEmpty || rest.hasPrefix("-")
        }
    }

    /// `adb mdns services` 출력 파싱
    ///
    /// 실측 출력(그대로 테스트 픽스처에 고정):
    /// ```
    /// List of discovered mdns services
    /// adb-14141FDF600081         _adb._tcp          192.168.86.38:5555
    /// adb-14141FDF600081-QXjCrW  _adb-tls-pairing._tcp  192.168.86.38:33861
    /// ```
    /// 헤더·빈 줄은 버리고, 열 구분은 **공백/탭 가변**이므로 토큰 분리로 읽는다.
    static func parseMdnsServices(_ text: String) -> [MdnsService] {
        text.split(separator: "\n").compactMap { raw in
            let tokens = raw.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard tokens.count == 3 else { return nil }
            let instance = String(tokens[0])
            let type = String(tokens[1])
            guard !instance.isEmpty, type.hasPrefix("_adb") else { return nil }
            guard let hp = splitHostPort(String(tokens[2])), isIPv4(hp.host) else { return nil }
            return MdnsService(instance: instance, type: type, host: hp.host, port: hp.port)
        }
    }

    /// 페어링 창이 열린 기기 — 사용자가 코드를 읽어 올 대상
    static func pairingEndpoints(_ services: [MdnsService]) -> [String] {
        services.filter(\.isPairing).map(\.endpoint)
    }

    /// 표시 순서 — **페어링 창을 먼저** 올린다
    ///
    /// 무선 디버깅(connect) 광고는 늘 떠 있어서 목록 맨 위를 차지한다. 정작 사용자가
    /// 주소를 옮겨 적어야 하는 줄은 페어링 창 쪽이라, adb 출력 순서를 그대로 쓰면
    /// 매번 두 번째 줄을 눌러야 한다. 같은 종류끼리는 주소순으로 고정한다(순서 흔들림 방지).
    static func displayOrdered(_ services: [MdnsService]) -> [MdnsService] {
        services.sorted { a, b in
            if a.isPairing != b.isPairing { return a.isPairing }
            if a.host != b.host { return a.host < b.host }
            return a.port < b.port
        }
    }

    /// 이 주소가 **connect(무선 디버깅) 광고**인가 — 페어링 주소에 넣으면 반드시 실패한다
    ///
    /// 포트가 다르다(실측: connect 45325 / pairing 45673). 사용자는 폰 화면이 아니라
    /// 목록 첫 줄을 눌러 connect 포트를 넣기 쉽고, 그때 adb 는 `protocol fault` 만 뱉는다.
    static func isConnectEndpoint(_ endpoint: String, services: [MdnsService]) -> Bool {
        let e = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return services.contains { $0.isConnect && $0.endpoint == e }
    }

    /// 같은 호스트의 페어링 주소 — 잘못된 포트를 넣었을 때 대신 안내할 값
    static func pairingEndpoint(host: String, services: [MdnsService]) -> String? {
        services.first { $0.isPairing && $0.host == host }?.endpoint
    }

    /// **우리 기기**의 connect 엔드포인트만 고른다
    ///
    /// 같은 네트워크에 폰이 여러 대면 아무 폰에나 붙으면 안 된다 — 붙어도 `device` 로 보이므로
    /// `adoptEndpoint` 의 검증을 통과해 **남의 폰을 우리 기기로 착각**한다.
    /// ① 인스턴스 이름의 시리얼 일치(가장 정확) → ② 기억된 호스트 IP 일치(시리얼을 모를 때).
    static func matchingConnectEndpoints(
        services: [MdnsService],
        physicalId: String?,
        knownHosts: Set<String>
    ) -> [String] {
        let connect = services.filter(\.isConnect)
        if let pid = physicalId, !pid.isEmpty {
            let bySerial = connect.filter { $0.belongs(to: pid) }
            if !bySerial.isEmpty { return bySerial.map(\.endpoint) }
        }
        guard !knownHosts.isEmpty else { return [] }
        return connect.filter { knownHosts.contains($0.host) }.map(\.endpoint)
    }

    /// 발견된 엔드포인트를 후보 **앞**으로 — 같은 호스트의 옛 후보는 버린다
    ///
    /// 페어링·재부팅 뒤 포트는 바뀌고 레거시 5555 는 **닫혀 있다**. 옛 후보를 남겨두면
    /// 그 포트로 connect 를 날려 adb 서버 목록만 오염시킨다.
    static func mergeDiscovered(discovered: [String], base: [String]) -> [String] {
        guard !discovered.isEmpty else { return base }
        let discoveredHosts = Set(discovered.compactMap { host(ofEndpoint: $0) })
        var out: [String] = []
        for ep in discovered + base {
            guard !out.contains(ep) else { continue }
            if !discovered.contains(ep),
               let h = host(ofEndpoint: ep),
               discoveredHosts.contains(h) {
                continue
            }
            out.append(ep)
        }
        return out
    }

    /// 페어링 코드 정규화 — 6자리 숫자. 폰 화면에서 옮겨 적을 때 공백·하이픈이 묻어온다
    static func normalizePairingCode(_ raw: String) -> String {
        raw.filter(\.isNumber)
    }

    static func isValidPairingCode(_ raw: String) -> Bool {
        normalizePairingCode(raw).count == 6
    }

    static func pairArgs(endpoint: String, code: String) -> [String] {
        ["pair", endpoint.trimmingCharacters(in: .whitespacesAndNewlines), normalizePairingCode(code)]
    }

    /// `adb pair` 성공 판정 — **출력으로** 판정한다(adb는 실패해도 exit 0인 경우가 있다).
    /// 실측 기준 출력: `Successfully paired to 192.168.86.38:43811 [guid=adb-…]`
    static func isPairSuccess(output: String) -> Bool {
        output.lowercased().contains("successfully paired")
    }

    /// 페어링 실패 원문 → 사용자 문구 키 (원문은 UI가 함께 노출한다 — [표시②])
    static func pairFailureKey(output: String) -> String {
        let t = output.lowercased()
        if t.contains("wrong password") || t.contains("authentication failed") || t.contains("invalid") {
            return "wifi.pair.error.code"
        }
        if t.contains("already paired") { return "wifi.pair.error.already" }
        if t.contains("timed out") || t.contains("timeout") { return "wifi.pair.error.timeout" }
        if t.contains("failed to connect") || t.contains("cannot connect")
            || t.contains("protocol fault") || t.contains("no route") || t.contains("unreachable") {
            return "wifi.pair.error.unreachable"
        }
        return "wifi.pair.error.failed"
    }

    // MARK: - private helpers

    static func isLoopback(_ s: String) -> Bool { s.hasPrefix("127.") }

    /// 인터페이스 헤더("60: swlan0:", "wlan0: flags=…") 기준으로 텍스트를 블록으로 나눈다
    private static func blocks(of text: String) -> [String] {
        var out: [String] = []
        var current: [String] = []
        for raw in text.split(separator: "\n") {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let looksLikeHeader = trimmed.contains(":") && {
                let head = trimmed.prefix { $0 != ":" }.trimmingCharacters(in: .whitespaces)
                let after = trimmed.split(separator: ":", maxSplits: 1).last.map(String.init) ?? ""
                return head.isEmpty || head.allSatisfy(\.isNumber) || after.contains("flags=")
            }()
            if looksLikeHeader, !current.isEmpty {
                out.append(current.joined(separator: "\n"))
                current = []
            }
            if !trimmed.isEmpty { current.append(line) }
        }
        if !current.isEmpty { out.append(current.joined(separator: "\n")) }
        return out
    }

    private static func firstIPv4(inLines lines: [String], interfaceHints: [String]?) -> String? {
        for line in lines {
            // ifconfig: "inet 192.168.0.5  netmask ..."
            if let r = line.range(of: #"\binet\s+([0-9.]+)"#, options: .regularExpression) {
                let token = line[r].split(separator: " ").last.map(String.init) ?? ""
                if let ip = ipv4(fromToken: token), !ip.hasPrefix("127.") {
                    return ip
                }
            }
        }
        return nil
    }

    private static func ipv4(fromToken token: String) -> String? {
        let cleaned = token.trimmingCharacters(in: CharacterSet(charactersIn: ".,;/"))
        guard isIPv4(cleaned) else { return nil }
        return cleaned
    }
}

// MARK: - Controller (IO)

/// USB→Wi-Fi 전환·수동 connect — MainActor UI 바인딩
@MainActor
final class WifiAdbController: ObservableObject {
    static let shared = WifiAdbController()

    @Published var busy = false
    @Published var statusMessage: String?
    @Published var statusIsError = false
    @Published var lastEndpoint: String?
    /// 자동 모드가 마지막으로 실패했나 (버튼 배지용) — 자동 실패는 조용히 남긴다
    @Published private(set) var autoFailed = false
    /// 자동 실행 중인 시리얼 — 중복 실행 방지 (같은 기기에 tcpip 2번 걸면 adbd 2번 재시작)
    private var autoInFlight: Set<String> = []
    /// 아직 못 찾은 TCP 엔드포인트 — **1회성이면 Wi-Fi 복귀를 놓친다**
    /// 유실 이벤트 때 1회만 시도하고 끝내면, 그 시도가 Wi-Fi 꺼진 구간에 소진된 뒤
    /// Wi-Fi 가 돌아와도 재시도 트리거가 없다. 매 틱 쿨다운 걸고 재시도한다.
    private var lostNetworkEndpoints: Set<String> = []
    /// 마지막으로 본 mDNS 광고 (유실 시리얼 → 광고 지문) — **새 광고가 뜨면 쿨다운을 건너뛴다**
    private var lastSeenAdvertisement: [String: String] = [:]
    /// 사용자가 **[끊기]** 로 끊은 전송 — 되살리지도, "다시 찾는 중"이라고 말하지도 않는다 (2026-10-18)
    private var userDisconnectedEndpoints: Set<String> = []
    /// 재연결 상태 — 쿨다운과 연속 실패 횟수
    private var reconnectLastAttemptAt: Date?
    private var reconnectFailures = 0
    /// 기기별 기억 — 물리 ID → 마지막 TCP 엔드포인트 (2대 운용 · UserDefaults 영속)
    private var endpointsByDevice: [String: String] = {
        WifiAdbLogic.decodeEndpointsByDevice(
            UserDefaults.standard.string(forKey: WifiAdbLogic.endpointsByDeviceKey)
        )
    }()

    private init() {}

    // MARK: - 재연결 (2026-09-27 · PLAN_wifi_reconnect)

    /// 유실 기록 — tick 의 유실 이벤트에서 부른다 (TCP 만)
    ///
    /// 끊긴 **순간** 상태 줄을 바꾼다 — 직전 성공 문구("다시 연결했습니다")가 그대로 남으면
    /// "지금 연결됨"처럼 보인다 (2026-10-18 사용자 신고: "안 없어지네").
    /// 사용자가 [끊기] 로 끊은 건 알리지 않는다 — 되살리지도 않고, 한 일을 사건처럼 말하지도 않는다.
    func noteLostNetworkEndpoint(_ serial: String) {
        guard WifiAdbLogic.isNetworkEndpoint(serial) else { return }
        guard !userDisconnectedEndpoints.contains(serial) else { return }
        let isNew = !lostNetworkEndpoints.contains(serial)
        lostNetworkEndpoints.insert(serial)
        guard isNew else { return }  // 틱마다 같은 문구를 새로 쓰지 않는다
        let enabled = UserDefaults.standard.object(forKey: WifiAdbLogic.autoModeKey) as? Bool ?? true
        statusIsError = true
        statusMessage = L10n.string(WifiAdbLogic.lostStatusKey(autoEnabled: enabled))
        DebugLogger.shared.warn("WifiAdb", "[WARN] [LOST] \(serial) — \(statusMessage ?? "")")
    }

    /// 매 틱 재시도 — 돌아온 기기는 빼고, 남은 건 쿨다운 걸고 `autoReconnect`
    ///
    /// `shouldReconnect` 가 쿨다운 전이면 IO 없이 지나간다 (매 틱 호출해도 부담 없음).
    /// 성공한 기기는 `adoptEndpoint` 에서 목록에서 뺀다.
    func retryLostNetworkEndpoints(found: Set<String>) async {
        lostNetworkEndpoints.subtract(found)
        // 기기별 기억 시드 — S22가 살아 있어도 Router 기억은 살린다 (단일 슬롯의 foundEmpty 게이트와 달리).
        // 죽은 기기 기억은 쿨다운+백오프로 소진되므로 폭주하지 않는다.
        for ep in WifiAdbLogic.seedLostEndpoints(
            remembered: endpointsByDevice, found: found, pending: lostNetworkEndpoints,
            userDisconnected: userDisconnectedEndpoints
        ) {
            lostNetworkEndpoints.insert(ep)
        }
        // 재시작 기억상실 방지 — 비어 시작했는데 저장된 엔드포인트가 있으면 선등록한다.
        // 자동모드 OFF면 shouldReconnect 게이트가 막으므로 여기서 꺼내지 않는다.
        // (기기별 기억이 있으면 이미 위에서 시드됐으므로 구 단일 슬롯은 폴백으로만)
        if endpointsByDevice.isEmpty,
           let seed = WifiAdbLogic.seedLostEndpoint(
               savedLastEndpoint: UserDefaults.standard.string(forKey: WifiAdbLogic.lastEndpointKey),
               foundEmpty: found.isEmpty,
               hasPending: !lostNetworkEndpoints.isEmpty
           ) {
            lostNetworkEndpoints.insert(seed)
        }
        // 사용자가 [끊기] 한 전송은 어떤 경로로도 되살리지 않는다 (기억 시드·구 단일 슬롯 포함)
        lostNetworkEndpoints.subtract(userDisconnectedEndpoints)

        // ★ 새 광고 감지 — 폰이 **돌아온 순간**은 "없는 기기"가 아니다 (2026-10-18)
        //
        //   재시도 백오프(60초→2분→…→15분)는 정말 없는 기기를 두드리지 않으려는 장치인데,
        //   재부팅·토글 직후 **새 포트가 광고되는 순간**까지 기다리게 만들었다.
        //   실측: 폰을 10분 만에 다시 켜면 최대 15분을 더 기다리게 된다.
        //   → 광고가 **새로 보였을 때만** 그 기기의 쿨다운을 건너뛴다(같은 광고면 평소 백오프).
        //   조회는 한 틱에 **한 번**만 한다(`adb mdns services` ≈20ms) — 잃어버린 기기가 있을 때만 돈다.
        var services: [WifiAdbLogic.MdnsService] = []
        if !lostNetworkEndpoints.isEmpty, let adb = DeviceMonitor.adbPathNow(),
           let out = try? WifiAdbRunner.runMdnsServices(adb) {
            services = WifiAdbLogic.parseMdnsServices(out)
        }
        let knownHosts = Set(endpointsByDevice.values.compactMap { WifiAdbLogic.host(ofEndpoint: $0) })

        for s in lostNetworkEndpoints {
            let discovered = WifiAdbLogic.matchingConnectEndpoints(
                services: services,
                physicalId: WifiAdbLogic.physicalIdForEndpoint(s, in: endpointsByDevice),
                knownHosts: knownHosts
            )
            let bypass = WifiAdbLogic.bypassCooldownOnNewAdvertisement(
                discovered: discovered, lastSeen: lastSeenAdvertisement[s]
            )
            lastSeenAdvertisement[s] = discovered.isEmpty
                ? nil
                : WifiAdbLogic.advertisedKey(discovered)
            await autoReconnect(lostSerial: s, bypassCooldown: bypass)
        }
    }

    /// TCP 엔드포인트가 사라졌을 때 자동 재연결을 시도한다.
    ///
    /// "USB 를 뽑아도 IP 로 계속" 의 목표는 **IP 가 바뀌어도** 성립해야 한다.
    /// 핫스팟 이동이나 Wi-Fi 재연결로 IP 가 바뀌면 기존 엔드포인트가 죽고,
    /// USB 를 다시 꽂지 않아도 앱이 스스로 새 IP 로 붙어야 한다.
    ///
    /// 실패해도 조용히 지나가지 않는다 — 사유를 상태로 남긴다 ([표시②])
    ///
    /// - Parameter bypassCooldown: 새 mDNS 광고를 봤을 때 `true` — **쿨다운만** 건너뛴다.
    ///   자동모드 OFF·USB 시리얼 같은 다른 조건은 `shouldReconnect` 가 그대로 지킨다
    ///   (`lastAttemptAt` 을 nil 로 넘기는 방식).
    func autoReconnect(lostSerial: String, bypassCooldown: Bool = false) async {
        let now = Date()
        let enabled = UserDefaults.standard.object(forKey: WifiAdbLogic.autoModeKey) as? Bool ?? true
        guard WifiAdbLogic.shouldReconnect(
            autoEnabled: enabled,
            lostSerial: lostSerial,
            now: now,
            lastAttemptAt: bypassCooldown ? nil : reconnectLastAttemptAt,
            failures: reconnectFailures
        ) else { return }
        guard !busy, !autoInFlight.contains(lostSerial) else { return }
        guard let adb = DeviceMonitor.adbPathNow() else { return }

        autoInFlight.insert(lostSerial)
        reconnectLastAttemptAt = now
        defer { autoInFlight.remove(lostSerial) }

        // IP 는 **다시 판별**한다 — 옛 IP 로는 붙을 수 없다
        //
        // ★ 2026-09-28: 종전엔 **게이트웨이 IP 하나만** 보고 곧바로 붙으려 했다.
        //   게이트웨이 = 기기 IP 는 **SoftAP 일 때만** 성립한다(실측 `SoftApManagers:0` —
        //   이 기기는 SoftAP 가 아니었다). 집 Wi-Fi 에서 같은 로직은 **라우터로** 붙으러 가고,
        //   거기 adbd 가 없으니 "USB 로는 붙는데 인터넷으로 넘어가면 못 찾는다" 가 된다.
        //   → **후보들을 순서대로 시도**하고, **실제로 붙은 것을 확인**한다.
        let candidates = await resolveReconnectCandidates(adb: adb, lostSerial: lostSerial)
        guard !candidates.isEmpty else {
            reconnectFailures += 1
            failAutoMessage(L10n.string("wifi.reconnect.ipNotFound"),
                            serial: lostSerial,
                            retryIn: WifiAdbLogic.reconnectDelay(failures: reconnectFailures),
                            logKind: IssueLog.Kind.wifiReconnectFailed)
            return
        }

        var lastFailureDetail = ""
        var tried: Set<String> = []
        for endpoint in candidates {
            tried.insert(endpoint)
            guard let ip = WifiAdbLogic.host(ofEndpoint: endpoint) else { continue }
            // adbd 가 이미 TCP 모드다(TCP 로 붙어 있었으니) — **tcpip 은 건드리지 않는다**
            // tcpip 은 adbd 를 재시작해서 그 순간 연결을 **또** 끊는다
            //
            // ★ **그 엔드포인트의 포트로** 도달을 확인한다.
            //   - 후보가 여러 개일 때 `adb connect` 를 전부 시도하면 adb 서버 상태가 오염된다
            //     (connect 실패가 device 로 남음) — 2026-09-28 실측: ARP 이웃 3개 중 5555 가
            //     열린 것은 1개뿐이었다. 포트로 거르면 시도가 2회 줄어든다.
            //   - 종전엔 이 확인이 **5555 를 하드코딩**했다(도달 확인·포트 확인 두 곳 모두).
            //     재부팅 뒤 폰은 5555 를 닫고 무선 디버깅 포트만 연다. 게다가 `mergeDiscovered` 가
            //     같은 호스트의 옛 5555 후보를 버리므로 후보는 무선 포트 **하나뿐**인데,
            //     그 하나가 두 게이트에서 걸러져 **mDNS 로 찾아 놓고도 못 붙었다**
            //     (2026-10-18 실측: 광고 37311 이 5분 넘게 떠 있어도 재연결 0회).
            //   - 도달 확인과 포트 확인은 **같은 `nc -z` 프로브**라 한 번으로 합쳤다.
            guard PingProbe.reachable(ip: ip, port: WifiAdbLogic.probePort(forEndpoint: endpoint)) else {
                lastFailureDetail = L10n.format("wifi.reconnect.notReachable", endpoint)
                continue
            }
            if await adoptEndpoint(endpoint, adb: adb, lostSerial: lostSerial, detail: &lastFailureDetail) {
                return
            }
        }

        // 2차: 같은 대역 5555 스윕 — DHCP 로 IP 가 바뀐 기기는 ARP 에 없다.
        // 1차 후보가 전부 빗나갔을 때만 돈다 (254회 TCP connect, 쿨다운 구간 내).
        // 포트가 열린 곳에만 `adb connect` 를 날리므로 서버 오염 없음.
        if let gw = MacRoute.defaultGateway(),
           let prefix = WifiAdbLogic.subnetPrefix(ip: gw) {
            for ip in await Self.sweepSubnetForAdbd(prefix: prefix) {
                let endpoint = WifiAdbLogic.defaultEndpoint(ip: ip)
                guard !tried.contains(endpoint) else { continue }
                tried.insert(endpoint)
                if await adoptEndpoint(endpoint, adb: adb, lostSerial: lostSerial, detail: &lastFailureDetail) {
                    return
                }
            }
        }

        // 후보를 전부 시도해도 안 붙었다 — 사유를 그대로 남긴다 ([표시②])
        // pending 에는 남겨둔다 — 다음 쿨다운에 다시 시도한다 (1회성이면 복귀를 놓친다)
        reconnectFailures += 1
        let msg = (lastFailureDetail.isEmpty || lastFailureDetail == "-")
            ? L10n.format("wifi.reconnect.failed", lostSerial)
            : lastFailureDetail
        failAutoMessage(msg,
                        serial: lostSerial,
                        retryIn: WifiAdbLogic.reconnectDelay(failures: reconnectFailures),
                        logKind: IssueLog.Kind.wifiReconnectFailed)
        DebugLogger.shared.info(
            "WifiAdb",
            "[INFO] 재연결 실패 \(lostSerial) · 후보 \(tried.count)개 모두 불명"
        )
    }

    /// 후보에 실제로 붙는다 — connect 의 **성공**이 아니라 adb 가 그 기기를
    /// **실제로 device 로 인식했는지** 가 기준이다 (router 로 붙으면 즉시 떨어진다)
    /// - Returns: true 면 재연결 완료 (호출자는 종료), pending 에서 빠진다
    private func adoptEndpoint(
        _ endpoint: String,
        adb: String,
        lostSerial: String,
        detail: inout String
    ) async -> Bool {
        do {
            do {
                // 미러링 중인 전송은 끊지 않는다 (Demuxer error 원인) — 붙어 있는 연결은 그대로 쓴다
                if endpoint != mirroredSerial {
                    try? WifiAdbRunner.run(adb, WifiAdbLogic.disconnectArgs(endpoint: endpoint))
                }
                try WifiAdbRunner.runConnect(adb, WifiAdbLogic.connectArgs(endpoint: endpoint))
            } catch {
                // 서버 stuck이면 여기서 포기하지 않고 1회 회복 후 재시도 (스크립트와 동일).
                // 이 폴백이 없으면 앱은 쿨다운마다 같은 실패를 반복하고 사용자는 스크립트를 직접 돌리게 된다.
                guard WifiAdbLogic.shouldRestartAdbServer(cause: cause(error)) else {
                    throw error
                }
                statusMessage = L10n.string("wifi.reconnect.serverRestart")
                await restartAdbServerOnce(adb: adb, serial: lostSerial)
                if endpoint != mirroredSerial {
                    try? WifiAdbRunner.run(adb, WifiAdbLogic.disconnectArgs(endpoint: endpoint))
                }
                try WifiAdbRunner.runConnect(adb, WifiAdbLogic.connectArgs(endpoint: endpoint))
            }
            guard await Self.isConnectedAsDeviceSettled(adb: adb, endpoint: endpoint) else {
                detail = L10n.format("wifi.reconnect.failed", endpoint)
                return false
            }
            reconnectFailures = 0
            rememberEndpoint(endpoint, physicalId: physicalId(of: endpoint, adb: adb))
            // 붙었으니 [끊기] 표식은 의미가 없다 (다시 잃어버리면 정상 경로로 재시도한다)
            userDisconnectedEndpoints.remove(endpoint)
            lostNetworkEndpoints.remove(lostSerial)
            statusIsError = false
            statusMessage = L10n.format("wifi.reconnect.done", endpoint)
            DebugLogger.shared.info("WifiAdb", "[INFO] 재연결 성공 \(lostSerial) → \(endpoint)")
            await disconnectStaleEndpoints(adb: adb, keep: endpoint)
            return true
        } catch {
            detail = cause(error)
            return false
        }
    }

    /// 같은 대역에서 5555 가 열린 호스트 — 찾으면 조기 종료 (5555 는 보통 1개)
    ///
    /// `nc -z` 는 데이터 없이 연결만 시도하고 바로 닫는다 (adb 를 건드리지 않는다).
    /// 32개씩 묶어 병렬로 돈다 — closed/refused 는 즉시 떨어지고, 무응답만 1초 대기.
    private static nonisolated func sweepSubnetForAdbd(prefix: String) async -> [String] {
        let targets = WifiAdbLogic.sweepTargets(prefix: prefix)
        var found: [String] = []
        var index = targets.startIndex
        while index < targets.endIndex {
            let end = targets.index(index, offsetBy: 32, limitedBy: targets.endIndex) ?? targets.endIndex
            let batch = targets[index..<end]
            let hits = await withTaskGroup(of: String?.self, returning: [String].self) { group in
                for ip in batch {
                    group.addTask {
                        adbdPortOpen(ip: ip, port: WifiAdbLogic.defaultPort, timeoutSeconds: 1) ? ip : nil
                    }
                }
                var out: [String] = []
                for await hit in group {
                    if let hit { out.append(hit) }
                }
                return out
            }
            found.append(contentsOf: hits)
            if !found.isEmpty { break }
            index = end
        }
        return found.sorted()
    }

    /// 재연결 후보 IP — **순서대로 시도**한다 (2026-09-28)
    ///
    /// 게이트웨이 하나에 의존하지 않는다. **아직 USB 로 붙어 있는 기기**라면
    /// 기기에게 직접 `ip addr` / `ifconfig` / `ip route` 를 물어 후보를 얻는다
    /// (이게 "USB 로는 연결되는데 인터넷으로 넘어가면 못 찾는다" 의 해법이다).
    /// 기기가 이미 떨어졌다면 물을 수 없으므로 게이트웨이(SoftAP 가정)를 후보로 넣는다.
    private func resolveReconnectCandidates(adb: String, lostSerial: String) async -> [String] {
        // 기기가 아직 살아 있으면(USB 로) **직접 물어본다** — 가장 정확한 정보
        var deviceReported: [String] = []
        if let probe = WifiAdbLogic.host(ofEndpoint: lostSerial) {
            let ifAddr = try? await WifiAdbRunner.runCapture(adb, ["-s", probe, "shell", "ip", "-f", "inet", "addr"])
            let ifconfig = try? await WifiAdbRunner.runCapture(adb, ["-s", probe, "shell", "ifconfig"])
            let route = try? await WifiAdbRunner.runCapture(adb, ["-s", probe, "shell", "ip", "route", "get", "1.1.1.1"])
            deviceReported = WifiAdbLogic.resolveIpCandidates(
                gateway: nil, ifAddrText: ifAddr, ifconfigText: ifconfig, routeText: route
            )
        }

        // 같은 서브넷에서 이미 대화한 적 있는 이웃 — **포트 확인 전 후보**로만 쓴다
        let gateway = MacRoute.defaultGateway()
        let neighbours = gateway
            .flatMap { WifiAdbLogic.subnetPrefix(ip: $0) }
            .map { MacRoute.arpNeighbours(onSubnet: $0) } ?? []

        // 순서는 **순수 함수**가 정한다 — 여기서 손대지 않는다 (테스트가 고정한다)
        // ①번(전에 붙었던 IP)은 기기별 기억에서 — 유실된 엔드포인트의 물리 ID를 역조회.
        // 못 찾으면 구 단일 슬롯으로 폴백 (마이그레이션 전 기억).
        let ownEndpoint: String? = {
            if let pid = WifiAdbLogic.physicalIdForEndpoint(lostSerial, in: endpointsByDevice) {
                return endpointsByDevice[pid]
            }
            return lastEndpoint
        }()
        let order = WifiAdbLogic.reconnectCandidateOrder(
            lastEndpoint: ownEndpoint,
            lostSerial: lostSerial,
            deviceReported: deviceReported,
            gateway: gateway,
            arpNeighbours: neighbours
        )
        // ★ 새 후보 소스(2026-10-17 · PLAN_wifi_pairing): mDNS 광고.
        //   페어링해 둔 기기는 **재부팅 뒤에도** `_adb-tls-connect` 를 광고하고, 포트는 매번 다르다.
        //   그 포트는 ARP·게이트웨이 추정으로 알 수 없다 — 광고가 유일한 단서다.
        //   로직은 늘리지 않는다: 기존 후보 **앞에** 놓기만 한다(순수 함수가 순서를 고정).
        let discovered = Self.mdnsConnectEndpoints(
            adb: adb,
            physicalId: WifiAdbLogic.physicalIdForEndpoint(lostSerial, in: endpointsByDevice),
            knownHosts: Set(order)
        )
        return WifiAdbLogic.mergeDiscovered(
            discovered: discovered,
            base: order.map { WifiAdbLogic.defaultEndpoint(ip: $0) }
        )
    }

    /// mDNS 광고에서 **우리 기기**의 connect 엔드포인트 — 실패하면 빈 배열(추정으로 채우지 않는다)
    private static func mdnsConnectEndpoints(
        adb: String,
        physicalId: String?,
        knownHosts: Set<String>
    ) -> [String] {
        guard (physicalId?.isEmpty == false) || !knownHosts.isEmpty else { return [] }
        guard let out = try? WifiAdbRunner.runMdnsServices(adb) else { return [] }
        return WifiAdbLogic.matchingConnectEndpoints(
            services: WifiAdbLogic.parseMdnsServices(out),
            physicalId: physicalId,
            knownHosts: knownHosts
        )
    }

    /// adb 가 그 엔드포인트를 **실제 device 로** 인식했는지 확인
    private static func isConnectedAsDevice(adb: String, endpoint: String) async -> Bool {
        guard let out = try? await WifiAdbRunner.runCapture(adb, ["devices"]) else { return false }
        return out.split(separator: "\n").contains { line in
            line.hasPrefix(endpoint) && line.contains("device")
        }
    }

    /// connect 직후 settle 대기 — 서버 목록에 오르는 데 시간이 걸린다.
    /// 스크립트 test_device와 동일하게 최대 3회까지 2초 간격으로 확인한다.
    /// 즉시 1회만 보고 판정하면 붙을 수 있는 기기를 "실패"로 버린다.
    private static func isConnectedAsDeviceSettled(adb: String, endpoint: String) async -> Bool {
        for _ in 1...WifiAdbLogic.connectAttempts {
            if await Self.isConnectedAsDevice(adb: adb, endpoint: endpoint) { return true }
            try? await Task.sleep(for: .seconds(WifiAdbLogic.connectRetryInterval))
        }
        return false
    }

    /// adbd 포트가 열려 있는지 — **TCPconnect 만** 하고 즉시 끊는다
    ///
    /// 왜 이게 필요한가 (2026-09-28 실측)
    /// 후보가 여러 개일 때 전부 `adb connect` 를 시도하면 **adb 서버 상태가 오염된다.**
    /// 실패한 connect 가 `devices` 에 남아 다음 판정을 흐리게 만든다.
    /// 계측: ARP 이웃 3개 중 5555 가 열린 것은 **1개뿐**이었다.
    /// → 포트로 먼저 걸러내면 **시도 횟수가 줄고** adb 가 깨끗하게 남는다.
    static nonisolated func adbdPortOpen(ip: String, port: Int, timeoutSeconds: Int = 2) -> Bool {
        // `nc -z` 는 데이터 없이 연결만 시도하고 바로 닫는다 (adb 를 건드리지 않는다)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
        proc.arguments = ["-z", "-G", String(timeoutSeconds), ip, String(port)]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do { try proc.run() } catch { return false }
        proc.waitUntilExit()
        return proc.terminationStatus == 0
    }

    /// USB 기기: tcpip → IP 판별 → connect
    ///
    /// 순서가 곧 정확도다 (2026-09-27 · `PLAN_wifi_auto_tcpip`):
    /// **tcpip 을 걸기 전에 IP 를 먼저 판별하고 도달 가능 여부를 확인한다.**
    /// 종전에는 tcpip 을 먼저 걸고 IP 를 뒤에서 찾았는데, 그 IP 판별이 이 기기에서
    /// **셀룰러 주소**를 잡았다(`ip route get` 의 src). 게다가 값을 반환하므로
    /// 올바른 후보(기기 `ip addr` 의 `swlan0`)에 도달하지 못했다.
    func enableWifi(serial: String, port: Int = WifiAdbLogic.defaultPort) {
        guard !busy else { return }
        busy = true
        statusIsError = false
        statusMessage = L10n.string("wifi.status.enabling")
        Task {
            defer { busy = false }
            guard let adb = DeviceMonitor.adbPathNow() else {
                fail("wifi.error.adbMissing")
                return
            }
            await runEnable(serial: serial, port: port, adb: adb, quiet: false)
        }
    }

    /// 자동 모드 — 실패해도 사용자 방해 금지(팝업 없음), 상태만 남긴다 (PLAN_wifi_auto_tcpip §2)
    func enableWifiAutomatically(serial: String, port: Int = WifiAdbLogic.defaultPort) async {
        guard !autoInFlight.contains(serial) else { return }
        guard !busy else { return }
        autoInFlight.insert(serial)
        defer { autoInFlight.remove(serial) }
        guard let adb = DeviceMonitor.adbPathNow() else {
            DebugLogger.shared.warn("WifiAdb", "[WARN] wifi.error.adbMissing (auto)")
            return
        }
        await runEnable(serial: serial, port: port, adb: adb, quiet: true)
    }

    /// 자동 모드 진입점 — 설정이 꺼져 있으면 아무것도 하지 않는다 (기본 ON)
    ///
    /// 판정은 **기기별**이다 (2026-10-11): 이 기기의 기억된 엔드포인트가 열려 있을 때만
    /// 스킵한다. 종전엔 전역 lastEndpoint 하나만 보고 "이미 Wi-Fi 연결됨"으로 생략해서,
    /// S22 IP가 살아 있으면 Router USB 감지 시 Router 자동 연결이 영원히 안 됐다.
    func autoEnableIfEnabled(serial: String) async {
        guard UserDefaults.standard.object(forKey: WifiAdbLogic.autoModeKey) as? Bool ?? true else { return }
        guard let adb = DeviceMonitor.adbPathNow() else { return }
        if let pid = physicalId(of: serial, adb: adb),
           let own = endpointsByDevice[pid],
           WifiAdbLogic.isNetworkEndpoint(own),
           await isEndpointOpen(own) {
            if await Self.isConnectedAsDevice(adb: adb, endpoint: own) {
                rememberEndpoint(own, physicalId: pid)
                DebugLogger.shared.info("WifiAdb", "[INFO] 이미 Wi-Fi 연결됨 — 자동 실행 생략 \(serial) → \(own)")
                return
            }
            // 포트는 열려 있는데 adb 목록에만 없음(맥·서버 재시작 직후) — connect만, tcpip 금지
            // (tcpip은 adbd 재시작이라 멀쩡한 연결을 끊는다)
            try? WifiAdbRunner.run(adb, WifiAdbLogic.disconnectArgs(endpoint: own))
            if (try? WifiAdbRunner.runConnect(adb, WifiAdbLogic.connectArgs(endpoint: own))) != nil,
               await Self.isConnectedAsDeviceSettled(adb: adb, endpoint: own) {
                rememberEndpoint(own, physicalId: pid)
                statusIsError = false
                statusMessage = L10n.format("wifi.reconnect.done", own)
                DebugLogger.shared.info("WifiAdb", "[INFO] Wi-Fi 재등록 \(serial) → \(own)")
                return
            }
            // connect 실패 → 아래 전체 경로(tcpip 포함)로 폴백
        }
        autoFailed = false
        await enableWifiAutomatically(serial: serial)
    }

    /// 자동 모드 설정 키 — 기본 ON (사용자 확정)
    static let autoModeKey = "relay.wifiAutoTcpip"

    /// 지정 엔드포인트의 포트가 실제로 열려 있는지 — `nc` 는 detached 실행이라 MainActor를 막지 않는다.
    ///
    /// 메모리 문자열 접미사가 아니라 **실제 포트 개방**으로 판정한다.
    /// 재부팅은 포트를 닫는데 문자열은 남으므로, 접미사만 보면 재부팅 직후 USB 재연결이
    /// 영원히 스킵된다 (2026-10-10 실측).
    /// 전역 lastEndpoint가 아닌 인자 endpoint 기준 — 다른 기기 IP 때문에 스킵되면 안 된다 (2026-10-11).
    func isEndpointOpen(_ endpoint: String, port: Int = WifiAdbLogic.defaultPort) async -> Bool {
        guard let ip = WifiAdbLogic.openEndpointHost(lastEndpoint: endpoint, port: port) else { return false }
        return await Task.detached { Self.adbdPortOpen(ip: ip, port: port) }.value
    }

    private func runEnable(serial: String, port: Int, adb: String, quiet: Bool) async {
        do {
            // ① IP 판별 — 게이트웨이 1순위
            guard let ip = try? await resolveIp(serial: serial, adb: adb) else {
                if quiet { failAuto("wifi.error.ipNotFound") } else { fail("wifi.error.ipNotFound") }
                return
            }
            let endpoint = WifiAdbLogic.defaultEndpoint(ip: ip, port: port)

            // ② USB 전송 확인 — tcpip은 USB로 걸므로 USB가 살아 있으면 진행한다.
            //    포트 닫힘(재부팅 직후)은 이 버튼이 해결해야 할 본래 작업이라,
            //    TCP 포트로 게이트하면 닫힌 뒤엔 영원히 복구되지 않는다 (2026-10-10 실측:
            //    재부팅 후 `service.adb.tcp.port` 빈칸 + `nc` 실패 상태에서 버튼이
            //    tcpip을 한 번도 실행하지 못하고 "닿지 않습니다"만 반복).
            //    (ping이 아니라 USB get-state — 핫스팟 폰은 ICMP를 막는다, 실측)
            let usbState = try? WifiAdbRunner.runCapture(adb, ["-s", serial, "get-state"])
            guard usbState?.trimmingCharacters(in: .whitespacesAndNewlines) == "device" else {
                if quiet {
                    failAuto("wifi.auto.notReachable", detail: endpoint)
                } else {
                    failDetail("wifi.auto.notReachable", detail: endpoint)
                }
                return
            }

            // ③ 멱등 — 이 기기의 엔드포인트 포트가 실제로 열려 있으면 그대로 쓴다
            // (전역 lastEndpoint 기준이 아님 — 다른 기기 IP가 열려 있다고 스킵되면 안 됨, 2026-10-11)
            if await isEndpointOpen(endpoint, port: port) {
                rememberEndpoint(endpoint, physicalId: physicalId(of: serial, adb: adb))
                statusMessage = L10n.format("wifi.auto.alreadyOpen", endpoint)
                DebugLogger.shared.info("WifiAdb", "[INFO] 이미 열려 있음 — tcpip 생략 \(endpoint)")
                return
            }

            // ④ tcpip → ⑤ 준비 대기(재시도) → ⑥ 정리 → ⑦ connect
            try WifiAdbRunner.run(adb, WifiAdbLogic.tcpipArgs(serial: serial, port: port))
            try await connectWithRetry(adb: adb, endpoint: endpoint, port: port)
            rememberEndpoint(endpoint, physicalId: physicalId(of: serial, adb: adb))
            // ⑧ 옛 IP 정리 — IP 가 바뀌면 옛 항목이 남아 **같은 폰이 2개 기기**로 잡힌다(폴링 2배)
            await disconnectStaleEndpoints(adb: adb, keep: endpoint)
            statusMessage = L10n.format("wifi.status.connected", endpoint)
            DebugLogger.shared.info("WifiAdb", "[INFO] [FEATURE] Wi-Fi 연결 \(endpoint)")
        } catch {
            if quiet {
                // 자동 실패는 기기 로그에 남긴다 — 시트가 닫혀 있으면 상태 문구가 어디에도 안 보여
                // 다음 진단 때 원인을 찾을 수 없다 (2026-10-10 실측: 재시작 뒤 실패가 로그에 없었다)
                failAuto("wifi.error.connectFailed", detail: cause(error), serial: serial, logKind: IssueLog.Kind.wifiReconnectFailed)
            } else {
                failDetail("wifi.error.connectFailed", detail: cause(error))
            }
        }
    }

    /// 옛 TCP 엔드포인트 정리 — **같은 폰의 옛 IP** 만 끊는다 (2026-09-27 실측 발견)
    ///
    /// ## 왜 필요한가
    ///
    /// Wi-Fi IP 는 바뀐다(같은 폰이 하루에 세 번 바뀐 것을 관측). 그런데 `adb devices` 의
    /// TCP 키는 IP 그 자체라 **옛 항목이 계속 살아남고**, 같은 폰이 2개 기기로 잡혀
    /// **폴링이 두 배**로 돌아간다(adb 자식 3개 실측).
    ///
    /// ## "같은 기기" 를 어떻게 아는가
    ///
    /// IP 로는 알 수 없다. `ro.boot.serialno` 로 판별한다 — 이 값은 IP 가 바뀌어도
    /// 고정이고 **TCP 로도 읽힌다**(인증 불필요, `shell getprop` 1회).
    ///
    /// ## 안전장치
    ///
    /// - 판별 근거가 모호하면 **아무것도 끊지 않는다** (조용히 남겨두는 편이 낫다)
    /// - `keep` (방금 연 엔드포인트) 는 절대 건드리지 않는다
    /// - 실패해도 연결 성 자체에는 영향이 없다 — 정리 실패는 경고로만 남긴다
    /// 지금 scrcpy 가 화면을 띄우고 있는 전송 — **이걸 끊으면 미러링이 죽는다**
    ///
    /// 실측(2026-10-17): S22 하나가 레거시 `:5555` 와 무선 디버깅 `:45325` 로 **동시에** 잡힌다.
    /// 정리 로직이 미러링 중인 전송을 disconnect 하면 화면이 즉시 죽고 scrcpy 는
    /// `ERROR: Demuxer error` 만 남긴다("미러링이 끊긴다"의 실제 경로).
    private var mirroredSerial: String? { ScrcpyController.shared.runningSerial }

    private func disconnectStaleEndpoints(adb: String, keep: String) async {
        guard let list = try? WifiAdbRunner.runCapture(adb, ["devices"]) else {
            DebugLogger.shared.warn("WifiAdb", "[WARN] stale 정리 — adb devices 실패, 건너뜀")
            return
        }
        let alive = Self.parseDeviceList(list)
        let networkSerials = alive.filter { WifiAdbLogic.isNetworkEndpoint($0) }
        // 이미 하나뿐이면 정리할 것이 없다 (대부분의 경우)
        guard networkSerials.count > 1 else { return }

        // 이번에 붙은 기기의 물리 고유값
        guard let keepPhysicalId = physicalId(of: keep, adb: adb) else {
            DebugLogger.shared.warn("WifiAdb", "[WARN] stale 정리 — 물리 식별 실패, 건너뜀")
            return
        }
        // 각 TCP 후보의 물리 고유값 — **판별의 유일한 근거**
        var ids: [String: String] = [:]
        for endpoint in networkSerials {
            guard let id = physicalId(of: endpoint, adb: adb) else { continue }
            ids[endpoint] = id
        }
        let stale = WifiAdbLogic.staleNetworkEndpoints(
            physicalIdsByEndpoint: ids, physicalId: keepPhysicalId, keep: keep
        )
        // 미러링 중인 전송은 **정리 대상에서 빼낸다** — 정리는 중복 전송을 줄이는 편의일 뿐이고,
        // 사용자가 보고 있는 화면을 끊는 것보다 중복을 남기는 편이 낫다.
        let mirroring = mirroredSerial
        let targets = stale.filter { $0 != mirroring }
        if targets.count != stale.count {
            DebugLogger.shared.info("WifiAdb", "[INFO] 옛 IP 정리 보류 — 미러링 중 \(mirroring ?? "-")")
        }
        guard !targets.isEmpty else { return }
        for endpoint in targets {
            do {
                try WifiAdbRunner.run(adb, WifiAdbLogic.disconnectArgs(endpoint: endpoint))
                DebugLogger.shared.info("WifiAdb", "[INFO] 옛 IP 정리: \(endpoint) disconnect")
            } catch {
                DebugLogger.shared.warn("WifiAdb", "[WARN] 옛 IP 정리 실패 \(endpoint): \(cause(error))")
            }
        }
    }

    /// 엔드포인트의 물리 고유값 — 실패 시 nil (판별 불가 → 아무것도 하지 않는다)
    private func physicalId(of endpoint: String, adb: String) -> String? {
        guard let out = try? WifiAdbRunner.runCapture(
            adb, ["-s", endpoint, "shell", "getprop", WifiAdbLogic.physicalIdProp]
        ) else { return nil }
        let value = out.trimmingCharacters(in: .whitespacesAndNewlines)
        // 빈 값·에러 문구는 식별 실패로 본다 — 추측으로 채우지 않는다
        guard !value.isEmpty, value.count <= 64, !value.contains("not found") else { return nil }
        return value
    }

    /// `adb devices` 출력에서 정상 상태인 기기만 뽑는다 (순수 파싱)
    nonisolated static func parseDeviceList(_ text: String) -> [String] {
        text.split(separator: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("List of devices") else { return nil }
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard let serial = parts.first, parts.contains("device") else { return nil }
            return String(serial)
        }
    }

    /// adb 서버 stuck 회복 — kill-server → start-server 1회 (스크립트와 동일 단계)
    /// USB·TCP 자동·수동 경로가 함께 쓴다. 데몬 재시작이라 진행 중 poll 1틱은
    /// 실패할 수 있으나 다음 틱에 복구된다 (USB 경로에서 이미 하던 일).
    private func restartAdbServerOnce(adb: String, serial: String?) async {
        DebugLogger.shared.warn("WifiAdb", "[WARN] No route to host — adb 서버 재시작 후 재시도")
        IssueLog.append(
            IssueLog.Entry(
                kind: IssueLog.Kind.wifiServerRestart,
                detail: "adb kill-server → start-server 후 재시도",
                serial: serial
            ),
            name: "device"
        )
        try? WifiAdbRunner.run(adb, ["kill-server"])
        try? await Task.sleep(for: .seconds(1))
        try? WifiAdbRunner.run(adb, ["start-server"])
    }

    /// adbd 재시작 직후엔 아직 준비 중일 수 있다 — 고정 대기 대신 **재시도로** 판정한다
    private func connectWithRetry(adb: String, endpoint: String, port: Int) async throws {
        var lastError: Error = WifiAdbError(cause: "")
        for attempt in 1...WifiAdbLogic.connectAttempts {
            // 고아 연결 정리 — 남아 있으면 새 연결이 붙지 않는다.
            // 단 미러링 중인 전송은 예외다 — 끊으면 scrcpy 가 Demuxer error 로 죽는다.
            if endpoint != mirroredSerial {
                try? WifiAdbRunner.run(adb, WifiAdbLogic.disconnectArgs(endpoint: endpoint))
            }
            do {
                try WifiAdbRunner.runConnect(adb, WifiAdbLogic.connectArgs(endpoint: endpoint))
                return
            } catch {
                lastError = error
                if attempt < WifiAdbLogic.connectAttempts {
                    statusMessage = L10n.format("wifi.auto.waiting", attempt, WifiAdbLogic.connectAttempts)
                    try? await Task.sleep(for: .seconds(WifiAdbLogic.connectRetryInterval))
                }
            }
        }
        // 마지막 시도도 "No route to host" 면 adb 서버 재시작 후 1회 (스크립트와 동일)
        if WifiAdbLogic.shouldRestartAdbServer(cause: WifiAdbLogic.cause(lastError)) {
            await restartAdbServerOnce(adb: adb, serial: nil)
            // 재시작 직후엔 목록 반영이 늦는다 — device 확인 없이 성공을 말하지 않는다
            // (2026-10-10 실측: 재시작 1회성 connect 뒤 entries에 오르지 않아 조용히 죽었다)
            var connected = false
            for _ in 1...WifiAdbLogic.postRestartAttempts {
                try? WifiAdbRunner.run(adb, WifiAdbLogic.disconnectArgs(endpoint: endpoint))
                do {
                    try WifiAdbRunner.runConnect(adb, WifiAdbLogic.connectArgs(endpoint: endpoint))
                    connected = true
                    break
                } catch {
                    lastError = error
                }
            }
            if connected, await Self.isConnectedAsDeviceSettled(adb: adb, endpoint: endpoint) { return }
            throw WifiAdbError(cause: WifiAdbLogic.cause(lastError))
        }
        throw lastError
    }

    func connect(endpoint: String) {
        guard !busy else { return }
        if let key = WifiAdbLogic.validateEndpoint(endpoint) {
            fail(key)
            return
        }
        busy = true
        statusIsError = false
        statusMessage = L10n.string("wifi.status.connecting")
        let clean = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            defer { busy = false }
            guard let adb = DeviceMonitor.adbPathNow() else {
                fail("wifi.error.adbMissing")
                return
            }
            do {
                try WifiAdbRunner.runConnect(adb, WifiAdbLogic.connectArgs(endpoint: clean))
            } catch {
                // 서버 stuck이면 수동 연결도 같은 함정에 빠진다 — 1회 회복 후 재시도 (스크립트와 동일)
                guard WifiAdbLogic.shouldRestartAdbServer(cause: cause(error)) else {
                    failDetail("wifi.error.connectFailed", detail: cause(error))
                    return
                }
                statusMessage = L10n.string("wifi.reconnect.serverRestart")
                await restartAdbServerOnce(adb: adb, serial: clean)
                do {
                    try WifiAdbRunner.runConnect(adb, WifiAdbLogic.connectArgs(endpoint: clean))
                } catch {
                    failDetail("wifi.error.connectFailed", detail: cause(error))
                    return
                }
            }
            rememberEndpoint(clean, physicalId: physicalId(of: clean, adb: adb))
            // 사용자가 직접 다시 이었다 — [끊기] 표식을 풀어 자동 재연결도 다시 살린다
            userDisconnectedEndpoints.remove(clean)
            statusMessage = L10n.format("wifi.status.connected", clean)
            DebugLogger.shared.info("WifiAdb", "[INFO] [FEATURE] Wi-Fi 연결 \(clean)")
        }
    }

    // MARK: - 무선 디버깅 페어링 (Android 11+ · 2026-10-17 · PLAN_wifi_pairing)

    /// mDNS 광고 목록 — UI가 보여주고, 재연결 후보의 새 소스가 된다 (매 틱 조회는 하지 않는다)
    @Published private(set) var mdnsServices: [WifiAdbLogic.MdnsService] = []

    /// 마지막 광고 조회 시각 — "기기 찾기가 실제로 돌았는가"를 화면에서 확인할 수 있게 (0건도 표시)
    @Published private(set) var mdnsLastRefresh: Date?

    /// 페어링 섹션 **전용** 결과 문구
    ///
    /// 시트 하단의 공용 상태줄(`statusMessage`)은 다른 섹션(USB→Wi-Fi·수동 연결)도 같이 쓴다.
    /// 페어링은 실패 원문이 길어 그 줄이 화면 밖으로 밀리기 쉬워, 섹션 안에 직접 남긴다.
    @Published var pairStatus: String?
    @Published var pairStatusIsError = false

    /// 시각 표기 — 조회·시도 시점을 문구에 붙인다 (HH:mm:ss)
    static func clockText(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }

    /// 광고 조회 — 무선 디버깅이 켜진 기기(`_adb-tls-connect`)와 페어링 창이 열린 기기가 보인다
    ///
    /// - returns: 발견 건수. adb 를 못 찾거나 조회가 실패하면 `nil`(기존 목록은 그대로 둔다).
    @discardableResult
    func refreshMdnsServices() async -> Int? {
        guard let adb = DeviceMonitor.adbPathNow() else { return nil }
        guard let text = try? WifiAdbRunner.runMdnsServices(adb) else { return nil }
        let found = WifiAdbLogic.parseMdnsServices(text)
        mdnsServices = found
        mdnsLastRefresh = Date()
        return found.count
    }

    /// [기기 찾기] 버튼 경로 — "돌았다"는 사실은 `mdnsLastRefresh` 줄이 화면에 남긴다 (0건도 표시)
    ///
    /// 실패만 문구로 알린다 — 그리고 **기존 목록을 지우지 않는다**("광고 없음"과 "조회 실패"는 다르다).
    func lookupMdns() {
        pairStatus = nil
        Task {
            guard await refreshMdnsServices() != nil else {
                pairFail("wifi.pair.error.mdns")
                return
            }
        }
    }

    /// Android 11+ 무선 디버깅 페어링 — **USB 없이** 첫 연결을 만든다
    ///
    /// 폰에서 "페어링 코드로 기기 페어링"을 열면 6자리 코드와 `IP:포트`가 나온다.
    /// 성공하면 곧바로 connect 까지 시도한다 — 페어링만 하고 끝나면 사용자가 다시 눌러야 한다.
    /// connect 포트는 페어링 포트와 **다르다**: mDNS 광고가 정답이고, 없으면 폰 화면의 포트를
    /// 수동 연결에 넣는 길을 안내한다.
    func pair(endpoint: String, code: String) {
        guard !busy else { return }
        if let key = WifiAdbLogic.validateEndpoint(endpoint) {
            pairFail(key)
            return
        }
        guard WifiAdbLogic.isValidPairingCode(code) else {
            pairFail("wifi.pair.error.code.format")
            return
        }
        let clean = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        // 페어링 포트와 connect 포트는 다르다 — connect 주소를 넣으면 adb 는 `protocol fault` 만 뱉는다.
        // 0.05초 만에 원문만 남기고 끝나므로, 여기서 걸러 **다음에 누를 주소**를 알려준다.
        if WifiAdbLogic.isConnectEndpoint(clean, services: mdnsServices) {
            let host = WifiAdbLogic.host(ofEndpoint: clean) ?? ""
            if let alt = WifiAdbLogic.pairingEndpoint(host: host, services: mdnsServices) {
                pairFail("wifi.pair.error.wrongPort", detail: alt)
            } else {
                pairFail("wifi.pair.error.wrongPort.noPairing")
            }
            return
        }
        busy = true
        pairStatusIsError = false
        pairStatus = L10n.string("wifi.pair.status.pairing")
        Task {
            defer { busy = false }
            guard let adb = DeviceMonitor.adbPathNow() else {
                pairFail("wifi.error.adbMissing")
                return
            }
            do {
                try WifiAdbRunner.runPair(adb, WifiAdbLogic.pairArgs(endpoint: clean, code: code))
            } catch {
                pairFailFromAdb(
                    cause: cause(error),
                    host: WifiAdbLogic.host(ofEndpoint: clean) ?? "",
                    services: mdnsServices
                )
                return
            }
            DebugLogger.shared.info("WifiAdb", "[INFO] [FEATURE] 무선 디버깅 페어링 \(clean)")
            await refreshMdnsServices()
            let host = WifiAdbLogic.host(ofEndpoint: clean) ?? ""
            let discovered = WifiAdbLogic.matchingConnectEndpoints(
                services: mdnsServices,
                physicalId: nil,
                knownHosts: host.isEmpty ? [] : [host]
            )
            let target = discovered.first ?? WifiAdbLogic.defaultEndpoint(ip: host)
            do {
                try WifiAdbRunner.runConnect(adb, WifiAdbLogic.connectArgs(endpoint: target))
            } catch {
                // 페어링은 성공했다 — 연결 실패는 별개 사실로 알린다 (원문 노출)
                pairFail("wifi.pair.error.connectAfter", detail: cause(error))
                return
            }
            rememberEndpoint(target, physicalId: physicalId(of: target, adb: adb))
            pairOK(L10n.format("wifi.pair.status.done", target))
            DebugLogger.shared.info("WifiAdb", "[INFO] [FEATURE] 무선 디버깅 연결 \(target)")
        }
    }

    /// 페어링 섹션 전용 성공 문구
    private func pairOK(_ message: String) {
        pairStatusIsError = false
        pairStatus = message
    }

    /// 페어링 섹션 전용 실패 문구 — 시트 하단 공용 상태줄 대신 섹션 안에 남긴다
    private func pairFail(_ key: String, detail: String? = nil) {
        pairStatusIsError = true
        pairStatus = WifiAdbLogic.failText(key: key, detail: detail)
        DebugLogger.shared.warn("WifiAdb", "[WARN] [PAIR] \(key)\(detail.map { " \($0)" } ?? "")")
    }

    /// `adb pair` 실패 원문 → 사용자 문구
    ///
    /// 실측(2026-10-17): 폰이 **이미 이 맥의 키를 신뢰**해 `adb devices` 에 `device` 로 붙어 있는
    /// 상태에서 페어링을 다시 걸면 adb 는 `protocol fault (couldn't read status message)` 만 돌려준다.
    /// 원문만 보여주면 "폰에 닿지 않았다"로 오해한다 — 같은 호스트의 무선 디버깅 광고가 떠 있으면
    /// 이미 신뢰된 기기일 수 있다는 쪽으로 안내하고, 대신 누를 주소를 준다.
    private func pairFailFromAdb(cause: String, host: String, services: [WifiAdbLogic.MdnsService]) {
        let reachable = host.isEmpty ? [] : WifiAdbLogic.matchingConnectEndpoints(
            services: services,
            physicalId: nil,
            knownHosts: [host]
        )
        if let endpoint = reachable.first {
            pairFail("wifi.pair.error.alreadyTrusted", detail: endpoint)
            return
        }
        pairFail(WifiAdbLogic.pairFailureKey(output: cause), detail: cause)
    }

    func disconnect(serial: String) {
        guard !busy else { return }
        busy = true
        // enableWifi/connect와 동일 — 이전 실패의 오류 스타일이 성공 문구에 남지 않도록 리셋
        statusIsError = false
        Task {
            defer { busy = false }
            guard let adb = DeviceMonitor.adbPathNow() else {
                fail("wifi.error.adbMissing")
                return
            }
            do {
                try WifiAdbRunner.run(adb, WifiAdbLogic.disconnectArgs(endpoint: serial))
                // [끊기] 는 "다시 잇지 마" 라는 뜻이다 (2026-10-18 실측 결함: 기억이 남아 1분 뒤 되살아났다)
                userDisconnectedEndpoints.insert(serial)
                lostNetworkEndpoints.remove(serial)
                lastSeenAdvertisement[serial] = nil
                forgetEndpointMemory(serial)
                statusMessage = L10n.string("wifi.status.disconnected")
                DebugLogger.shared.info("WifiAdb", "[INFO] [FEATURE] Wi-Fi 해제 \(serial)")
            } catch {
                failDetail("wifi.error.disconnectFailed", detail: cause(error))
            }
        }
    }

    /// 기기 Wi-Fi IP — 실패 시 nil
    func fetchDeviceIp(serial: String) async throws -> String? {
        guard let adb = DeviceMonitor.adbPathNow() else { return nil }
        return try await resolveIp(serial: serial, adb: adb)
    }

    /// IP 판별 — **후보 순서가 곧 정확도다** (2026-09-27 실측 · PLAN_wifi_auto_tcpip §0)
    ///
    /// ① 맥 기본 게이트웨이 — 폰이 핫스팟이면 **게이트웨이가 곧 폰 IP**
    /// ② 기기 `ip addr` 전체 — Wi-Fi 인터페이스(`swlan0` 등)만 골라
    /// ③ 기기 `ifconfig` 전체
    /// ④ `ip route get` 의 src — **마지막**. 인터넷으로 나가는 쪽의 주소라
    ///    핫스팟 + 셀룰러 동시 켜진 기기에서는 **셀룰러 IP** 를 준다(실측 `10.148.183.154`)
    ///
    /// 종전에는 ④가 **1순위**였고, 그래서 이 기기에서 잘못된 IP로 connect 를 시도했다.
    private func resolveIp(serial: String, adb: String) async throws -> String? {
        let gateway = MacRoute.defaultGateway()
        let ifAddr = try? WifiAdbRunner.runCapture(adb, ["-s", serial, "shell", "ip", "-f", "inet", "addr"])
        let ifconfig = try? WifiAdbRunner.runCapture(adb, ["-s", serial, "shell", "ifconfig"])
        let route = try? WifiAdbRunner.runCapture(
            adb, ["-s", serial, "shell", "ip", "route", "get", "1.1.1.1"]
        )
        return WifiAdbLogic.resolveIp(
            gateway: gateway,
            ifAddrText: ifAddr,
            ifconfigText: ifconfig,
            routeText: route
        )
    }

    private func fail(_ key: String) {
        failDetail(key, detail: nil)
    }

    /// 자동 경로 실패 — 조용히 상태만 남긴다. 사용자가 아무것도 안 했는데
    /// 팝업이 튀면 방해가 된다. 대신 배지와 로그로는 남긴다 ([표시②]의 "조용한 return" 금지).
    /// - retryIn: 다음 자동 재시도까지 남은 쿨다운(초). 있으면 "약 N분 후 재시도"를 상태에 함께 표시한다 (C).
    /// - logKind/serial: IssueLog device 로그 기록용 (B) — 다음번 원인 추적을 위해 남긴다.
    private func failAuto(_ key: String, detail: String? = nil, serial: String? = nil, retryIn: TimeInterval? = nil, logKind: String? = nil) {
        let message = WifiAdbLogic.failText(key: key, detail: detail)
        failAutoMessage(message, serial: serial, retryIn: retryIn, logKind: logKind)
    }

    /// 완성된 문장으로 실패 기록 — base 키의 `%@` 를 이중으로 붙이지 않기 위해
    /// 이미 포맷된 detail을 가진 호출부(autoReconnect)가 쓴다.
    private func failAutoMessage(_ message: String, serial: String?, retryIn: TimeInterval?, logKind: String?) {
        autoFailed = true
        statusIsError = true
        var msg = message
        if let retryIn {
            let mins = max(1, Int((retryIn + 59) / 60))
            msg += " · \(L10n.format("wifi.reconnect.nextRetry", mins))"
        }
        statusMessage = msg
        DebugLogger.shared.warn("WifiAdb", "[WARN] [AUTO] \(msg)")
        if let logKind {
            IssueLog.append(
                IssueLog.Entry(kind: logKind, detail: msg, serial: serial),
                name: "device"
            )
        }
    }

    /// 실패 표시 — 원문(adb stderr 등)을 함께 노출 (AGENTS.local §4 [표시②])
    private func failDetail(_ key: String, detail: String?) {
        statusIsError = true
        statusMessage = WifiAdbLogic.failText(key: key, detail: detail)
        DebugLogger.shared.warn("WifiAdb", "[WARN] \(key)\(detail.map { " \($0)" } ?? "")")
    }

    /// 마지막 연결 기록 — 메모리 + UserDefaults 동시 저장 (재시작 기억상실 방지)
    /// physicalId가 있으면 기기별 기억에도 저장 (2대 운용 · 2026-10-11)
    private func rememberEndpoint(_ endpoint: String, physicalId: String? = nil) {
        lastEndpoint = endpoint
        UserDefaults.standard.set(endpoint, forKey: WifiAdbLogic.lastEndpointKey)
        if let physicalId, !physicalId.isEmpty {
            endpointsByDevice[physicalId] = endpoint
            UserDefaults.standard.set(
                WifiAdbLogic.encodeEndpointsByDevice(endpointsByDevice),
                forKey: WifiAdbLogic.endpointsByDeviceKey
            )
        }
    }

    /// 기억에서 이 엔드포인트를 지운다 — [끊기] 는 "다시 잇지 마" 다 (2026-10-18)
    ///
    /// 지우지 않으면 다음 틱의 기억 시드가 이 전송을 "잃어버린 기기"로 올려 **되살린다**.
    /// 수동 연결의 "최근:" 바로가기(`lastEndpoint`)는 남긴다 — 그건 사용자가 눌러야 동작한다.
    private func forgetEndpointMemory(_ endpoint: String) {
        let next = WifiAdbLogic.forgetEndpoint(endpoint, in: endpointsByDevice)
        guard next != endpointsByDevice else { return }
        endpointsByDevice = next
        UserDefaults.standard.set(
            WifiAdbLogic.encodeEndpointsByDevice(next),
            forKey: WifiAdbLogic.endpointsByDeviceKey
        )
    }

    /// 외부 명령 실패 원인 — WifiAdbError.cause 우선, 없으면 빈 문자열 (내부 코드 노출 금지)
    private func cause(_ error: Error) -> String { WifiAdbLogic.cause(error) }
}

/// adb 실행 실패 — 실제 stderr 원인을 보존 (AGENTS.local §4 [표시②])
struct WifiAdbError: LocalizedError, Sendable {
    let cause: String
    var errorDescription: String? { cause.isEmpty ? nil : cause }
}

/// IP 도달 확인 — 닿지 않는 기기에 tcpip 을 걸면 **adbd 만 재시작된 채** 끝난다
///
/// ## 왜 ping 이 아니라 TCP 포트 확인인가 (2026-09-27 실측)
///
/// 스크립트는 `ping -c 1` 을 쓰지만 **이 기기(핫스팟 + 셀룰러)에서는 ping 이 실패한다.**
/// ```
/// 맥 → 10.233.247.205 ping      : 100.0% packet loss   ← 실패
/// 폰 → 10.233.247.205 ping(자기) : 0% packet loss, 0.142ms  ← 같은 주소가 통함
/// 맥 → nc -z 10.233.247.205 5555: succeeded            ← adb 포트는 열려 있음
/// ```
/// 즉 **경로가 막힌 게 아니라 폰이 ICMP 응답을 안 하는 것**이다. ping 이 유일한 기준이면
/// 실제로 연결 가능한 기기를 "닿지 않습니다" 로 오판해 tcpip 을 건너뛴다.
/// 그래서 **실제 서비스 포트(adb 5555)** 로 확인한다 — 우리가 하려는 일의 대상이 그 포트이니
/// 더 직접적인 신호다.
enum PingProbe {
    /// adb TCP 포트 도달 확인
    ///
    /// **포트는 반드시 넘긴다** — 기본값을 두면 호출부가 무심코 5555 로 확인하고,
    /// 재부팅 뒤 무선 디버깅 포트 후보를 통째로 버린다(2026-10-18 실측 · 그 실수를 되풀이하지 않게
    /// 기본 인자를 **없앴다**).
    static func reachable(ip: String, port: Int) -> Bool {
        guard WifiAdbLogic.isIPv4(ip), !WifiAdbLogic.isLoopback(ip) else { return false }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
        // -z : 연결만 하고 데이터 없음 · -G : 타임아웃(초) · -w : 전체 대기 제한
        proc.arguments = ["-z", "-G", "2", "-w", "2", ip, String(port)]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            return false
        }
        _ = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return proc.terminationStatus == 0
    }
}

/// 맥 기본 게이트웨이 — **핫스팟 폰이면 곧 폰 IP** 다 (스크립트와 동일 아이디어)
enum MacRoute {
    /// 같은 서브넷에서 **이미 통신한 적 있는** IP — ARP 테이블에 있는 것만
    ///
    /// ## 왜 ping 스캔을 하지 않는가 (2026-09-28)
    /// 새 기기 IP 를 모를 때 "같은 LAN 에 누가 있나" 를 아는 유일한 단서가 ARP 테이블이다.
    /// 그런데 **전체 스캔(ping sweep)은 하지 않는다:**
    /// - 라우터·배터리 소모 (256 회 ping)
    /// - 응답 없는 기기까지 후보가 되어 **connect 시도**가 폭발한다
    /// → **이미 대화한 적이 있는** 이웃만 쓴다. 비용 0, 오탐 적음
    static func arpNeighbours(onSubnet prefix: String) -> [String] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
        proc.arguments = ["-an"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do { try proc.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let out = String(data: data, encoding: .utf8) ?? ""
        return WifiAdbLogic.parseArpIPs(out, onSubnet: prefix)
    }

    static func defaultGateway() -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/sbin/route")
        proc.arguments = ["-n", "get", "default"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            return nil
        }
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        proc.waitUntilExit()
        for line in text.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("gateway:") else { continue }
            let ip = t.replacingOccurrences(of: "gateway:", with: "")
                .trimmingCharacters(in: .whitespaces)
            if WifiAdbLogic.isIPv4(ip) { return ip }
        }
        return nil
    }

    /// 테스트용 — `route -n get default` 출력 파싱
    static func parseGateway(_ text: String) -> String? {
        for line in text.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("gateway:") else { continue }
            let ip = t.replacingOccurrences(of: "gateway:", with: "")
                .trimmingCharacters(in: .whitespaces)
            if WifiAdbLogic.isIPv4(ip) { return ip }
        }
        return nil
    }
}

/// adb 프로세스 실행 (Controller에서만)
enum WifiAdbRunner {
    static func run(_ path: String, _ args: [String]) throws {
        _ = try runCapture(path, args)
    }

    /// adb connect 전용 — exit 코드가 아니라 **출력**으로 성공 판별한다.
    /// adb는 실패해도 exit 0을 반환하므로 출력에 "connected to"가 없으면 실패로 던진다
    /// (스크립트의 grep 판별과 동일 — exit 코드만 믿으면 실패를 성공으로 오판한다).
    @discardableResult
    static func runConnect(_ path: String, _ args: [String]) throws -> String {
        let text = try runCapture(path, args)
        guard WifiAdbLogic.isConnectSuccess(output: text) else {
            throw WifiAdbError(cause: text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return text
    }

    @discardableResult
    /// `adb mdns services` — 즉시 끝난다(실측 0.02초). 광고 목록만 읽고 adb 상태는 건드리지 않는다.
    ///
    /// 실패는 **빈 문자열이 아니라 오류**로 알린다 — 호출부가 "광고 없음"과 "조회 실패"를
    /// 구분해야 기존 목록을 잘못 비우지 않는다.
    static func runMdnsServices(_ path: String) throws -> String {
        let out = try ProcessRunner.capture(path, ["mdns", "services"], timeout: 5)
        guard !out.timedOut else {
            throw WifiAdbError(cause: "mdns services timed out")
        }
        return out.stdout
    }

    /// `adb pair` — 코드를 **인자로** 넘긴다.
    ///
    /// 인자 없이 실행하면 `Enter pairing code:` 로 입력을 기다려 **멈춘다**(실측).
    /// 그래서 항상 인자로 넘기고 타임아웃을 걸어 프로세스가 남지 않게 한다.
    @discardableResult
    static func runPair(_ path: String, _ args: [String], timeout: TimeInterval = 30) throws -> String {
        let out = try ProcessRunner.capture(path, args, timeout: timeout)
        if out.timedOut {
            throw WifiAdbError(cause: L10n.string("wifi.pair.error.timeout"))
        }
        let text = "\(out.stdout)\n\(out.stderr)"
        guard WifiAdbLogic.isPairSuccess(output: text) else {
            let cause = out.cause
            throw WifiAdbError(cause: cause.isEmpty ? L10n.string("wifi.pair.error.failed") : cause)
        }
        return text
    }

    @discardableResult
    static func runCapture(_ path: String, _ args: [String]) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        try proc.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        // connect/tcpip는 출력으로 성공 판별 — exit 0 외 already connected 등 허용
        let text = String(data: data, encoding: .utf8) ?? ""
        let errText = String(data: errData, encoding: .utf8) ?? ""
        if proc.terminationStatus != 0 {
            // "already connected" 등은 성공으로 간주
            let haystack = "\(text)\n\(errText)".lowercased()
            if haystack.contains("already connected") || haystack.contains("connected to") {
                return text
            }
            let cause = errText.trimmingCharacters(in: .whitespacesAndNewlines)
            throw WifiAdbError(cause: cause.isEmpty ? text.trimmingCharacters(in: .whitespacesAndNewlines) : cause)
        }
        return text
    }
}
