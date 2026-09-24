import Foundation
import Testing
@testable import RelayConsole

@MainActor
struct NotifyChannelTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func e(
        kind: WatchKind = .throttling,
        sev: WatchSeverity = .critical,
        serial: String = "R5CR10ABCDE",
        title: String = "Throttling",
        detail: String = "Status 3",
        isClear: Bool = false
    ) -> WatchEvent {
        WatchEvent(
            kind: kind,
            severity: sev,
            serial: serial,
            title: title,
            detail: detail,
            at: t0,
            isClear: isClear
        )
    }

    private func readyNtfy(
        min: WatchSeverity = .warning,
        recovery: Bool = false
    ) -> NotifyConfig {
        NotifyConfig(
            ntfyEnabled: true,
            ntfyServer: "https://ntfy.sh/",
            ntfyTopic: "relay-test",
            ntfyToken: "",
            slackEnabled: false,
            slackWebhook: "",
            minSeverity: min,
            sendRecovery: recovery
        )
    }

    // MARK: - 필터

    @Test func shouldSendFalseWhenNoChannelReady() {
        let config = NotifyConfig.default
        #expect(!NotifyChannel.shouldSend(e(sev: .critical), config: config))
    }

    @Test func shouldSendCriticalWhenMinWarning() {
        #expect(NotifyChannel.shouldSend(e(sev: .critical), config: readyNtfy()))
    }

    @Test func shouldSkipInfoWhenMinWarning() {
        #expect(!NotifyChannel.shouldSend(e(sev: .info), config: readyNtfy()))
    }

    @Test func shouldSkipWarningWhenMinCritical() {
        #expect(!NotifyChannel.shouldSend(e(sev: .warning), config: readyNtfy(min: .critical)))
    }

    @Test func shouldSendCriticalWhenMinCritical() {
        #expect(NotifyChannel.shouldSend(e(sev: .critical), config: readyNtfy(min: .critical)))
    }

    @Test func recoverySkippedUnlessEnabled() {
        let clear = e(sev: .info, isClear: true)
        #expect(!NotifyChannel.shouldSend(clear, config: readyNtfy()))
        #expect(NotifyChannel.shouldSend(clear, config: readyNtfy(recovery: true)))
    }

    // MARK: - ntfy URL

    @Test func ntfyURLStripsTrailingSlash() {
        let url = NotifyChannel.ntfyURL(server: "https://ntfy.sh///", topic: "abc")
        #expect(url?.absoluteString == "https://ntfy.sh/abc")
    }

    @Test func ntfyURLEncodesTopicPathUnsafe() {
        let url = NotifyChannel.ntfyURL(server: "https://ntfy.example", topic: "a b/c")
        #expect(url != nil)
        #expect(url?.absoluteString.contains("a%20b") == true || url?.absoluteString.contains("a%20b/c") == true)
    }

    @Test func ntfyURLNilWhenEmptyTopic() {
        #expect(NotifyChannel.ntfyURL(server: "https://ntfy.sh", topic: "  ") == nil)
        #expect(NotifyChannel.ntfyURL(server: "", topic: "t") == nil)
    }

    // MARK: - ntfy 요청

    @Test func ntfyPriorityMapping() {
        #expect(NotifyChannel.ntfyPriority(for: .critical, isClear: false) == 4)
        #expect(NotifyChannel.ntfyPriority(for: .warning, isClear: false) == 3)
        #expect(NotifyChannel.ntfyPriority(for: .info, isClear: false) == 2)
        #expect(NotifyChannel.ntfyPriority(for: .critical, isClear: true) == 2)
    }

    @Test func ntfyRequestHasMethodAndPriorityHeader() throws {
        let req = try #require(NotifyChannel.ntfyRequest(event: e(), config: readyNtfy()))
        #expect(req.httpMethod == "POST")
        #expect(req.value(forHTTPHeaderField: "Priority") == "4")
        #expect(req.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("text/plain") == true)
        #expect(req.url?.absoluteString == "https://ntfy.sh/relay-test")
        let body = try #require(req.httpBody)
        #expect(String(data: body, encoding: .utf8)?.contains("Throttling") == true)
    }

    @Test func ntfyRequestAddsBearerWhenTokenPresent() throws {
        var config = readyNtfy()
        config.ntfyToken = "tk_secret_value"
        let req = try #require(NotifyChannel.ntfyRequest(event: e(), config: config))
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer tk_secret_value")
    }

    // MARK: - Slack

    @Test func slackBodyMasksSerialAndTagsSeverity() throws {
        let data = try #require(NotifyChannel.slackBody(event: e(sev: .critical)))
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: String])
        let text = try #require(obj["text"])
        #expect(text.contains("critical"))
        #expect(text.contains("…BCDE"))
        #expect(!text.contains("R5CR10ABCDE"))
    }

    @Test func slackRequestPostsJSONToWebhook() throws {
        let config = NotifyConfig(
            ntfyEnabled: false,
            ntfyServer: "",
            ntfyTopic: "",
            ntfyToken: "",
            slackEnabled: true,
            slackWebhook: "https://hooks.slack.com/services/T000/B000/XXXX",
            minSeverity: .warning,
            sendRecovery: false
        )
        let req = try #require(NotifyChannel.slackRequest(event: e(), config: config))
        #expect(req.httpMethod == "POST")
        #expect(req.url?.host == "hooks.slack.com")
        #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    // MARK: - 마스킹

    @Test func maskSerialKeepsLastFour() {
        #expect(NotifyChannel.maskSerial("R5CR10ABCDE") == "…BCDE")
        #expect(NotifyChannel.maskSerial("AB") == "AB")
    }

    @Test func maskSecretHidesMiddle() {
        let masked = NotifyChannel.maskSecret("https://hooks.slack.com/services/AAAABBBBCCCC")
        #expect(masked.contains("…"))
        #expect(!masked.contains("AAAABBBBCCCC"))
        #expect(NotifyChannel.maskSecret("short") == "•••••")
    }

    // MARK: - ConsoleStore 필터 위임

    @Test func storeShouldSendExternalDelegates() {
        let config = readyNtfy(min: .critical)
        #expect(ConsoleStore.shouldSendExternal(e(sev: .warning), config: config) == false)
        #expect(ConsoleStore.shouldSendExternal(e(sev: .critical), config: config) == true)
    }
}
