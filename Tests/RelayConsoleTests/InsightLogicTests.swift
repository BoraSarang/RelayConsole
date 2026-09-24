import Foundation
import Testing
@testable import RelayConsole

// MARK: - ConnectionSession

struct ConnectionSessionTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func dayKeyFormat() {
        let cal = Calendar(identifier: .gregorian)
        var c = DateComponents()
        c.year = 2026
        c.month = 9
        c.day = 24
        let d = cal.date(from: c)!
        #expect(ConnectionSession.dayKey(for: d, calendar: cal) == "20260924")
    }

    @Test func openAndCloseSession() {
        var sessions: [ConnectionSession] = []
        ConnectionSessionLogic.open(sessions: &sessions, serial: "S1", kind: .usb, at: t0)
        #expect(sessions.count == 1)
        #expect(sessions[0].isOngoing)
        let ok = ConnectionSessionLogic.close(sessions: &sessions, serial: "S1", at: t0.addingTimeInterval(600))
        #expect(ok)
        #expect(!sessions[0].isOngoing)
        #expect(abs(sessions[0].durationSeconds() - 600) < 0.001)
    }

    @Test func openClosesPreviousOngoing() {
        var sessions: [ConnectionSession] = []
        ConnectionSessionLogic.open(sessions: &sessions, serial: "S1", kind: .usb, at: t0)
        ConnectionSessionLogic.open(sessions: &sessions, serial: "S1", kind: .network, at: t0.addingTimeInterval(30))
        #expect(sessions.count == 2)
        #expect(sessions[0].disconnectedAt != nil)
        #expect(sessions[1].isOngoing)
    }

    @Test func dailySummaryCounts() {
        var sessions: [ConnectionSession] = []
        ConnectionSessionLogic.open(sessions: &sessions, serial: "S1", kind: .usb, at: t0)
        ConnectionSessionLogic.close(sessions: &sessions, serial: "S1", at: t0.addingTimeInterval(120))
        ConnectionSessionLogic.open(sessions: &sessions, serial: "S1", kind: .network, at: t0.addingTimeInterval(200))
        ConnectionSessionLogic.close(sessions: &sessions, serial: "S1", at: t0.addingTimeInterval(500))

        let day = ConnectionSession.dayKey(for: t0)
        let s = ConnectionSessionLogic.dailySummary(sessions, dayKey: day, serial: "S1", now: t0.addingTimeInterval(1000))
        #expect(s.count == 2)
        #expect(abs(s.totalMinutes - (120 + 300) / 60.0) < 0.01)
        #expect(abs(s.longestMinutes - 300 / 60.0) < 0.01)
        #expect(s.usbCount == 1)
        #expect(s.networkCount == 1)
    }

    @Test func pruneRemovesOlderThanRetention() {
        var sessions: [ConnectionSession] = []
        // 40일 전 세션
        let old = t0.addingTimeInterval(-40 * 86400)
        ConnectionSessionLogic.open(sessions: &sessions, serial: "S1", kind: .usb, at: old)
        ConnectionSessionLogic.close(sessions: &sessions, serial: "S1", at: old.addingTimeInterval(60))
        ConnectionSessionLogic.open(sessions: &sessions, serial: "S1", kind: .usb, at: t0)
        ConnectionSessionLogic.close(sessions: &sessions, serial: "S1", at: t0.addingTimeInterval(60))

        let removed = ConnectionSessionLogic.prune(&sessions, retentionDays: 30, now: t0)
        #expect(removed == 1)
        #expect(sessions.count == 1)

        // 무제한(0) — 제거 없음
        let removed2 = ConnectionSessionLogic.prune(&sessions, retentionDays: 0, now: t0)
        #expect(removed2 == 0)
    }
}

// MARK: - DeviceDaily

