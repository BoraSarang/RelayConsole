import Foundation

// MARK: - 일자별 인사이트 (DeviceDaily + WatchEvent + ConnectionSession → UI)

struct PackageCount: Equatable, Sendable, Hashable {
    let package: String
    let count: Int
}

struct DeviceInsight: Equatable, Sendable, Identifiable {
    var id: String { "\(serial)|\(dayKey)" }
    let serial: String
    let dayKey: String
    let eventsByKind: [WatchKind: Int]
    let criticalCount: Int
    let warningCount: Int
    let crashCount: Int
    let anrCount: Int
    /// 패키지별 발생 횟수 (crash/ANR 등 fatal only)
    let packageNameCounts: [String: Int]
    let batteryMin: Int?
    let batteryMax: Int?
    let batteryDrainPct: Int?
    let tempMax: Double?
    let cpuAvg: Double?
    let onlineMinutes: Double?
    let chargeMinutes: Double?
    let sessionCount: Int
    let sessionTotalMinutes: Double
    let sessionLongestMinutes: Double
    /// 전일 대비 delta (nil = 전일 데이터 없음)
    let vsPrevEventDelta: Int?
    let vsPrevCrashDelta: Int?
    let vsPrevTempMaxDelta: Double?
    let vsPrevBatteryDrainDelta: Int?
    let packagesTop: [PackageCount]
}

enum InsightLogic {
    /// dayKey YYYYMMDD — Calendar 기준
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        DeviceDailyLogic.dayKey(for: date, calendar: calendar)
    }

    /// 이전 날짜 dayKey
    static func previousDayKey(_ dayKey: String, calendar: Calendar = .current) -> String? {
        let y = Int(dayKey.prefix(4))
        let m = Int(dayKey.dropFirst(4).prefix(2))
        let d = Int(dayKey.suffix(2))
        guard let y, let m, let d,
              let comps = calendar.date(from: DateComponents(year: y, month: m, day: d)),
              let prev = calendar.date(byAdding: .day, value: -1, to: comps) else {
            return nil
        }
        return Self.dayKey(for: prev, calendar: calendar)
    }

    /// 핵심 빌드 — events + sessions + daily
    static func insight(
        serial: String,
        dayKey key: String,
        events: [WatchEvent],
        daily: DeviceDaily?,
        sessions: [ConnectionSession],
        previousDaily: DeviceDaily?,
        previousEvents: [WatchEvent],
        now: Date = .now
    ) -> DeviceInsight {
        let dayEvents = events.filter {
            $0.serial == serial && !$0.isClear && dayKey(for: $0.at) == key
        }
        var byKind: [WatchKind: Int] = [:]
        var pkgCounts: [String: Int] = [:]
        var criticalCount = 0
        var warningCount = 0
        var crashCount = 0
        var anrCount = 0
        for e in dayEvents {
            byKind[e.kind, default: 0] += 1
            if e.severity == .critical { criticalCount += 1 }
            else if e.severity == .warning { warningCount += 1 }
            if e.kind == .crash {
                crashCount += 1
                if let p = e.packageName { pkgCounts[p, default: 0] += 1 }
            }
            if e.kind == .anr {
                anrCount += 1
                if let p = e.packageName { pkgCounts[p, default: 0] += 1 }
            }
        }

        let prevKey = previousDayKey(key)
        let prevDayEvents = previousEvents.filter {
            $0.serial == serial && !$0.isClear
                && prevKey != nil
                && dayKey(for: $0.at) == prevKey!
        }

        let drain: Int?
        if let minL = daily?.batteryMin, let maxL = daily?.batteryMax {
            drain = max(0, maxL - minL)
        } else {
            drain = nil
        }
        var prevDrain: Int?
        if let a = previousDaily?.batteryMin, let b = previousDaily?.batteryMax {
            prevDrain = max(0, b - a)
        }

        let summary = ConnectionSessionLogic.dailySummary(
            sessions,
            dayKey: key,
            serial: serial,
            now: now
        )

        let top = pkgCounts
            .sorted { $0.value > $1.value }
            .prefix(8)
            .map { PackageCount(package: $0.key, count: $0.value) }

        return DeviceInsight(
            serial: serial,
            dayKey: key,
            eventsByKind: byKind,
            criticalCount: criticalCount,
            warningCount: warningCount,
            crashCount: crashCount,
            anrCount: anrCount,
            packageNameCounts: pkgCounts,
            batteryMin: daily?.batteryMin,
            batteryMax: daily?.batteryMax,
            batteryDrainPct: drain,
            tempMax: daily?.tempMax,
            cpuAvg: daily?.cpuAvg,
            onlineMinutes: daily?.onlineMinutes,
            chargeMinutes: daily?.chargeMinutes,
            sessionCount: summary.count,
            sessionTotalMinutes: summary.totalMinutes,
            sessionLongestMinutes: summary.longestMinutes,
            vsPrevEventDelta: previousEvents.isEmpty && previousDaily == nil
                ? nil
                : dayEvents.count - prevDayEvents.count,
            vsPrevCrashDelta: previousEvents.isEmpty && previousDaily == nil
                ? nil
                : crashCount - prevDayEvents.filter { $0.kind == .crash }.count,
            vsPrevTempMaxDelta: mapDelta(previousDaily?.tempMax, daily?.tempMax),
            vsPrevBatteryDrainDelta: mapDelta(
                prevDrain.map(Double.init),
                drain.map(Double.init)
            ).map(Int.init),
            packagesTop: top
        )
    }

    private static func mapDelta(_ a: Double?, _ b: Double?) -> Double? {
        guard let a, let b else { return nil }
        return b - a
    }

    /// 캘린더 색 상태 — critical > warning > data > none
    static func dayStatus(
        serial: String?,
        dayKey key: String,
        events: [WatchEvent],
        daily: DeviceDaily?
    ) -> InsightsDayStatus {
        let dayEvents = events.filter {
            !$0.isClear
                && dayKey(for: $0.at) == key
                && (serial == nil || $0.serial == serial)
        }
        if dayEvents.contains(where: { $0.severity == .critical }) { return .critical }
        if dayEvents.contains(where: { $0.severity == .warning }) { return .warning }
        if daily != nil || !dayEvents.isEmpty { return .ok }
        return .none
    }
}

