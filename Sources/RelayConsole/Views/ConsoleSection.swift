import Foundation

/// 콘솔 사이드바 섹션 — ConsoleView 선택 + 위젯 딥링크 공용 진입점
enum ConsoleSection: String, CaseIterable, Identifiable {
    case devices, alerts, insights, plugins
    var id: String { rawValue }

    var label: String {
        L10n.string("sidebar.\(rawValue)")
    }

    var icon: String {
        switch self {
        case .devices: return "iphone"
        case .alerts: return "bell"
        case .insights: return "chart.bar.xaxis"
        case .plugins: return "puzzlepiece"
        }
    }
}
