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
    /// Android 11+ 무선 디버깅 페어링 입력 (PLAN_wifi_pairing)
    @State private var pairEndpoint = ""
    @State private var pairCode = ""
    /// 마지막 연결 — 탭하면 입력칸에 채움 (재시작 기억상실 방지용 영속값)
    @AppStorage("relay.wifi.lastEndpoint") private var lastEndpoint = ""

    private var usbDevices: [DeviceSnapshot] {
        store.inventory.devices.filter { $0.connectionKind == .usb || $0.connectionKind == nil }
    }

    private var networkDevices: [DeviceSnapshot] {
        store.inventory.devices.filter { $0.connectionKind == .network }
    }

    /// 이 시트가 **무선 기기에서** 열렸는가 — USB→Wi-Fi 섹션은 "이미 Wi-Fi" 안내만 보여준다
    ///
    /// (`adb tcpip 5555` 는 adbd 를 재시작해서 무선 연결을 끊을 수 있다 — 2026-10-18)
    private var presetIsNetworkDevice: Bool {
        guard let p = presetSerial else { return false }
        guard let d = store.inventory.devices.first(where: { $0.serial == p }) else {
            return connectionKind == .network
        }
        return d.connectionKind == .network
    }

    /// USB 로 붙어 있는(또는 아직 종류를 모르는) 기기인가 — 시트 1번 섹션 대상 판정
    private func isUsbDevice(_ serial: String) -> Bool {
        guard let d = store.inventory.devices.first(where: { $0.serial == serial }) else { return false }
        return WifiAdbLogic.canEnableTcpip(connectionKind: d.connectionKind)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSpace.lg) {
            Text(L10n.string("wifi.sheet.title"))
                .font(OPFont.title(16))
                .foregroundStyle(OPColor.ink)

            // 1) USB → Wi-Fi 원클릭 — **대상은 USB 기기만** (2026-10-18 수정)
            //
            //   이 버튼은 `adb tcpip 5555` = adbd 재시작이라, 무선 기기에 눌리면 **지금 붙어 있는
            //   무선 연결을 끊는다**. 종전엔 시트를 무선 기기에서 열면 그 기기가 대상으로 보였다.
            sectionCard(L10n.string("wifi.section.enable")) {
                if usbDevices.isEmpty {
                    Text(L10n.string(presetIsNetworkDevice ? "wifi.enable.alreadyNetwork" : "wifi.enable.noUsb"))
                        .font(OPFont.body(12))
                        .foregroundStyle(OPColor.inkDim)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    if usbDevices.count > 1 {
                        Picker(L10n.string("wifi.field.device"), selection: $selectedUsbSerial) {
                            ForEach(usbDevices, id: \.serial) { d in
                                Text(displayName(d)).tag(d.serial)
                            }
                            // 인벤토리 반영이 늦을 때의 폴백 — **USB 기기일 때만** 올린다
                            // (무선 기기를 여기 올리면 adb tcpip 5555 로 무선 연결을 끊을 수 있다)
                            if let p = presetSerial, isUsbDevice(p),
                               !usbDevices.contains(where: { $0.serial == p }) {
                                Text(store.identLabel(for: p)).tag(p)
                            }
                        }
                        .labelsHidden()
                    } else if let only = usbDevices.first {
                        Text(displayName(only))
                            .font(OPFont.body(12))
                            .foregroundStyle(OPColor.ink)
                    }
                    OPPrimaryButton(title: L10n.string("wifi.enable.action")) {
                        let target = selectedUsbSerial.isEmpty
                            ? (usbDevices.first?.serial ?? "")
                            : selectedUsbSerial
                        guard !target.isEmpty else { return }
                        wifi.enableWifi(serial: target)
                    }
                    .disabled(wifi.busy || (selectedUsbSerial.isEmpty && usbDevices.isEmpty))
                }
            }

            // 2) Android 11+ 무선 디버깅 페어링 — USB 없이 첫 연결 (PLAN_wifi_pairing)
            sectionCard(L10n.string("wifi.pair.section")) {
                Text(L10n.string("wifi.pair.steps"))
                    .font(OPFont.body(10))
                    .foregroundStyle(OPColor.inkDim)
                    .fixedSize(horizontal: false, vertical: true)

                if !wifi.mdnsServices.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.string("wifi.pair.discovered"))
                            .font(OPFont.body(10))
                            .foregroundStyle(OPColor.inkDim)
                        // id: \.instance 로는 안 된다 — 한 폰이 connect·pairing 을 같은 인스턴스 이름으로
                        // 광고한다(실측). 그대로 쓰면 페어링 줄이 사라지고 connect 줄이 두 번 그려진다.
                        ForEach(WifiAdbLogic.displayOrdered(wifi.mdnsServices)) { s in
                            discoveredRow(s)
                        }
                    }
                }

                if let at = wifi.mdnsLastRefresh {
                    Text(L10n.format("wifi.pair.lastLookup", WifiAdbController.clockText(at), wifi.mdnsServices.count))
                        .font(OPFont.body(10))
                        .foregroundStyle(wifi.mdnsServices.isEmpty ? OPColor.inkDim : OPColor.ok)
                }

                HStack(spacing: 8) {
                    TextField(
                        "",
                        text: $pairCode,
                        prompt: Text(L10n.string("wifi.pair.code.placeholder"))
                    )
                    .textFieldStyle(.plain)
                    .font(OPFont.number(13))
                    .foregroundStyle(OPColor.ink)
                    .padding(8)
                    .frame(width: 130)
                    .background(OPColor.popBG, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(OPColor.border, lineWidth: 1))

                    TextField(
                        "",
                        text: $pairEndpoint,
                        prompt: Text(L10n.string("wifi.pair.endpoint.placeholder"))
                    )
                    .textFieldStyle(.plain)
                    .font(OPFont.body(13))
                    .foregroundStyle(OPColor.ink)
                    .padding(8)
                    .background(OPColor.popBG, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(OPColor.border, lineWidth: 1))
                }

                HStack(spacing: 8) {
                    OPPrimaryButton(title: L10n.string("wifi.pair.action")) {
                        wifi.pair(endpoint: pairEndpoint, code: pairCode)
                    }
                    .disabled(wifi.busy || pairCode.isEmpty || pairEndpoint.isEmpty)

                    OPSecondaryButton(title: L10n.string("wifi.pair.refresh")) {
                        wifi.lookupMdns()
                    }
                    .disabled(wifi.busy)

                    if wifi.busy {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let msg = wifi.pairStatus {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: wifi.pairStatusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(wifi.pairStatusIsError ? OPColor.bad : OPColor.ok)
                        Text(msg)
                            .font(OPFont.body(11))
                            .foregroundStyle(wifi.pairStatusIsError ? OPColor.bad : OPColor.ok)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        (wifi.pairStatusIsError ? OPColor.bad : OPColor.ok).opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }

                Text(L10n.string("wifi.pair.hint"))
                    .font(OPFont.body(10))
                    .foregroundStyle(OPColor.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
                // 약속(hint)과 한계(rebootNote)를 **각각 자기 줄**로 둔다 — 한 문장으로 이어 붙이면
                // 창 폭에 따라 뒤 문장이 잘려 안 보인다 (실측: 재부팅 안내가 잘렸다).
                Text(L10n.string("wifi.pair.rebootNote"))
                    .font(OPFont.body(10))
                    .foregroundStyle(OPColor.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 3) 수동 연결
            sectionCard(L10n.string("wifi.section.manual")) {
                if !lastEndpoint.isEmpty {
                    Button(L10n.format("wifi.manual.last", lastEndpoint)) {
                        manualEndpoint = lastEndpoint
                    }
                    .buttonStyle(.plain)
                    .font(OPFont.number(12))
                    .foregroundStyle(OPColor.cta)
                }
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
                Text(L10n.string("wifi.manual.pairHint"))
                    .font(OPFont.body(10))
                    .foregroundStyle(OPColor.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 4) 연결 해제
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
        .frame(minWidth: 420, minHeight: 480)
        .preferredColorScheme(ThemeManager.shared.mode.preferred)
        .task {
            // 무선 디버깅 기기·페어링 창이 열린 기기를 미리 보여준다(수동 입력을 줄인다)
            await wifi.refreshMdnsServices()
        }
        .onAppear {
            // 재오픈 시 지난 성공/실패 메시지가 새 상태처럼 보이지 않도록 초기화 (AGENTS.local §4 [표시②])
            wifi.statusMessage = nil
            wifi.statusIsError = false
            wifi.pairStatus = nil
            wifi.pairStatusIsError = false
            if pairEndpoint.isEmpty,
               let first = WifiAdbLogic.pairingEndpoints(wifi.mdnsServices).first {
                pairEndpoint = first
            }
            if selectedUsbSerial.isEmpty {
                if let p = presetSerial, usbDevices.contains(where: { $0.serial == p }) {
                    selectedUsbSerial = p
                } else {
                    // **무선 기기를 대상으로 삼지 않는다** — 이 섹션은 USB 기기 전용 (2026-10-18)
                    selectedUsbSerial = usbDevices.first?.serial ?? ""
                }
            }
            if let kind = connectionKind, kind == .network, let p = presetSerial {
                manualEndpoint = p
            }
        }
    }

    /// 발견된 광고 한 줄
    ///
    /// 페어링 줄을 누르면 주소가 채워진다(그리고 페어링 포트가 아닌 주소를 넣는 흔한 실수를 막는다).
    /// connect 줄은 **바로 연결**할 수 있다 — 무선 디버깅만 켠 기기는 페어링 없이도 붙는 경우가 많다.
    @ViewBuilder
    private func discoveredRow(_ s: WifiAdbLogic.MdnsService) -> some View {
        HStack(spacing: 6) {
            Button {
                if s.isPairing {
                    pairEndpoint = s.endpoint
                } else {
                    manualEndpoint = s.endpoint
                }
            } label: {
                Text("\(s.isPairing ? L10n.string("wifi.pair.kind.pairing") : L10n.string("wifi.pair.kind.connect")) · \(s.endpoint)")
                    .font(OPFont.number(11))
                    .foregroundStyle(OPColor.cta)
            }
            .buttonStyle(.plain)
            .help(L10n.string("wifi.pair.discovered.help"))

            Spacer(minLength: 4)

            if s.isPairing {
                Text(L10n.string("wifi.pair.row.fill"))
                    .font(OPFont.body(10))
                    .foregroundStyle(OPColor.inkDim)
            } else {
                Button(L10n.string("wifi.pair.connect.action")) {
                    wifi.connect(endpoint: s.endpoint)
                }
                .buttonStyle(.plain)
                .font(OPFont.body(10))
                .foregroundStyle(OPColor.cta)
                .disabled(wifi.busy)
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
        d.identLabel
    }

    private func displayNameById(_ serial: String) -> String {
        store.identLabel(for: serial)
    }
}
