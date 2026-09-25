import SwiftUI

/// Apple Phase 1 카드 — Battery / Storage / Thermal / Device (shell 재사용)
@MainActor
enum AppleCards {
    static func battery(_ device: AppleSnapshot?) -> some View {
        DroidCards.shell(L10n.string("apple.card.battery.title"), accent: OPColor.apple) {
            Text(batteryValue(device))
                .font(OPFont.number(18))
                .foregroundStyle(OPColor.ink)
                .lineLimit(1)
            if let level = device?.batteryLevel {
                ProgressView(value: Double(level), total: 100)
                    .progressViewStyle(.linear)
                    .tint(device?.isCharging == true ? OPColor.ok : OPColor.cta)
                    .frame(height: 4)
            }
            HStack(spacing: 8) {
                if device?.isCharging == true {
                    TagChip(L10n.string("droid.card.battery.charging"), color: OPColor.ok)
                }
                if let health = device?.batteryHealthPct {
                    Text(L10n.format("apple.card.battery.health", "\(health)%"))
                        .font(OPFont.number(11))
                        .foregroundStyle(OPColor.inkDim)
                }
                if let cycle = device?.cycleCount {
                    Text(L10n.format("apple.card.battery.cycle", "\(cycle)"))
                        .font(OPFont.number(11))
                        .foregroundStyle(OPColor.inkDim)
                }
            }
        }
    }

    static func storage(_ device: AppleSnapshot?) -> some View {
        DroidCards.shell(L10n.string("apple.card.storage.title"), accent: OPColor.apple) {
            Text(storageValue(device))
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

    static func thermal(_ device: AppleSnapshot?) -> some View {
        DroidCards.shell(L10n.string("apple.card.thermal.title"), accent: OPColor.apple) {
            let state = device?.thermalState?.lowercased()
            Text(thermalLabel(state))
                .font(OPFont.number(14))
                .foregroundStyle(thermalColor(state))
                .lineLimit(1)
            if state == nil {
                Text(L10n.string("apple.card.thermal.na"))
                    .font(OPFont.number(10))
                    .foregroundStyle(OPColor.inkDim)
            }
        }
    }

    static func deviceInfo(_ device: AppleSnapshot?) -> some View {
        DroidCards.shell(L10n.string("apple.card.info.title"), accent: OPColor.apple) {
            infoRow(L10n.string("apple.card.info.model"), device?.productType ?? L10n.na)
            infoRow(L10n.string("apple.card.info.os"), device?.productVersion ?? L10n.na)
            infoRow(L10n.string("apple.card.info.udid"), device?.udid ?? L10n.na)
        }
    }

    // MARK: - helpers

    private static func batteryValue(_ d: AppleSnapshot?) -> String {
        guard let level = d?.batteryLevel else { return L10n.na }
        return "\(level)%"
    }

    private static func storageValue(_ d: AppleSnapshot?) -> String {
        guard let used = d?.storageUsedGB, let total = d?.storageTotalGB else { return L10n.na }
        return String(format: "%.1f / %.0f GB", used, total)
    }

    private static func thermalLabel(_ state: String?) -> String {
        switch state {
        case "nominal": return L10n.string("apple.thermal.nominal")
        case "fair": return L10n.string("apple.thermal.fair")
        case "serious": return L10n.string("apple.thermal.serious")
        case "critical": return L10n.string("apple.thermal.critical")
        default: return L10n.na
        }
    }

    private static func thermalColor(_ state: String?) -> Color {
        switch state {
        case "nominal": return OPColor.ok
        case "fair": return OPColor.warn
        case "serious", "critical": return OPColor.bad
        default: return OPColor.inkDim
        }
    }

    private static func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(OPFont.body(11))
                .foregroundStyle(OPColor.inkDim)
            Spacer(minLength: 8)
            Text(value)
                .font(OPFont.number(11))
                .foregroundStyle(OPColor.ink)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct TagChip: View {
    let text: String
    let color: Color
    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }
    var body: some View {
        Text(text)
            .font(OPFont.number(10))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
    }
}