enum InsightsDayStatus: String, Sendable {
    case critical, warning, ok, none
}

// MARK: - 반복 패턴 / 해소 리포트

enum IssuePatternStatus: String, Sendable, Codable, CaseIterable {
    case active
    case repeating
    case resolved
    case dormant
    case once
}

struct IssuePattern: Equatable, Sendable, Identifiable, Codable {
    var id: String { fingerprint }
    let fingerprint: String
    let serial: String
    let kind: WatchKind
    let packageName: String?
    let exceptionClass: String?
    let occurrenceCount: Int
    let firstAt: Date
    let lastAt: Date
    /// 서로 다른 날짜 수
    let daySpread: Int
    let status: IssuePatternStatus
    /// clear가 있었는지 (isClear 이벤트)
    let hasClear: Bool
    /// enter→clear 평균 (MTTR 초) — clear 없으면 nil
    let avgTimeToResolveSec: Double?
    /// 마지막 clear 이후 경과일 (nil = clear 없음)
    let daysSinceLastClear: Int?
    /// 최근 N일 내 발생 수 (repeating 판정용)
    let recentCount: Int
}

enum PatternLogic {
    /// 패턴 키 — errorFingerprint 우선, 없으면 serial:kind
    static func fingerprint(of e: WatchEvent) -> String {
        e.patternFingerprint
    }

