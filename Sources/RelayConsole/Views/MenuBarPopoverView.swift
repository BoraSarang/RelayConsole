import SwiftUI

struct MenuBarPopoverView: View {
    @ObservedObject var store: ConsoleStore
    var openConsole: () -> Void
    var openDebug: () -> Void = {}

    @State private var showDeviceDetail = false
    @State private var showEvents = true

    private var device: DeviceSnapshot? { store.inventory.devices.first }
    private var metrics: DroidMetrics? {
        device.map { store.metrics(for: $0.serial) }
    }

    var body: some View {
        // SOLID root — macOS 26 red/rainbow hotfix
        // 구조: 고정 헤더 + 스크롤 중간 + 고정 푸터
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
                    VStack(alignment: .leading, spacing: 12) {
                        if let d = device, d.isThermalAlert {
                            thermalBanner(device: d)
                        }
                        cards
                        deviceDetailSection
                        eventsSection
                    }
                    .padding(OPSpace.lg)
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
                if let d = device, let level = d.batteryLevel {
                    Text("\(level)%")
                        .font(OPFont.number(11))
                        .foregroundStyle(OPColor.inkDim)
                }
                Text("0.1.0")
                    .font(OPFont.number(10))
                    .foregroundStyle(OPColor.inkDim)
            }

