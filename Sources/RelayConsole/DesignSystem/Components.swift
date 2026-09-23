import SwiftUI

struct OPPrimaryButton: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(OPFont.body(13))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(OPColor.cta, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

struct OPSecondaryButton: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(OPFont.body(13))
                .foregroundStyle(OPColor.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(OPColor.card, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(OPColor.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct StatusDot: View {
    let state: StatusState

    var body: some View {
        Circle()
            .fill(OPColor.statusColor(state))
            .frame(width: 8, height: 8)
            .shadow(color: OPColor.statusColor(state).opacity(0.7), radius: 4)
    }
}

struct OPCard: View {
    var scheme: ColorScheme = .dark
    @ViewBuilder var content: () -> AnyView

    var body: some View {
        content()
            .padding(OPSpace.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OPColor.card, in: RoundedRectangle(cornerRadius: OPSpace.radiusCard))
            .overlay(
                RoundedRectangle(cornerRadius: OPSpace.radiusCard)
                    .stroke(OPColor.border, lineWidth: 1)
            )
    }
}
