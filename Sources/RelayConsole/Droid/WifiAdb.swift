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
    /// ① 맥 기본 게이트웨이 — 폰이 핫스팟이면 **게이트웨이가 곧 폰 IP** (기기한테 묻지 않아도 안다)
    /// ② 기기 `ip addr` 의 Wi-Fi 인터페이스 (`swlan0` 등)
    /// ③ 기기 `ifconfig` 전체
    /// ④ `ip route get` 의 `src` — **마지막**이다. 인터넷으로 나가는 쪽의 주소라
    ///    핫스팟 + 셀룰러 동시 켜진 기기에서는 **셀룰러 IP** 가 나온다 (실측 `10.148.183.154`).
    ///    게다가 빈 값이 아니라 **값을 반환해서** ②③에 도달하지 못하게 만든다.
    static func resolveIp(
        gateway: String?,
        ifAddrText: String?,
        ifconfigText: String?,
        routeText: String?
    ) -> String? {
        if let gw = gateway.map({ $0.trimmingCharacters(in: .whitespaces) }), isIPv4(gw), !isLoopback(gw) {
            return gw
        }
        if let t = ifAddrText, let ip = parseWifiIp(fromIfAddr: t) { return ip }
        if let t = ifconfigText, let ip = parseWlanIp(from: t) { return ip }
        if let t = routeText, let ip = parseWlanIp(from: t) { return ip }
        return nil
    }

    /// 이미 해당 엔드포인트가 열려 있으면 tcpip 을 다시 걸지 않는다.
    /// 이유: `adb tcpip` 은 **adbd 를 재시작**해서 그 순간 USB 연결이 잠깐 사라진다.
    /// 이미 TCP 로 열려 있다면 기기는 재부팅된 적이 없으니 다시 걸 이유가 없다.
    static func needsTcpip(isNetworkSerialPresent: Bool) -> Bool { !isNetworkSerialPresent }

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

    /// adbd 재기동 대기 — 고정 대기 대신 재시도로 판정한다 (스크립트는 4초 고정 대기)
    static let connectAttempts = 3
    static let connectRetryInterval: TimeInterval = 2

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
    /// 재연결 상태 — 쿨다운과 연속 실패 횟수
    private var reconnectLastAttemptAt: Date?
    private var reconnectFailures = 0
    /// 추적 중인 기기의 물리 ID — TCP 엔드포인트가 IP 라 바뀌어도 "어느 폰" 이었는지 알 수 있다
    private(set) var trackedPhysicalId: String?

    private init() {}

    // MARK: - 재연결 (2026-09-27 · PLAN_wifi_reconnect)

    /// TCP 엔드포인트가 사라졌을 때 자동 재연결을 시도한다.
    ///
    /// "USB 를 뽑아도 IP 로 계속" 의 목표는 **IP 가 바뀌어도** 성립해야 한다.
    /// 핫스팟 이동이나 Wi-Fi 재연결로 IP 가 바뀌면 기존 엔드포인트가 죽고,
    /// USB 를 다시 꽂지 않아도 앱이 스스로 새 IP 로 붙어야 한다.
    ///
    /// 실패해도 조용히 지나가지 않는다 — 사유를 상태로 남긴다 ([표시②])
    func autoReconnect(lostSerial: String) async {
        let now = Date()
        let enabled = UserDefaults.standard.object(forKey: WifiAdbLogic.autoModeKey) as? Bool ?? true
        guard WifiAdbLogic.shouldReconnect(
            autoEnabled: enabled,
            lostSerial: lostSerial,
            now: now,
            lastAttemptAt: reconnectLastAttemptAt,
            failures: reconnectFailures
        ) else { return }
        guard !busy, !autoInFlight.contains(lostSerial) else { return }
        guard let adb = DeviceMonitor.adbPathNow() else { return }

        autoInFlight.insert(lostSerial)
        reconnectLastAttemptAt = now
        defer { autoInFlight.remove(lostSerial) }

        // IP 는 **다시 판별**한다 — 옛 IP 로는 붙을 수 없다
        guard let ip = MacRoute.defaultGateway().flatMap({ WifiAdbLogic.isIPv4($0) ? $0 : nil }) else {
            reconnectFailures += 1
            failAuto("wifi.reconnect.ipNotFound")
            return
        }
        let endpoint = WifiAdbLogic.defaultEndpoint(ip: ip)
        // adbd 가 이미 TCP 모드다(TCP 로 붙어 있었으니) — **tcpip 은 건드리지 않는다**
        // tcpip 은 adbd 를 재시작해서 그 순간 연결을 **또** 끊는다
        guard PingProbe.reachable(ip: ip) else {
            reconnectFailures += 1
            failAuto("wifi.reconnect.notReachable", detail: endpoint)
            return
        }
        do {
            try? WifiAdbRunner.run(adb, WifiAdbLogic.disconnectArgs(endpoint: endpoint))
            try WifiAdbRunner.run(adb, WifiAdbLogic.connectArgs(endpoint: endpoint))
            reconnectFailures = 0
            lastEndpoint = endpoint
            statusIsError = false
            statusMessage = L10n.format("wifi.reconnect.done", endpoint)
            DebugLogger.shared.info("WifiAdb", "[INFO] 재연결 성공 \(lostSerial) → \(endpoint)")
            await disconnectStaleEndpoints(adb: adb, keep: endpoint)
        } catch {
            reconnectFailures += 1
            failAuto("wifi.reconnect.failed", detail: cause(error))
        }
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
    func autoEnableIfEnabled(serial: String) async {
        guard UserDefaults.standard.object(forKey: WifiAdbLogic.autoModeKey) as? Bool ?? true else { return }
        // 이미 TCP 로 열려 있으면 adbd 를 건드리지 않는다 (tcpip 은 adbd 재시작을 부른다)
        if isNetworkEndpointOpen() {
            DebugLogger.shared.info("WifiAdb", "[INFO] 이미 Wi-Fi 연결됨 — 자동 실행 생략 \(serial)")
            return
        }
        autoFailed = false
        await enableWifiAutomatically(serial: serial)
    }

    /// 자동 모드 설정 키 — 기본 ON (사용자 확정)
    static let autoModeKey = "relay.wifiAutoTcpip"

    /// 이미 TCP 로 열려 있으면 adbd 를 건드리지 않는다 — `tcpip` 은 adbd 를 재시작해서
    /// 그 순간 USB 연결이 잠깐 사라지기 때문(기기가 재부팅된 적 없다면 다시 걸 이유가 없다)
    func isNetworkEndpointOpen(port: Int = WifiAdbLogic.defaultPort) -> Bool {
        lastEndpoint.map { $0.hasSuffix(":\(port)") } ?? false
    }

    private func runEnable(serial: String, port: Int, adb: String, quiet: Bool) async {
        do {
            // ① IP 판별 — 게이트웨이 1순위
            guard let ip = try? await resolveIp(serial: serial, adb: adb) else {
                if quiet { failAuto("wifi.error.ipNotFound") } else { fail("wifi.error.ipNotFound") }
                return
            }
            let endpoint = WifiAdbLogic.defaultEndpoint(ip: ip, port: port)

            // ② 도달 확인 — 닿지 않는 기기에 tcpip 을 걸면 adbd 만 재시작된 채 끝난다
            //    (ping 이 아니라 adb 포트 — 핫스팟 폰은 ICMP 를 막는다, 실측)
            guard PingProbe.reachable(ip: ip, port: port) else {
                if quiet {
                    failAuto("wifi.auto.notReachable", detail: endpoint)
                } else {
                    failDetail("wifi.auto.notReachable", detail: endpoint)
                }
                return
            }

            // ③ 멱등 — 이미 TCP 로 열려 있으면 그대로 쓴다
            if isNetworkEndpointOpen(port: port) {
                lastEndpoint = endpoint
                statusMessage = L10n.format("wifi.auto.alreadyOpen", endpoint)
                DebugLogger.shared.info("WifiAdb", "[INFO] 이미 열려 있음 — tcpip 생략 \(endpoint)")
                return
            }

            // ④ tcpip → ⑤ 준비 대기(재시도) → ⑥ 정리 → ⑦ connect
            try WifiAdbRunner.run(adb, WifiAdbLogic.tcpipArgs(serial: serial, port: port))
            try await connectWithRetry(adb: adb, endpoint: endpoint, port: port)
            lastEndpoint = endpoint
            // ⑧ 옛 IP 정리 — IP 가 바뀌면 옛 항목이 남아 **같은 폰이 2개 기기**로 잡힌다(폴링 2배)
            await disconnectStaleEndpoints(adb: adb, keep: endpoint)
            statusMessage = L10n.format("wifi.status.connected", endpoint)
            DebugLogger.shared.info("WifiAdb", "[INFO] [FEATURE] Wi-Fi 연결 \(endpoint)")
        } catch {
            if quiet {
                failAuto("wifi.error.connectFailed", detail: cause(error))
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
        guard !stale.isEmpty else { return }
        for endpoint in stale {
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

    /// adbd 재시작 직후엔 아직 준비 중일 수 있다 — 고정 대기 대신 **재시도로** 판정한다
    private func connectWithRetry(adb: String, endpoint: String, port: Int) async throws {
        var lastError: Error = WifiAdbError(cause: "")
        for attempt in 1...WifiAdbLogic.connectAttempts {
            // 고아 연결 정리 — 남아 있으면 새 연결이 붙지 않는다
            try? WifiAdbRunner.run(adb, WifiAdbLogic.disconnectArgs(endpoint: endpoint))
            do {
                try WifiAdbRunner.run(adb, WifiAdbLogic.connectArgs(endpoint: endpoint))
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
        if WifiAdbLogic.cause(lastError).localizedCaseInsensitiveContains("no route to host") {
            DebugLogger.shared.warn("WifiAdb", "[WARN] No route to host — adb 서버 재시작 후 재시도")
            try? WifiAdbRunner.run(adb, ["kill-server"])
            try? await Task.sleep(for: .seconds(1))
            try? WifiAdbRunner.run(adb, ["start-server"])
            try WifiAdbRunner.run(adb, WifiAdbLogic.disconnectArgs(endpoint: endpoint))
            try WifiAdbRunner.run(adb, WifiAdbLogic.connectArgs(endpoint: endpoint))
            return
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
                try WifiAdbRunner.run(adb, WifiAdbLogic.connectArgs(endpoint: clean))
                lastEndpoint = clean
                statusMessage = L10n.format("wifi.status.connected", clean)
                DebugLogger.shared.info("WifiAdb", "[INFO] [FEATURE] Wi-Fi 연결 \(clean)")
            } catch {
                failDetail("wifi.error.connectFailed", detail: cause(error))
            }
        }
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
    private func failAuto(_ key: String, detail: String? = nil) {
        autoFailed = true
        statusIsError = true
        let base = L10n.string(key)
        statusMessage = (detail?.isEmpty == false) ? "\(base) — \(detail!)" : base
        DebugLogger.shared.warn("WifiAdb", "[WARN] [AUTO] \(key)\(detail.map { " \($0)" } ?? "")")
    }

    /// 실패 표시 — 원문(adb stderr 등)을 함께 노출 (AGENTS.local §4 [표시②])
    private func failDetail(_ key: String, detail: String?) {
        statusIsError = true
        let base = L10n.string(key)
        statusMessage = (detail?.isEmpty == false) ? "\(base) — \(detail!)" : base
        DebugLogger.shared.warn("WifiAdb", "[WARN] \(key)\(detail.map { " \($0)" } ?? "")")
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
    static func reachable(ip: String, port: Int = WifiAdbLogic.defaultPort) -> Bool {
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
