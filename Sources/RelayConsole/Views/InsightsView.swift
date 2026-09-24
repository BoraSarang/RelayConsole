import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Insights — 일자 캘린더 · 반복/해소 패턴 · 전일 대비 · 연결 세션 (PLAN 인사이트 리모델링 Phase3)
struct InsightsView: View {
    @ObservedObject var store: ConsoleStore

    @State private var selectedDay: Date = Calendar.current.startOfDay(for: .now)
    @State private var serialFilter: String? = nil
    @State private var exportMessage: String?

    private var calendar: Calendar { .current }
    private var todayKey: String { InsightLogic.dayKey(for: .now, calendar: calendar) }
    private var selectedKey: String {
        InsightLogic.dayKey(for: selectedDay, calendar: calendar)
    }

    private var serials: [String] {
        var set = Set(store.inventory.devices.map(\.serial))
        set.formUnion(store.recentWatchEvents.map(\.serial))
        set.formUnion(DeviceDailyStore.shared.map.values.map(\.serial))
        return set.sorted()
    }

    private var insight: DeviceInsight {
        let prevKey = InsightLogic.previousDayKey(selectedKey, calendar: calendar)
        let prevDaily = prevKey.flatMap { key in
            serialFilter.flatMap { DeviceDailyStore.shared.day(serial: $0, dayKey: key) }
                ?? DeviceDailyStore.shared.map.values.first { $0.dayKey == key && $0.serial == (serialFilter ?? $0.serial) }
        }
        let daily = serialFilter.flatMap {
            DeviceDailyStore.shared.day(serial: $0, dayKey: selectedKey)
        } ?? DeviceDailyStore.shared.map.values.first {
            $0.dayKey == selectedKey && (serialFilter == nil || $0.serial == serialFilter)
        }
        let sessions = ConnectionSessionStore.shared.sessions
        let events = store.recentWatchEvents
        let prevEvents: [WatchEvent] = prevKey.map { key in
            events.filter { InsightLogic.dayKey(for: $0.at, calendar: calendar) == key }
        } ?? []
        let targetSerial = serialFilter ?? store.selectedSerial ?? "ALL"
        return InsightLogic.insight(
            serial: targetSerial,
            dayKey: selectedKey,
            events: events,
            daily: daily,
            sessions: sessions,
            previousDaily: prevDaily,
            previousEvents: prevEvents
        )
    }

    private var patterns: [IssuePattern] {
        PatternLogic.patterns(
            from: store.recentWatchEvents,
            thresholds: store.patternThresholds()
        )
    }

    private var report: DayOverDayReport {
        ReportLogic.dayOverDay(
            events: store.recentWatchEvents,
            dailies: Array(DeviceDailyStore.shared.map.values),
            sessions: ConnectionSessionStore.shared.sessions,
            dayKey: selectedKey,
            serial: serialFilter,
            thresholds: store.patternThresholds()
        )
    }

