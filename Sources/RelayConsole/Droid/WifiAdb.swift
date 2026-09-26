import Foundation
import Combine

// MARK: - 순수 로직 (테스트)

enum WifiAdbLogic {
    static let defaultPort = 5555

    /// `ip route` / `ip -f inet addr` / ifconfig 텍스트에서 wlan IPv4 추출
    /// 우선: `wlan0` 인터페이스 · 그 외 default src
    static func parseWlanIp(from text: String) -> String? {
        // 1) wlan0 블록의 inet
        if let ip = firstIPv4(inLines: linesContaining(text, interfaceHints: ["wlan0"]), interfaceHints: ["wlan0"]) {
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

    private static func linesContaining(_ text: String, interfaceHints: [String]) -> [String] {
        var out: [String] = []
        var capturing = false
        for line in text.split(separator: "\n") {
            let l = String(line)
            if interfaceHints.contains(where: { l.contains($0) }) {
                capturing = true
                out.append(l)
                continue
            }
            if capturing {
                // 새 인터페이스 헤더면 중단
                if l.hasPrefix("inet ") || l.contains("wlan") || l.hasPrefix("wlp") {
                    if l.contains("wlan") || l.contains("wlp") { out.append(l); continue }
                    capturing = false
                } else {
                    out.append(l)
                }
            }
        }
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

    private init() {}

    /// USB 기기: tcpip → wlan IP → connect
    func enableWifi(serial: String, port: Int = WifiAdbLogic.defaultPort) {
        guard !busy else { return }
        busy = true
        statusIsError = false
        statusMessage = L10n.string("wifi.status.enabling")
        Task {
            defer {
                busy = false
            }
            guard let adb = DeviceMonitor.adbPathNow() else {
                fail("wifi.error.adbMissing")
                return
            }
            do {
                try WifiAdbRunner.run(adb, WifiAdbLogic.tcpipArgs(serial: serial, port: port))
                // adb 서버 재시작 대기
                try? await Task.sleep(nanoseconds: 800_000_000)
                guard let ip = try? await fetchDeviceIp(serial: serial, adb: adb) else {
                    fail("wifi.error.ipNotFound")
                    return
                }
                let endpoint = WifiAdbLogic.defaultEndpoint(ip: ip, port: port)
                try WifiAdbRunner.run(adb, WifiAdbLogic.connectArgs(endpoint: endpoint))
                lastEndpoint = endpoint
                statusMessage = L10n.format("wifi.status.connected", endpoint)
                DebugLogger.shared.info("WifiAdb", "[INFO] [FEATURE] Wi-Fi 연결 \(endpoint)")
            } catch {
                failDetail("wifi.error.connectFailed", detail: cause(error))
            }
        }
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

    /// 기기 wlan IP — 실패 시 nil
    func fetchDeviceIp(serial: String) async throws -> String? {
        guard let adb = DeviceMonitor.adbPathNow() else { return nil }
        return try await fetchDeviceIp(serial: serial, adb: adb)
    }

    private func fetchDeviceIp(serial: String, adb: String) async throws -> String? {
        // 빠른 경로: ip route get 1.1.1.1
        if let out = try? WifiAdbRunner.runCapture(
            adb,
            ["-s", serial, "shell", "ip", "route", "get", "1.1.1.1"]
        ), let ip = WifiAdbLogic.parseWlanIp(from: out) {
            return ip
        }
        if let out = try? WifiAdbRunner.runCapture(
            adb,
            ["-s", serial, "shell", "ip", "-f", "inet", "addr", "show", "wlan0"]
        ), let ip = WifiAdbLogic.parseWlanIp(from: out) {
            return ip
        }
        if let out = try? WifiAdbRunner.runCapture(
            adb,
            ["-s", serial, "shell", "ifconfig", "wlan0"]
        ), let ip = WifiAdbLogic.parseWlanIp(from: out) {
            return ip
        }
        return nil
    }

    private func fail(_ key: String) {
        failDetail(key, detail: nil)
    }

    /// 실패 표시 — 원문(adb stderr 등)을 함께 노출 (AGENTS.local §4 [표시②])
    private func failDetail(_ key: String, detail: String?) {
        statusIsError = true
        let base = L10n.string(key)
        statusMessage = (detail?.isEmpty == false) ? "\(base) — \(detail!)" : base
        DebugLogger.shared.warn("WifiAdb", "[WARN] \(key)\(detail.map { " \($0)" } ?? "")")
    }

    /// 외부 명령 실패 원인 — WifiAdbError.cause 우선, 없으면 빈 문자열 (내부 코드 노출 금지)
    private func cause(_ error: Error) -> String {
        (error as? WifiAdbError)?.cause ?? ""
    }
}

/// adb 실행 실패 — 실제 stderr 원인을 보존 (AGENTS.local §4 [표시②])
struct WifiAdbError: LocalizedError, Sendable {
    let cause: String
    var errorDescription: String? { cause.isEmpty ? nil : cause }
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
