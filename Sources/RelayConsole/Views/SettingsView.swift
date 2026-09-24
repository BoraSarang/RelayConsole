import SwiftUI

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general, watch, cards, alertsJobs, integrations, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return L10n.string("settings.section.general")
        case .watch: return L10n.string("settings.section.watch")
        case .cards: return L10n.string("settings.section.cards")
        case .alertsJobs: return L10n.string("settings.section.alertsJobs")
        case .integrations: return L10n.string("settings.section.integrations")
        case .about: return L10n.string("settings.section.about")
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .watch: return "bell.badge"
        case .cards: return "rectangle.3.group"
        case .alertsJobs: return "waveform.path.ecg"
        case .integrations: return "link"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: ConsoleStore
    @ObservedObject private var theme = ThemeManager.shared
    @AppStorage("relay.menubarMetrics") private var menubarMetrics = true
    @AppStorage("relay.alerts.defaultPeriod") private var alertsPeriod = "24h"
    @State private var selection: SettingsTab? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selection) { tab in
                Label(tab.title, systemImage: tab.icon)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            Form {
                switch selection {
                case .general, .none:
                    generalSection
                case .watch:
                    watchSection
                case .cards:
                    cardsSection
                case .alertsJobs:
                    alertsSection
                    jobsSection
                case .integrations:
                    notifySection
                    appleSection
                    scrcpySection
                    droidSection
                case .about:
                    aboutSection
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 360, minHeight: 320)
        }
        .frame(minWidth: 560, minHeight: 400)
        .background(Color(hex: 0x0F111A))
        .preferredColorScheme(.dark)
    }

    // MARK: - 탭 섹션

    @ViewBuilder
    private var generalSection: some View {
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
        }
    }

    @ViewBuilder
    private var watchSection: some View {
        Section(L10n.string("settings.section.watch")) {
            Section(L10n.string("settings.watch.group.overview")) {
                Toggle(L10n.string("settings.watch.enabled"), isOn: $store.watchNotifications)
                Toggle(L10n.string("settings.watch.banner"), isOn: $store.watchBanner)
                Toggle(L10n.string("settings.watch.recovery"), isOn: $store.watchRecovery)
            }
            Section(L10n.string("settings.watch.group.device")) {
                Toggle(L10n.string("settings.watch.charge"), isOn: $store.watchCharge)
                Toggle(L10n.string("settings.watch.protection"), isOn: $store.watchProtection)
                Toggle(L10n.string("settings.watch.lowPower"), isOn: $store.watchLowPower)
                Toggle(L10n.string("settings.watch.battery"), isOn: $store.watchBattery)
                Toggle(L10n.string("settings.watch.throttling"), isOn: $store.watchThrottling)
            }
            Section(L10n.string("settings.watch.group.perf")) {
                Toggle(L10n.string("settings.watch.psi"), isOn: $store.watchPsi)
                Toggle(L10n.string("settings.watch.load"), isOn: $store.watchLoad)
                Toggle(L10n.string("settings.watch.memory"), isOn: $store.watchMemory)
                Toggle(L10n.string("settings.watch.bsoh"), isOn: $store.watchBsoh)
                Toggle(L10n.string("settings.watch.rsrp"), isOn: $store.watchRsrp)
            }
            Section(L10n.string("settings.watch.group.fatal")) {
                Toggle(L10n.string("settings.watch.anr"), isOn: $store.watchAnr)
                Toggle(L10n.string("settings.watch.crash"), isOn: $store.watchCrash)
            }
        }
    }

    @ViewBuilder
    private var cardsSection: some View {
        Section(L10n.string("settings.section.cards")) {
            Toggle(L10n.string("settings.cards.cpu"), isOn: $store.cardCpu)
            Toggle(L10n.string("settings.cards.gpu"), isOn: $store.cardGpu)
            Toggle(L10n.string("settings.cards.memory"), isOn: $store.cardMemory)
            Toggle(L10n.string("settings.cards.sensors"), isOn: $store.cardSensors)
            Toggle(L10n.string("settings.cards.battery"), isOn: $store.cardBattery)
            Toggle(L10n.string("settings.cards.network"), isOn: $store.cardNetwork)
            Toggle(L10n.string("settings.cards.thermal"), isOn: $store.cardThermal)
            Toggle(L10n.string("settings.cards.storage"), isOn: $store.cardStorage)
        }
    }

    @ViewBuilder
    private var alertsSection: some View {
        Section(L10n.string("settings.section.alerts")) {
            Picker(L10n.string("alerts.filter.period"), selection: $alertsPeriod) {
                Text(L10n.string("alerts.period.1h")).tag("1h")
                Text(L10n.string("alerts.period.24h")).tag("24h")
                Text(L10n.string("alerts.period.7d")).tag("7d")
                Text(L10n.string("alerts.period.all")).tag("all")
            }
        }
    }

    @ViewBuilder
    private var jobsSection: some View {
        Section(L10n.string("settings.section.jobs")) {
            HStack {
                Text(L10n.string("settings.hb.port"))
                    .font(OPFont.body(12))
                    .foregroundStyle(OPColor.ink)
                Spacer()
                TextField("", value: Binding(
                    get: { Int(store.heartbeatPort) },
                    set: { v in
                        let p = UInt16(clamping: max(1, min(65535, v)))
                        store.restartHeartbeat(port: p)
                    }
                ), format: .number)
                .textFieldStyle(.plain)
                .font(OPFont.number(12))
                .foregroundStyle(OPColor.ink)
                .frame(width: 70)
                .multilineTextAlignment(.trailing)
                Button(L10n.string("settings.hb.restart")) {
                    store.restartHeartbeat(port: store.heartbeatPort)
                }
                .buttonStyle(.plain)
                .font(OPFont.body(11))
                .foregroundStyle(OPColor.jobs)
            }
        }
    }

    @ViewBuilder
    private var notifySection: some View {
        Section(L10n.string("settings.notify.section")) {
            Toggle(L10n.string("settings.notify.ntfy"), isOn: $store.notifyNtfy)
            if store.notifyNtfy {
                TextField(L10n.string("settings.notify.ntfy.server"), text: $store.notifyNtfyServer)
                    .textFieldStyle(.roundedBorder)
                    .font(OPFont.body(12))
                TextField(L10n.string("settings.notify.ntfy.topic"), text: $store.notifyNtfyTopic)
                    .textFieldStyle(.roundedBorder)
                    .font(OPFont.body(12))
                SecureField(L10n.string("settings.notify.ntfy.token"), text: $store.notifyNtfyToken)
                    .textFieldStyle(.roundedBorder)
                    .font(OPFont.body(12))
            }
            Toggle(L10n.string("settings.notify.slack"), isOn: $store.notifySlack)
            if store.notifySlack {
                SecureField(L10n.string("settings.notify.slack.webhook"), text: $store.notifySlackWebhook)
                    .textFieldStyle(.roundedBorder)
                    .font(OPFont.body(12))
            }
            Picker(L10n.string("settings.notify.minSeverity"), selection: $store.notifyMinSeverity) {
                Text(L10n.string("settings.notify.severity.warning")).tag("warning")
                Text(L10n.string("settings.notify.severity.critical")).tag("critical")
            }
            Toggle(L10n.string("settings.notify.recovery"), isOn: $store.notifyRecovery)
            HStack {
                Button(L10n.string("settings.notify.test")) {
                    store.sendNotifyTest()
                }
                .buttonStyle(.plain)
                .font(OPFont.body(11))
                .foregroundStyle(OPColor.cta)
                Spacer()
            }
            Text(L10n.string("settings.notify.hint"))
                .font(OPFont.body(10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var appleSection: some View {
        Section(L10n.string("settings.section.apple")) {
            LabeledContent(L10n.string("settings.apple.tools"), value: IdeviceClient.toolsAvailable
                ? L10n.string("settings.apple.toolsOk")
                : L10n.string("settings.apple.toolsMissing"))
            Text(L10n.string("apple.tools.policy"))
                .font(OPFont.body(11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var scrcpySection: some View {
        Section(L10n.string("settings.section.scrcpy")) {
            ScrcpySettingsSection()
        }
    }

    @ViewBuilder
    private var droidSection: some View {
        Section(L10n.string("settings.section.droid")) {
            Text(L10n.string("settings.keyPrefix"))
                .font(OPFont.body(12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private var aboutSection: some View {
        Section(L10n.string("settings.section.about")) {
            LabeledContent(L10n.string("settings.version"), value: "1.2.0")
            LabeledContent(L10n.string("settings.bundleId"), value: "com.borasarang.relayconsole")
        }
    }
}

/// scrcpy A안 — 경로·읽기전용·추가 옵션 (기본 8종은 코드 고정)
private struct ScrcpySettingsSection: View {
    @ObservedObject private var scrcpy = ScrcpyController.shared

    var body: some View {
        Toggle(L10n.string("settings.scrcpy.noControl"), isOn: $scrcpy.noControl)
        TextField(L10n.string("settings.scrcpy.path"), text: $scrcpy.customPath)
            .textFieldStyle(.roundedBorder)
            .font(OPFont.body(12))
        TextField(L10n.string("settings.scrcpy.opts"), text: $scrcpy.customOpts)
            .textFieldStyle(.roundedBorder)
            .font(OPFont.body(12))
        HStack {
            if scrcpy.binaryPath != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(OPColor.ok)
                Text(scrcpy.binaryPath ?? "")
                    .font(OPFont.number(10))
                    .foregroundStyle(OPColor.inkDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(OPColor.warn)
                Text(L10n.string("scrcpy.install.body"))
                    .font(OPFont.body(11))
                    .foregroundStyle(OPColor.inkDim)
                    .lineLimit(2)
            }
            Spacer()
            Button(L10n.string("settings.scrcpy.rescan")) {
                scrcpy.refresh()
            }
            .buttonStyle(.plain)
            .font(OPFont.body(11))
            .foregroundStyle(OPColor.cta)
        }
    }
}
