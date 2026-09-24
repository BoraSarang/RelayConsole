import SwiftUI

/// Apple Phase 1 대시보드 — Trust-only 카드 (Device/Battery/Storage/Thermal)
struct AppleDashboardView: View {
    @ObservedObject var store: ConsoleStore

    private let columns = [
        GridItem(.flexible(), spacing: 16, alignment: .top),
        GridItem(.flexible(), spacing: 16, alignment: .top)
    ]

    private var devices: [AppleSnapshot] { store.appleDevices }
    private var device: AppleSnapshot? { store.selectedAppleDevice }

    var body: some View {
        ZStack {
            Color(hex: 0x0F111A).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: OPSpace.lg) {
                    if !IdeviceClient.toolsAvailable {
                        toolsMissing
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else if device == nil {
                        emptyState
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                    } else {
                        header
                        if devices.count > 1 {
                            devicePicker
                        }
                        LazyVGrid(columns: columns, spacing: 16) {
                            if store.cardBattery {
                                AppleCards.battery(device)
                            }
                            if store.cardStorage {
                                AppleCards.storage(device)
                            }
                            if store.cardThermal {
                                AppleCards.thermal(device)
                            }
                            AppleCards.deviceInfo(device)
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
        .onAppear {
            Task { await AppleDeviceMonitor.shared.refreshNow() }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            StatusDot(state: device?.isOnline == true ? .ok : .bad)
            Text(device?.displayName ?? L10n.na)
                .font(OPFont.title(15))
                .foregroundStyle(OPColor.ink)
                .lineLimit(1)
            Text(L10n.string("apple.badge.trust"))
                .font(OPFont.number(10))
                .foregroundStyle(OPColor.apple)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(OPColor.card, in: RoundedRectangle(cornerRadius: 4))
            if let level = device?.batteryLevel {
                Text("\(level)%")
                    .font(OPFont.number(12))
                    .foregroundStyle(OPColor.inkDim)
            }
            Spacer(minLength: 4)
            Text(device?.isOnline == true
                ? L10n.string("menubar.status.connected")
                : L10n.string("menubar.status.disconnected"))
                .font(OPFont.body(12))
                .foregroundStyle(device?.isOnline == true ? OPColor.ok : OPColor.bad)
        }
    }

    private var devicePicker: some View {
        Menu {
            ForEach(devices) { d in
                Button {
                    store.selectedAppleUdid = d.udid
                    UserDefaults.standard.set(d.udid, forKey: "relay.selectedAppleUdid")
                } label: {
                    Label(d.displayName, systemImage: d.isOnline ? "iphone" : "iphone.slash")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(L10n.string("apple.device.picker"))
                    .font(OPFont.body(12))
                    .foregroundStyle(OPColor.cta)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(OPColor.cta)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(OPColor.card, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack {
            Text(L10n.string("apple.footer.poll"))
                .font(OPFont.number(10))
                .foregroundStyle(OPColor.inkDim)
            Spacer()
            if let at = device?.at {
                Text(at.formatted(date: .omitted, time: .standard))
                    .font(OPFont.number(10))
                    .foregroundStyle(OPColor.inkDim)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "iphone.badge.play")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(OPColor.inkDim)
            Text(L10n.string("apple.empty.noDevice"))
                .font(OPFont.body(13))
                .foregroundStyle(OPColor.ink)
            Text(L10n.string("apple.empty.noDeviceBody"))
                .font(OPFont.body(12))
                .foregroundStyle(OPColor.inkDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 420)
    }

    private var toolsMissing: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(OPColor.warn)
            Text(L10n.string("apple.tools.title"))
                .font(OPFont.title(15))
                .foregroundStyle(OPColor.ink)
            Text(L10n.string("apple.tools.body"))
                .font(OPFont.body(12))
                .foregroundStyle(OPColor.inkDim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n.string("apple.tools.policy"))
                .font(OPFont.number(10))
                .foregroundStyle(OPColor.inkDim)
            HStack(spacing: 8) {
                AppleInstallButtons()
            }
        }
        .padding(OPSpace.xl)
        .frame(maxWidth: 460)
        .background(OPColor.card, in: RoundedRectangle(cornerRadius: OPSpace.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: OPSpace.radiusCard)
                .stroke(OPColor.border, lineWidth: 1)
        )
    }
}

/// brew 설치 안내 버튼 — 사용자 확인 1회 (자동 다운로드 금지)
private struct AppleInstallButtons: View {
    @ObservedObject private var scrcpy = ScrcpyController.shared
    @State private var installing = false

    var body: some View {
        if installing {
            ProgressView().controlSize(.small)
        } else {
            Button(L10n.string("apple.tools.brew")) {
                installing = true
                // scrcpy와 동일 패턴 — brew 한 줄, 사용자 확인 후
                scrcpy.runBrew(["install", "libimobiledevice"]) { _ in
                    installing = false
                    Task { await AppleDeviceMonitor.shared.refreshNow() }
                }
            }
            .buttonStyle(.plain)
            .font(OPFont.body(12))
            .foregroundStyle(OPColor.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(OPColor.cta.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(OPColor.cta.opacity(0.5), lineWidth: 1)
            )

            TerminalOpenButton()
        }
    }
}

private struct TerminalOpenButton: View {
    var body: some View {
        Button(L10n.string("scrcpy.install.terminal")) {
            let script = """
            tell application "Terminal"
                activate
                do script "brew install libimobiledevice"
            end tell
            """
            NSAppleScript(source: script)?.executeAndReturnError(nil)
        }
        .buttonStyle(.plain)
        .font(OPFont.body(12))
        .foregroundStyle(OPColor.inkDim)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(OPColor.card, in: RoundedRectangle(cornerRadius: 8))
    }
}