struct DeviceDailyStoreTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func mergeRunningAverage() {
        var d = DeviceDaily(serial: "S1", dayKey: "20260924")
        DeviceDailyLogic.merge(into: &d, sample: DeviceDailySample(cpu: 10, temp: 30, batteryLevel: 80, isCharging: false, at: t0))
        DeviceDailyLogic.merge(into: &d, sample: DeviceDailySample(cpu: 20, temp: 40, batteryLevel: 70, isCharging: true, at: t0.addingTimeInterval(60)))
        #expect(d.samples == 2)
        #expect(abs((d.cpuAvg ?? 0) - 15) < 0.01)
        #expect(d.cpuMax == 20)
        #expect(d.tempMax == 40)
        #expect(d.batteryMin == 70)
        #expect(d.batteryMax == 80)
        #expect(d.chargeMinutes == 1)
        #expect(d.onlineMinutes == 2)
    }

    @Test func mergeAccumulatesNetwork() {
        var d = DeviceDaily(serial: "S1", dayKey: "20260924")
        DeviceDailyLogic.merge(into: &d, sample: DeviceDailySample(netUpMB: 1, netDownMB: 2, at: t0))
        DeviceDailyLogic.merge(into: &d, sample: DeviceDailySample(netUpMB: 3, netDownMB: 4, at: t0))
        #expect(d.netUpMB == 4)
        #expect(d.netDownMB == 6)
    }

    @Test func countEventClassifies() {
        var d = DeviceDaily(serial: "S1", dayKey: "20260924")
        DeviceDailyLogic.countEvent(into: &d, kind: .crash, isClear: false)
        DeviceDailyLogic.countEvent(into: &d, kind: .anr, isClear: false)
        DeviceDailyLogic.countEvent(into: &d, kind: .throttling, isClear: false)
        DeviceDailyLogic.countEvent(into: &d, kind: .throttling, isClear: true) // clear 무시
        #expect(d.crashEvents == 1)
        #expect(d.anrEvents == 1)
        #expect(d.warnEvents == 1)
        #expect(d.criticalEvents == 2) // crash + anr
    }

    @Test func pruneDailyMap() {
        var map: [String: DeviceDaily] = [:]
        // t0(=2023-11-15) 기준 40일 전 / 오늘 dayKey
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cal = Calendar.current
        let oldDate = cal.date(byAdding: .day, value: -40, to: cal.startOfDay(for: now))!
        let oldKey = DeviceDailyLogic.dayKey(for: oldDate, calendar: cal)
        let todayKey = DeviceDailyLogic.dayKey(for: now, calendar: cal)
        map["S1|\(oldKey)"] = DeviceDaily(serial: "S1", dayKey: oldKey)
        map["S1|\(todayKey)"] = DeviceDaily(serial: "S1", dayKey: todayKey)
        let removed = DeviceDailyLogic.prune(&map, retentionDays: 30, now: now)
        #expect(removed == 1)
        #expect(map.count == 1)
        #expect(map["S1|\(todayKey)"] != nil)
    }
}

// MARK: - InsightLogic

