import Foundation

/// 콘솔 사이드바 섹션 — ConsoleView 선택 + 위젯 딥링크 공용 진입점
enum ConsoleSection: String, CaseIterable, Identifiable {
    case devices, sites, jobs, alerts, insights
    var id: String { rawValue }

    var label: String {
        L10n.string("sidebar.\(rawValue)")
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
