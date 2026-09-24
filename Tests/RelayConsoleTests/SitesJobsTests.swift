import XCTest
@testable import RelayConsole

final class SitesJobsTests: XCTestCase {
    // MARK: - Site

    func testSiteAppendCheckCapByCount() {
        var site = Site(name: "api", target: "https://example.com", probe: .http)
        for i in 0..<305 {
            site.appendCheck(SiteCheck(at: Date().addingTimeInterval(Double(i)), ok: i % 2 == 0), now: .distantFuture)
        }
        XCTAssertLessThanOrEqual(site.history.count, 300)
    }

    func testSiteAppendCheckPrunesOlderThan90Days() {
        var site = Site(name: "api", target: "https://example.com", probe: .http)
        let now = Date()
        site.appendCheck(SiteCheck(at: now.addingTimeInterval(-100 * 86400), ok: true), now: now)
        site.appendCheck(SiteCheck(at: now, ok: true), now: now)
        XCTAssertEqual(site.history.count, 1)
        XCTAssertTrue(site.history[0].ok)
    }

    func testSiteIsUpNilWhenEmpty() {
        let site = Site(name: "api", target: "https://example.com", probe: .http)
        XCTAssertNil(site.isUp())
    }

    func testSiteIsUpUsesLastCheck() {
        var site = Site(name: "api", target: "https://example.com", probe: .http)
        site.appendCheck(SiteCheck(ok: true), now: .now)
        XCTAssertEqual(site.isUp(), true)
        site.appendCheck(SiteCheck(ok: false, detail: "HTTP 500"), now: .now)
        XCTAssertEqual(site.isUp(), false)
    }

    func testSiteRecentBarsOrderNewestFirst() {
        var site = Site(name: "api", target: "https://example.com", probe: .http)
        site.appendCheck(SiteCheck(ok: true), now: .now)
        site.appendCheck(SiteCheck(ok: false), now: .now)
        site.appendCheck(SiteCheck(ok: true), now: .now)
        XCTAssertEqual(site.recentBars(), [true, false, true])
    }

    func testSanitizeTargetStripsQueryAndUserinfo() {
        let raw = "https://user:pass@example.com/path?token=secret#frag"
        let clean = SitesJobsLogic.sanitizeTarget(raw, probe: .http)
        XCTAssertFalse(clean.contains("secret"))
        XCTAssertFalse(clean.contains("user"))
        XCTAssertFalse(clean.contains("pass"))
        XCTAssertTrue(clean.contains("example.com/path"))
    }

    func testSiteTransitionDownAndUp() {
        XCTAssertNil(SitesJobsLogic.siteTransition(before: nil, after: false))
        XCTAssertEqual(SitesJobsLogic.siteTransition(before: true, after: false), .down)
        XCTAssertEqual(SitesJobsLogic.siteTransition(before: false, after: true), .up)
        XCTAssertNil(SitesJobsLogic.siteTransition(before: true, after: true))
        XCTAssertNil(SitesJobsLogic.siteTransition(before: false, after: false))
    }

    // MARK: - Job

    func testJobOverdueNilBeforeGrace() {
        let now = Date()
        let job = Job(name: "backup", expectEverySec: 3600, createdAt: now.addingTimeInterval(-60))
        XCTAssertNil(job.isOverdue(now: now))
    }

    func testJobOverdueAfterGraceWithoutBeat() {
        let now = Date()
        let job = Job(name: "backup", expectEverySec: 3600, createdAt: now.addingTimeInterval(-4000))
        XCTAssertEqual(job.isOverdue(now: now), true)
    }

    func testJobOverdueFalseWithinExpect() {
        var job = Job(name: "backup", expectEverySec: 3600, createdAt: .now.addingTimeInterval(-7200))
        job.beat(at: .now.addingTimeInterval(-60))
        XCTAssertEqual(job.isOverdue(now: .now), false)
    }

    func testJobOverdueTrueBeyondHalfGrace() {
        var job = Job(name: "backup", expectEverySec: 3600, createdAt: .now.addingTimeInterval(-7200))
        job.beat(at: .now.addingTimeInterval(-5500)) // 3600 * 1.5 = 5400
        XCTAssertEqual(job.isOverdue(now: .now), true)
    }

    func testJobOverdueNilInGraceWindowBetweenExpectAndHalf() {
        var job = Job(name: "backup", expectEverySec: 3600, createdAt: .now.addingTimeInterval(-7200))
        job.beat(at: .now.addingTimeInterval(-4000)) // 4000 < 5400, 4000 > 3600
        XCTAssertNil(job.isOverdue(now: .now))
    }

    func testJobDisabledNeverOverdue() {
        var job = Job(name: "backup", expectEverySec: 30, createdAt: .now.addingTimeInterval(-9999))
        job.enabled = false
        XCTAssertEqual(job.isOverdue(now: .now), false)
    }

    func testJobTransition() {
        XCTAssertNil(SitesJobsLogic.jobTransition(before: nil, after: nil))
        XCTAssertEqual(SitesJobsLogic.jobTransition(before: nil, after: true), .overdue)
        XCTAssertNil(SitesJobsLogic.jobTransition(before: nil, after: false))
        XCTAssertEqual(SitesJobsLogic.jobTransition(before: false, after: true), .overdue)
        XCTAssertEqual(SitesJobsLogic.jobTransition(before: true, after: false), .recovered)
        XCTAssertNil(SitesJobsLogic.jobTransition(before: true, after: true))
    }

