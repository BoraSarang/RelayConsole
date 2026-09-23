import SwiftUI

struct DebugPanelView: View {
    @ObservedObject private var logger = DebugLogger.shared

    var body: some View {
        ZStack {
            Color(hex: 0x0F111A).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(L10n.string("ui.debug.title"))
                        .font(OPFont.title(14))
                        .foregroundStyle(OPColor.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Button(L10n.string("ui.debug.clear")) { logger.clear() }
                        .buttonStyle(.plain)
                }
                .padding(OPSpace.md)
                Divider().overlay(OPColor.border)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(logger.logs.reversed()) { entry in
                            Text("[\(entry.timestamp)] [\(entry.level.rawValue)] [\(entry.platform)] [\(entry.category)] \(entry.message)")
                                .font(OPFont.number(11))
                                .foregroundStyle(entry.level == .error ? OPColor.bad : OPColor.inkDim)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(OPSpace.sm)
                }
            }
        }
        .background(Color(hex: 0x0F111A))
        .preferredColorScheme(.dark)
    }
}
