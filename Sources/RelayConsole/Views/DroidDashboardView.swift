import SwiftUI

struct DroidDashboardView: View {
    @ObservedObject var store: ConsoleStore

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        ZStack {
            Color(hex: 0x0F111A).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: OPSpace.lg) {
                    header
                    LazyVGrid(columns: columns, spacing: 16) {
                        card(L10n.string("droid.card.cpu.title"), cpuValue)
                        card(L10n.string("droid.card.memory.title"), "\(L10n.na) / \(L10n.na)")
                        card(L10n.string("droid.card.battery.title"), L10n.na)
                        card(L10n.string("droid.card.network.title"), L10n.na)
                        cardTHERMAL
                        card(L10n.string("droid.card.storage.title"), "\(L10n.na) / \(L10n.na)")
                    }
                    footer
                }
                .padding(OPSpace.xl)
            }
        }
        .background(Color(hex: 0x0F111A))
        .preferredColorScheme(.dark)
    }

    private var cpuValue: String {
        guard let device = store.inventory.devices.first,
              let use = device.cpuUsePercent else { return L10n.na }
        return String(format: "%.0f%%", use)
    }

    private var header: some View {
        let device = store.inventory.devices.first
        return HStack {
            StatusDot(state: device?.isOnline == true ? .ok : .idle)
            Text(device?.model ?? "SM_S901N")
                .font(OPFont.title(16))
                .foregroundStyle(OPColor.ink)
            if let level = device?.batteryLevel {
                Text("\(level)%")
                    .font(OPFont.number(13))
                    .foregroundStyle(OPColor.inkDim)
            }
            if let temp = device?.batteryTempC {
                Text(String(format: "%.1f°C", temp))
                    .font(OPFont.number(13))
                    .foregroundStyle(OPColor.thermal)
            }
            Spacer()
            if let serial = device?.serial, !serial.isEmpty {
                Text(AdbClient.shortId(serial))
                    .font(OPFont.number(12))
                    .foregroundStyle(OPColor.inkDim)
            }
        }
    }

    private var cardTHERMAL: some View {
        let device = store.inventory.devices.first
        let status = device?.thermalStatus
        return VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("droid.card.thermal.title"))
                .font(OPFont.number(12))
                .foregroundStyle(OPColor.inkDim)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(status.map { "Status \($0)" } ?? L10n.na)
                .font(OPFont.number(20))
                .foregroundStyle(OPColor.thermal)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSpace.lg)
        .background(OPColor.card, in: RoundedRectangle(cornerRadius: OPSpace.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: OPSpace.radiusCard).stroke(OPColor.border, lineWidth: 1))
    }

    private func card(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(OPFont.number(12))
                .foregroundStyle(OPColor.inkDim)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(value)
                .font(OPFont.number(20))
                .foregroundStyle(OPColor.ink)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSpace.lg)
        .background(OPColor.card, in: RoundedRectangle(cornerRadius: OPSpace.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: OPSpace.radiusCard).stroke(OPColor.border, lineWidth: 1))
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
