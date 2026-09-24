import SwiftUI

private enum ConsoleSection: String, CaseIterable, Identifiable {
    case devices, sites, jobs, alerts
    var id: String { rawValue }

    var label: String {
        switch self {
        case .devices: return L10n.string("sidebar.devices")
        case .sites: return L10n.string("sidebar.sites")
        case .jobs: return L10n.string("sidebar.jobs")
        case .alerts: return L10n.string("sidebar.alerts")
        }
    }

    var icon: String {
        switch self {
        case .devices: return "iphone"
        case .sites: return "globe"
        case .jobs: return "clock"
        case .alerts: return "bell"
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
        ZStack {
            Color(hex: 0x0F111A).ignoresSafeArea()
            NavigationSplitView {
                List(ConsoleSection.allCases, selection: $selection) { section in
                    Label(section.label, systemImage: section.icon)
                        .tag(section)
                }
                .listStyle(.sidebar)
                .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
            } detail: {
                switch selection {
                case .devices, .none:
                    devicesDetail
                case .sites:
                    placeholder(ConsoleSection.sites.label, systemImage: ConsoleSection.sites.icon)
                case .jobs:
                    placeholder(ConsoleSection.jobs.label, systemImage: ConsoleSection.jobs.icon)
                case .alerts:
                    AlertsView(store: store)
                }
            }
            .navigationTitle(L10n.string("droid.header.title"))
        }
        .background(Color(hex: 0x0F111A))
        .preferredColorScheme(.dark)
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
            .background(Color(hex: 0x0F111A))

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
            Color(hex: 0x0F111A).ignoresSafeArea()
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
