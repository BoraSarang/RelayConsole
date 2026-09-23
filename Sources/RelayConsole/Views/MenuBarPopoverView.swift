import SwiftUI

struct MenuBarPopoverView: View {
    @ObservedObject var store: ConsoleStore
    var openConsole: () -> Void
    var openDebug: () -> Void = {}
    var openSettings: () -> Void = {}

    @State private var showDeviceDetail = false
    @State private var showEvents = false
    /// 메뉴바는 아이콘만 — 기기 수는 팝오버에서만 (설정 토글)
    @AppStorage("relay.menubarMetrics") private var menubarMetrics = true

    private var devices: [DeviceSnapshot] { store.inventory.devices }
    private var device: DeviceSnapshot? { store.selectedDevice }
    private var metrics: DroidMetrics? {
        device.map { store.metrics(for: $0.serial) }
    }
    private var multiDevice: Bool { devices.count > 1 }

    var body: some View {
        ZStack {
            Color(hex: 0x0F111A).ignoresSafeArea()
            VStack(spacing: 0) {
                headerBlock
                    .padding(.horizontal, OPSpace.lg)
                    .padding(.top, OPSpace.lg)
                    .padding(.bottom, OPSpace.sm)
                    .background(Color(hex: 0x0F111A))

                Divider().overlay(OPColor.border)

                ScrollView(.vertical, showsIndicators: true) {
                    if device == nil {
                        emptyState
                            .frame(maxWidth: .infinity)
                            .padding(.top, 72)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            if let d = device, d.isThermalAlert {
                                thermalBanner(device: d)
                            }
                            // 기기 상세 ⌄ → 상세 + 대시보드 카드
                            if showDeviceDetail {
                                deviceExpandSection
                                cards
                                eventsSection
                            } else {
                                Text(L10n.string("menubar.device.detailHint"))
                                    .font(OPFont.body(12))
                                    .foregroundStyle(OPColor.inkDim)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.top, 48)
                            }
                        }
                        .padding(OPSpace.lg)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider().overlay(OPColor.border)

                footer
                    .padding(.horizontal, OPSpace.lg)
                    .padding(.vertical, OPSpace.md)
                    .background(Color(hex: 0x0F111A))
            }
        }
        .frame(width: 360, height: 560)
        .background(Color(hex: 0x0F111A))
        .preferredColorScheme(.dark)
    }

    // MARK: - Header (fixed)

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                StatusDot(state: device?.isOnline == true ? .ok : (device == nil ? .idle : .bad))
                Text(L10n.string("menubar.label"))
                    .font(OPFont.title(13))
                    .foregroundStyle(OPColor.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if menubarMetrics && !devices.isEmpty {
                    Text("\(devices.filter(\.isOnline).count)/\(devices.count)")
                        .font(OPFont.number(11))
                        .foregroundStyle(OPColor.inkDim)
                        .lineLimit(1)
                }
                if let d = device, let level = d.batteryLevel {
                    Text("\(level)%")
                        .font(OPFont.number(11))
                        .foregroundStyle(OPColor.inkDim)
                }
                Text("0.4.0")
                    .font(OPFont.number(10))
                    .foregroundStyle(OPColor.inkDim)
            }

