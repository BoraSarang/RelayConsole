import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: ConsoleStore
    @ObservedObject private var theme = ThemeManager.shared
    @AppStorage("relay.menubarMetrics") private var menubarMetrics = true

    var body: some View {
        ZStack {
            Color(hex: 0x0F111A).ignoresSafeArea()
            Form {
                Section(L10n.string("settings.section.general")) {
                    Picker(L10n.string("settings.theme"), selection: Binding(
                        get: { theme.mode },
                        set: { theme.select($0) }
                    )) {
                        Text(L10n.string("settings.theme.system")).tag(OPThemeMode.system)
                        Text(L10n.string("settings.theme.dark")).tag(OPThemeMode.dark)
                        Text(L10n.string("settings.theme.light")).tag(OPThemeMode.light)
                    }
                    Toggle(L10n.string("settings.menubarMetrics"), isOn: $menubarMetrics)
                    LabeledContent(L10n.string("settings.version"), value: "0.4.0")
                    LabeledContent(L10n.string("settings.bundleId"), value: "com.borasarang.relayconsole")
                }
                Section(L10n.string("settings.section.droid")) {
                    Text(L10n.string("settings.keyPrefix"))
                        .font(OPFont.body(12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 420, height: 340)
        .background(Color(hex: 0x0F111A))
        .preferredColorScheme(.dark)
    }
}