    func testJobTokenFromPath() {
        XCTAssertEqual(SitesJobsLogic.token(fromPath: "/hb/ab12cd34"), "ab12cd34")
        XCTAssertEqual(SitesJobsLogic.token(fromPath: "/api/hb/xyz"), "xyz")
        XCTAssertNil(SitesJobsLogic.token(fromPath: "/health"))
        XCTAssertNil(SitesJobsLogic.token(fromPath: "/hb/"))
    }

    func testJobBeatSetsFields() {
        var job = Job(name: "backup")
        let at = Date()
        job.beat(at: at, ok: true)
        XCTAssertEqual(job.lastBeatAt, at)
        XCTAssertEqual(job.lastBeatOk, true)
    }

    // MARK: - 검증 · curl

    func testValidateTargetHTTP() {
        XCTAssertNil(SitesJobsLogic.validateTarget("https://example.com", probe: .http))
        XCTAssertNil(SitesJobsLogic.validateTarget("http://127.0.0.1:8080/health", probe: .http))
        XCTAssertEqual(SitesJobsLogic.validateTarget("", probe: .http), "sites.error.target.empty")
        XCTAssertEqual(SitesJobsLogic.validateTarget("example.com", probe: .http), "sites.error.target.http")
        XCTAssertEqual(SitesJobsLogic.validateTarget("ftp://example.com", probe: .http), "sites.error.target.http")
        XCTAssertEqual(SitesJobsLogic.validateTarget("https://", probe: .http), "sites.error.target.http")
    }

    func testValidateTargetTCP() {
        XCTAssertNil(SitesJobsLogic.validateTarget("example.com", probe: .tcp))
        XCTAssertNil(SitesJobsLogic.validateTarget("example.com:443", probe: .tcp))
        XCTAssertNil(SitesJobsLogic.validateTarget("[::1]:9", probe: .tcp))
        XCTAssertEqual(SitesJobsLogic.validateTarget("example.com:abc", probe: .tcp), "sites.error.target.tcp")
        XCTAssertEqual(SitesJobsLogic.validateTarget("example.com:0", probe: .tcp), "sites.error.target.tcp")
        XCTAssertEqual(SitesJobsLogic.validateTarget("bad host:80", probe: .tcp), "sites.error.target.tcp")
    }

    func testValidateTargetPing() {
        XCTAssertNil(SitesJobsLogic.validateTarget("example.com", probe: .ping))
        XCTAssertEqual(SitesJobsLogic.validateTarget("", probe: .ping), "sites.error.target.empty")
        XCTAssertEqual(SitesJobsLogic.validateTarget("a b", probe: .ping), "sites.error.target.ping")
        XCTAssertEqual(SitesJobsLogic.validateTarget("-c 1", probe: .ping), "sites.error.target.ping")
    }

    func testTokenFromCurl() {
        let curl = #"curl -fsS "http://127.0.0.1:8787/hb/ab12cd34" || true"#//
        XCTAssertEqual(SitesJobsLogic.token(fromCurl: curl), "ab12cd34")
        XCTAssertEqual(SitesJobsLogic.token(fromCurl: "GET /hb/xyz789 HTTP/1.1"), "xyz789")
        XCTAssertNil(SitesJobsLogic.token(fromCurl: "curl https://example.com"))
        XCTAssertNil(SitesJobsLogic.token(fromCurl: ""))
    }

    func testStrictHostPort() {
        XCTAssertEqual(SitesJobsLogic.strictHostPort("a:1")?.0, "a")
        XCTAssertEqual(SitesJobsLogic.strictHostPort("a:1")?.1, 1)
        XCTAssertNil(SitesJobsLogic.strictHostPort("a"))
        XCTAssertNil(SitesJobsLogic.strictHostPort("a:port"))
        XCTAssertNil(SitesJobsLogic.strictHostPort(":80"))
    }

    // MARK: - parse

    func testParseHostPort() {
        XCTAssertEqual(SiteChecker.parseHostPort("example.com:8080", defaultPort: 443)?.0, "example.com")
        XCTAssertEqual(SiteChecker.parseHostPort("example.com:8080", defaultPort: 443)?.1, 8080)
        XCTAssertEqual(SiteChecker.parseHostPort("example.com", defaultPort: 443)?.1, 443)
        XCTAssertEqual(SiteChecker.parseHostPort("[::1]:9", defaultPort: 443)?.0, "::1")
        XCTAssertEqual(SiteChecker.parseHostPort("[::1]:9", defaultPort: 443)?.1, 9)
    }

    // MARK: - Codable 하위호환

    func testSiteJSONRoundTrip() throws {
        var site = Site(name: "api", target: "https://example.com", probe: .http)
        site.appendCheck(SiteCheck(ok: true, latencyMs: 42), now: .now)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode([site])
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let back = try dec.decode([Site].self, from: data)
        XCTAssertEqual(back.count, 1)
        XCTAssertEqual(back[0].name, "api")
        XCTAssertEqual(back[0].history.last?.latencyMs, 42)
    }

    func testJobJSONRoundTrip() throws {
        let job = Job(name: "backup", expectEverySec: 900)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode([job])
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let back = try dec.decode([Job].self, from: data)
        XCTAssertEqual(back[0].token, job.token)
        XCTAssertEqual(back[0].expectEverySec, 900)
    }

    func testLegacyWatchKindSiteJobCodable() throws {
        let e = WatchEvent(kind: .siteDown, severity: .critical, serial: "site:X", title: "API", detail: "down")
        let data = try JSONEncoder().encode(e)
        let back = try JSONDecoder().decode(WatchEvent.self, from: data)
        XCTAssertEqual(back.kind, .siteDown)
    }
}
