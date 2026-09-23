import SwiftUI

struct MenuBarPopoverView: View {
    @ObservedObject var store: ConsoleStore
    var openConsole: () -> Void
    var openDebug: () -> Void = {}

    private let popBG = Color(hex: 0x0F111A)
    private let cardBG = Color(hex: 0x1C1F2A)

    var body: some View {
        // SOLID root — macOS 26 red/rainbow hotfix
        ZStack {
            Color(hex: 0x0F111A).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                header
                Divider().overlay(OPColor.border)
                cards
                Divider().overlay(OPColor.border)
                events
                Divider().overlay(OPColor.border)
                footer
            }
            .padding(OPSpace.lg)
        }
        .frame(width: 360)
        .frame(maxHeight: 560)
        .background(Color(hex: 0x0F111A))
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            Circle().fill(OPColor.ok).frame(width: 8, height: 8)
            Text(L10n.string("menubar.label"))
                .font(OPFont.title(13))
                .foregroundStyle(OPColor.ink)
            Spacer()
            Text("0.1.0")
                .font(OPFont.number(11))
                .foregroundStyle(OPColor.inkDim)
        }
    }

    private var cards: some View {
        VStack(spacing: 12) {
            cardFull(L10n.string("droid.card.cpu.title"), L10n.na)
            HStack(spacing: 12) {
                cardMini(L10n.string("droid.card.memory.title"), L10n.na)
                cardMini(L10n.string("droid.card.storage.title"), L10n.na)
            }
            cardFull(L10n.string("droid.card.battery.title"), L10n.na)
            cardFull(L10n.string("droid.card.network.title"), L10n.na)
        }
    }

    private func cardFull(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(OPFont.number(11))
                .foregroundStyle(OPColor.inkDim)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Text(value).font(OPFont.number(13)).foregroundStyle(OPColor.ink)
        }
        .padding(OPSpace.md)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBG)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func cardMini(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(OPFont.number(10))
                .foregroundStyle(OPColor.inkDim)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(value).font(OPFont.number(13)).foregroundStyle(OPColor.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSpace.md)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBG)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var events: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.format("menubar.events.recent", min(store.recentEvents.count, 5)))
                .font(OPFont.number(11))
                .foregroundStyle(OPColor.inkDim)
                .lineLimit(1)
                .truncationMode(.tail)
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

    private var footer: some View {
        HStack(spacing: OPSpace.sm) {
            OPPrimaryButton(title: L10n.string("menubar.button.openConsole"), action: openConsole)
            OPSecondaryButton(title: L10n.string("menubar.button.debug"), action: openDebug)
            Spacer()
            SettingsLink {
                Image(systemName: "gearshape")
                    .foregroundStyle(OPColor.inkDim)
            }
            .buttonStyle(.plain)
            .help(L10n.string("settings.section.general"))
        }
    }
}
