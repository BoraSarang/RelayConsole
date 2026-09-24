import Foundation

/// 외부 알림 채널 설정 — UserDefaults `relay.notify.*` (시크릿 하드코딩 금지)
struct NotifyConfig: Equatable, Sendable {
    var ntfyEnabled: Bool
    var ntfyServer: String
    var ntfyTopic: String
    var ntfyToken: String
    var slackEnabled: Bool
    var slackWebhook: String
    /// 외부 전송 최소 심각도
    var minSeverity: WatchSeverity
    /// clear(복구) 이벤트 포함 여부
    var sendRecovery: Bool

    static let `default` = NotifyConfig(
        ntfyEnabled: false,
        ntfyServer: "",
        ntfyTopic: "",
        ntfyToken: "",
        slackEnabled: false,
        slackWebhook: "",
        minSeverity: .warning,
        sendRecovery: false
    )

    var ntfyReady: Bool {
        ntfyEnabled && !ntfyServer.trimmed.isEmpty && !ntfyTopic.trimmed.isEmpty
    }

    var slackReady: Bool {
        slackEnabled && slackWebhook.trimmed.hasPrefix("https://")
    }

    var anyReady: Bool { ntfyReady || slackReady }
}

/// 외부 알림 요청 빌더 — 순수 (테스트 대상) · 실제 발송은 ConsoleStore/URLSession
enum NotifyChannel {
    static let errorPublishFailed = "E-MAC-NOTIFY-0001"

    // MARK: - 필터

    /// 심각도·복구 임계 — minSeverity 미만·복구 OFF 시 발송 생략
    static func shouldSend(_ event: WatchEvent, config: NotifyConfig) -> Bool {
        guard config.anyReady else { return false }
        if event.isClear {
            return config.sendRecovery
        }
        return event.severity >= config.minSeverity
    }

    // MARK: - ntfy

    /// ntfy 발행 URL — server 끝 슬래시 정리 + topic 인코딩
    static func ntfyURL(server: String, topic: String) -> URL? {
        var s = server.trimmed
        while s.hasSuffix("/") { s.removeLast() }
        let t = topic.trimmed
        guard !s.isEmpty, !t.isEmpty else { return nil }
        guard let encoded = t.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "\(s)/\(encoded)")
    }

    /// ntfy Priority 헤더 (1=min … 5=max)
    static func ntfyPriority(for severity: WatchSeverity, isClear: Bool) -> Int {
        if isClear { return 2 }
        switch severity {
        case .critical: return 4
        case .warning: return 3
        case .info: return 2
        }
    }

    /// 헤더 + body — Title은 UTF-8 percent 인코딩 (MIME 안전)
    static func ntfyRequest(event: WatchEvent, config: NotifyConfig) -> URLRequest? {
        guard let url = ntfyURL(server: config.ntfyServer, topic: config.ntfyTopic) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        if !config.ntfyToken.trimmed.isEmpty {
            req.setValue("Bearer \(config.ntfyToken.trimmed)", forHTTPHeaderField: "Authorization")
        }
        if let title = event.title.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
            req.setValue(title, forHTTPHeaderField: "Title")
        }
        req.setValue(String(ntfyPriority(for: event.severity, isClear: event.isClear)), forHTTPHeaderField: "Priority")
        req.setValue("relay_console,\(event.kind.rawValue)", forHTTPHeaderField: "Tags")
        let body = event.isClear ? "✅ \(event.title) — \(event.detail)" : event.summary
        req.httpBody = Data(body.utf8)
        return req
    }

    // MARK: - Slack

    /// Slack Incoming Webhook JSON body
    static func slackBody(event: WatchEvent) -> Data? {
        let tag = event.isClear ? "recovered" : event.severity.rawValue
        let serial = NotifyChannel.maskSerial(event.serial)
        let text = "[\(tag)] \(event.summary)\n\(event.kind.rawValue) · \(serial)"
        let payload: [String: String] = ["text": text]
        return try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    static func slackRequest(event: WatchEvent, config: NotifyConfig) -> URLRequest? {
        guard let url = URL(string: config.slackWebhook.trimmed) else { return nil }
        guard let body = slackBody(event: event) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        return req
    }

    // MARK: - 마스킹

    /// 시리얼 축약 — 뒤 4자리만 (로그·Slack 공통)
    static func maskSerial(_ serial: String) -> String {
        guard serial.count > 4 else { return serial }
        return "…\(serial.suffix(4))"
    }

    /// 토큰·웹훅 마스킹 — 앞 6 + … + 뒤 4
    static func maskSecret(_ secret: String) -> String {
        let s = secret.trimmed
        guard s.count > 12 else { return String(repeating: "•", count: max(s.count, 4)) }
        return "\(s.prefix(6))…\(s.suffix(4))"
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
