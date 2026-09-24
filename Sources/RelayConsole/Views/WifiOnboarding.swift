import SwiftUI

/// 헤더용 Wi-Fi 온보딩 버튼 (USB 기기에서)
struct WifiOnboardingHeaderButton: View {
    let serial: String
    let connectionKind: ConnectionKind?
    @ObservedObject private var wifi = WifiAdbController.shared
    @State private var showSheet = false

    var body: some View {
        Button {
            showSheet = true
        } label: {
            HStack(spacing: 4) {
                if wifi.busy {
                    ProgressView()
                        .controlSize(.mini)
                        .padding(.trailing, 2)
                } else {
                    Image(systemName: connectionKind == .network ? "wifi" : "wifi.circle")
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(L10n.string(connectionKind == .network ? "wifi.button.disconnect" : "wifi.button.enable"))
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
        .disabled(wifi.busy)
        .help(L10n.string("wifi.button.help"))
        .sheet(isPresented: $showSheet) {
            WifiOnboardingSheet(presetSerial: serial, connectionKind: connectionKind)
        }
    }
}

/// Wi-Fi ADB 온보딩 시트 — USB 전환 · 수동 connect · disconnect
struct WifiOnboardingSheet: View {
    var presetSerial: String?
    var connectionKind: ConnectionKind?
    @ObservedObject private var wifi = WifiAdbController.shared
    @ObservedObject private var store = ConsoleStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var manualEndpoint = ""
    @State private var selectedUsbSerial: String = ""

    private var usbDevices: [DeviceSnapshot] {
        store.inventory.devices.filter { $0.connectionKind == .usb || $0.connectionKind == nil }
    }

    private var networkDevices: [DeviceSnapshot] {
        store.inventory.devices.filter { $0.connectionKind == .network }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSpace.lg) {
            Text(L10n.string("wifi.sheet.title"))
                .font(OPFont.title(16))
                .foregroundStyle(OPColor.ink)

            // 1) USB → Wi-Fi 원클릭
            sectionCard(L10n.string("wifi.section.enable")) {
                if usbDevices.isEmpty && presetSerial == nil {
                    Text(L10n.string("wifi.enable.noUsb"))
                        .font(OPFont.body(12))
                        .foregroundStyle(OPColor.inkDim)
                } else {
                    if usbDevices.count > 1 || presetSerial == nil {
                        Picker(L10n.string("wifi.field.device"), selection: $selectedUsbSerial) {
                            ForEach(usbDevices, id: \.serial) { d in
                                Text(displayName(d)).tag(d.serial)
                            }
                            if let p = presetSerial, !usbDevices.contains(where: { $0.serial == p }) {
                                Text(AdbClient.shortId(p)).tag(p)
                            }
                        }
                        .labelsHidden()
                    } else if let p = presetSerial {
                        Text(displayNameById(p))
                            .font(OPFont.body(12))
                            .foregroundStyle(OPColor.ink)
                    }
                    OPPrimaryButton(title: L10n.string("wifi.enable.action")) {
                        let target = selectedUsbSerial.isEmpty ? (presetSerial ?? "") : selectedUsbSerial
                        guard !target.isEmpty else { return }
                        wifi.enableWifi(serial: target)
                    }
                    .disabled(wifi.busy || (selectedUsbSerial.isEmpty && presetSerial == nil))
                }
            }

            // 2) 수동 연결
            sectionCard(L10n.string("wifi.section.manual")) {
                TextField(
                    "",
                    text: $manualEndpoint,
                    prompt: Text(L10n.string("wifi.endpoint.placeholder"))
                )
                .textFieldStyle(.plain)
                .font(OPFont.body(13))
                .foregroundStyle(OPColor.ink)
                .padding(8)
                .background(OPColor.popBG, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(OPColor.border, lineWidth: 1))
                OPSecondaryButton(title: L10n.string("wifi.connect.action")) {
                    wifi.connect(endpoint: manualEndpoint)
                }
                .disabled(wifi.busy)
            }

            // 3) 연결 해제
            if !networkDevices.isEmpty {
                sectionCard(L10n.string("wifi.section.disconnect")) {
                    ForEach(networkDevices, id: \.serial) { d in
                        HStack {
                            Text(d.serial)
                                .font(OPFont.number(12))
                                .foregroundStyle(OPColor.ink)
                            Spacer()
                            Button(L10n.string("wifi.disconnect.action")) {
                                wifi.disconnect(serial: d.serial)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(wifi.busy)
                        }
                    }
                }
            }

            if let msg = wifi.statusMessage {
                Text(msg)
                    .font(OPFont.body(12))
                    .foregroundStyle(wifi.statusIsError ? OPColor.bad : OPColor.ok)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                OPSecondaryButton(title: L10n.string("alerts.note.cancel")) {
                    dismiss()
                }
                if wifi.busy {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .padding(OPSpace.xl)
        .frame(minWidth: 420, minHeight: 380)
        .preferredColorScheme(.dark)
        .onAppear {
            if selectedUsbSerial.isEmpty {
                if let p = presetSerial, usbDevices.contains(where: { $0.serial == p }) {
                    selectedUsbSerial = p
                } else {
                    selectedUsbSerial = usbDevices.first?.serial ?? presetSerial ?? ""
                }
            }
            if let kind = connectionKind, kind == .network, let p = presetSerial {
                manualEndpoint = p
            }
        }
    }

    private func sectionCard(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(OPFont.body(12))
                .foregroundStyle(OPColor.inkDim)
            content()
        }
        .padding(OPSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPColor.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(OPColor.border, lineWidth: 1))
    }

    private func displayName(_ d: DeviceSnapshot) -> String {
        AdbClient.displayDeviceName(deviceName: d.deviceName, model: d.model, serial: d.serial)
    }

    private func displayNameById(_ serial: String) -> String {
        if let d = store.inventory.device(serial: serial) {
            return displayName(d)
        }
        return AdbClient.shortId(serial)
    }
}
