import SwiftUI

private enum ConsoleSection: String, CaseIterable, Identifiable {
    case droid, apple, sites, jobs, notify
    var id: String { rawValue }

    var label: String {
        switch self {
        case .droid: return "Droid"
        case .apple: return "Apple"
        case .sites: return "Sites"
        case .jobs: return "Jobs"
        case .notify: return "Notify"
        }
    }

    var icon: String {
        switch self {
        case .droid: return "cpu"
        case .apple: return "iphone"
        case .sites: return "globe"
        case .jobs: return "clock"
        case .notify: return "bell"
        }
    }
}

struct ConsoleView: View {
    @ObservedObject var store: ConsoleStore
    @State private var selection: ConsoleSection? = .droid

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
                case .droid, .none:
                    DroidDashboardView(store: store)
                case .apple:
                    placeholder("Apple", systemImage: "iphone")
                case .sites:
                    placeholder("Sites", systemImage: "globe")
                case .jobs:
                    placeholder("Jobs", systemImage: "clock")
                case .notify:
                    placeholder("Notify", systemImage: "bell")
                }
            }
            .navigationTitle(L10n.string("droid.header.title"))
        }
        .background(Color(hex: 0x0F111A))
        .preferredColorScheme(.dark)
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
                Text(L10n.string("menubar.events.empty"))
                    .font(OPFont.body(13))
                    .foregroundStyle(OPColor.inkDim)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
