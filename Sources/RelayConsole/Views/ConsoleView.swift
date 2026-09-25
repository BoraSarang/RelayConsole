import SwiftUI

private enum ConsoleSection: String, CaseIterable, Identifiable {
    case devices, sites, jobs, alerts, insights
    var id: String { rawValue }

    var label: String {
        switch self {
        case .devices: return L10n.string("sidebar.devices")
        case .sites: return L10n.string("sidebar.sites")
        case .jobs: return L10n.string("sidebar.jobs")
        case .alerts: return L10n.string("sidebar.alerts")
        case .insights: return L10n.string("sidebar.insights")
        }
    }

    var icon: String {
        switch self {
        case .devices: return "iphone"
        case .sites: return "globe"
        case .jobs: return "clock"
        case .alerts: return "bell"
        case .insights: return "chart.bar.xaxis"
        }
    }
}

/// Devices 하위 플랫폼 — Android 실구현 · Apple 예정
private enum DevicePlatform: String, CaseIterable, Identifiable {
    case android, apple
    var id: String { rawValue }

    var label: String {
        switch self {
        case .android: return L10n.string("sidebar.platform.android")
        case .apple: return L10n.string("sidebar.platform.apple")
        }
    }
}

struct ConsoleView: View {
    @ObservedObject var store: ConsoleStore
    @State private var selection: ConsoleSection? = .devices
    @State private var platform: DevicePlatform = .android

    var body: some View {
        // 설정(SettingsView)과 동일 구조 — HStack 고정 사이드바 180 (NavigationSplitView 접기 버튼/폭 차이 제거)
        HStack(spacing: 0) {
            sidebar
            Divider()
                .overlay(OPColor.border)
            detail
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(OPColor.popBG)
        .preferredColorScheme(ThemeManager.shared.mode.preferred)
    }

    private var sidebar: some View {
        List(ConsoleSection.allCases, selection: $selection) { section in
            Label(section.label, systemImage: section.icon)
                .tag(section)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .frame(width: 180)
        .background(OPColor.popBG)
    }

    private var detail: some View {
        Group {
            switch selection {
            case .devices, .none:
                devicesDetail
            case .sites:
                SitesView(store: store)
            case .jobs:
                JobsView(store: store)
            case .alerts:
                AlertsView(store: store)
            case .insights:
                InsightsView(store: store)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OPColor.popBG)
    }

    /// Android / Apple 세그먼트 — Apple Trust-only Phase1
    private var devicesDetail: some View {
        VStack(spacing: 0) {
            Picker(L10n.string("sidebar.devices"), selection: $platform) {
                ForEach(DevicePlatform.allCases) { p in
                    Text(p.label).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(OPSpace.md)
            .background(OPColor.popBG)

            switch platform {
            case .android:
                DroidDashboardView(store: store)
            case .apple:
                AppleDashboardView(store: store)
            }
        }
    }

    private func placeholder(_ title: String, systemImage: String) -> some View {
        ZStack {
            OPColor.popBG.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(OPColor.inkDim)
                Text(title)
                    .font(OPFont.title(16))
                    .foregroundStyle(OPColor.ink)
                Text(L10n.string("sidebar.soon"))
                    .font(OPFont.body(13))
                    .foregroundStyle(OPColor.inkDim)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
