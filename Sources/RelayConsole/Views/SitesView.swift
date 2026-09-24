import SwiftUI

/// Sites — 업타임 목록 · 90일 상태 바 · ms 스파크라인 (PLAN_sites_jobs)
struct SitesView: View {
    @ObservedObject var store: ConsoleStore
    @State private var showingAdd = false
    @State private var name = ""
    @State private var target = ""
    @State private var probe: SiteProbe = .http
    @State private var interval = 60

    var body: some View {
        ZStack {
            Color(hex: 0x0F111A).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Divider().overlay(OPColor.border)
                if store.sites.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(store.sites) { site in
                                siteCard(site)
                            }
                        }
                        .padding(OPSpace.md)
                    }
                }
            }
        }
        .background(Color(hex: 0x0F111A))
        .preferredColorScheme(.dark)
        .navigationTitle(L10n.string("sidebar.sites"))
        .sheet(isPresented: $showingAdd) { addSheet }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(L10n.format("sites.count", store.sites.count))
                .font(OPFont.body(12))
                .foregroundStyle(OPColor.inkDim)
            Spacer()
            Button(L10n.string("sites.add")) {
                showingAdd = true
            }
            .buttonStyle(.plain)
            .font(OPFont.body(12))
            .foregroundStyle(OPColor.sites)
        }
        .padding(OPSpace.md)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(OPColor.inkDim)
            Text(L10n.string("sites.empty"))
                .font(OPFont.body(13))
                .foregroundStyle(OPColor.inkDim)
            OPSecondaryButton(title: L10n.string("sites.add")) { showingAdd = true }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 80)
    }

    private func siteCard(_ site: Site) -> some View {
        let up = site.isUp()
        let state: StatusState = {
            if !site.enabled { return .idle }
            switch up {
            case .some(true): return .ok
            case .some(false): return .bad
            case nil: return .idle
            }
        }()
        let last = site.history.last
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StatusDot(state: state)
                Text(site.name)
                    .font(OPFont.body(13))
                    .foregroundStyle(OPColor.ink)
                Text(site.probe.rawValue.uppercased())
                    .font(OPFont.number(10))
                    .foregroundStyle(OPColor.sites)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(OPColor.sites.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                Spacer()
                if let ms = last?.latencyMs, last?.ok == true {
                    Text("\(ms) ms")
                        .font(OPFont.number(11))
                        .foregroundStyle(OPColor.inkDim)
                }
                Toggle("", isOn: Binding(
                    get: { site.enabled },
                    set: { store.toggleSite(id: site.id, enabled: $0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
                Button {
                    Task { await store.runSiteCheck(site) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(OPColor.inkDim)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(L10n.string("sites.check.now"))
                Button {
                    store.removeSite(id: site.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(OPColor.bad)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            Text(site.target)
                .font(OPFont.body(11))
                .foregroundStyle(OPColor.inkDim)
                .lineLimit(1)

            // 90일 상태 바
            if !site.history.isEmpty {
                statusBar(site.recentBars())
            }

            // latency 스파크라인
            let spark = site.latencySpark().map(Double.init)
            if spark.count >= 2 {
                HStack(spacing: 6) {
                    OPSparkline(points: spark, color: OPColor.sites, height: 16)
                        .frame(height: 16)
                    if let ms = last?.latencyMs {
                        Text("\(ms) ms")
                            .font(OPFont.number(10))
                            .foregroundStyle(OPColor.inkDim)
                    }
                }
            }

            HStack(spacing: 8) {
                Text("\(L10n.string("sites.interval")) \(site.intervalSec)s")
                    .font(OPFont.body(10))
                    .foregroundStyle(OPColor.inkDim)
                if let last {
                    Text(last.at.formatted(date: .abbreviated, time: .shortened))
                        .font(OPFont.body(10))
                        .foregroundStyle(OPColor.inkDim)
                }
                if let detail = last?.detail, !detail.isEmpty {
                    Text(detail)
                        .font(OPFont.body(10))
                        .foregroundStyle(OPColor.bad.opacity(0.9))
                }
                Spacer()
            }
        }
        .padding(OPSpace.md)
        .background(OPColor.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(OPColor.border, lineWidth: 1))
    }

    /// 최근 N건 초록/빨강 막대 (최신 → 과거, DESIGN 90일 상태 바)
    private func statusBar(_ bars: [Bool]) -> some View {
        HStack(spacing: 1) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, ok in
                Rectangle()
                    .fill(ok ? OPColor.ok.opacity(0.85) : OPColor.bad)
                    .frame(maxWidth: .infinity, minHeight: 8, maxHeight: 8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }

    private var addSheet: some View {
        ZStack {
            Color(hex: 0x0F111A).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.string("sites.add.title"))
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
                    TextField(probe == .http ? "https://example.com" : probe == .tcp ? "host:443" : "example.com", text: $target)
                        .textFieldStyle(.plain)
                        .font(OPFont.body(13))
                        .foregroundStyle(OPColor.ink)
                        .padding(8)
                        .background(OPColor.popBG, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(OPColor.border, lineWidth: 1))
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

                HStack {
                    Spacer()
                    OPSecondaryButton(title: L10n.string("alerts.note.cancel")) {
                        showingAdd = false
                        name = ""
                        target = ""
                    }
                    OPPrimaryButton(title: L10n.string("sites.add")) {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        let t = target.trimmingCharacters(in: .whitespaces)
                        guard !n.isEmpty, !t.isEmpty else { return }
                        store.addSite(name: n, target: t, probe: probe, intervalSec: interval)
                        showingAdd = false
                        name = ""
                        target = ""
                    }
                }
            }
            .padding(OPSpace.xl)
        }
        .frame(minWidth: 380, minHeight: 340)
        .preferredColorScheme(.dark)
    }
}
