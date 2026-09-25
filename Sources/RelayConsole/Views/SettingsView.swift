import SwiftUI
import AppKit

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
        case .cards: return "square.grid.2x2"
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
    @AppStorage("relay.float.showNetwork") private var showFloatNetwork = true
    @AppStorage("relay.float.showCPU") private var showFloatCPU = true
    @AppStorage("relay.float.showGPU") private var showFloatGPU = false
    @AppStorage("relay.float.showMemory") private var showFloatMemory = false
    @AppStorage(FloatingGraphLogic.opacityKey) private var floatOpacity = FloatingGraphLogic.defaultOpacity
    /// On/Off 단일 진실원천 — FloatingGraphController.isEnabled (AppStorage 분리 기록 금지)
    @ObservedObject private var float = FloatingGraphController.shared
    @AppStorage(LoginItemLogic.headlessKey) private var headless = LoginItemLogic.defaultHeadless()
    @ObservedObject private var login = LoginItemController.shared
    @State private var selection: SettingsTab? = .general

    var body: some View {
        // NavigationSplitView 금지 — Settings 타이틀바 + toolbar 숨김 조합에서
        // 상단 여백 붕괴/접기 버튼 깨짐 발생. HStack 고정 사이드바.
        HStack(spacing: 0) {
            sidebar
            Divider()
                .overlay(OPColor.border)
            detail
        }
        // 가로 제한 — 사이드바 180 + 폼 ~460. maxWidth 없으면 Form이 넓어져 우측 여백 과다
        .frame(minWidth: 560, maxWidth: 640, minHeight: 400, maxHeight: 720)
        .background(OPColor.popBG)
        .preferredColorScheme(theme.mode.preferred)
    }

    private var sidebar: some View {
        List(SettingsTab.allCases, selection: $selection) { tab in
            Label(tab.title, systemImage: tab.icon)
                .tag(tab)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .frame(width: 180)
        .background(OPColor.popBG)
    }

    private var detail: some View {
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
                insightsSection
                sitesSection
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OPColor.popBG)
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
            Toggle(L10n.string("settings.briefing"), isOn: $store.briefingEnabled)
            floatSection
            loginSection
        }
    }

    // MARK: - 로그인 항목 + 헤드리스 (A8)

    @ViewBuilder
    private var loginSection: some View {
        Section(L10n.string("settings.login.section")) {
            Toggle(L10n.string("settings.login.launch"), isOn: Binding(
                get: { login.launchAtLogin },
                set: { login.setLaunchAtLogin($0) }
            ))
            .disabled(login.busy)
            Toggle(L10n.string("settings.launch.headless"), isOn: $headless)
            Text(L10n.string("settings.launch.headless.help"))
                .font(OPFont.body(10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let key = login.messageKey {
                Text(L10n.string(key))
                    .font(OPFont.body(11))
                    .foregroundStyle(OPColor.cta)
                    .lineLimit(2)
            } else {
                Text(L10n.string(login.statusKey))
                    .font(OPFont.body(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - 플로팅 그래프 (PLAN_floating_graphs)

    @ViewBuilder
    private var floatSection: some View {
        Section(L10n.string("settings.float.section")) {
            Toggle(L10n.string("settings.float.enabled"), isOn: Binding(
                get: { float.isEnabled },
                set: { float.setEnabled($0) }
            ))
            Toggle(L10n.string("settings.float.network"), isOn: $showFloatNetwork)
            Toggle(L10n.string("settings.float.cpu"), isOn: $showFloatCPU)
            Toggle(L10n.string("settings.float.gpu"), isOn: $showFloatGPU)
            Toggle(L10n.string("settings.float.memory"), isOn: $showFloatMemory)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L10n.string("settings.float.opacity"))
                    Spacer()
                    Text("\(Int(FloatingGraphLogic.clampOpacity(floatOpacity) * 100))%")
                        .font(OPFont.number(11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $floatOpacity, in: FloatingGraphLogic.minOpacity...FloatingGraphLogic.maxOpacity)
                    .onChange(of: floatOpacity) { _, new in
                        FloatingGraphController.shared.setOpacity(new)
                    }
            }
            Text(L10n.string("settings.float.hint"))
                .font(OPFont.body(10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
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
                Toggle(L10n.string("settings.incident.auto"), isOn: $store.incidentAuto)
                Text(L10n.string("settings.incident.auto.help"))
                    .font(OPFont.body(10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
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
            Toggle(L10n.string("settings.cards.health"), isOn: $store.cardHealth)
        }
    }

    @ViewBuilder
    private var alertsSection: some View {
        Section(L10n.string("settings.section.alerts")) {
            Picker(L10n.string("alerts.filter.period"), selection: $alertsPeriod) {
                Text(L10n.string("alerts.period.1h")).tag("1h")
                Text(L10n.string("alerts.period.24h")).tag("24h")
                Text(L10n.string("alerts.period.today")).tag("today")
                Text(L10n.string("alerts.period.yesterday")).tag("yesterday")
                Text(L10n.string("alerts.period.7d")).tag("7d")
                Text(L10n.string("alerts.period.all")).tag("all")
            }
        }
    }

    /// 인사이트 보관·패턴 임계값 (Phase1 설정화)
    @ViewBuilder
    private var insightsSection: some View {
        Section(L10n.string("settings.section.insights")) {
            Picker(L10n.string("settings.retention.label"), selection: $store.retentionDays) {
                ForEach(RetentionDays.allCases) { r in
                    Text(L10n.string(r.labelKey)).tag(r.rawValue)
                }
            }
            .onChange(of: store.retentionDays) { _, _ in
                store.applyRetentionNow()
            }
            stepperRow(
                L10n.string("settings.pattern.repeatingDays"),
                value: $store.patternRepeatingDays,
                range: 1...90
            )
            stepperRow(
                L10n.string("settings.pattern.repeatingCount"),
                value: $store.patternRepeatingCount,
                range: 1...50
            )
            stepperRow(
                L10n.string("settings.pattern.resolvedQuietDays"),
                value: $store.patternResolvedQuietDays,
                range: 1...30
            )
            stepperRow(
                L10n.string("settings.pattern.dormantQuietDays"),
                value: $store.patternDormantQuietDays,
                range: 1...90
            )
        }
    }

    /// 라벨 좌 · 숫자+스텝어 우 (Picker "30일 ⌄"과 동일 정렬)
    private func stepperRow(
        _ title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Text("\(value.wrappedValue)")
                    .font(OPFont.number(12))
                    .monospacedDigit()
                    .foregroundStyle(OPColor.ink)
                Stepper(value: value, in: range) {
                    EmptyView()
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    /// Sites SSL 경고 D-day (A5)
    @ViewBuilder
    private var sitesSection: some View {
        Section(L10n.string("settings.section.sites")) {
            stepperRow(
                L10n.string("settings.sites.sslWarnDays"),
                value: $store.sslWarnDays,
                range: 1...90
            )
            Text(L10n.string("settings.sites.sslWarnDays.help"))
                .font(OPFont.body(10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
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
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("settings.app.name"))
                        .font(OPFont.title(15))
                        .foregroundStyle(OPColor.ink)
                    Text("\(L10n.string("settings.version")) 1.13.0")
                        .font(OPFont.number(12))
                        .foregroundStyle(OPColor.inkDim)
                    Text("com.borasarang.relayconsole")
                        .font(OPFont.number(10))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            LabeledContent(L10n.string("settings.github")) {
                Link("BoraSarang/RelayConsole", destination: URL(string: "https://github.com/BoraSarang/RelayConsole")!)
                    .font(OPFont.body(12))
                    .foregroundStyle(OPColor.cta)
            }
        }
        Section(L10n.string("settings.mcp.section")) {
            Text(L10n.string("settings.mcp.help"))
                .font(OPFont.body(11))
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Text(L10n.string("settings.mcp.command"))
                .font(OPFont.number(11))
                .foregroundStyle(OPColor.inkDim)
                .textSelection(.enabled)
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
