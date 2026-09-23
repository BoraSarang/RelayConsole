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
                    // 메뉴바는 아이콘만 — 이 토글은 팝오버 헤더 n/m 표시
                    Toggle(L10n.string("settings.menubarMetrics"), isOn: $menubarMetrics)
                    LabeledContent(L10n.string("settings.version"), value: "0.5.0")
                    LabeledContent(L10n.string("settings.bundleId"), value: "com.borasarang.relayconsole")
                }
                Section(L10n.string("settings.section.watch")) {
                    Toggle(L10n.string("settings.watch.enabled"), isOn: $store.watchNotifications)
                    Toggle(L10n.string("settings.watch.banner"), isOn: $store.watchBanner)
                    Toggle(L10n.string("settings.watch.throttling"), isOn: $store.watchThrottling)
                    Toggle(L10n.string("settings.watch.charge"), isOn: $store.watchCharge)
                    Toggle(L10n.string("settings.watch.protection"), isOn: $store.watchProtection)
                    Toggle(L10n.string("settings.watch.lowPower"), isOn: $store.watchLowPower)
                    Toggle(L10n.string("settings.watch.battery"), isOn: $store.watchBattery)
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
        .frame(width: 420, height: 440)
        .background(Color(hex: 0x0F111A))
        .preferredColorScheme(.dark)
    }
}