            HStack(spacing: 8) {
                if let d = device {
                    // 기기 이름 (deviceName > model)
                    Text(d.displayName)
                        .font(OPFont.body(12))
                        .foregroundStyle(OPColor.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    // 연결 종류: USB | IP:5555
                    connectionBadge(d)
                    StatusDot(state: d.isOnline ? .ok : .bad)
                    Text(d.isOnline
                        ? L10n.string("menubar.status.connected")
                        : L10n.string("menubar.status.disconnected"))
                        .font(OPFont.body(11))
                        .foregroundStyle(d.isOnline ? OPColor.ok : OPColor.bad)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showDeviceDetail.toggle()
                        }
                    } label: {
                        Image(systemName: showDeviceDetail ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(OPColor.inkDim)
                            .frame(width: 20, height: 16)
                            .background(OPColor.card, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help(multiDevice
                        ? L10n.string("menubar.device.list")
                        : L10n.string("menubar.device.detail"))
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func connectionBadge(_ d: DeviceSnapshot) -> some View {
        Text(d.connectionLabel ?? L10n.na)
            .font(OPFont.number(9))
            .foregroundStyle(d.connectionKind == .network ? OPColor.cta : OPColor.inkDim)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(OPColor.card, in: RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(OPColor.border, lineWidth: 1)
            )
    }

    // MARK: - Device list / detail expand

    /// 헤더 ⌄ 펼침 — 다중: 기기 목록 / 단일: 상세 3줄
    private var deviceExpandSection: some View {
        Group {
            if multiDevice {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("menubar.device.list"))
                        .font(OPFont.body(10))
                        .foregroundStyle(OPColor.inkDim)
                    ForEach(devices, id: \.serial) { d in
                        deviceRow(d)
                    }
                }
                .padding(OPSpace.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(OPColor.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(OPColor.border, lineWidth: 1)
                )
            } else if let d = device {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string("menubar.device.detail"))
                        .font(OPFont.body(10))
                        .foregroundStyle(OPColor.inkDim)
                    detailRow(L10n.string("menubar.device.model"), d.model.isEmpty ? L10n.na : d.model)
                    detailRow(
                        L10n.string("menubar.device.android"),
                        [d.androidVersion, d.sdkInt.map { "SDK \($0)" } ?? nil]
                            .compactMap { $0 }
                            .joined(separator: " · ")
                            .isEmpty ? L10n.na
                            : [d.androidVersion, d.sdkInt.map { "SDK \($0)" } ?? nil]
                                .compactMap { $0 }
                                .joined(separator: " · ")
                    )
                    detailRow(L10n.string("menubar.device.adb"), adbValue(d))
                }
                .padding(OPSpace.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(OPColor.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(OPColor.border, lineWidth: 1)
                )
            }
        }
    }

    /// 기기 행 클릭 → 선택 + 콘솔 대시보드 (PLAN_v0.3)
    private func deviceRow(_ d: DeviceSnapshot) -> some View {
        let isSelected = d.serial == store.selectedSerial
        return Button {
            store.select(d.serial)
            openConsole()
        } label: {
            HStack(spacing: 8) {
                StatusDot(state: d.isOnline ? (isSelected ? .ok : .ok) : .bad)
                Text(d.displayName)
                    .font(OPFont.body(12))
                    .foregroundStyle(OPColor.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(d.connectionLabel ?? L10n.na)
                    .font(OPFont.number(9))
                    .foregroundStyle(OPColor.inkDim)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let level = d.batteryLevel {
                    Text("\(level)%")
                        .font(OPFont.number(11))
                        .foregroundStyle(OPColor.inkDim)
                }
                if let t = d.deviceTempC ?? d.batteryTempC {
                    Text(String(format: "%.0f°", t))
                        .font(OPFont.number(11))
                        .foregroundStyle(OPColor.thermal)
                }
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(OPColor.cta)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? OPColor.cta.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func adbValue(_ d: DeviceSnapshot) -> String {
        d.connectionKind == .network ? (d.connectionLabel ?? d.serial) : AdbClient.shortId(d.serial)
    }

    // MARK: - Thermal banner

    private func thermalBanner(device d: DeviceSnapshot) -> some View {
        HStack(spacing: 6) {
            let temp = d.deviceTempC ?? d.batteryTempC
            Text("⚠ " + L10n.format(
                "menubar.alert.thermal",
                temp.map { String(format: "%.1f", $0) } ?? L10n.na
            ))
                .font(OPFont.body(11))
                .foregroundStyle(OPColor.thermal)
                .lineLimit(1)
                .truncationMode(.tail)
            if let s = d.thermalStatus, s >= 2 {
                Text("[\(L10n.string("menubar.alert.throttling"))]")
                    .font(OPFont.number(10))
                    .foregroundStyle(OPColor.thermalSoft)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            OPSparkline(
                points: metrics?.tempHistory ?? [],
                color: OPColor.thermal,
                height: 14
            )
            .frame(width: 72, height: 14)
        }
        .padding(OPSpace.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(OPColor.thermal.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(OPColor.thermal.opacity(0.3), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { openConsole() }
    }

    // MARK: - Cards (dashboard 동일 형식 — DroidCards 공유)

    private var cards: some View {
        VStack(spacing: 12) {
            DroidCards.cpu(device: device, metrics: metrics)
            DroidCards.gpu(device: device, metrics: metrics)
            DroidCards.memory(device: device, metrics: metrics)
            DroidCards.sensors(device: device, metrics: metrics)
            DroidCards.battery(device: device, metrics: metrics)
            DroidCards.network(device: device, metrics: metrics)
            DroidCards.thermal(device: device, metrics: metrics)
            DroidCards.storage(device: device, metrics: metrics)
        }
    }

    // MARK: - Empty (연결된 기기 없음)

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "cable.connector")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(OPColor.inkDim)
            Text(L10n.string("droid.empty.noDevice"))
                .font(OPFont.title(15))
                .foregroundStyle(OPColor.ink)
            Text(L10n.string("droid.empty.noDeviceBody"))
                .font(OPFont.body(12))
                .foregroundStyle(OPColor.inkDim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n.string("droid.empty.noDeviceHint"))
                .font(OPFont.number(11))
                .foregroundStyle(OPColor.inkDim.opacity(0.85))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(.horizontal, OPSpace.xl)
    }

    // MARK: - Detail rows

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(OPFont.body(11))
                .foregroundStyle(OPColor.inkDim)
            Spacer(minLength: 8)
            Text(value)
                .font(OPFont.number(11))
                .foregroundStyle(OPColor.ink)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    // MARK: - Events (접힘 기본 · 점3)

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showEvents.toggle()
                }
            } label: {
                HStack {
                    Text(L10n.format("menubar.events.recent", min(store.recentEvents.count, 5)))
                        .font(OPFont.body(11))
                        .foregroundStyle(OPColor.inkDim)
                    Spacer()
                    Image(systemName: showEvents ? "chevron.up" : "ellipsis")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(OPColor.inkDim)
                }
            }
            .buttonStyle(.plain)

            if showEvents {
                if store.recentEvents.isEmpty {
                    Text(L10n.string("menubar.events.empty"))
                        .font(OPFont.body(12))
                        .foregroundStyle(OPColor.inkDim)
                        .lineLimit(1)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(store.recentEvents.prefix(5).enumerated()), id: \.offset) { _, e in
                            HStack(alignment: .top, spacing: 6) {
                                Circle()
                                    .fill(OPColor.cta.opacity(0.7))
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 5)
                                Text(e)
                                    .font(OPFont.body(11))
                                    .foregroundStyle(OPColor.ink)
                                    .lineLimit(2)
                                    .truncationMode(.tail)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                    .padding(.leading, 2)
                }
            }
        }
    }

    // MARK: - Footer (fixed)

    private var footer: some View {
        HStack(spacing: OPSpace.sm) {
            if device != nil {
                OPPrimaryButton(title: L10n.string("menubar.button.openConsole"), action: openConsole)
            }
            OPSecondaryButton(title: L10n.string("menubar.button.debug"), action: openDebug)
            Spacer()
            Button(action: openSettings) {
                Image(systemName: "gearshape")
                    .foregroundStyle(OPColor.inkDim)
                    .frame(width: 32, height: 32)
                    .background(OPColor.card, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(OPColor.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help(L10n.string("settings.section.general"))
        }
    }
}
