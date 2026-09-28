import Foundation
import Network

/// 로컬 하트비트 서버 — 127.0.0.1 고정 (외부 노출 금지)
/// GET/POST /hb/{token} → Job.beat · GET /metrics → Prometheus 지표 (TIER A)
final class HeartbeatServer: @unchecked Sendable {
    static let shared = HeartbeatServer()

    /// `/metrics` 경로 — 하트비트 토큰 경로와 **겹치지 않는다** (`/hb/` 접두사와 다른 계층)
    static let metricsPath = "/metrics"
    /// Prometheus exposition format 0.0.4 규격의 미디어 타입
    static let metricsContentType = "text/plain; version=0.0.4; charset=utf-8"

    private let queue = DispatchQueue(label: "relay.hb", qos: .utility)
    private var listener: NWListener?
    private var portRaw: UInt16 = 8787
    private var onBeat: (@Sendable (String) -> Void)?
    private var onBindError: (@Sendable (String, String) -> Void)?
    private var onReady: (@Sendable () -> Void)?
    /// 지표 본문 — **store 를 모른다.** 주입만 받는다 (Jobs 계층이 App 계층을 알면 계층이 뒤집힌다)
    private var onMetrics: (@Sendable () async -> String)?
    private(set) var isRunning = false

    var port: UInt16 { portRaw }

    /// 시작 — 실패 시 onBindError(코드·원인), 성공 시 onReady 콜백 (E-MAC-JOB-0001)
    func start(
        port: UInt16 = 8787,
        onBeat: @escaping @Sendable (String) -> Void,
        onBindError: @escaping @Sendable (String, String) -> Void,
        onReady: @escaping @Sendable () -> Void = {},
        onMetrics: (@Sendable () async -> String)? = nil
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopLocked()
            self.onBeat = onBeat
            self.onBindError = onBindError
            self.onReady = onReady
            self.onMetrics = onMetrics
            self.portRaw = port

            let params = NWParameters.tcp
            params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port) ?? .any)
            // 외부 인터페이스 바인드 방지 — loopback only
            params.allowLocalEndpointReuse = true

            do {
                let l = try NWListener(using: params)
                l.stateUpdateHandler = { [weak self] state in
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        DebugLogger.shared.info("HB", "[INFO] [FEATURE] 하트비트 서버 listening 127.0.0.1:\(port)")
                        self?.onReady?()
                    case .failed(let err):
                        self?.isRunning = false
                        DebugLogger.shared.error("HB", "[ERROR] E-MAC-JOB-0001 하트비트 바인드 실패: \(err)")
                        self?.onBindError?("E-MAC-JOB-0001", String(describing: err))
                    case .cancelled:
                        self?.isRunning = false
                    default:
                        break
                    }
                }
                l.newConnectionHandler = { [weak self] conn in
                    self?.handle(conn)
                }
                l.start(queue: self.queue)
                self.listener = l
            } catch {
                self.isRunning = false
                DebugLogger.shared.error("HB", "[ERROR] E-MAC-JOB-0001 하트비트 서버 생성 실패: \(error)")
                onBindError("E-MAC-JOB-0001", error.localizedDescription)
            }
        }
    }

    func stop() {
        queue.async { [weak self] in self?.stopLocked() }
    }

    private func stopLocked() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    // MARK: - connection

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        receiveRequest(conn, buffer: Data())
    }

    private func receiveRequest(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }
            if let range = buf.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(data: buf[buf.startIndex..<range.lowerBound], encoding: .utf8) ?? ""
                Task { [weak self] in
                    await self?.respond(conn, head: head)
                }
                return
            }
            if isComplete || error != nil {
                conn.cancel()
                return
            }
            self.receiveRequest(conn, buffer: buf)
        }
    }

    private func respond(_ conn: NWConnection, head: String) async {
        let lines = head.split(separator: "\r\n")
        guard let first = lines.first else {
            send(conn, status: "400 Bad Request", body: "bad request")
            return
        }
        let parts = first.split(separator: " ")
        guard parts.count >= 2 else {
            send(conn, status: "400 Bad Request", body: "bad request")
            return
        }
        let method = String(parts[0])
        let path = String(parts[1])
        // `/metrics` — 하트비트 토큰과 **무관한** 경로라 토큰 검사보다 먼저 처리한다
        if path == Self.metricsPath {
            guard method == "GET" else {
                await DebugLogger.shared.error("HB", "[ERROR] E-MAC-JOB-0003 /metrics 는 GET 만 받는다: \(method)")
                send(conn, status: "405 Method Not Allowed", body: "E-MAC-JOB-0003")
                return
            }
            await DebugLogger.shared.info("HB", "[INFO] [FEATURE] /metrics 응답")
            let body = await onMetrics?() ?? ""
            send(conn, status: "200 OK", body: body,
                 contentType: Self.metricsContentType)
            return
        }
        guard let token = SitesJobsLogic.token(fromPath: path) else {
            send(conn, status: "404 Not Found", body: "E-MAC-JOB-0002")
            return
        }
        onBeat?(token)
        send(conn, status: "200 OK", body: "ok")
    }

    private func send(_ conn: NWConnection, status: String, body: String,
                      contentType: String = "text/plain") {
        let payload = Data(body.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
        var data = Data(head.utf8)
        data.append(payload)
        conn.send(content: data, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }
}