struct InsightLogicTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private var dayKey: String { InsightLogic.dayKey(for: t0) }

    private func ev(
        kind: WatchKind,
        severity: WatchSeverity = .critical,
        serial: String = "S1",
        pkg: String? = nil,
        clear: Bool = false,
        at: Date
    ) -> WatchEvent {
        WatchEvent(
            kind: kind,
            severity: severity,
            serial: serial,
            title: "t",
            detail: "d",
            at: at,
            isClear: clear,
            packageName: pkg
        )
    }

    @Test func previousDayKey() {
        let cal = Calendar(identifier: .gregorian)
        #expect(InsightLogic.previousDayKey("20260924", calendar: cal) == "20260923")
        #expect(InsightLogic.previousDayKey("20260301", calendar: cal) == "20260228")
    }

    @Test func insightCountsFatalAndPackages() {
        let events = [
            ev(kind: .crash, pkg: "com.a", at: t0),
            ev(kind: .crash, pkg: "com.a", at: t0.addingTimeInterval(10)),
            ev(kind: .anr, pkg: "com.b", at: t0.addingTimeInterval(20)),
            ev(kind: .throttling, severity: .warning, at: t0.addingTimeInterval(30))
        ]
        let daily = DeviceDaily(serial: "S1", dayKey: dayKey, samples: 10)
        var d = daily
        d.batteryMin = 70
        d.batteryMax = 90
        d.tempMax = 42

        let insight = InsightLogic.insight(
            serial: "S1",
            dayKey: dayKey,
            events: events,
            daily: d,
            sessions: [],
            previousDaily: nil,
            previousEvents: []
        )
        #expect(insight.crashCount == 2)
        #expect(insight.anrCount == 1)
        #expect(insight.criticalCount == 3)
        #expect(insight.warningCount == 1)
        #expect(insight.packageNameCounts["com.a"] == 2)
        #expect(insight.batteryDrainPct == 20)
        #expect(insight.tempMax == 42)
        #expect(insight.packagesTop.first?.package == "com.a")
    }

    @Test func insightVsPreviousDeltas() {
        let prevDay = InsightLogic.previousDayKey(dayKey)!
        // dayKey 오프셋 계산용 — t0 기준 전일
        let todayEvents = [ev(kind: .crash, at: t0)]
        // 전일 이벤트는 전일 dayKey에 들어야 함
        let prevDate = Calendar.current.date(byAdding: .day, value: -1, to: t0)!
        let prevEvents = [
            ev(kind: .crash, at: prevDate),
            ev(kind: .crash, at: prevDate)
        ]
        let insight = InsightLogic.insight(
            serial: "S1",
            dayKey: dayKey,
            events: todayEvents + prevEvents,
            daily: DeviceDaily(serial: "S1", dayKey: dayKey),
            sessions: [],
            previousDaily: nil,
            previousEvents: prevEvents
        )
        #expect(insight.vsPrevEventDelta == 1 - 2)
        #expect(insight.vsPrevCrashDelta == 1 - 2)
        _ = prevDay
    }

    @Test func dayStatusCriticalWins() {
        let events = [
            ev(kind: .throttling, severity: .warning, at: t0),
            ev(kind: .crash, severity: .critical, at: t0.addingTimeInterval(1))
        ]
        let status = InsightLogic.dayStatus(
            serial: nil,
            dayKey: dayKey,
            events: events,
            daily: nil
        )
        #expect(status == .critical)
    }

    @Test func dayStatusNoneWithoutData() {
        let status = InsightLogic.dayStatus(
            serial: "S1",
            dayKey: dayKey,
            events: [],
            daily: nil
        )
        #expect(status == .none)
    }
}

// MARK: - PatternLogic

