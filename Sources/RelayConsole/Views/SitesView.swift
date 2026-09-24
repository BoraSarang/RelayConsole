import SwiftUI

/// Sites — Google식 서비스 행 · 날짜 세그먼트 바 · 가동률% (PLAN_sites_v1_1)
struct SitesView: View {
    @ObservedObject var store: ConsoleStore
    @State private var sheetMode: SiteSheetMode?
    @State private var name = ""
    @State private var target = ""
    @State private var probe: SiteProbe = .http
    @State private var interval = 60
    @State private var failThreshold = 2
    @State private var formError: String?
    @State private var rangeDays = 7

    private enum SiteSheetMode: Identifiable {
        case add
        case edit(Site)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let site): return site.id.uuidString
            }
        }
    }

    private var downSites: [Site] {
        store.sites.filter { $0.enabled && $0.effectiveUp() == false }
    }

    var body: some View {
        ZStack {
            Color(hex: 0x0F111A).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Divider().overlay(OPColor.border)
                if store.sites.isEmpty {
                    emptyState
                } else {
                    legend
                    if !downSites.isEmpty {
                        activeIncidents
                    }
                    ScrollView {
                        LazyVStack(spacing: OPSpace.sm) {
                            ForEach(store.sites) { site in
                                siteRow(site)
                            }
                        }
                        .padding(.horizontal, OPSpace.md)
                        .padding(.top, OPSpace.xs)
                        .padding(.bottom, OPSpace.md)
                    }
                }
            }
        }
        .background(Color(hex: 0x0F111A))
        .preferredColorScheme(.dark)
        .navigationTitle(L10n.string("sidebar.sites"))
        .sheet(item: $sheetMode) { mode in
            siteFormSheet(mode)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(L10n.format("sites.count", store.sites.count))
                .font(OPFont.body(12))
                .foregroundStyle(OPColor.inkDim)
            Spacer()
            Picker("", selection: $rangeDays) {
                Text(L10n.string("sites.range.7d")).tag(7)
                Text(L10n.string("sites.range.30d")).tag(30)
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
            .labelsHidden()
            Button(L10n.string("sites.add")) {
                openAdd()
            }
            .buttonStyle(.plain)
            .font(OPFont.body(12))
            .foregroundStyle(OPColor.sites)
        }
        .padding(OPSpace.md)
    }

    /// Google식 범례 — 카드 좌우와 동일 수평 패딩 · 도트/라벨 수직 정렬
    private var legend: some View {
        HStack(alignment: .center, spacing: 14) {
            legendItem(OPColor.ok, L10n.string("sites.legend.up"))
            legendItem(OPColor.warn, L10n.string("sites.legend.partial"))
            legendItem(OPColor.bad, L10n.string("sites.legend.down"))
            legendItem(OPColor.inkDim.opacity(0.35), L10n.string("sites.legend.none"))
            Spacer(minLength: 0)
        }
        .frame(height: 28, alignment: .leading)
        .padding(.horizontal, OPSpace.md)
        .padding(.top, OPSpace.xs)
        .padding(.bottom, OPSpace.xs)
    }

    private func legendItem(_ color: Color, _ label: String) -> some View {
        HStack(alignment: .center, spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(OPFont.body(10))
                .foregroundStyle(OPColor.inkDim)
                .fixedSize(horizontal: true, vertical: false)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var activeIncidents: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(downSites) { site in
                HStack(spacing: 6) {
                    Circle().fill(OPColor.bad).frame(width: 6, height: 6)
                    Text(L10n.format("sites.incident.active", site.name))
                        .font(OPFont.body(11))
                        .foregroundStyle(OPColor.bad)
                        .lineLimit(1)
                    if let since = site.stateSince() {
                        Text(since.formatted(date: .omitted, time: .shortened))
                            .font(OPFont.number(10))
                            .foregroundStyle(OPColor.inkDim)
                    }
                    Spacer()
                }
            }
        }
        .padding(.horizontal, OPSpace.md)
        .padding(.bottom, OPSpace.xs)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(OPColor.inkDim)
            Text(L10n.string("sites.empty"))
                .font(OPFont.body(13))
                .foregroundStyle(OPColor.inkDim)
            OPSecondaryButton(title: L10n.string("sites.add")) { openAdd() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 80)
    }

    // MARK: - 서비스 행

    private func siteRow(_ site: Site) -> some View {
        let up = site.enabled ? site.effectiveUp() : nil
        let state: StatusState = {
            if !site.enabled { return .idle }
            switch up {
            case .some(true): return .ok
            case .some(false): return .bad
            case nil: return .idle
            }
        }()
        let last = site.history.last
        let since = Date().addingTimeInterval(-Double(rangeDays) * 86400)
        let uptime = site.uptimePercent(since: since)

        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                StatusDot(state: state)
                    .frame(width: 8, height: 8)
                Text(site.name)
                    .font(OPFont.body(13))
                    .foregroundStyle(OPColor.ink)
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(site.probe.rawValue.uppercased())
                    .font(OPFont.number(9))
                    .foregroundStyle(OPColor.sites)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(OPColor.sites.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                Spacer(minLength: 8)
                // 우측 메트릭 — 잘림 방지 고정 폭
                if site.enabled, let up {
                    Text(stateDurationLabel(site: site, up: up))
                        .font(OPFont.number(10))
                        .foregroundStyle(up ? OPColor.inkDim : OPColor.bad)
                        .lineLimit(1)
                        .frame(minWidth: 44, maxWidth: 72, alignment: .trailing)
                }
                if let uptime {
                    Text(String(format: "%.1f%%", uptime))
                        .font(OPFont.number(11))
                        .foregroundStyle(OPColor.ink)
                        .lineLimit(1)
                        .frame(minWidth: 48, alignment: .trailing)
                } else if let ms = last?.latencyMs, last?.ok == true {
                    Text("\(ms) ms")
                        .font(OPFont.number(11))
                        .foregroundStyle(OPColor.inkDim)
                        .lineLimit(1)
                        .frame(minWidth: 48, alignment: .trailing)
                }
                Toggle("", isOn: Binding(
                    get: { site.enabled },
                    set: { store.toggleSite(id: site.id, enabled: $0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
                .fixedSize()
                Button {
                    openEdit(site)
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(OPColor.inkDim)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.string("sites.edit"))
                Button {
                    Task { await store.runSiteCheck(site) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(OPColor.inkDim)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.string("sites.check.now"))
                Button {
                    store.removeSite(id: site.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(OPColor.bad)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(height: 24)

            HStack(spacing: 8) {
                Text(site.target)
                    .font(OPFont.body(10))
                    .foregroundStyle(OPColor.inkDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                if let last, let detail = last.detail, !detail.isEmpty, last.ok == false {
                    Text(detail)
                        .font(OPFont.body(10))
                        .foregroundStyle(OPColor.bad.opacity(0.9))
                        .lineLimit(1)
                }
                if let ms = last?.latencyMs, last?.ok == true {
                    Text("\(ms) ms")
                        .font(OPFont.number(10))
                        .foregroundStyle(OPColor.inkDim)
                        .lineLimit(1)
                }
            }

            dayStatusBar(site)
        }
        .padding(OPSpace.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPColor.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(OPColor.border, lineWidth: 1))
    }

    private func stateDurationLabel(site: Site, up: Bool) -> String {
        guard let since = site.stateSince() else {
            return up ? L10n.string("sites.state.up") : L10n.string("sites.state.down")
        }
        let elapsed = Date().timeIntervalSince(since)
        let label = Self.relativeDuration(elapsed)
        return up
            ? L10n.format("sites.state.up.for", label)
            : L10n.format("sites.state.down.for", label)
    }

    static func relativeDuration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 { return "\(s / 3600)h" }
        return "\(s / 86400)d"
    }

    private func dayStatusBar(_ site: Site) -> some View {
        let bars = site.dayBars(days: rangeDays)
        return HStack(spacing: 2) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, bucket in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color(for: bucket.status))
                    .frame(maxWidth: .infinity, minHeight: 8, maxHeight: 8)
                    .help(bucket.date.formatted(date: .abbreviated, time: .omitted))
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 1)
    }

    private func color(for status: DayBarStatus) -> Color {
        switch status {
        case .up: return OPColor.ok.opacity(0.9)
        case .partial: return OPColor.warn.opacity(0.95)
        case .down: return OPColor.bad
        case .unknown: return OPColor.inkDim.opacity(0.12)
        }
    }

    private func openAdd() {
        name = ""
        target = ""
        probe = .http
        interval = 60
        failThreshold = 2
        formError = nil
        sheetMode = .add
    }

    private func openEdit(_ site: Site) {
        name = site.name
        target = site.target
        probe = site.probe
        interval = site.intervalSec
        failThreshold = site.failThreshold
        formError = nil
        sheetMode = .edit(site)
    }

    private func siteFormSheet(_ mode: SiteSheetMode) -> some View {
        let isEdit: Bool
        let title: String
        switch mode {
        case .add:
            isEdit = false
            title = L10n.string("sites.add.title")
        case .edit:
            isEdit = true
            title = L10n.string("sites.edit.title")
        }
        return ZStack {
            Color(hex: 0x0F111A).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(OPFont.title(15))
                    .foregroundStyle(OPColor.ink)

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("sites.field.name"))
                        .font(OPFont.body(11))
                        .foregroundStyle(OPColor.inkDim)
                    TextField("", text: $name)
                        .textFieldStyle(.plain)
                        .font(OPFont.body(13))
                        .foregroundStyle(OPColor.ink)
                        .padding(8)
                        .background(OPColor.popBG, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(OPColor.border, lineWidth: 1))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("sites.field.target"))
                        .font(OPFont.body(11))
                        .foregroundStyle(OPColor.inkDim)
                    TextField(
                        probe == .http ? "https://example.com/health" : probe == .tcp ? "host:5432" : "example.com",
                        text: $target
                    )
                    .textFieldStyle(.plain)
                    .font(OPFont.body(13))
                    .foregroundStyle(OPColor.ink)
                    .padding(8)
                    .background(OPColor.popBG, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(OPColor.border, lineWidth: 1))
                    Text(L10n.string("sites.field.hint"))
                        .font(OPFont.body(9))
                        .foregroundStyle(OPColor.inkDim.opacity(0.7))
                }

                Picker(L10n.string("sites.field.probe"), selection: $probe) {
                    Text("HTTP").tag(SiteProbe.http)
                    Text("TCP").tag(SiteProbe.tcp)
                    Text("PING").tag(SiteProbe.ping)
                }
                .pickerStyle(.segmented)

                Stepper(
                    "\(L10n.string("sites.field.interval")): \(interval)s",
                    value: $interval,
                    in: 10...3600,
                    step: 10
                )
                .font(OPFont.body(12))
                .foregroundStyle(OPColor.ink)

                Stepper(
                    "\(L10n.string("sites.field.threshold")): \(failThreshold)",
                    value: $failThreshold,
                    in: 1...5,
                    step: 1
                )
                .font(OPFont.body(12))
                .foregroundStyle(OPColor.ink)
                .help(L10n.string("sites.field.threshold.help"))

                if let formError {
                    Text(formError)
                        .font(OPFont.body(11))
                        .foregroundStyle(OPColor.bad)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Spacer()
                    OPSecondaryButton(title: L10n.string("alerts.note.cancel")) {
                        sheetMode = nil
                        formError = nil
                    }
                    OPPrimaryButton(title: L10n.string(isEdit ? "alerts.note.save" : "sites.add")) {
                        submit(mode)
                    }
                }
            }
            .padding(OPSpace.xl)
        }
        .frame(minWidth: 380, minHeight: 420)
        .preferredColorScheme(.dark)
    }

    private func submit(_ mode: SiteSheetMode) {
        let n = name.trimmingCharacters(in: .whitespaces)
        let t = target.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else {
            formError = L10n.string("sites.error.name")
            return
        }
        if let errKey = SitesJobsLogic.validateTarget(t, probe: probe) {
            formError = L10n.string(errKey)
            return
        }
        formError = nil
        switch mode {
        case .add:
            store.addSite(name: n, target: t, probe: probe, intervalSec: interval, failThreshold: failThreshold)
        case .edit(let site):
            store.updateSite(id: site.id, name: n, target: t, probe: probe, intervalSec: interval, failThreshold: failThreshold)
        }
        sheetMode = nil
        name = ""
        target = ""
    }
}