    /// 반복/해소 판정 — thresholds는 설정 주입 (테스트기/안정기)
    static func patterns(
        from events: [WatchEvent],
        thresholds: PatternThresholds = .default,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [IssuePattern] {
        // fingerprint → 이벤트 목록 (시간순)
        var buckets: [String: [WatchEvent]] = [:]
        for e in events where isPatternKind(e.kind) {
            buckets[fingerprint(of: e), default: []].append(e)
        }

        let repeatingCutoff = calendar.date(
            byAdding: .day,
            value: -thresholds.repeatingDays,
            to: now
        ) ?? Date.distantPast

        var out: [IssuePattern] = []
        for (fp, list) in buckets {
            let sorted = list.sorted { $0.at < $1.at }
            guard let head = sorted.first, let tail = sorted.last else { continue }
            let enters = sorted.filter { !$0.isClear }
            let clears = sorted.filter { $0.isClear }
            guard !enters.isEmpty else { continue }

            let dayKeys = Set(enters.map { InsightLogic.dayKey(for: $0.at, calendar: calendar) })
            let recentCount = enters.filter { $0.at >= repeatingCutoff }.count

            // MTTR — 같은 fingerprint enter→가장 가까운 clear
            var mttrTotal: Double = 0
            var mttrN = 0
            for enter in enters {
                if let clear = clears.first(where: { $0.at >= enter.at }) {
                    mttrTotal += clear.at.timeIntervalSince(enter.at)
                    mttrN += 1
                }
            }
            let mttr = mttrN > 0 ? mttrTotal / Double(mttrN) : nil

            let lastClear = clears.last?.at
            var daysSinceClear: Int?
            if let lastClear {
                daysSinceClear = calendar.dateComponents(
                    [.day],
                    from: calendar.startOfDay(for: lastClear),
                    to: calendar.startOfDay(for: now)
                ).day ?? 0
            }

            let status = resolveStatus(
                recentCount: recentCount,
                daySpread: dayKeys.count,
                hasClear: !clears.isEmpty,
                daysSinceClear: daysSinceClear,
                lastEnterAt: enters.last?.at ?? tail.at,
                thresholds: thresholds,
                now: now,
                calendar: calendar
            )

            out.append(
                IssuePattern(
                    fingerprint: fp,
                    serial: head.serial,
                    kind: head.kind,
                    packageName: head.packageName ?? enters.compactMap(\.packageName).last,
                    exceptionClass: head.exceptionClass ?? enters.compactMap(\.exceptionClass).last,
                    occurrenceCount: enters.count,
                    firstAt: head.at,
                    lastAt: tail.at,
                    daySpread: dayKeys.count,
                    status: status,
                    hasClear: !clears.isEmpty,
                    avgTimeToResolveSec: mttr,
                    daysSinceLastClear: daysSinceClear,
                    recentCount: recentCount
                )
            )
        }
        // 최근 발생 우선 정렬
        return out.sorted { $0.lastAt > $1.lastAt }
    }

    static func resolveStatus(
        recentCount: Int,
        daySpread: Int,
        hasClear: Bool,
        daysSinceClear: Int?,
        lastEnterAt: Date,
        thresholds: PatternThresholds,
        now: Date,
        calendar: Calendar
    ) -> IssuePatternStatus {
        let daysSinceLastEnter = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: lastEnterAt),
            to: calendar.startOfDay(for: now)
        ).day ?? 0