struct PatternLogicTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func crash(at: Date, clear: Bool = false, pkg: String = "com.x") -> WatchEvent {
        WatchEvent(
            kind: .crash,
            severity: clear ? .info : .critical,
            serial: "S1",
            title: "c",
            detail: "d",
            at: at,
            isClear: clear,
            packageName: pkg,
            exceptionClass: "java.lang.RuntimeException",
            errorFingerprint: "S1:crash:\(pkg):java.lang.RuntimeException"
        )
    }

    @Test func repeatingWhenThreeInSevenDays() {
        var events: [WatchEvent] = []
        for i in 0..<3 {
            // 0, 1, 2일 전
            let d = Calendar.current.date(byAdding: .day, value: -i, to: t0)!
            events.append(crash(at: d))
        }
        let pats = PatternLogic.patterns(from: events, thresholds: .default, now: t0)
        #expect(pats.count == 1)
        #expect(pats[0].status == .repeating)
        #expect(pats[0].occurrenceCount == 3)
        #expect(pats[0].packageName == "com.x")
    }

    @Test func notRepeatingBelowThreshold() {
        var events: [WatchEvent] = []
        for i in 0..<2 {
            let d = Calendar.current.date(byAdding: .day, value: -i, to: t0)!
            events.append(crash(at: d))
        }
        let pats = PatternLogic.patterns(from: events, thresholds: .default, now: t0)
        #expect(pats[0].status != .repeating)
    }

    @Test func resolvedAfterQuietDays() {
        // 5일 전 마지막 crash + clear, 그 후 무재발
        let base = Calendar.current.date(byAdding: .day, value: -5, to: t0)!
        let events = [
            crash(at: base),
            crash(at: base.addingTimeInterval(60), clear: true)
        ]
        let pats = PatternLogic.patterns(from: events, thresholds: .default, now: t0)
        #expect(pats[0].status == .resolved)
        #expect(pats[0].hasClear)
        #expect(pats[0].avgTimeToResolveSec == 60)
        #expect(pats[0].daysSinceLastClear == 5)
    }

    @Test func thresholdOverrideLowersBar() {
        // 기본 3회 미달이지만 임계 2로 낮추면 repeating
        var events: [WatchEvent] = []
        for i in 0..<2 {
            let d = Calendar.current.date(byAdding: .day, value: -i, to: t0)!
            events.append(crash(at: d))
        }
        var t = PatternThresholds.default
        t.repeatingCount = 2
        let pats = PatternLogic.patterns(from: events, thresholds: t, now: t0)
        #expect(pats[0].status == .repeating)
    }

    @Test func patternFingerprintGroupsSameError() {
        let a = crash(at: t0)
        let b = crash(at: t0.addingTimeInterval(3600))
        #expect(PatternLogic.fingerprint(of: a) == PatternLogic.fingerprint(of: b))
        let pats = PatternLogic.patterns(from: [a, b], now: t0.addingTimeInterval(7200))
        #expect(pats.count == 1)
        #expect(pats[0].occurrenceCount == 2)
    }

    @Test func clearEventsDoNotCountAsOccurrences() {
        let enter = crash(at: t0)
        let clear = crash(at: t0.addingTimeInterval(10), clear: true)
        let pats = PatternLogic.patterns(from: [enter, clear], now: t0.addingTimeInterval(20))
        #expect(pats[0].occurrenceCount == 1)
        #expect(pats[0].hasClear)
    }

    @Test func dayOverDayReport() {
        let events = [
            crash(at: t0),
            crash(at: t0.addingTimeInterval(1))
        ]
        let report = ReportLogic.dayOverDay(
            events: events,
            dailies: [],
            sessions: [],
            dayKey: InsightLogic.dayKey(for: t0),
            now: t0
        )
        #expect(report.eventCount == 2)
        #expect(report.crashCount == 2)
        #expect(report.eventDelta != nil) // prev 없으면 nil
    }

    // MARK: Phase4 반복/해소 리포트 export

    @Test func exportCSVIncludesAllColumns() {
        var events: [WatchEvent] = []
        for i in 0..<3 {
            let d = Calendar.current.date(byAdding: .day, value: -i, to: t0)!
            events.append(crash(at: d))
        }
        events.append(crash(at: t0.addingTimeInterval(60), clear: true))
        let pats = PatternLogic.patterns(from: events, thresholds: .default, now: t0)
        let csv = PatternLogic.exportCSV(pats)
        let header = csv.components(separatedBy: "\n")[0]
        #expect(header.contains("fingerprint"))
        #expect(header.contains("status"))
        #expect(header.contains("package"))
        #expect(header.contains("avgMttrSec"))
        #expect(header.contains("recentCount"))
        #expect(csv.contains("com.x"))
        #expect(csv.contains("java.lang.RuntimeException"))
        #expect(csv.contains("repeating") || csv.contains("active"))
    }

    @Test func exportRowsEscapesCommasInFields() {
        let p = IssuePattern(
            fingerprint: "fp,with,comma",
            serial: "S1",
            kind: .crash,
            packageName: "com.a,b",
            exceptionClass: nil,
            occurrenceCount: 1,
            firstAt: t0,
            lastAt: t0,
            daySpread: 1,
            status: .once,
            hasClear: false,
            avgTimeToResolveSec: nil,
            daysSinceLastClear: nil,
            recentCount: 1
        )
        let rows = PatternLogic.exportRows([p])
        #expect(rows[0].0.contains("\""))
        #expect(rows[0].1.contains("\"com.a,b\""))
    }

    @Test func insightReportExportRoundTrip() throws {
        var events: [WatchEvent] = []
        for i in 0..<3 {
            let d = Calendar.current.date(byAdding: .day, value: -i, to: t0)!
            events.append(crash(at: d))
        }
        let pats = PatternLogic.patterns(from: events, thresholds: .default, now: t0)
        let insight = InsightLogic.insight(
            serial: "S1",
            dayKey: InsightLogic.dayKey(for: t0),
            events: events,
            daily: nil,
            sessions: [],
            previousDaily: nil,
            previousEvents: []
        )
        let report = ReportLogic.dayOverDay(
            events: events,
            dailies: [],
            sessions: [],
            dayKey: InsightLogic.dayKey(for: t0),
            now: t0
        )
        let built = InsightReportLogic.build(
            dayKey: InsightLogic.dayKey(for: t0),
            serial: "S1",
            insight: insight,
            report: report,
            patterns: pats,
            thresholds: .default,
            generatedAt: t0
        )
        #expect(built.schema == InsightReportLogic.schemaVersion)
        #expect(built.repeatingCount == 1)
        #expect(built.patterns.count == 1)
        #expect(built.thresholds.repeatingCount == 3)

        let data = try #require(InsightReportLogic.exportJSON(built))
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let back = try dec.decode(InsightReportExport.self, from: data)
        #expect(back.dayKey == built.dayKey)
        #expect(back.patterns.count == 1)
        #expect(back.patterns[0].packageName == "com.x")
        #expect(back.repeatingCount == 1)
        #expect(back.dayMetrics["crash"] == 0 || back.dayMetrics["critical"] != nil)
    }
}

