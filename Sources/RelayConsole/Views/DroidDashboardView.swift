import SwiftUI

struct DroidDashboardView: View {
    @ObservedObject var store: ConsoleStore

    private let columns = [
        GridItem(.flexible(), spacing: 16, alignment: .top),
        GridItem(.flexible(), spacing: 16, alignment: .top)
    ]

    private var device: DeviceSnapshot? { store.inventory.devices.first }
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
            Text(device?.model.isEmpty == false ? device!.model : L10n.na)
                .font(OPFont.title(15))
                .foregroundStyle(OPColor.ink)
                .lineLimit(1)
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
            if let serial = device?.serial, !serial.isEmpty {
                Text(AdbClient.shortId(serial))
                    .font(OPFont.number(11))
                    .foregroundStyle(OPColor.inkDim)
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
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
            OPSparkline(points: metrics?.cpuHistory ?? [], color: OPColor.cta, height: 24)
                .frame(height: 24)
        }
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
                    .tint(OPColor.cta)
                    .frame(height: 4)
            }
        }
    }

    private var cardBattery: some View {
        cardShell(L10n.string("droid.card.battery.title")) {
            Text(batteryValue)
                .font(OPFont.number(16))
                .foregroundStyle(OPColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            OPSparkline(points: metrics?.levelHistory ?? [], color: OPColor.ok, height: 24)
                .frame(height: 24)
        }
    }

    private var cardNetwork: some View {
        cardShell(L10n.string("droid.card.network.title")) {
            Text(networkValue)
                .font(OPFont.number(16))
                .foregroundStyle(OPColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .truncationMode(.tail)
            OPSparkline(points: metrics?.netHistory ?? [], color: OPColor.cta, height: 24)
                .frame(height: 24)
        }
    }

    private var cardThermal: some View {
        cardShell(L10n.string("droid.card.thermal.title"), accent: OPColor.thermal) {
            Text(thermalValue)
                .font(OPFont.number(16))
                .foregroundStyle(OPColor.thermal)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .truncationMode(.tail)
            OPSparkline(points: metrics?.tempHistory ?? [], color: OPColor.thermal, height: 24)
                .frame(height: 24)
        }
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

    private var cpuValue: String {
        guard let d = device, let use = d.cpuUsePercent else { return L10n.na }
        var parts = [String(format: "%.0f%%", use)]
        if let t = d.deviceTempC ?? d.batteryTempC {
            parts.append(String(format: "%.0f°C", t))
        }
        if let l = d.load1 {
            parts.append(String(format: "load %.2f", l))
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
        if let v = d.voltageMV {
            parts.append(String(format: "%.2fV", Double(v) / 1000.0))
        }
        return parts.joined(separator: " ")
    }

    private var networkValue: String {
        device?.networkInfo ?? L10n.na
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

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.format("droid.footer.settingsChanged", 0))
                .font(OPFont.body(12))
                .foregroundStyle(OPColor.inkDim)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(L10n.format("droid.footer.logcatHits", 0))
                .font(OPFont.body(12))
                .foregroundStyle(OPColor.inkDim)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(OPSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPColor.card, in: RoundedRectangle(cornerRadius: 12))
    }
}
