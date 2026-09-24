import SwiftUI

struct DroidDashboardView: View {
    @ObservedObject var store: ConsoleStore
    @State private var showProcessList = false
    @State private var showLogs = false
    @State private var showScreenshot = false
    @State private var showWifiOnboarding = false
    @State private var showAppHub = false
    @ObservedObject private var shots = ScreenshotService.shared
    @ObservedObject private var scrcpy = ScrcpyController.shared

    private let columns = [
        GridItem(.flexible(), spacing: 16, alignment: .top),
        GridItem(.flexible(), spacing: 16, alignment: .top)
    ]

    private var device: DeviceSnapshot? { store.selectedDevice }
    private var devices: [DeviceSnapshot] { store.inventory.devices }
    private var metrics: DroidMetrics? {
        device.map { store.metrics(for: $0.serial) }
    }

    var body: some View {
        ZStack {
            Color(hex: 0x0F111A).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: OPSpace.lg) {
                    if device == nil {
                        emptyState
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                    } else {
                        header
                        if devices.count > 1 {
                            devicePicker
                        }
                        if let d = device, d.isThermalAlert {
                            thermalBanner(device: d)
                        }
                        LazyVGrid(columns: columns, spacing: 16) {
                            if store.cardCpu {
                                DroidCards.cpu(device: device, metrics: metrics)
                            }
                            if store.cardGpu {
                                DroidCards.gpu(device: device, metrics: metrics)
                            }
                            if store.cardMemory {
                                DroidCards.memory(device: device, metrics: metrics) {
                                    showProcessList = true
                                }
                            }
                            if store.cardSensors {
                                DroidCards.sensors(device: device, metrics: metrics)
                            }
                            if store.cardBattery {
                                DroidCards.battery(device: device, metrics: metrics)
                            }
                            if store.cardNetwork {
                                DroidCards.network(device: device, metrics: metrics)
                            }
                            if store.cardThermal {
                                DroidCards.thermal(device: device, metrics: metrics)
                            }
                            if store.cardStorage {
                                DroidCards.storage(device: device, metrics: metrics)
                            }
                        }
                        footer
                    }
                }
                .padding(OPSpace.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(hex: 0x0F111A))
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showProcessList) {
            ProcessListSheet(store: store)
        }
        .sheet(isPresented: $showLogs) {
            LogViewerSheet(store: store)
        }
        .sheet(isPresented: $showScreenshot) {
            if let d = device, !d.serial.isEmpty {
                ScreenshotPreviewSheet(serial: d.serial)
            }
        }
        .sheet(isPresented: $showAppHub) {
            if let d = device, !d.serial.isEmpty {
                AppHubSheet(serial: d.serial)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            StatusDot(state: device?.isOnline == true ? .ok : .bad)
            Text(device?.displayName ?? L10n.na)
                .font(OPFont.title(15))
                .foregroundStyle(OPColor.ink)
                .lineLimit(1)
            if let kind = device?.connectionKind {
                Text(device?.connectionLabel ?? (kind == .usb ? L10n.string("menubar.device.usb") : L10n.string("menubar.device.network")))
                    .font(OPFont.number(10))
                    .foregroundStyle(kind == .network ? OPColor.cta : OPColor.inkDim)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(OPColor.card, in: RoundedRectangle(cornerRadius: 4))
            }
            if let level = device?.batteryLevel {
                Text("\(level)%")
                    .font(OPFont.number(12))
                    .foregroundStyle(OPColor.inkDim)
            }
            if let temp = device?.deviceTempC ?? device?.batteryTempC {
                Text(String(format: "%.1f°C", temp))
                    .font(OPFont.number(12))
                    .foregroundStyle(OPColor.thermal)
            }
            if let online = device?.isOnline {
                Text(online
                    ? L10n.string("menubar.status.connected")
                    : L10n.string("menubar.status.disconnected"))
                    .font(OPFont.body(12))
                    .foregroundStyle(online ? OPColor.ok : OPColor.bad)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let d = device, !d.serial.isEmpty {
                ScrcpyHeaderButton(serial: d.serial)
                WifiOnboardingHeaderButton(serial: d.serial, connectionKind: d.connectionKind)
                Button {
                    showAppHub = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 10, weight: .semibold))
                        Text(L10n.string("apphub.button"))
                            .font(OPFont.number(10))
                    }
                    .foregroundStyle(OPColor.cta)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(OPColor.cta.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(OPColor.cta.opacity(0.35), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.string("apphub.button.help"))
                Button {
                    showScreenshot = true
                } label: {
                    HStack(spacing: 3) {
                        if shots.loadingSerials.contains(d.serial) {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "camera")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        Text(L10n.string("scrcpy.thumb.title"))
                            .font(OPFont.number(10))
                    }
                    .foregroundStyle(OPColor.inkDim)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(OPColor.card, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(OPColor.border, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.string("scrcpy.thumb.openHint"))
                Text(d.connectionKind == .network ? (d.connectionLabel ?? "") : AdbClient.shortId(d.serial))
                    .font(OPFont.number(11))
                    .foregroundStyle(OPColor.inkDim)
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
    }

    private var devicePicker: some View {
        HStack(spacing: 6) {
            Text(L10n.string("droid.header.picker"))
                .font(OPFont.body(10))
                .foregroundStyle(OPColor.inkDim)
            ForEach(devices, id: \.serial) { d in
                Button {
                    store.select(d.serial)
                } label: {
                    Text(d.displayName)
                        .font(OPFont.number(10))
                        .foregroundStyle(d.serial == store.selectedSerial ? .white : OPColor.inkDim)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(d.serial == store.selectedSerial
                                    ? OPColor.cta.opacity(0.25)
                                    : OPColor.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(d.serial == store.selectedSerial
                                    ? OPColor.cta
                                    : OPColor.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func thermalBanner(device d: DeviceSnapshot) -> some View {
        HStack(spacing: 8) {
            let temp = d.deviceTempC ?? d.batteryTempC
            Text("⚠ " + L10n.format(
                "menubar.alert.thermal",
                temp.map { String(format: "%.1f", $0) } ?? L10n.na
            ))
                .font(OPFont.body(12))
                .foregroundStyle(OPColor.thermal)
                .lineLimit(1)
                .truncationMode(.tail)
            if let s = d.thermalStatus, s >= 2 {
                Text("[\(L10n.string("menubar.alert.throttling"))]")
                    .font(OPFont.number(11))
                    .foregroundStyle(OPColor.thermalSoft)
            }
            Spacer(minLength: 0)
            OPSparkline(
                points: metrics?.tempHistory ?? [],
                color: OPColor.thermal,
                height: 16
            )
            .frame(width: 100, height: 16)
        }
        .padding(OPSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(OPColor.thermal.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(OPColor.thermal.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "cable.connector")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(OPColor.inkDim)
            Text(L10n.string("droid.empty.noDevice"))
                .font(OPFont.title(16))
                .foregroundStyle(OPColor.ink)
            Text(L10n.string("droid.empty.noDeviceBody"))
                .font(OPFont.body(13))
                .foregroundStyle(OPColor.inkDim)
                .multilineTextAlignment(.center)
            Text(L10n.string("droid.empty.noDeviceHint"))
                .font(OPFont.number(12))
                .foregroundStyle(OPColor.inkDim.opacity(0.85))
                .multilineTextAlignment(.center)
            Button(L10n.string("wifi.button.enable")) {
                showWifiOnboarding = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 6)
        }
        .padding(.horizontal, OPSpace.xl)
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showWifiOnboarding) {
            WifiOnboardingSheet(presetSerial: nil, connectionKind: nil)
        }
    }

    // MARK: - Values

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.format(
                "droid.footer.settingsChanged",
                device?.settingsChangedCount ?? 0
            ))
                .font(OPFont.body(12))
                .foregroundStyle((device?.settingsChangedCount ?? 0) > 0
                    ? OPColor.thermal
                    : OPColor.inkDim)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(L10n.format(
                "droid.footer.logcatHits",
                device?.logcatHitCount ?? 0
            ))
                .font(OPFont.body(12))
                .foregroundStyle((device?.logcatHitCount ?? 0) > 0
                    ? OPColor.cta
                    : OPColor.inkDim)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(OPSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPColor.card, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture { showLogs = true }
        .help(L10n.string("droid.logs.button"))
    }
}
