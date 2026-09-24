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
            OPColor.popBG.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: OPSpace.lg) {
                    // 주입/기기 우선 — USB·도구 없이도 오프라인 UI 육안 가능
                    if device != nil {
                        if let err = store.appleLastError {
                            errorBanner(err)
                        }
                        if !IdeviceClient.toolsAvailable {
                            toolsNotice
                        }
                        header
                        if device?.isOnline != true {
                            offlineBanner
                        }
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
                            if !store.cardBattery && !store.cardStorage && !store.cardThermal {
                                Text(L10n.string("cards.empty"))
                                    .font(OPFont.body(12))
                                    .foregroundStyle(OPColor.inkDim)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(OPSpace.lg)
                            }
                        }
                        footer
                    } else if let err = store.appleLastError {
                        errorState(err)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else if !IdeviceClient.toolsAvailable {
                        toolsMissing
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else {
                        emptyState
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                    }
                }
                .padding(OPSpace.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(OPColor.popBG)
        .preferredColorScheme(ThemeManager.shared.mode.preferred)
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

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "cable.connector.slash")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(OPColor.bad)
            Text(L10n.string("apple.offline.banner"))
                .font(OPFont.body(12))
                .foregroundStyle(OPColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(OPSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPColor.bad.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(OPColor.bad.opacity(0.45), lineWidth: 1)
        )
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "xmark.octagon")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(OPColor.bad)
            Text(text)
                .font(OPFont.body(12))
                .foregroundStyle(OPColor.bad)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            Button(L10n.string("ui.debug.clear")) {
                store.clearAppleError()
            }
            .buttonStyle(.plain)
            .font(OPFont.body(11))
            .foregroundStyle(OPColor.inkDim)
        }
        .padding(OPSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPColor.bad.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(OPColor.bad.opacity(0.45), lineWidth: 1)
        )
    }

    private func errorState(_ text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "xmark.octagon")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(OPColor.bad)
            Text(L10n.string("apple.error.title"))
                .font(OPFont.title(15))
                .foregroundStyle(OPColor.ink)
            Text(text)
                .font(OPFont.body(12))
                .foregroundStyle(OPColor.bad)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Button(L10n.string("ui.debug.clear")) {
                store.clearAppleError()
            }
            .buttonStyle(.plain)
            .font(OPFont.body(12))
            .foregroundStyle(OPColor.inkDim)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(OPColor.card, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(OPSpace.xl)
        .frame(maxWidth: 460)
        .background(OPColor.card, in: RoundedRectangle(cornerRadius: OPSpace.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: OPSpace.radiusCard)
                .stroke(OPColor.bad.opacity(0.4), lineWidth: 1)
        )
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
            Text("[\(ErrorCode.appleBinaryMissing.rawValue)]")
                .font(OPFont.number(10))
                .foregroundStyle(OPColor.inkDim.opacity(0.8))
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

    /// 기기 보유 중 도구 없음 — 카드 아래 안내
    private var toolsNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(OPColor.warn)
            Text(L10n.string("apple.tools.missing"))
                .font(OPFont.body(12))
                .foregroundStyle(OPColor.ink)
            Spacer(minLength: 0)
        }
        .padding(OPSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPColor.warn.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(OPColor.warn.opacity(0.45), lineWidth: 1)
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
                scrcpy.runBrew(["install", "libimobiledevice"]) { ok in
                    installing = false
                    if !ok {
                        ConsoleStore.shared.setAppleError(
                            "[\(ErrorCode.appleInstallFailed.rawValue)] \(ErrorCode.appleInstallFailed.koMessage)"
                        )
                    } else {
                        ConsoleStore.shared.clearAppleError()
                    }
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
