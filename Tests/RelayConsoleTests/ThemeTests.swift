import Testing
import SwiftUI
@testable import RelayConsole

@Suite("Theme")
struct ThemeTests {
    @Test("OPThemeMode preferred 매핑")
    func preferredMapping() {
        #expect(OPThemeMode.system.preferred == nil)
        #expect(OPThemeMode.dark.preferred == .dark)
        #expect(OPThemeMode.light.preferred == .light)
    }

    @Test("OPThemeMode 3종 rawValue")
    func modeCases() {
        #expect(OPThemeMode.allCases.map(\.rawValue) == ["system", "dark", "light"])
    }

    @Test("OPColor 상태색 매핑")
    func statusColorMapping() {
        #expect(OPColor.statusColor(.ok) == OPColor.ok)
        #expect(OPColor.statusColor(.warn) == OPColor.warn)
        #expect(OPColor.statusColor(.bad) == OPColor.bad)
        #expect(OPColor.statusColor(.idle) == OPColor.inkDim)
    }
}
