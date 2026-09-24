import Foundation
import Network
import Security

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
            return await checkHTTP(site)
        case .tcp:
            return await checkTCP(site.target)
        case .ping:
            return await checkPing(site.target)
        }
    }

    // MARK: - HTTP (+ SSL expiry · assertion)

    private func checkHTTP(_ site: Site) async -> SiteCheck {
        let urlString = SitesJobsLogic.sanitizeTarget(site.target, probe: .http)
        guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return SiteCheck(ok: false, detail: "bad-url")
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = Self.timeout
        req.httpMethod = "GET"
        req.setValue("RelayConsole/1.0", forHTTPHeaderField: "User-Agent")
        let start = Date()
        let box = TrustExpiryBox()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = Self.timeout
        let session = URLSession(configuration: config, delegate: box, delegateQueue: nil)
        do {
            let (data, response) = try await session.data(for: req)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            session.finishTasksAndInvalidate()
            let sslExp = box.expiry
            if let http = response as? HTTPURLResponse {
                guard (200...399).contains(http.statusCode) else {
                    return SiteCheck(
                        ok: false,
                        latencyMs: ms,
                        detail: SitesJobsLogic.summarize(error: nil, httpStatus: http.statusCode),
                        sslExpiresAt: sslExp
                    )
                }
                let body = String(data: data, encoding: .utf8) ?? ""
                if !SslAssertLogic.assertBody(body, expected: site.assertBody) {
                    return SiteCheck(
                        ok: false,
                        latencyMs: ms,
                        detail: "assert-fail",
                        sslExpiresAt: sslExp
                    )
                }
                return SiteCheck(ok: true, latencyMs: ms, detail: nil, sslExpiresAt: sslExp)
            }
            return SiteCheck(ok: false, detail: "bad-response", sslExpiresAt: sslExp)
        } catch {
            session.finishTasksAndInvalidate()
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

/// HTTPS trust 챌린지에서 인증서 만료일만 수집 (체크 실패로 연결 거부 안 함)
final class TrustExpiryBox: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _expiry: Date?

    var expiry: Date? {
        lock.lock()
        defer { lock.unlock() }
        return _expiry
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        if let date = Self.expiryDate(from: trust) {
            lock.lock()
            _expiry = date
            lock.unlock()
        }
        // reachability 유지 — 만료 수집만 · pinning/CA down 처리는 OUT
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    /// leaf cert notAfter 추출 — 실패 시 nil
    static func expiryDate(from trust: SecTrust) -> Date? {
        var error: CFError?
        guard SecTrustEvaluateWithError(trust, &error) else {
            // evaluate 실패여도 체인에서 시도
            return leafNotAfter(trust)
        }
        return leafNotAfter(trust)
    }

    private static func leafNotAfter(_ trust: SecTrust) -> Date? {
        var cert: SecCertificate?
        if #available(macOS 12.0, *) {
            if let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] {
                cert = chain.first
            }
        } else {
            cert = SecTrustGetCertificateAtIndex(trust, 0)
        }
        guard let cert else { return nil }
        // notAfter OID = 2.5.29.15 (kSecOIDX509CertificateValidityNotAfter)
        let keys = ["2.5.29.15"] as CFArray
        guard let dict = SecCertificateCopyValues(cert, keys, nil) as? [String: Any],
              let notAfterDict = dict["2.5.29.15"] as? [String: Any]
        else { return nil }
        let raw = notAfterDict[kSecPropertyKeyValue as String]
        if let date = raw as? Date { return date }
        if let str = raw as? String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "yyyyMMddHHmmss'Z'"
            return f.date(from: str)
        }
        return nil
    }
}
