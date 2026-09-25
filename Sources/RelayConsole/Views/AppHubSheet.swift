import SwiftUI

/// 앱 미니 허브 시트 — 목록·검색·런치·강제종료·삭제 (A3)
struct AppHubSheet: View {
    let serial: String
    @ObservedObject private var hub = AppHubController.shared
    @State private var query = ""
    @State private var confirmUninstall: String?

    private var visible: [String] {
        AppHubLogic.filter(hub.packages, query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(OPColor.border)
            searchRow
            Divider().overlay(OPColor.border)

            if hub.loading && hub.packages.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visible.isEmpty {
                Text(hub.lastMessage ?? L10n.string("apphub.empty"))
                    .font(OPFont.body(12))
                    .foregroundStyle(OPColor.inkDim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visible, id: \.self) { pkg in
                            row(pkg)
                            if pkg != visible.last {
                                Divider().overlay(OPColor.border).padding(.leading, 12)
                            }
                        }
                    }
                }
            }

            Divider().overlay(OPColor.border)
            statusLine
        }
        .frame(minWidth: 520, minHeight: 440)
        .background(OPColor.popBG)
        .preferredColorScheme(ThemeManager.shared.mode.preferred)
        .onAppear { hub.refresh(serial: serial) }
        .onChange(of: hub.includeSystem) { _, _ in
            hub.refresh(serial: serial)
        }
        .confirmationDialog(
            L10n.format("apphub.confirm.uninstall", confirmUninstall ?? ""),
            isPresented: Binding(
                get: { confirmUninstall != nil },
                set: { if !$0 { confirmUninstall = nil } }
            )
        ) {
            Button(L10n.string("apphub.action.uninstall"), role: .destructive) {
                if let pkg = confirmUninstall {
                    hub.uninstall(serial: serial, package: pkg)
                }
                confirmUninstall = nil
            }
            Button(L10n.string("alerts.note.cancel"), role: .cancel) {
                confirmUninstall = nil
            }
        }
    }

    private var header: some View {
        HStack {
            Text(L10n.string("apphub.title"))
                .font(OPFont.title(14))
                .foregroundStyle(OPColor.ink)
            Spacer()
            Toggle(L10n.string("apphub.system"), isOn: $hub.includeSystem)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(OPFont.body(11))
            Button {
                hub.refresh(serial: serial)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(OPColor.cta)
                    .frame(width: 24, height: 24)
                    .background(OPColor.cta.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help(L10n.string("apphub.action.refresh"))
            .disabled(hub.loading)
        }
        .padding(OPSpace.md)
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(OPColor.inkDim)
            TextField(L10n.string("apphub.search"), text: $query)
                .textFieldStyle(.plain)
                .font(OPFont.body(12))
                .foregroundStyle(OPColor.ink)
            Text(L10n.format("apphub.count", visible.count))
                .font(OPFont.number(11))
                .foregroundStyle(OPColor.inkDim)
        }
        .padding(.horizontal, OPSpace.md)
        .padding(.vertical, 8)
    }

    private func row(_ pkg: String) -> some View {
        HStack(spacing: 8) {
            Text(pkg)
                .font(OPFont.body(12))
                .monospaced()
                .foregroundStyle(OPColor.ink)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if hub.busyPackage == pkg {
                ProgressView().controlSize(.mini)
            } else {
                actionButton("play.fill", tint: OPColor.ok, help: "apphub.action.launch") {
                    hub.launch(serial: serial, package: pkg)
                }
                actionButton("stop.fill", tint: OPColor.warn, help: "apphub.action.stop") {
                    hub.forceStop(serial: serial, package: pkg)
                }
                actionButton("trash", tint: OPColor.bad, help: "apphub.action.uninstall") {
                    confirmUninstall = pkg
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func actionButton(
        _ icon: String,
        tint: Color,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help(L10n.string(help))
    }

    private var statusLine: some View {
        Text(hub.lastMessage ?? " ")
            .font(OPFont.body(11))
            .foregroundStyle(OPColor.inkDim)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(OPSpace.sm)
    }
}
