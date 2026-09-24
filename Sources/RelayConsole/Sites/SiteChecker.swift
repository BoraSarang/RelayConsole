import Foundation
import Network

/// 사이트 업타임 체커 — HTTP / TCP / ping
/// 동시 상한은 호출부(ConsoleStore)에서 prefix로 제한 · 외부 바이너리 다운로드 없음
final class SiteChecker: @unchecked Sendable {
    static let shared = SiteChecker()
    static let timeout: TimeInterval = 10
    static let maxConcurrent = 8

    /// 대상 1건 체크
    func check(_ site: Site) async -> SiteCheck {
        switch site.probe {
        case .http:
            return await checkHTTP(SitesJobsLogic.sanitizeTarget(site.target, probe: .http))
        case .tcp:
            return await checkTCP(site.target)
        case .ping:
            return await checkPing(site.target)
        }
    }

    // MARK: - HTTP

    private func checkHTTP(_ urlString: String) async -> SiteCheck {
        guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return SiteCheck(ok: false, detail: "bad-url")
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = Self.timeout
        req.httpMethod = "GET"
        req.setValue("RelayConsole/1.0", forHTTPHeaderField: "User-Agent")
        let start = Date()
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            if let http = response as? HTTPURLResponse {
                if (200...399).contains(http.statusCode) {
                    return SiteCheck(ok: true, latencyMs: ms, detail: nil)
                }
                return SiteCheck(ok: false, latencyMs: ms, detail: SitesJobsLogic.summarize(error: nil, httpStatus: http.statusCode))
            }
            return SiteCheck(ok: false, detail: "bad-response")
        } catch {
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            return SiteCheck(ok: false, latencyMs: ms, detail: SitesJobsLogic.summarize(error: error))
        }
    }

    // MARK: - TCP

    private func checkTCP(_ target: String) async -> SiteCheck {
        guard let (host, port) = Self.parseHostPort(target, defaultPort: 443) else {
            return SiteCheck(ok: false, detail: "bad-host")
        }
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            return SiteCheck(ok: false, detail: "bad-port")
        }
        let start = Date()
        return await withCheckedContinuation { (cont: CheckedContinuation<SiteCheck, Never>) in
            let box = OnceBox<SiteCheck>()
            let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
            let settle: @Sendable (SiteCheck) -> Void = { value in
                if let v = box.complete(value) {
                    cont.resume(returning: v)
                }
            }
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    settle(SiteCheck(ok: true, latencyMs: Int(Date().timeIntervalSince(start) * 1000), detail: nil))
                    conn.cancel()
                case .failed:
                    settle(SiteCheck(ok: false, latencyMs: nil, detail: "failed"))
                    conn.cancel()
                case .waiting:
                    settle(SiteCheck(ok: false, latencyMs: nil, detail: "waiting"))
                    conn.cancel()
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .utility))
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.timeout) {
                settle(SiteCheck(ok: false, latencyMs: nil, detail: "timeout"))
                conn.cancel()
            }
        }
    }

    // MARK: - ping (/sbin/ping — OS 기본, 다운로드 없음)

    private func checkPing(_ host: String) async -> SiteCheck {
        let clean = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !clean.contains(" "), !clean.contains(";") else {
            return SiteCheck(ok: false, detail: "bad-host")
        }
        let start = Date()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/sbin/ping")
        proc.arguments = ["-c", "1", "-W", "2000", clean]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do {
            try proc.run()
            let deadline = Date().addingTimeInterval(Self.timeout)
            while proc.isRunning, Date() < deadline {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            if proc.isRunning {
                proc.terminate()
                return SiteCheck(ok: false, latencyMs: nil, detail: "timeout")
            }
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            if proc.terminationStatus == 0 {
                return SiteCheck(ok: true, latencyMs: ms, detail: nil)
            }
            return SiteCheck(ok: false, latencyMs: nil, detail: "ping-fail")
        } catch {
            return SiteCheck(ok: false, detail: "ping-missing")
        }
    }

    // MARK: - parse

    static func parseHostPort(_ target: String, defaultPort: Int) -> (String, Int)? {
        let t = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if t.hasPrefix("["), let close = t.firstIndex(of: "]") {
            let host = String(t[t.index(after: t.startIndex)..<close])
            let rest = t[t.index(after: close)...]
            if rest.hasPrefix(":"), let p = Int(rest.dropFirst()) { return (host, p) }
            return (host, defaultPort)
        }
        if t.contains(":") {
            let parts = t.split(separator: ":", maxSplits: 1)
            if parts.count == 2, let p = Int(parts[1]), !parts[0].isEmpty {
                return (String(parts[0]), p)
            }
        }
        return (t, defaultPort)
    }
}

/// 1회 완료 박스 (멀티 resume 방지)
final class OnceBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T?

    func complete(_ v: T) -> T? {
        lock.lock()
        defer { lock.unlock() }
        guard value == nil else { return nil }
        value = v
        return v
    }
}