// MARK: - WatchEvent structured fields

struct WatchEventStructuredTests {
    @Test func structuredFieldsCodableRoundTrip() throws {
        let e = WatchEvent(
            kind: .crash,
            severity: .critical,
            serial: "S1",
            title: "t",
            detail: "d",
            packageName: "com.x",
            exceptionClass: "java.lang.RuntimeException",
            errorFingerprint: "S1:crash:com.x:java.lang.RuntimeException",
            appVersion: "1.2.3"
        )
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(e)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let back = try dec.decode(WatchEvent.self, from: data)
        #expect(back.packageName == "com.x")
        #expect(back.exceptionClass == "java.lang.RuntimeException")
        #expect(back.errorFingerprint == "S1:crash:com.x:java.lang.RuntimeException")
        #expect(back.appVersion == "1.2.3")
        #expect(back.patternFingerprint == "S1:crash:com.x:java.lang.RuntimeException")
    }

    @Test func legacyJSONWithoutNewFieldsDecodes() throws {
        // 기존 JSON — 신규 키 없음
        let json = """
        {"id":"6F1E0A00-0000-0000-0000-000000000001","kind":"crash","severity":"critical",
         "serial":"S1","title":"t","detail":"d","at":1700000000,"isClear":false}
        """
        struct Legacy: Decodable {
            // WatchEvent 직접 디코드
        }
        _ = Legacy.self
        let dec = JSONDecoder()
        // ISO8601 또는 Double 모두 가능 — Foundation 기본 DeferredDate 아님
        dec.dateDecodingStrategy = .iso8601
        // 숫자 timestamp는 iso8601 실패 → secondsSince1970 시도용
        if let _ = try? dec.decode(WatchEvent.self, from: Data(json.utf8)) {
            // OK
        } else {
            dec.dateDecodingStrategy = .secondsSince1970
            let e = try dec.decode(WatchEvent.self, from: Data(json.utf8))
            #expect(e.packageName == nil)
            #expect(e.errorFingerprint == nil)
            #expect(e.patternFingerprint == "S1:crash")
        }
    }

    @Test func makeErrorFingerprintRequiresPackage() {
        #expect(
            WatchEvent.makeErrorFingerprint(
                serial: "S1",
                kind: .crash,
                packageName: "com.x",
                exceptionClass: "E"
            ) == "S1:crash:com.x:E"
        )
        #expect(
            WatchEvent.makeErrorFingerprint(
                serial: "S1",
                kind: .crash,
                packageName: nil,
                exceptionClass: "E"
            ) == nil
        )
    }

    @Test func androidConnectKindsExist() {
        #expect(WatchKind.allCases.contains(.androidConnected))
        #expect(WatchKind.allCases.contains(.androidDisconnected))
    }

    @Test func csvIncludesPackageColumns() {
        let e = WatchEvent(
            kind: .crash,
            severity: .critical,
            serial: "S1",
            title: "t",
            detail: "d",
            packageName: "com.x",
            exceptionClass: "java.lang.Exception"
        )
        let csv = WatchEventAlerts.exportCSV([e])
        #expect(csv.contains("package,exception"))
        #expect(csv.contains("com.x"))
        #expect(csv.contains("java.lang.Exception"))
    }
}

// MARK: - AdbClient ANR / version / foreground parsers

struct AdbEnhancedParserTests {
    @Test func extractAnrContextFromAmAnr() {
        let text = """
        09-24 10:00:00.000 E/ActivityManager: ANR in com.example.app (com.example.app)
        09-24 10:00:01.000 E/am_anr: [0,1234,com.example.app,552039,Input dispatching timed out]
        """
        let ctx = AdbClient.extractAnrContext(text)
        #expect(ctx != nil)
        #expect(ctx?.packageName == "com.example.app")
        #expect(ctx?.exceptionClass == "ANR")
    }