        // 반복: 최근 window 내 N회 이상 — 재발 중이면 repeating
        if recentCount >= thresholds.repeatingCount {
            return .repeating
        }
        // 해소: clear 있고 이후 quietDays 무재발
        if hasClear, let d = daysSinceClear, d >= thresholds.resolvedQuietDays,
           daysSinceLastEnter >= thresholds.resolvedQuietDays {
            return .resolved
        }
        // dormant: 과거 반복(daySpread≥2 또는 횟수≥2)했으나 quietDays 침묵
        if (daySpread >= 2 || recentCount >= 2),
           daysSinceLastEnter >= thresholds.dormantQuietDays {
            return .dormant
        }
        // 활성: clear 없고 최근 enter
        if !hasClear, daysSinceLastEnter < thresholds.dormantQuietDays {
            return .active
        }
        if hasClear && daysSinceLastEnter < thresholds.resolvedQuietDays {
            return .active
        }
        return .once
    }

    /// 패턴 리포트 대상 kind — 상태 전이·fatal·사이트 등
    static func isPatternKind(_ kind: WatchKind) -> Bool {
        switch kind {
        case .crash, .anr, .throttling, .psiPressure, .loadSpike,
             .memoryLow, .signalDrop, .bsohDrop, .batteryThreshold,
             .siteDown, .jobOverdue, .sslExpiring,
             .androidConnected, .androidDisconnected,
             .appleConnected, .appleDisconnected:
            return true
        default:
            return false
        }
    }

    /// 패턴 → CSV 행 (전체 컬럼 — 반복/해소 리포트 Phase4)
    static func csvHeader() -> String {
        "fingerprint,serial,kind,status,package,exception,occurrences,daySpread,recentCount,hasClear,avgMttrSec,daysSinceClear,firstAt,lastAt"
    }

    static func exportRows(_ patterns: [IssuePattern]) -> [(String, String)] {
        patterns.map { p in
            let mttr = p.avgTimeToResolveSec.map { String(format: "%.1f", $0) } ?? ""
            let days = p.daysSinceLastClear.map(String.init) ?? ""
            let rest = [
                csvEscape(p.serial),
                p.kind.rawValue,
                p.status.rawValue,
                csvEscape(p.packageName ?? ""),
                csvEscape(p.exceptionClass ?? ""),
                "\(p.occurrenceCount)",
                "\(p.daySpread)",
                "\(p.recentCount)",
                p.hasClear ? "1" : "0",
                mttr,
                days,
                p.firstAt.ISO8601Format(),
                p.lastAt.ISO8601Format()
            ].joined(separator: ",")
            return (csvEscape(p.fingerprint), rest)
        }
    }

    static func exportCSV(_ patterns: [IssuePattern]) -> String {
        var lines = [csvHeader()]
        for (fp, rest) in exportRows(patterns) {
            lines.append("\(fp),\(rest)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func csvEscape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return s
    }
}

// MARK: - 반복/해소 리포트 export (Phase4)

/// 반복/해소 리포트 — JSON 한 파일에 일자·임계값·패턴 전체
struct InsightReportExport: Codable, Equatable, Sendable {
    let schema: String
    let dayKey: String
    let serial: String?
    let generatedAt: Date
    let repeatingCount: Int
    let resolvedCount: Int
    let thresholds: PatternThresholds
    let dayMetrics: [String: Double]
    let patterns: [IssuePattern]
}

enum InsightReportLogic {
    static let schemaVersion = "insight-report/1"

    /// 반복/해소 리포트 빌드 — UI export 버튼 공용
    static func build(
        dayKey: String,
        serial: String?,
        insight: DeviceInsight,
        report: DayOverDayReport,
        patterns: [IssuePattern],
        thresholds: PatternThresholds,
        generatedAt: Date = .now
    ) -> InsightReportExport {
        var metrics: [String: Double] = [
            "critical": Double(insight.criticalCount),
            "warning": Double(insight.warningCount),
            "crash": Double(insight.crashCount),
            "anr": Double(insight.anrCount),
            "sessionMinutes": insight.sessionTotalMinutes,
            "reportRepeating": Double(report.repeatingCount),
            "reportResolved": Double(report.resolvedCount),
            "eventCount": Double(report.eventCount),
            "prevEventCount": report.prevEventCount.map(Double.init) ?? -1
        ]
        if let t = insight.tempMax { metrics["tempMax"] = t }
        if let b = insight.batteryDrainPct { metrics["batteryDrain"] = Double(b) }
        return InsightReportExport(
            schema: schemaVersion,
            dayKey: dayKey,
            serial: serial,
            generatedAt: generatedAt,
            repeatingCount: patterns.filter { $0.status == .repeating }.count,
            resolvedCount: patterns.filter { $0.status == .resolved }.count,
            thresholds: thresholds,
            dayMetrics: metrics,
            patterns: patterns
        )
    }

    static func exportJSON(_ report: InsightReportExport) -> Data? {
        ReportLogic.exportJSON(report)
    }
}

// MARK: - 전일 대비 / 일일 리포트 한 줄

struct DayOverDayReport: Equatable, Sendable {
    let dayKey: String
    let prevDayKey: String?
    let eventCount: Int
    let prevEventCount: Int?
    let crashCount: Int
    let prevCrashCount: Int?
    let criticalCount: Int
    let prevCriticalCount: Int?
    let tempMax: Double?
    let prevTempMax: Double?
    let batteryDrain: Int?
    let prevBatteryDrain: Int?
    let sessionMinutes: Double
    let prevSessionMinutes: Double?
    let repeatingCount: Int
    let resolvedCount: Int

    var eventDelta: Int? {
        guard let prev = prevEventCount else { return nil }
        return eventCount - prev
    }

    var crashDelta: Int? {
        guard let prev = prevCrashCount else { return nil }
        return crashCount - prev
    }
}

enum ReportLogic {
    static func dayOverDay(
        events: [WatchEvent],
        dailies: [DeviceDaily],
        sessions: [ConnectionSession],
        dayKey: String,
        serial: String? = nil,
        thresholds: PatternThresholds = .default,
        now: Date = .now
    ) -> DayOverDayReport {
        let prevKey = InsightLogic.previousDayKey(dayKey)

        func filterDay(_ key: String?) -> [WatchEvent] {
            guard let key else { return [] }
            return events.filter {
                !$0.isClear
                    && InsightLogic.dayKey(for: $0.at) == key
                    && (serial == nil || $0.serial == serial)
            }
        }
        let today = filterDay(dayKey)
        let prev = filterDay(prevKey)

        func daily(_ key: String?) -> DeviceDaily? {
            guard let key else { return nil }
            return dailies.first {
                $0.dayKey == key && (serial == nil || $0.serial == serial)
            }
        }
        let t = daily(dayKey)
        let p = daily(prevKey)

        func drain(_ d: DeviceDaily?) -> Int? {
            guard let minL = d?.batteryMin, let maxL = d?.batteryMax else { return nil }
            return max(0, maxL - minL)
        }

        let sess = ConnectionSessionLogic.dailySummary(
            sessions, dayKey: dayKey, serial: serial, now: now
        )
        let prevSessMinutes: Double? = prevKey.map {
            ConnectionSessionLogic.dailySummary(
                sessions, dayKey: $0, serial: serial, now: now
            ).totalMinutes
        }

        let pats = PatternLogic.patterns(from: events, thresholds: thresholds, now: now)
        return DayOverDayReport(
            dayKey: dayKey,
            prevDayKey: prevKey,
            eventCount: today.count,
            prevEventCount: prevKey == nil ? nil : prev.count,
            crashCount: today.filter { $0.kind == .crash }.count,
            prevCrashCount: prevKey == nil ? nil : prev.filter { $0.kind == .crash }.count,
            criticalCount: today.filter { $0.severity == .critical }.count,
            prevCriticalCount: prevKey == nil ? nil : prev.filter { $0.severity == .critical }.count,
            tempMax: t?.tempMax,
            prevTempMax: p?.tempMax,
            batteryDrain: drain(t),
            prevBatteryDrain: drain(p),
            sessionMinutes: sess.totalMinutes,
            prevSessionMinutes: prevSessMinutes,
            repeatingCount: pats.filter { $0.status == .repeating }.count,
            resolvedCount: pats.filter { $0.status == .resolved }.count
        )
    }

    /// JSON export — 패턴/인사이트 공용
    static func exportJSON<T: Encodable>(_ value: T) -> Data? {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? enc.encode(value)
    }
}
