import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Alerts 사이드바 — 3탭(활성/무음/해소) · 필터 · 기기 그룹 · ack/mute/메모 · export
/// PLAN_alerts · 벤치마크 Kandji/Intune/Zabbix/Grafana
struct AlertsView: View {
    @ObservedObject var store: ConsoleStore
    @AppStorage("relay.alerts.defaultPeriod") private var defaultPeriodRaw = "24h"

    @State private var tab: AlertsState = .active
    @State private var severities: Set<WatchSeverity> = []
    @State private var sources: Set<WatchSource> = []
    @State private var kinds: Set<WatchKind> = []
    @State private var period: AlertsPeriod = .h24
    @State private var searchText = ""
    @State private var collapsed: Set<String> = []
    @State private var noteDrafts: [UUID: String] = [:]
    @State private var editingNote: UUID?
    @State private var exportMessage: String?
    @State private var exportFailed = false

    var body: some View {
        ZStack {
            OPColor.popBG.ignoresSafeArea()
            VStack(spacing: 0) {
                filterBar
                Divider().overlay(OPColor.border)
                tabPicker
                Divider().overlay(OPColor.border)
                listOrEmpty
            }
        }
        .background(OPColor.popBG)
        .preferredColorScheme(ThemeManager.shared.mode.preferred)
        .navigationTitle(L10n.string("sidebar.alerts"))
        .onAppear {
            if period == .h24 {
                period = AlertsPeriod(raw: defaultPeriodRaw) ?? .h24
            }
        }
        .alert(
            L10n.string(exportFailed ? "alerts.export.failed" : "alerts.export.done"),
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

    // MARK: - 필터 바

    private var filterBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    Button {
                        if severities.isEmpty { severities = Set(WatchSeverity.allCases) }
                        else { severities.removeAll() }
                    } label: {
                        Text(severities.isEmpty
                             ? L10n.string("alerts.filter.severity.all")
                             : L10n.format("alerts.filter.severity.count", severities.count))
                    }
                    Divider()
                    ForEach(WatchSeverity.allCases, id: \.self) { sev in
                        Toggle(isOn: severityBinding(sev)) {
                            Text(severityLabel(sev))
                        }
                    }
                } label: {
                    filterChip(
                        L10n.string("alerts.filter.severity"),
                        value: severities.isEmpty ? nil : severityLabel(severities.sorted().first ?? .info)
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                // kind 필터 — 크래시/ANR/온도 등 카테고리
                Menu {
                    Button {
                        if kinds.isEmpty { kinds = Set(WatchKind.allCases) }
                        else { kinds.removeAll() }
                    } label: {
                        Text(kinds.isEmpty
                             ? L10n.string("alerts.filter.kind.all")
                             : L10n.format("alerts.filter.kind.count", kinds.count))
                    }
                    Divider()
                    // 주요 카테고리 먼저 (크래시/ANR 강조)
                    ForEach(primaryKinds, id: \.self) { kind in
                        Toggle(isOn: kindBinding(kind)) {
                            Text(kindLabel(kind))
                        }
                    }
                    if Set(primaryKinds) != Set(WatchKind.allCases) {
                        Divider()
                        ForEach(WatchKind.allCases.filter { !primaryKinds.contains($0) }, id: \.self) { kind in
                            Toggle(isOn: kindBinding(kind)) {
                                Text(kindLabel(kind))
                            }
                        }
                    }
                } label: {
                    filterChip(
                        L10n.string("alerts.filter.kind"),
                        value: kinds.isEmpty ? nil : kindFilterValue()
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                // 기간 — 오늘/어제 day 칩 + 1h/24h/7d/all
                Menu {
                    ForEach(AlertsPeriod.allCases) { p in
                        Button(L10n.string(p.labelKey)) { period = p }
                    }
                } label: {
                    filterChip(L10n.string("alerts.filter.period"), value: L10n.string(period.labelKey))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                // 오늘/어제 바로가기 칩 (A 표시 위치)
                HStack(spacing: 4) {
                    dayChip(.today)
                    dayChip(.yesterday)
                }

                Menu {
                    Button {
                        if sources.isEmpty { sources = [.android, .apple] }
                        else { sources.removeAll() }
                    } label: {
                        Text(sources.isEmpty
                             ? L10n.string("alerts.filter.source.all")
                             : L10n.format("alerts.filter.source.count", sources.count))
                    }
                    Divider()
                    Toggle(L10n.string("sidebar.platform.android"), isOn: sourceBinding(.android))
                    Toggle(L10n.string("sidebar.platform.apple"), isOn: sourceBinding(.apple))
                } label: {
                    filterChip(L10n.string("alerts.filter.source"), value: nil)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer()

                Button {
                    IncidentBundleStore.shared.openRoot()
                } label: {
                    Label(L10n.string("incident.open"), systemImage: "folder")
                }
                .buttonStyle(.plain)
                .font(OPFont.body(12))
                .foregroundStyle(OPColor.cta)
                .help(L10n.string("incident.open.help"))

                Button(L10n.string("alerts.export.json")) { exportJSON() }
                    .buttonStyle(.plain)
                    .font(OPFont.body(12))
                    .foregroundStyle(OPColor.cta)
                Button(L10n.string("alerts.export.csv")) { exportCSV() }
                    .buttonStyle(.plain)
                    .font(OPFont.body(12))
                    .foregroundStyle(OPColor.cta)
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(OPColor.inkDim)
                TextField(L10n.string("alerts.search.placeholder"), text: $searchText)
                    .textFieldStyle(.plain)
                    .font(OPFont.body(12))
                    .foregroundStyle(OPColor.ink)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(OPColor.inkDim)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(OPColor.card, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(OPColor.border, lineWidth: 1))
        }
        .padding(OPSpace.md)
    }

    // MARK: - 탭

    private var tabPicker: some View {
        let counts = store.alertsStateCounts(base: baseFilterWithoutState)
        return HStack(spacing: 0) {
            ForEach(AlertsState.allCases, id: \.self) { s in
                Button {
                    tab = s
                } label: {
                    VStack(spacing: 2) {
                        Text(L10n.string(tabKey(s)))
                            .font(OPFont.body(12))
                            .foregroundStyle(tab == s ? OPColor.ink : OPColor.inkDim)
                        Text("\(counts[s] ?? 0)")
                            .font(OPFont.number(11))
                            .foregroundStyle(tab == s ? OPColor.cta : OPColor.inkDim)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(tab == s ? OPColor.cta.opacity(0.15) : Color.clear)
                    .contentShape(Rectangle())
                    .overlay(alignment: .bottom) {
                        if tab == s {
                            Rectangle()
                                .fill(OPColor.cta)
                                .frame(height: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .background(OPColor.popBG)
    }

    // MARK: - 목록

    private var filtered: [WatchEvent] {
        var f = baseFilterWithoutState
        f.state = tab
        return store.filteredWatchEvents(f)
    }

    private var baseFilterWithoutState: AlertsFilter {
        var f = AlertsFilter()
        f.severities = severities.isEmpty ? nil : severities
        f.sources = sources.isEmpty ? nil : sources
        f.kinds = kinds.isEmpty ? nil : kinds
        f.since = period.since(now: .now)
        f.until = period.until(now: .now)
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        f.search = q.isEmpty ? nil : q
        return f
    }

    @ViewBuilder
    private var listOrEmpty: some View {
        let groups = WatchEventAlerts.groupByDevice(filtered)
        if groups.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(groups, id: \.key) { group in
                        deviceGroup(group)
                    }
                }
                .padding(OPSpace.md)
            }
        }
    }

    private func deviceGroup(_ group: (key: String, source: WatchSource, events: [WatchEvent])) -> some View {
        let isOpen = !collapsed.contains(group.key)
        let short = shortSerial(group.key)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if isOpen { collapsed.insert(group.key) }
                else { collapsed.remove(group.key) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(OPColor.inkDim)
                    Text(group.source == .apple
                         ? L10n.string("sidebar.platform.apple")
                         : L10n.string("sidebar.platform.android"))
                        .font(OPFont.body(11))
                        .foregroundStyle(group.source == .apple ? OPColor.apple : OPColor.droid)
                    Text(short)
                        .font(OPFont.body(12))
                        .foregroundStyle(OPColor.ink)
                    Spacer()
                    Text(L10n.format("alerts.group.count", group.events.count))
                        .font(OPFont.body(11))
                        .foregroundStyle(OPColor.inkDim)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .background(OPColor.card.opacity(0.5))

            if isOpen {
                VStack(spacing: 0) {
                    ForEach(group.events) { event in
                        eventRow(event)
                        if event.id != group.events.last?.id {
                            Divider().overlay(OPColor.border).padding(.leading, 28)
                        }
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .background(OPColor.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(OPColor.border, lineWidth: 1))
    }

    private func eventRow(_ e: WatchEvent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(dotColor(e))
                    .frame(width: 7, height: 7)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(e.title)
                            .font(OPFont.body(13))
                            .foregroundStyle(titleColor(e))
                            .lineLimit(1)
                        if e.ackAt != nil {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(OPColor.ok)
                        }
                        if e.state() == .muted {
                            Image(systemName: "bell.slash.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(OPColor.inkDim)
                        }
                    }
                    if !e.detail.isEmpty {
                        Text(e.detail)
                            .font(OPFont.body(11))
                            .foregroundStyle(OPColor.inkDim)
                            .lineLimit(2)
                    }
                    if let note = e.note, !note.isEmpty {
                        Text(note)
                            .font(OPFont.body(11))
                            .foregroundStyle(OPColor.cta.opacity(0.9))
                            .lineLimit(2)
                    }
                    HStack(spacing: 8) {
                        Text(e.at.formatted(date: .abbreviated, time: .shortened))
                            .font(OPFont.body(10))
                            .foregroundStyle(OPColor.inkDim)
                        if let until = e.mutedUntil, until > .now {
                            Text(L10n.format("alerts.muted.until", until.formatted(date: .omitted, time: .shortened)))
                                .font(OPFont.body(10))
                                .foregroundStyle(OPColor.warn.opacity(0.85))
                        }
                    }
                }
                Spacer(minLength: 0)
                if tab != .cleared {
                    rowActions(e)
                }
            }
            if editingNote == e.id {
                HStack(spacing: 6) {
                    TextField(L10n.string("alerts.note.placeholder"), text: Binding(
                        get: { noteDrafts[e.id] ?? e.note ?? "" },
                        set: { noteDrafts[e.id] = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .font(OPFont.body(12))
                    .foregroundStyle(OPColor.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(OPColor.popBG, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(OPColor.border, lineWidth: 1))
                    Button(L10n.string("alerts.note.save")) {
                        store.setWatchNote(id: e.id, note: noteDrafts[e.id] ?? "")
                        editingNote = nil
                    }
                    .buttonStyle(.plain)
                    .font(OPFont.body(11))
                    .foregroundStyle(OPColor.cta)
                    Button(L10n.string("alerts.note.cancel")) {
                        editingNote = nil
                    }
                    .buttonStyle(.plain)
                    .font(OPFont.body(11))
                    .foregroundStyle(OPColor.inkDim)
                }
                .padding(.leading, 15)
                .padding(.trailing, 8)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func rowActions(_ e: WatchEvent) -> some View {
        HStack(spacing: 4) {
            if IncidentBundleLogic.captures(kind: e.kind) && !e.isClear {
                Button {
                    IncidentBundleStore.shared.capture(
                        event: e,
                        adbPath: DeviceMonitor.adbPathNow()
                    )
                } label: {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(OPColor.cta)
                        .frame(width: 22, height: 22)
                        .background(OPColor.cta.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help(L10n.string("incident.capture"))
            }

            if e.ackAt == nil {
                Button {
                    store.ackWatchEvent(id: e.id)
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(OPColor.ok)
                        .frame(width: 22, height: 22)
                        .background(OPColor.ok.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help(L10n.string("alerts.action.ack"))
            }

            Menu {
                Button(L10n.string("alerts.action.mute1h")) {
                    store.muteWatchEvent(id: e.id, until: .now.addingTimeInterval(3600))
                }
                Button(L10n.string("alerts.action.mute24h")) {
                    store.muteWatchEvent(id: e.id, until: .now.addingTimeInterval(86400))
                }
                if e.mutedUntil != nil {
                    Divider()
                    Button(L10n.string("alerts.action.muteOff")) {
                        store.muteWatchEvent(id: e.id, until: nil)
                    }
                }
            } label: {
                Image(systemName: e.state() == .muted ? "bell.slash.fill" : "bell.slash")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(e.state() == .muted ? OPColor.warn : OPColor.inkDim)
                    .frame(width: 22, height: 22)
                    .background(
                        (e.state() == .muted ? OPColor.warn : OPColor.inkDim).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 5)
                    )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(L10n.string("alerts.action.mute"))

            Button {
                if editingNote == e.id {
                    editingNote = nil
                } else {
                    noteDrafts[e.id] = e.note ?? ""
                    editingNote = e.id
                }
            } label: {
                Image(systemName: e.note?.isEmpty == false ? "note.text.badge.plus" : "note.text")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(editingNote == e.id ? OPColor.cta : OPColor.inkDim)
                    .frame(width: 22, height: 22)
                    .background(OPColor.inkDim.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .help(L10n.string("alerts.action.note"))
        }
    }

    // MARK: - empty

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.slash")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(OPColor.inkDim)
            Text(L10n.string(emptyKey()))
                .font(OPFont.body(13))
                .foregroundStyle(OPColor.inkDim)
            if tab == .active && store.recentWatchEvents.isEmpty {
                Text(L10n.string("alerts.hint"))
                    .font(OPFont.body(11))
                    .foregroundStyle(OPColor.inkDim.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 80)
    }

    // MARK: - export

    private func exportJSON() {
        guard let data = store.exportWatchEventsJSON(filtered) else {
            exportFailed = true
            exportMessage = L10n.string("alerts.export.failed.convert")
            return
        }
        savePanel(data: data, name: "relay-alerts.json", isJSON: true)
    }

    private func exportCSV() {
        let csv = store.exportWatchEventsCSV(filtered)
        guard let data = csv.data(using: .utf8) else {
            exportFailed = true
            exportMessage = L10n.string("alerts.export.failed.convert")
            return
        }
        savePanel(data: data, name: "relay-alerts.csv", isJSON: false)
    }

    private func savePanel(data: Data, name: String, isJSON: Bool) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = isJSON ? [.json] : [.commaSeparatedText]
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
                exportFailed = false
                exportMessage = L10n.format("alerts.export.path", url.lastPathComponent)
            } catch {
                exportFailed = true
                exportMessage = L10n.format("alerts.export.failed.detail", error.localizedDescription)
            }
        }
    }

    // MARK: - helpers

    /// kind 필터 바인딩
    private func kindBinding(_ kind: WatchKind) -> Binding<Bool> {
        Binding(
            get: { kinds.contains(kind) },
            set: { on in
                if on { kinds.insert(kind) } else { kinds.remove(kind) }
            }
        )
    }

    /// 주요 kind (메뉴 상단에 노출) — 크래시/ANR 우선
    private var primaryKinds: [WatchKind] {
        [.crash, .anr, .siteDown, .jobOverdue, .throttling, .batteryThreshold]
    }

    /// kind 필터 chip 값 텍스트
    private func kindFilterValue() -> String {
        if kinds.count == 1, let only = kinds.first {
            return kindLabel(only)
        }
        return L10n.format("alerts.filter.kind.count", kinds.count)
    }

    /// kind 한국어/영문 라벨
    private func kindLabel(_ kind: WatchKind) -> String {
        switch kind {
        case .crash: return L10n.string("kind.crash")
        case .anr: return L10n.string("kind.anr")
        case .throttling: return L10n.string("kind.throttling")
        case .chargeChanged: return L10n.string("kind.chargeChanged")
        case .protectionChanged: return L10n.string("kind.protectionChanged")
        case .lowPowerChanged: return L10n.string("kind.lowPowerChanged")
        case .batteryThreshold: return L10n.string("kind.batteryThreshold")
        case .psiPressure: return L10n.string("kind.psiPressure")
        case .loadSpike: return L10n.string("kind.loadSpike")
        case .memoryLow: return L10n.string("kind.memoryLow")
        case .bsohDrop: return L10n.string("kind.bsohDrop")
        case .signalDrop: return L10n.string("kind.signalDrop")
        case .appleConnected: return L10n.string("kind.appleConnected")
        case .appleDisconnected: return L10n.string("kind.appleDisconnected")
        case .androidConnected: return L10n.string("kind.androidConnected")
        case .androidDisconnected: return L10n.string("kind.androidDisconnected")
        case .siteDown: return L10n.string("kind.siteDown")
        case .siteUp: return L10n.string("kind.siteUp")
        case .jobOverdue: return L10n.string("kind.jobOverdue")
        case .jobRecovered: return L10n.string("kind.jobRecovered")
        case .sslExpiring: return L10n.string("kind.sslExpiring")
        case .settingsChanged: return L10n.string("kind.settingsChanged")
        case .logcatHits: return L10n.string("kind.logcatHits")
        }
    }

    private func severityBinding(_ sev: WatchSeverity) -> Binding<Bool> {
        Binding(
            get: { severities.contains(sev) },
            set: { on in
                if on { severities.insert(sev) } else { severities.remove(sev) }
            }
        )
    }

    private func sourceBinding(_ src: WatchSource) -> Binding<Bool> {
        Binding(
            get: { sources.contains(src) },
            set: { on in
                if on { sources.insert(src) } else { sources.remove(src) }
            }
        )
    }

    private func severityLabel(_ s: WatchSeverity) -> String {
        switch s {
        case .info: return L10n.string("alerts.severity.info")
        case .warning: return L10n.string("alerts.severity.warning")
        case .critical: return L10n.string("alerts.severity.critical")
        }
    }

    private func filterChip(_ title: String, value: String?) -> some View {
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
        .background(OPColor.card, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(OPColor.border, lineWidth: 1))
    }

    /// 오늘/어제 day 칩 (A 표시 위치)
    private func dayChip(_ p: AlertsPeriod) -> some View {
        let active = period == p
        return Button {
            period = active ? .h24 : p
        } label: {
            Text(L10n.string(p.labelKey))
                .font(OPFont.body(11))
                .foregroundStyle(active ? Color.white : OPColor.inkDim)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(active ? OPColor.cta : OPColor.card, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(active ? OPColor.cta : OPColor.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func tabKey(_ s: AlertsState) -> String {
        switch s {
        case .active: return "alerts.tab.active"
        case .muted: return "alerts.tab.muted"
        case .cleared: return "alerts.tab.cleared"
        }
    }

    private func emptyKey() -> String {
        switch tab {
        case .active: return "alerts.empty.active"
        case .muted: return "alerts.empty.muted"
        case .cleared: return "alerts.empty.cleared"
        }
    }

    private func dotColor(_ e: WatchEvent) -> Color {
        if e.isClear { return OPColor.ok.opacity(0.45) }
        switch e.severity {
        case .critical: return OPColor.bad
        case .warning: return OPColor.warn
        case .info: return OPColor.cta
        }
    }

    private func titleColor(_ e: WatchEvent) -> Color {
        if e.isClear { return OPColor.inkDim }
        switch e.severity {
        case .critical: return OPColor.bad
        case .warning: return OPColor.warn
        case .info: return OPColor.ink
        }
    }

    private func shortSerial(_ serial: String) -> String {
        store.identLabel(for: serial)
    }
}

// MARK: - 기간

enum AlertsPeriod: String, CaseIterable, Identifiable {
    case h1, h24, today, yesterday, d7, all
    var id: String { rawValue }

    init?(raw: String) {
        switch raw {
        case "1h": self = .h1
        case "24h": self = .h24
        case "today": self = .today
        case "yesterday": self = .yesterday
        case "7d": self = .d7
        case "all": self = .all
        default: return nil
        }
    }

    var labelKey: String {
        switch self {
        case .h1: return "alerts.period.1h"
        case .h24: return "alerts.period.24h"
        case .today: return "alerts.period.today"
        case .yesterday: return "alerts.period.yesterday"
        case .d7: return "alerts.period.7d"
        case .all: return "alerts.period.all"
        }
    }

    var storageValue: String {
        switch self {
        case .h1: return "1h"
        case .h24: return "24h"
        case .today: return "today"
        case .yesterday: return "yesterday"
        case .d7: return "7d"
        case .all: return "all"
        }
    }

    func since(now: Date) -> Date? {
        let cal = Calendar.current
        switch self {
        case .h1: return now.addingTimeInterval(-3600)
        case .h24: return now.addingTimeInterval(-86400)
        case .today: return cal.startOfDay(for: now)
        case .yesterday:
            return cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now))
        case .d7: return now.addingTimeInterval(-604800)
        case .all: return nil
        }
    }

    /// day 필터용 상한 (yesterday = 오늘 0시, today/all = nil)
    func until(now: Date) -> Date? {
        let cal = Calendar.current
        switch self {
        case .yesterday: return cal.startOfDay(for: now)
        case .today, .h1, .h24, .d7, .all: return nil
        }
    }
}
