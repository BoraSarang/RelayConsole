import SwiftUI
import Combine
import AppKit

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
        didSet { objectWillChange.send(); applyAppearance() }
    }

    init() {
        // App.init 시점 NSApp 미준비 가능성 방어 — AppDelegate에서 한 번 더 적용
        if NSApp != nil {
            applyAppearance()
        }
    }

    func select(_ mode: OPThemeMode) {
        self.mode = mode
        DebugLogger.shared.system("Theme", "테마 변경: \(mode.rawValue)")
    }

    /// AppDelegate / Scene 공통 — NSApp.appearance를 테마에 맞춰 세팅
    func applyAppearance() {
        switch mode {
        case .system: NSApp.appearance = nil
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        }
    }
}

enum OPColor {
    /// 디자인 토큰 → 동적 NSColor (시스템/다크/화이트 3종 연동)
    private static func dynamic(
        dark: UInt32,
        light: UInt32
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let h = isDark ? dark : light
            return NSColor(
                srgbRed: CGFloat((h >> 16) & 0xFF) / 255.0,
                green: CGFloat((h >> 8) & 0xFF) / 255.0,
                blue: CGFloat(h & 0xFF) / 255.0,
                alpha: 1.0
            )
        })
    }

    private static func dynamicBorder() -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let base = isDark ? NSColor.white : NSColor.black
            return base.withAlphaComponent(0.08)
        })
    }

    // DESIGN.md light: abyss #F4F6FB, panel #FFFFFF, ink #131A2B, inkDim #5A6A86
    static let popBG = dynamic(dark: 0x0f111a, light: 0xF4F6FB)
    static let card = dynamic(dark: 0x1c1f2a, light: 0xFFFFFF)
    static let cta = dynamic(dark: 0x2f6bff, light: 0x2f6bff)
    static let thermal = dynamic(dark: 0xff8c32, light: 0xE67A1A)
    static let thermalSoft = dynamic(dark: 0xffb86a, light: 0xF5A24A)
    static let ok = dynamic(dark: 0x33D973, light: 0x1B9E4C)
    static let warn = dynamic(dark: 0xFFB333, light: 0xB87A00)
    static let bad = dynamic(dark: 0xFF4D52, light: 0xD81E26)
    static let ink = dynamic(dark: 0xEBF0FA, light: 0x131A2B)
    static let inkDim = dynamic(dark: 0x9EADC7, light: 0x5A6A86)
    static let border = dynamicBorder()

    static let droid = dynamic(dark: 0x33D973, light: 0x1B9E4C)
    /// DESIGN.md apple 실버 — Phase1 Apple 카드 accent
    static let apple = dynamic(dark: 0xD9E0F2, light: 0x3E4A68)
    /// DESIGN.md sites 블루
    static let sites = dynamic(dark: 0x4D99FF, light: 0x1A6FD4)
    /// DESIGN.md jobs 앰버
    static let jobs = dynamic(dark: 0xFFB333, light: 0xB87A00)

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