    @Test func extractAnrContextNilWhenNoAnr() {
        #expect(AdbClient.extractAnrContext("hello world") == nil)
    }

    @Test func parsePackageVersion() {
        let text = """
        Packages:
          versionCode=123 minSdk=26 targetSdk=34
          versionName=1.2.3
        """
        let v = AdbClient.parsePackageVersion(text)
        #expect(v.versionName == "1.2.3")
        #expect(v.versionCode == "123")
    }

    @Test func parseForegroundPackage() {
        let text = """
        ResumedActivity:
          ActivityRecord{abc u0 com.borasarang.droidrelay/.MainActivity t12}
        """
        #expect(AdbClient.parseForegroundPackage(text) == "com.borasarang.droidrelay")
    }

    @Test func parseDropboxRecentTags() {
        let text = """
        2026-09-24 19:46:03 com.borasarang.droidrelay@123.crash (age=12s)
        2026-09-24 18:00:00 system_app_anr (age=2h)
        unrelated line
        """
        let tags = AdbClient.parseDropboxRecentTags(text)
        #expect(tags.count == 2)
        #expect(tags[0].contains(".crash"))
    }

    @MainActor
    @Test func feedAnrPassesPackageName() {
        WatchEngine.shared.resetAll()
        defer { WatchEngine.shared.resetAll() }
        let ev = WatchEngine.shared.feedAnr(
            serial: "S1",
            detail: "ANR",
            packageName: "com.x",
            exceptionClass: "ANR",
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        #expect(ev?.packageName == "com.x")
        #expect(ev?.errorFingerprint?.contains("com.x") == true)
    }

    @MainActor
    @Test func feedCrashPassesException() {
        WatchEngine.shared.resetAll()
        defer { WatchEngine.shared.resetAll() }
        let ev = WatchEngine.shared.feedCrash(
            serial: "S1",
            detail: "FATAL",
            packageName: "com.x",
            exceptionClass: "java.lang.RuntimeException",
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        #expect(ev?.exceptionClass == "java.lang.RuntimeException")
        #expect(ev?.errorFingerprint == "S1:crash:com.x:java.lang.RuntimeException")
    }
}

// MARK: - InsightSettings / PatternThresholds

struct InsightSettingsTests {
    @Test func retentionDefaultsTo30WhenUnset() {
        let suite = UserDefaults(suiteName: "test.retention.\(UUID().uuidString)")!
        defer { suite.removePersistentDomain(forName: suite.dictionaryRepresentation().keys.first ?? "") }
        // 미설정 → 기본 30
        let v = InsightSettings.retentionDays(suite)
        #expect(v == 30)
        suite.set(90, forKey: InsightSettings.retentionKey)
        #expect(InsightSettings.retentionDays(suite) == 90)
        suite.set(0, forKey: InsightSettings.retentionKey)
        #expect(InsightSettings.retentionDays(suite) == 0) // 무제한 명시
    }

    @Test func patternThresholdsDefaultAndNormalize() {
        let suite = UserDefaults(suiteName: "test.pattern.\(UUID().uuidString)")!
        let t = PatternThresholds.fromDefaults(suite)
        #expect(t.repeatingDays == 7)
        #expect(t.repeatingCount == 3)
        #expect(t.resolvedQuietDays == 3)
        #expect(t.dormantQuietDays == 7)

        var custom = PatternThresholds.default
        custom.repeatingCount = 5
        custom.resolvedQuietDays = 1
        custom.save(to: suite)
        let t2 = PatternThresholds.fromDefaults(suite)
        #expect(t2.repeatingCount == 5)
        #expect(t2.resolvedQuietDays == 1)
        #expect(t2.repeatingDays == 7)
    }

    @Test func retentionDaysCaseLabels() {
        #expect(RetentionDays.d30.rawValue == 30)
        #expect(RetentionDays.unlimited.rawValue == 0)
        #expect(RetentionDays.defaultDays == 30)
        #expect(RetentionDays.allCases.count == 4)
    }
}