            HStack(spacing: 8) {
                if let d = device {
                    Text(d.model.isEmpty ? L10n.na : d.model)
                        .font(OPFont.body(12))
                        .foregroundStyle(OPColor.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !d.serial.isEmpty {
                        Text(AdbClient.shortId(d.serial))
                            .font(OPFont.number(11))
                            .foregroundStyle(OPColor.inkDim)
                    }
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
                    .help(L10n.string("menubar.device.detail"))
                } else {
                    Text(L10n.string("droid.empty.noDevice"))
                        .font(OPFont.body(12))
                        .foregroundStyle(OPColor.inkDim)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
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

    // MARK: - Cards

    private var cards: some View {
        VStack(spacing: 12) {
            cardFull(
                L10n.string("droid.card.cpu.title"),
                cpuValue,
                showBar: device?.cpuUsePercent,
                spark: metrics?.cpuHistory,
                sparkColor: OPColor.cta
            )
            HStack(spacing: 12) {
                cardMini(L10n.string("droid.card.memory.title"), memoryValue)
                cardMini(L10n.string("droid.card.storage.title"), storageValue)
            }
            cardFull(
                L10n.string("droid.card.battery.title"),
                batteryValue,
                sub: batterySubline,
                spark: metrics?.levelHistory,
                sparkColor: OPColor.ok
            )
            cardFull(
                L10n.string("droid.card.network.title"),
                networkValue,
                sub: networkSubline,
                spark: metrics?.netHistory,
                sparkColor: OPColor.cta
            )
            cardFull(
                L10n.string("droid.card.thermal.title"),
                thermalValue,
                spark: metrics?.tempHistory,
                sparkColor: OPColor.thermal,
                isThermal: true
            )
        }
    }

    // MARK: - Device detail (expand)

    private var deviceDetailSection: some View {
        Group {
            if showDeviceDetail, let d = device {
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
                    detailRow(L10n.string("menubar.device.adb"), AdbClient.shortId(d.serial))
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

    // MARK: - Events

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
                        .truncationMode(.tail)
                } else {
                    ForEach(Array(store.recentEvents.prefix(5).enumerated()), id: \.offset) { _, e in
                        Text(e)
                            .font(OPFont.body(12))
                            .foregroundStyle(OPColor.ink)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
        }
    }

    // MARK: - Footer (fixed)

    private var footer: some View {
        HStack(spacing: OPSpace.sm) {
            OPPrimaryButton(title: L10n.string("menubar.button.openConsole"), action: openConsole)
            OPSecondaryButton(title: L10n.string("menubar.button.debug"), action: openDebug)
            Spacer()
            SettingsLink {
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

    // MARK: - Values

    private var cpuValue: String {
        guard let d = device, let use = d.cpuUsePercent else { return L10n.na }
        var parts = ["\(L10n.string("menubar.cpu.8core"))", String(format: "%.0f%%", use)]
        if let t = d.deviceTempC ?? d.batteryTempC {
            parts.append(String(format: "%.0f°C", t))
        }
        if let l = d.load1 {
            parts.append(String(format: "load %.2f", l))
        }
        return parts.joined(separator: " ")
    }

    private var memoryValue: String {
        guard let d = device,
              let used = d.memoryUsedGB,
              let total = d.memoryTotalGB else { return "\(L10n.na) / \(L10n.na)" }
        return String(format: "%.1f/%.0f", used, total)
    }

    private var storageValue: String {
        guard let d = device,
              let used = d.storageUsedGB,
              let total = d.storageTotalGB else { return "\(L10n.na) / \(L10n.na)" }
        return String(format: "%.0f/%.0f", used, total)
    }

    private var batteryValue: String {
        guard let d = device, let level = d.batteryLevel else { return L10n.na }
        var parts = ["\(level)%"]
        if let t = d.batteryTempC {
            parts.append(String(format: "%.0f°C", t))
        }
        if d.isCharging == true {
            parts.append(L10n.string("droid.card.battery.charging"))
        } else if d.isCharging == false {
            // nil이면 표시 없음 (P0-b)
        }
        return parts.joined(separator: " ")
    }

    /// H · V · Cycle · 보호모드 — 있으면만
    private var batterySubline: String? {
        guard let d = device else { return nil }
        var parts: [String] = []
        if let h = d.batteryHealthPct {
            parts.append("H \(h)%")
        }
        if let v = d.voltageMV {
            parts.append(String(format: "%.2fV", Double(v) / 1000.0))
        }
        if let c = d.cycleEstimate {
            parts.append(L10n.format("menubar.battery.cycle", c))
        }
        if d.isProtectionMode == true {
            var p = L10n.string("droid.card.battery.protection")
            if let th = d.protectionThresholdPct {
                p += " \(th)%"
            }
            parts.append(p)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var networkValue: String {
        device?.networkInfo ?? L10n.na
    }

    private var networkSubline: String? {
        guard let d = device, let t = d.networkType, !t.isEmpty else { return nil }
        return t
    }

    private var thermalValue: String {
        guard let d = device else { return L10n.na }
        var parts: [String] = []
        if let s = d.thermalStatus { parts.append("Status \(s)") }
        if let t = d.deviceTempC ?? d.batteryTempC {
            parts.append(String(format: "%.1f°C", t))
        }
        return parts.isEmpty ? L10n.na : parts.joined(separator: " ")
    }

    // MARK: - Card chrome

    private func cardFull(
        _ title: String,
        _ value: String,
        sub: String? = nil,
        showBar: Double? = nil,
        spark: [Double]? = nil,
        sparkColor: Color = OPColor.cta,
        isThermal: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(OPFont.body(10))
                .foregroundStyle(isThermal ? OPColor.thermal : OPColor.inkDim)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(value)
                .font(OPFont.number(13))
                .foregroundStyle(OPColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .truncationMode(.tail)
            if let sub {
                Text(sub)
                    .font(OPFont.number(11))
                    .foregroundStyle(OPColor.inkDim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .truncationMode(.tail)
            }
            if let use = showBar {
                ProgressView(value: use, total: 100)
                    .progressViewStyle(.linear)
                    .tint(isThermal ? OPColor.thermal : OPColor.cta)
                    .frame(height: 3)
            }
            OPSparkline(
                points: spark ?? [],
                color: sparkColor,
                height: 14
            )
            .frame(height: 14)
        }
        .padding(OPSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: 0x1C1F2A))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func cardMini(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(OPFont.body(10))
                .foregroundStyle(OPColor.inkDim)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(value)
                .font(OPFont.number(13))
                .foregroundStyle(OPColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSpace.md)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: 0x1C1F2A))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
