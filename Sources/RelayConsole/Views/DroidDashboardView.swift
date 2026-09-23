import SwiftUI

struct DroidDashboardView: View {
    @ObservedObject var store: ConsoleStore

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
                        Text(L10n.string("droid.empty.noDevice"))
                            .font(OPFont.body(14))
                            .foregroundStyle(OPColor.inkDim)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, OPSpace.xl)
                    } else {
                        header
                        if devices.count > 1 {
                            devicePicker
                        }
                        if let d = device, d.isThermalAlert {
                            thermalBanner(device: d)
                        }
                    }
                    LazyVGrid(columns: columns, spacing: 16) {
                        cardCPU
                        cardMemory
                        cardBattery
                        cardNetwork
                        cardThermal
                        cardStorage
                    }
                    footer
                }
                .padding(OPSpace.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(hex: 0x0F111A))
        .preferredColorScheme(.dark)
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

    // MARK: - Cards

    private var cardCPU: some View {
        cardShell(L10n.string("droid.card.cpu.title"), accent: OPColor.inkDim) {
            Text(cpuValue)
                .font(OPFont.number(16))
                .foregroundStyle(OPColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .truncationMode(.tail)
            if let use = device?.cpuUsePercent {
                ProgressView(value: use, total: 100)
                    .progressViewStyle(.linear)
                    .tint(OPColor.cta)
                    .frame(height: 4)
            }
            if let freqs = device?.coreFreqsMHz, !freqs.isEmpty {
                coreBars(freqs: freqs, maxes: device?.coreMaxMHz ?? [], uses: device?.coreUsePercents ?? [])
            }
            if let g = device?.cpuGovernor {
                Text(g)
                    .font(OPFont.number(10))
                    .foregroundStyle(OPColor.inkDim)
            }
            OPSparkline(points: metrics?.cpuHistory ?? [], color: OPColor.cta, height: 24)
                .frame(height: 24)
        }
    }

    private func coreBars(freqs: [Double], maxes: [Double], uses: [Double]) -> some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(freqs.enumerated()), id: \.offset) { i, freq in
                VStack(spacing: 2) {
                    GeometryReader { geo in
                        let maxF = i < maxes.count && maxes[i] > 0 ? maxes[i] : max(freq, 1)
                        let ratio = CGFloat(min(1, max(0, freq / maxF)))
                        VStack {
                            Spacer()
                            RoundedRectangle(cornerRadius: 2)
                                .fill(OPColor.cta.opacity(0.75))
                                .frame(height: max(3, geo.size.height * ratio))
                        }
                    }
                    .frame(height: 28)
                    Text("C\(i)")
                        .font(OPFont.number(7))
                        .foregroundStyle(OPColor.inkDim)
                }
            }
        }
        .frame(height: 40)
    }

    private var cardMemory: some View {
        cardShell(L10n.string("droid.card.memory.title")) {
            Text(memoryValue)
                .font(OPFont.number(16))
                .foregroundStyle(OPColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let used = device?.memoryUsedGB, let total = device?.memoryTotalGB, total > 0 {
                ProgressView(value: used, total: total)
                    .progressViewStyle(.linear)
                    .tint(pressureColor)
                    .frame(height: 4)
                if let label = device?.memPressureLabel {
                    Text(L10n.format("droid.card.memory.pressure", label))
                        .font(OPFont.number(10))
                        .foregroundStyle(pressureColor)
                }
            }
            if let top = device?.topProcesses, !top.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(top.enumerated()), id: \.offset) { _, p in
                        HStack {
                            Text(p.name)
                                .font(OPFont.number(10))
                                .foregroundStyle(OPColor.ink.opacity(0.75))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(String(format: "%.0f MB", p.rssMB))
                                .font(OPFont.number(10))
                                .foregroundStyle(OPColor.inkDim)
                        }
                    }
                }
            }
        }
    }

    private var pressureColor: Color {
        switch device?.memPressureLabel {
        case "none", nil: return OPColor.cta
        case "low": return OPColor.ok
        case "moderate": return OPColor.thermalSoft
        default: return OPColor.thermal
        }
    }

    private var cardBattery: some View {
        cardShell(L10n.string("droid.card.battery.title")) {
            Text(batteryValue)
                .font(OPFont.number(16))
                .foregroundStyle(OPColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            batteryGrid
            OPSparkline(points: metrics?.levelHistory ?? [], color: OPColor.ok, height: 24)
                .frame(height: 24)
        }
    }

    private var batteryGrid: some View {
        let d = device
        let cells: [(String, String)] = [
            (L10n.string("droid.battery.health"), d?.batteryHealthPct.map { "\($0)%" } ?? L10n.na),
            (L10n.string("droid.battery.voltage"), d?.voltageMV.map { String(format: "%.2fV", Double($0) / 1000) } ?? L10n.na),
            (L10n.string("droid.battery.cycles"), d?.cycleEstimate.map(String.init) ?? L10n.na),
            (L10n.string("menubar.alert.thermal"), d?.batteryTempC.map { String(format: "%.1f°C", $0) } ?? L10n.na),
            (L10n.string("droid.battery.current"), L10n.na),
            (L10n.string("droid.battery.type"), L10n.na)
        ]
        return LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6)
        ], spacing: 6) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                VStack(spacing: 2) {
                    Text(cell.0)
                        .font(OPFont.number(8))
                        .foregroundStyle(OPColor.inkDim.opacity(0.75))
                        .lineLimit(1)
                    Text(cell.1)
                        .font(OPFont.number(12))
                        .foregroundStyle(OPColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.03))
                )
            }
        }
    }

    private var cardNetwork: some View {
        cardShell(L10n.string("droid.card.network.title")) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string("droid.card.network.up"))
                        .font(OPFont.body(9))
                        .foregroundStyle(OPColor.inkDim)
                    Text(device?.netUpMBps.map { String(format: "%.1f", $0) } ?? L10n.na)
                        .font(OPFont.number(16))
                        .foregroundStyle(OPColor.cta)
                    Text("MB/s")
                        .font(OPFont.number(9))
                        .foregroundStyle(OPColor.inkDim)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(L10n.string("droid.card.network.down"))
                        .font(OPFont.body(9))
                        .foregroundStyle(OPColor.inkDim)
                    Text(device?.netDownMBps.map { String(format: "%.1f", $0) } ?? L10n.na)
                        .font(OPFont.number(16))
                        .foregroundStyle(OPColor.thermalSoft)
                    Text("MB/s")
                        .font(OPFont.number(9))
                        .foregroundStyle(OPColor.inkDim)
                }
            }
            if let sub = networkSubline {
                Text(sub)
                    .font(OPFont.number(11))
                    .foregroundStyle(OPColor.inkDim)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            OPSparkline(points: metrics?.netHistory ?? [], color: OPColor.cta, height: 24)
                .frame(height: 24)
        }
    }

    private var networkSubline: String? {
        guard let d = device else { return nil }
        var parts: [String] = []
        if let ssid = d.wifiSsid {
            parts.append(ssid)
            if let rssi = d.wifiRssi { parts.append("\(rssi) dBm") }
        } else if d.networkType == "Wi-Fi" {
            parts.append(L10n.string("droid.card.network.wifiOff"))
        } else if let op = d.signalOperator {
            parts.append(op)
            if let rsrp = d.rsrp { parts.append("RSRP \(rsrp)") }
        }
        if let ip = d.ipV4 { parts.append(ip) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var cardThermal: some View {
        cardShell(L10n.string("droid.card.thermal.title"), accent: OPColor.thermal) {
            HStack(spacing: 8) {
                Text(thermalValue)
                    .font(OPFont.number(16))
                    .foregroundStyle(OPColor.thermal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                if let s = device?.thermalStatus {
                    Text("\(s)")
                        .font(OPFont.number(14))
                        .foregroundStyle(thermalStatusColor(s))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(thermalStatusColor(s).opacity(0.15))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(thermalStatusColor(s).opacity(0.4), lineWidth: 1)
                        )
                }
            }
            if let zones = device?.thermalZones, !zones.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(zones.prefix(8).enumerated()), id: \.offset) { _, z in
                        HStack(spacing: 6) {
                            Text(z.name)
                                .font(OPFont.number(10))
                                .foregroundStyle(OPColor.inkDim)
                                .frame(width: 64, alignment: .leading)
                            GeometryReader { geo in
                                let ratio = CGFloat(min(1, max(0, z.tempC / 80.0)))
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.white.opacity(0.06))
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(z.tempC >= 45 ? OPColor.thermal : OPColor.ok.opacity(0.7))
                                        .frame(width: geo.size.width * ratio)
                                }
                            }
                            .frame(height: 5)
                            Text(String(format: "%.1f°C", z.tempC))
                                .font(OPFont.number(10))
                                .foregroundStyle(OPColor.ink)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }
            }
            OPSparkline(points: metrics?.tempHistory ?? [], color: OPColor.thermal, height: 24)
                .frame(height: 24)
        }
    }

    private func thermalStatusColor(_ s: Int) -> Color {
        if s <= 1 { return OPColor.ok }
        if s == 2 { return OPColor.thermalSoft }
        return OPColor.thermal
    }

    private var cardStorage: some View {
        cardShell(L10n.string("droid.card.storage.title")) {
            Text(storageValue)
                .font(OPFont.number(16))
                .foregroundStyle(OPColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let used = device?.storageUsedGB, let total = device?.storageTotalGB, total > 0 {
                ProgressView(value: used, total: total)
                    .progressViewStyle(.linear)
                    .tint(OPColor.cta)
                    .frame(height: 4)
                let remain = total - used
                Text(L10n.format(
                    "droid.storage.remain",
                    String(format: "%.0f GB", remain)
                ))
                .font(OPFont.number(11))
                .foregroundStyle(OPColor.inkDim)
            }
        }
    }

    private func cardShell(
        _ title: String,
        accent: Color = OPColor.inkDim,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(OPFont.body(11))
                .foregroundStyle(accent)
                .lineLimit(1)
                .truncationMode(.tail)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSpace.lg)
        .background(OPColor.card, in: RoundedRectangle(cornerRadius: OPSpace.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: OPSpace.radiusCard).stroke(OPColor.border, lineWidth: 1))
    }

    // MARK: - Values

    private var cpuValue: String {
        guard let d = device, let use = d.cpuUsePercent else { return L10n.na }
        var parts = [String(format: "%.0f%%", use)]
        if let t = d.deviceTempC ?? d.batteryTempC {
            parts.append(String(format: "%.0f°C", t))
        }
        if let l = d.load1 {
            parts.append(String(format: "load %.2f", l))
        }
        if let l5 = d.load5, let l15 = d.load15 {
            parts.append(String(format: "· %.2f %.2f", l5, l15))
        }
        return parts.joined(separator: " · ")
    }

    private var memoryValue: String {
        guard let d = device,
              let used = d.memoryUsedGB,
              let total = d.memoryTotalGB else { return "\(L10n.na) / \(L10n.na)" }
        return String(format: "%.1f / %.0f GB", used, total)
    }

    private var storageValue: String {
        guard let d = device,
              let used = d.storageUsedGB,
              let total = d.storageTotalGB else { return "\(L10n.na) / \(L10n.na)" }
        return String(format: "%.0f / %.0f GB", used, total)
    }

    private var batteryValue: String {
        guard let d = device, let level = d.batteryLevel else { return L10n.na }
        var parts = ["\(level)%"]
        if let t = d.batteryTempC {
            parts.append(String(format: "%.1f°C", t))
        }
        if d.isCharging == true {
            parts.append(L10n.string("droid.card.battery.charging"))
        }
        return parts.joined(separator: " ")
    }

    private var thermalValue: String {
        guard let d = device else { return L10n.na }
        var parts: [String] = []
        if let t = d.deviceTempC ?? d.batteryTempC {
            parts.append(String(format: "%.1f°C", t))
        }
        return parts.isEmpty ? L10n.na : parts.joined(separator: " ")
    }

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
    }
}
