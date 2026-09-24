import Foundation
@testable import RelayConsole
import Testing

struct SitesCalendarTests {
    @Test func parseTagsLowercasesTrimsDedupes() {
        #expect(SitesCalendarLogic.parseTags("api, prod, API") == ["api", "prod"])
        #expect(SitesCalendarLogic.parseTags("  a  b ,,c") == ["a", "b", "c"])
        #expect(SitesCalendarLogic.parseTags("") == [])
        #expect(SitesCalendarLogic.parseTags(", ,") == [])
    }

    @Test func formatTagsJoinsWithCommaSpace() {
        #expect(SitesCalendarLogic.formatTags(["api", "prod"]) == "api, prod")
        #expect(SitesCalendarLogic.formatTags([]) == "")
    }

    @Test func allTagsUnionSorted() {
        let a = Site(name: "a", target: "https://a.com", probe: .http, tags: ["prod", "api"])
        let b = Site(name: "b", target: "https://b.com", probe: .http, tags: ["staging", "api"])
        #expect(SitesCalendarLogic.allTags([a, b]) == ["api", "prod", "staging"])
    }

    @Test func filterEmptySelectedReturnsAll() {
        let sites = [Site(name: "a", target: "https://a.com", probe: .http, tags: ["api"])]
        #expect(SitesCalendarLogic.filter(sites, selectedTags: []) == sites)
    }

    @Test func filterAndSubset() {
        let both = Site(name: "both", target: "https://a.com", probe: .http, tags: ["api", "prod"])
        let one = Site(name: "one", target: "https://b.com", probe: .http, tags: ["api"])
        let none = Site(name: "none", target: "https://c.com", probe: .http, tags: ["staging"])
        let sites = [both, one, none]

        let onlyApi = SitesCalendarLogic.filter(sites, selectedTags: ["api"])
        #expect(onlyApi.map(\.name) == ["both", "one"])

        let anded = SitesCalendarLogic.filter(sites, selectedTags: ["api", "prod"])
        #expect(anded.map(\.name) == ["both"])

        let miss = SitesCalendarLogic.filter(sites, selectedTags: ["nope"])
        #expect(miss.isEmpty)
    }

    @Test func calendarDaysIs90AscendingEndsToday() {
        let cal = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let days = SitesCalendarLogic.calendarDays(days: 90, now: now, calendar: cal)
        #expect(days.count == 90)
        let startOfToday = cal.startOfDay(for: now)
        #expect(days.last == startOfToday)
        #expect(days.first! < days.last!)
        #expect(cal.date(byAdding: .day, value: 1, to: days[days.count - 2]) == startOfToday)
    }

    @Test func leadingPadInRange() {
        let pad = SitesCalendarLogic.leadingPad()
        #expect((0..<7).contains(pad))
    }

    @Test func weekdayHeadersSevenCount() {
        let headers = SitesCalendarLogic.weekdayHeaders(calendar: Calendar(identifier: .gregorian))
        #expect(headers.count == 7)
        #expect(!headers.isEmpty)
    }

    @Test func combinedStatusUnknownWhenNoChecks() {
        let site = Site(name: "a", target: "https://a.com", probe: .http)
        let cal = Calendar(identifier: .gregorian)
        let day = cal.startOfDay(for: .now)
        #expect(SitesCalendarLogic.combinedStatus(site: site, day: day, calendar: cal) == .unknown)
    }

    @Test func combinedStatusAggregatesDay() {
        let cal = Calendar(identifier: .gregorian)
        let day = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let noon = cal.date(byAdding: .hour, value: 12, to: day)!
        let pruneNow = noon.addingTimeInterval(3600)

        var up = Site(name: "u", target: "https://u.com", probe: .http)
        up.appendCheck(SiteCheck(at: noon, ok: true), now: pruneNow)
        #expect(SitesCalendarLogic.combinedStatus(site: up, day: day, calendar: cal) == .up)

        var mixed = Site(name: "m", target: "https://m.com", probe: .http)
        mixed.appendCheck(SiteCheck(at: noon, ok: true), now: pruneNow)
        mixed.appendCheck(SiteCheck(at: noon.addingTimeInterval(1), ok: false), now: pruneNow)
        #expect(SitesCalendarLogic.combinedStatus(site: mixed, day: day, calendar: cal) == .partial)

        var down = Site(name: "d", target: "https://d.com", probe: .http)
        down.appendCheck(SiteCheck(at: noon, ok: false), now: pruneNow)
        #expect(SitesCalendarLogic.combinedStatus(site: down, day: day, calendar: cal) == .down)
    }

    @Test func aggregatePriorityDownBeatsPartialBeatsUp() {
        #expect(SitesCalendarLogic.aggregate([]) == .unknown)
        #expect(SitesCalendarLogic.aggregate([.up, .up]) == .up)
        #expect(SitesCalendarLogic.aggregate([.up, .down]) == .down)
        #expect(SitesCalendarLogic.aggregate([.up, .partial]) == .partial)
        #expect(SitesCalendarLogic.aggregate([.unknown, .up]) == .partial)
        #expect(SitesCalendarLogic.aggregate([.unknown]) == .unknown)
    }

    @Test func siteTagsDecodeDefaultsEmpty() throws {
        let json = """
        {"id":"6E1E8E3A-1111-2222-3333-444455556666","name":"api","target":"https://example.com","probe":"http","intervalSec":60,"enabled":true,"failThreshold":2,"history":[],"createdAt":"2026-01-01T00:00:00Z"}
        """
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let site = try dec.decode(Site.self, from: Data(json.utf8))
        #expect(site.tags.isEmpty)
    }

    @Test func siteTagsEncodeRoundTrip() throws {
        let site = Site(name: "api", target: "https://example.com", probe: .http, tags: ["prod", "api"])
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let back = try dec.decode(Site.self, from: try enc.encode(site))
        #expect(back.tags == ["prod", "api"])
    }
}