    var body: some View {
        ZStack {
            OPColor.popBG.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: OPSpace.lg) {
                    header
                    serialPicker
                    calendarCard
                    daySummaryCard
                    reportCard
                    patternsCard
                }
                .padding(OPSpace.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(OPColor.popBG)
        .preferredColorScheme(ThemeManager.shared.mode.preferred)
        .navigationTitle(L10n.string("sidebar.insights"))
        .alert(
            L10n.string("alerts.export.done"),
            isPresented: Binding(
                get: { exportMessage != nil },
                set: { if !$0 { exportMessage = nil } }
            )
        ) {
            Button(L10n.string("alerts.ok"), role: .cancel) {}
        } message: {
            Text(exportMessage ?? "")
        }
    }

    // MARK: - 헤더

    private var header: some View {
        HStack {
            Text(L10n.string("sidebar.insights"))
                .font(OPFont.title(16))
                .foregroundStyle(OPColor.ink)
            Spacer()
            Button(L10n.string("insights.export.json")) { exportJSON() }
                .buttonStyle(.plain)
                .font(OPFont.body(12))
                .foregroundStyle(OPColor.cta)
            Button(L10n.string("insights.export.patterns")) { exportPatterns() }
                .buttonStyle(.plain)
                .font(OPFont.body(12))
                .foregroundStyle(OPColor.cta)
        }
    }

    private var serialPicker: some View {
        HStack(spacing: 8) {
            Menu {
                Button(L10n.string("insights.serial.all")) { serialFilter = nil }
                Divider()
                ForEach(serials, id: \.self) { s in
                    Button("\(AdbClient.shortId(s)) — \(s)") { serialFilter = s }
                }
            } label: {
                chip(
                    L10n.string("insights.serial"),
                    value: serialFilter.map { AdbClient.shortId($0) }
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()
        }
    }

    // MARK: - 캘린더

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: OPSpace.md) {
            HStack {
                Text(L10n.string("insights.calendar.title"))
                    .font(OPFont.body(13))
                    .foregroundStyle(OPColor.ink)
                Spacer()
                Button(L10n.string("insights.calendar.today")) {
                    selectedDay = calendar.startOfDay(for: .now)
                }
                .buttonStyle(.plain)
                .font(OPFont.body(11))
                .foregroundStyle(OPColor.cta)
            }
            monthGrid
        }
        .padding(OPSpace.lg)
        .background(OPColor.card, in: RoundedRectangle(cornerRadius: OPSpace.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: OPSpace.radiusCard).stroke(OPColor.border, lineWidth: 1))
    }

    private var monthGrid: some View {
        let comps = calendar.dateComponents([.year, .month], from: selectedDay)
        let first = calendar.date(from: comps) ?? selectedDay
        let range = calendar.range(of: .day, in: .month, for: first) ?? 1..<32
        let firstWeekday = calendar.component(.weekday, from: first)
        let leading = firstWeekday - calendar.firstWeekday
        let pad = (leading + 7) % 7
        let days: [Date?] = Array(repeating: nil, count: pad)
            + range.map { calendar.date(byAdding: .day, value: $0 - 1, to: first) }

        return VStack(alignment: .leading, spacing: 6) {
            Text(monthLabel(first))
                .font(OPFont.number(11))
                .foregroundStyle(OPColor.inkDim)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(Array(calendar.shortWeekdaySymbols.enumerated()), id: \.offset) { _, name in
                    Text(name)
                        .font(OPFont.number(9))
                        .foregroundStyle(OPColor.inkDim.opacity(0.7))
                        .frame(maxWidth: .infinity)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayCell(date)
                    } else {
                        Color.clear.frame(height: 28)
                    }
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let key = InsightLogic.dayKey(for: date, calendar: calendar)
        let status = InsightLogic.dayStatus(
            serial: serialFilter,
            dayKey: key,
            events: store.recentWatchEvents,
            daily: serialFilter.flatMap { DeviceDailyStore.shared.day(serial: $0, dayKey: key) }
                ?? DeviceDailyStore.shared.map.values.first { $0.dayKey == key }
        )
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDay)
        let isToday = calendar.isDate(date, inSameDayAs: .now)
        let tint: Color
        switch status {
        case .critical: tint = OPColor.bad
        case .warning: tint = OPColor.warn
        case .ok: tint = OPColor.ok
        case .none: tint = OPColor.inkDim.opacity(0.35)
        }
        return Button {
            selectedDay = calendar.startOfDay(for: date)
        } label: {
            Text("\(calendar.component(.day, from: date))")
                .font(OPFont.number(11))
                .foregroundStyle(isSelected ? .white : OPColor.ink)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(
                    Circle()
                        .fill(isSelected ? OPColor.cta : tint.opacity(isToday ? 0.25 : 0.12))
                        .frame(width: 26, height: 26)
                )
                .overlay(Circle().stroke(isToday && !isSelected ? OPColor.cta : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func monthLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy년 M월"
        f.locale = Locale.current
        return f.string(from: date)
    }

    // MARK: - 일자 요약

    private var daySummaryCard: some View {
        VStack(alignment: .leading, spacing: OPSpace.md) {
            HStack {
                Text(L10n.string("insights.day.title"))
                    .font(OPFont.body(13))
                    .foregroundStyle(OPColor.ink)
                Spacer()
                Text(selectedKey)
                    .font(OPFont.number(11))
                    .foregroundStyle(OPColor.inkDim)
            }
            if insight.criticalCount == 0 && insight.warningCount == 0
                && insight.sessionCount == 0 && insight.tempMax == nil {
                Text(L10n.string("insights.day.empty"))
                    .font(OPFont.body(12))
                    .foregroundStyle(OPColor.inkDim)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    metric(L10n.string("insights.metric.critical"), "\(insight.criticalCount)", OPColor.bad)
                    metric(L10n.string("insights.metric.warning"), "\(insight.warningCount)", OPColor.warn)
                    metric(L10n.string("insights.metric.crash"), "\(insight.crashCount)", OPColor.bad)
                    metric(L10n.string("insights.metric.anr"), "\(insight.anrCount)", OPColor.bad)
                    metric(
                        L10n.string("insights.metric.temp"),
                        insight.tempMax.map { String(format: "%.1f°", $0) } ?? L10n.na,
                        OPColor.thermal
                    )
                    metric(
                        L10n.string("insights.metric.battery"),
                        insight.batteryDrainPct.map { "\($0)%" } ?? L10n.na,
                        OPColor.cta
                    )
                    metric(
                        L10n.string("insights.metric.sessions"),
                        "\(insight.sessionCount)",
                        OPColor.droid
                    )
                    metric(
                        L10n.string("insights.metric.online"),
                        insight.onlineMinutes.map { String(format: "%.0fm", $0) } ?? L10n.na,
                        OPColor.ok
                    )
                }
                if !insight.packagesTop.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.string("insights.packages.title"))
                            .font(OPFont.body(11))
                            .foregroundStyle(OPColor.inkDim)
                        ForEach(insight.packagesTop, id: \.package) { p in
                            HStack {
                                Text(p.package)
                                    .font(OPFont.number(11))
                                    .foregroundStyle(OPColor.ink)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text("\(p.count)")
                                    .font(OPFont.number(11))
                                    .foregroundStyle(OPColor.bad)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(OPSpace.lg)
        .background(OPColor.card, in: RoundedRectangle(cornerRadius: OPSpace.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: OPSpace.radiusCard).stroke(OPColor.border, lineWidth: 1))
    }

    // MARK: - 전일 대비

    private var reportCard: some View {
        VStack(alignment: .leading, spacing: OPSpace.md) {
            Text(L10n.string("insights.report.title"))
                .font(OPFont.body(13))
                .foregroundStyle(OPColor.ink)
            if report.prevDayKey == nil {
                Text(L10n.string("insights.report.noPrev"))
                    .font(OPFont.body(12))
                    .foregroundStyle(OPColor.inkDim)
            } else {
                row(L10n.string("insights.metric.critical"), report.criticalCount, report.prevCriticalCount)
                row(L10n.string("insights.metric.crash"), report.crashCount, report.prevCrashCount)
                row(L10n.string("insights.metric.events"), report.eventCount, report.prevEventCount)
                HStack {
                    Text(L10n.string("insights.pattern.repeating"))
                        .font(OPFont.body(12))
                        .foregroundStyle(OPColor.inkDim)
                    Spacer()
                    Text("\(report.repeatingCount)")
                        .font(OPFont.number(12))
                        .foregroundStyle(report.repeatingCount > 0 ? OPColor.bad : OPColor.ok)
                    Text(L10n.string("insights.pattern.resolved"))
                        .font(OPFont.body(12))
                        .foregroundStyle(OPColor.inkDim)
                    Text("\(report.resolvedCount)")
                        .font(OPFont.number(12))
                        .foregroundStyle(OPColor.ok)
                }
            }
        }
        .padding(OPSpace.lg)
        .background(OPColor.card, in: RoundedRectangle(cornerRadius: OPSpace.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: OPSpace.radiusCard).stroke(OPColor.border, lineWidth: 1))
    }

    private func row(_ label: String, _ today: Int, _ prev: Int?) -> some View {
        HStack {
            Text(label)
                .font(OPFont.body(12))
                .foregroundStyle(OPColor.inkDim)
            Spacer()
            if let prev {
                let delta = today - prev
                Text("\(prev) → \(today)")
                    .font(OPFont.number(12))
                    .foregroundStyle(OPColor.ink)
                Text(delta >= 0 ? "+\(delta)" : "\(delta)")
                    .font(OPFont.number(11))
                    .foregroundStyle(delta > 0 ? OPColor.bad : (delta < 0 ? OPColor.ok : OPColor.inkDim))
            } else {
                Text("\(today)")
                    .font(OPFont.number(12))
                    .foregroundStyle(OPColor.ink)
            }
        }
    }

    // MARK: - 패턴

    private var patternsCard: some View {
        VStack(alignment: .leading, spacing: OPSpace.md) {
            HStack {
                Text(L10n.string("insights.patterns.title"))
                    .font(OPFont.body(13))
                    .foregroundStyle(OPColor.ink)
                Spacer()
                Text(L10n.format("insights.patterns.count", patterns.count))
                    .font(OPFont.number(11))
                    .foregroundStyle(OPColor.inkDim)
            }
            if patterns.isEmpty {
                Text(L10n.string("insights.patterns.empty"))
                    .font(OPFont.body(12))
                    .foregroundStyle(OPColor.inkDim)
            } else {
                ForEach(patterns) { p in
                    patternRow(p)
                    if p.id != patterns.last?.id {
                        Divider().overlay(OPColor.border)
                    }
                }
            }
        }
        .padding(OPSpace.lg)
        .background(OPColor.card, in: RoundedRectangle(cornerRadius: OPSpace.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: OPSpace.radiusCard).stroke(OPColor.border, lineWidth: 1))
    }

    private func patternRow(_ p: IssuePattern) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                statusBadge(p.status)
                Text(p.packageName ?? p.kind.rawValue)
                    .font(OPFont.body(12))
                    .foregroundStyle(OPColor.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(L10n.format("insights.pattern.count", p.occurrenceCount, p.daySpread))
                    .font(OPFont.number(10))
                    .foregroundStyle(OPColor.inkDim)
            }
            if let exc = p.exceptionClass {
                Text(exc)
                    .font(OPFont.number(10))
                    .foregroundStyle(OPColor.inkDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack(spacing: 8) {
                Text(p.lastAt.formatted(date: .abbreviated, time: .shortened))
                    .font(OPFont.number(10))
                    .foregroundStyle(OPColor.inkDim)
                if let mttr = p.avgTimeToResolveSec {
                    Text(L10n.format("insights.pattern.mttr", Int(mttr)))
                        .font(OPFont.number(10))
                        .foregroundStyle(OPColor.ok)
                }
                if p.status == .repeating {
                    Text(L10n.format("insights.pattern.recent", p.recentCount))
                        .font(OPFont.number(10))
                        .foregroundStyle(OPColor.bad)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func statusBadge(_ status: IssuePatternStatus) -> some View {
        let key: String
        let color: Color
        switch status {
        case .repeating: key = "insights.status.repeating"; color = OPColor.bad
        case .resolved: key = "insights.status.resolved"; color = OPColor.ok
        case .active: key = "insights.status.active"; color = OPColor.warn
        case .dormant: key = "insights.status.dormant"; color = OPColor.inkDim
        case .once: key = "insights.status.once"; color = OPColor.inkDim
        }
        return Text(L10n.string(key))
            .font(OPFont.number(9))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }

    private func metric(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(OPFont.number(9))
                .foregroundStyle(OPColor.inkDim)
                .lineLimit(1)
            Text(value)
                .font(OPFont.number(14))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(OPColor.popBG.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }

    private func chip(_ title: String, value: String?) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(OPFont.body(11))
                .foregroundStyle(OPColor.inkDim)
            if let value {
                Text(value)
                    .font(OPFont.body(11))
                    .foregroundStyle(OPColor.ink)
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(OPColor.inkDim)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(OPColor.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(OPColor.border, lineWidth: 1))
    }

    // MARK: - Export (Phase4 반복/해소 리포트)

    private func exportJSON() {
        let report = InsightReportLogic.build(
            dayKey: selectedKey,
            serial: serialFilter,
            insight: insight,
            report: report,
            patterns: patterns,
            thresholds: store.patternThresholds()
        )
        guard let data = InsightReportLogic.exportJSON(report) else { return }
        exportMessage = writeExport(data, ext: "json", prefix: "insight-report-\(selectedKey)")
    }

    private func exportPatterns() {
        let csv = PatternLogic.exportCSV(patterns)
        let data = Data(csv.utf8)
        exportMessage = writeExport(data, ext: "csv", prefix: "patterns-\(selectedKey)")
    }

    private func writeExport(_ data: Data, ext: String, prefix: String) -> String? {
        let panel = NSSavePanel()
        if ext == "csv" {
            panel.allowedContentTypes = [.commaSeparatedText]
        } else {
            panel.allowedContentTypes = [.json]
        }
        panel.nameFieldStringValue = "\(prefix).\(ext)"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try data.write(to: url)
            return L10n.string("alerts.export.done")
        } catch {
            return error.localizedDescription
        }
    }
}
