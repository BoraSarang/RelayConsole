import SwiftUI
import Combine

enum OPThemeMode: String, CaseIterable, Identifiable {
    case system, dark, light
    var id: String { rawValue }

    var preferred: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}

@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    @AppStorage("relay.themeMode") var mode: OPThemeMode = .system {
        didSet { objectWillChange.send() }
    }

    func select(_ mode: OPThemeMode) {
        self.mode = mode
        DebugLogger.shared.system("Theme", "테마 변경: \(mode.rawValue)")
    }
}

enum OPColor {
    static let popBG = Color(hex: 0x0f111a)
    static let card = Color(hex: 0x1c1f2a)
    static let cta = Color(hex: 0x2f6bff)
    static let thermal = Color(hex: 0xff8c32)
    static let thermalSoft = Color(hex: 0xffb86a)
    static let ok = Color(hex: 0x33D973)
    static let warn = Color(hex: 0xFFB333)
    static let bad = Color(hex: 0xFF4D52)
    static let ink = Color(hex: 0xEBF0FA)
    static let inkDim = Color(hex: 0x9EADC7)
    static let border = Color.white.opacity(0.08)

    static let droid = Color(hex: 0x33D973)
    /// DESIGN.md apple 실버 — Phase1 Apple 카드 accent
    static let apple = Color(hex: 0xD9E0F2)
    /// DESIGN.md sites 블루
    static let sites = Color(hex: 0x4D99FF)
    /// DESIGN.md jobs 앰버
    static let jobs = Color(hex: 0xFFB333)

    static func statusColor(_ state: StatusState) -> Color {
        switch state {
        case .ok: return ok
        case .warn: return warn
        case .bad: return bad
        case .idle: return inkDim
        }
    }
}

enum StatusState {
    case ok, warn, bad, idle
}

enum OPFont {
    static func title(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
    static func number(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }
    static func body(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .medium)
    }
}

enum OPSpace {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let radiusCard: CGFloat = 16
    static let radiusOther: CGFloat = 12
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}
