import SwiftUI

/// APK 설치 확인 시트 — 파일·대상 기기·옵션을 한 화면에서 확정한다.
/// 설치는 사용자가 [설치]를 누른 뒤에만 시작한다 (DECISIONS D6).
/// 1.24.0 — 온라인 기기를 여러 대 골라 **순차 설치**할 수 있다 (C 단계).
struct AppInstallConfirmView: View {
    let serial: String
    let ident: String
    let fileURL: URL

    @ObservedObject private var hub = AppHubController.shared
    @ObservedObject private var store = ConsoleStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var options = AppInstallOptions()
    @State private var size: UInt64?
    @State private var digest: String?
    /// 기본값은 **현재 시트를 연 기기 하나** — 실수로 여러 대에 설치하지 않게.
    @State private var selected: Set<String> = []

    private var kind: AppBundleKind {
        AppHubLogic.installKind(path: fileURL.path) ?? .apk
    }

    /// 온라인 기기 + (인벤토리에 아직 없을 수 있는) 현재 기기.
    /// 인벤토리가 비어 있어도 현재 기기 한 대는 항상 고를 수 있다.
    private var deviceOptions: [InstallTarget] {
        var out = store.inventory.onlineDevices.map {
            InstallTarget(serial: $0.serial, label: $0.identLabel)
        }
        if !out.contains(where: { $0.serial == serial }) {
            out.insert(InstallTarget(serial: serial, label: ident.isEmpty ? serial : ident), at: 0)
        }
        return out
    }

    private var targets: [InstallTarget] {
        // 화면에 보인 순서 그대로 순차 설치한다 — 결과표 순서가 진행 순서와 같아진다
        deviceOptions.filter { selected.contains($0.serial) }
    }

    private var allSelected: Bool {
        !deviceOptions.isEmpty && selected.count >= deviceOptions.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(OPColor.border)

            ScrollView {
                VStack(alignment: .leading, spacing: OPSpace.lg) {
                    fileCard
                    optionsCard
                    deviceCard
                    warning
                }
                .padding(OPSpace.lg)
            }

            Divider().overlay(OPColor.border)
            footer
        }
        .frame(width: 540, height: 560)
        .background(OPColor.popBG)
        .preferredColorScheme(ThemeManager.shared.mode.preferred)
        .task {
            let path = fileURL.path
            let meta = await Task.detached(priority: .utility) {
                (FileDigest.sizeBytes(path: path), FileDigest.sha256Hex(path: path))
            }.value
            size = meta.0
            digest = meta.1
        }
        .onAppear {
            if selected.isEmpty { selected = [serial] }
        }
    }

    private var header: some View {
        HStack {
            Text(L10n.string("apphub.install.title"))
                .font(OPFont.title(14))
                .foregroundStyle(OPColor.ink)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(OPColor.inkDim)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(L10n.string("alerts.note.cancel"))
        }
        .padding(OPSpace.md)
    }

    private var fileCard: some View {
        HStack(alignment: .top, spacing: OPSpace.md) {
            RoundedRectangle(cornerRadius: 9)
                .fill(OPColor.cta.opacity(0.16))
                .frame(width: 44, height: 50)
                .overlay(
                    Text(kind.rawValue.uppercased())
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundStyle(OPColor.cta)
                )
            VStack(alignment: .leading, spacing: 5) {
                Text(fileURL.lastPathComponent)
                    .font(OPFont.body(12))
                    .monospaced()
                    .foregroundStyle(OPColor.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(fileURL.path.replacingOccurrences(
                    of: FileManager.default.homeDirectoryForCurrentUser.path,
                    with: "~"
                ))
                    .font(OPFont.body(10))
                    .foregroundStyle(OPColor.inkDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 10) {
                    Text(size.map { AdbClient.formatBytes($0) } ?? L10n.na)
                        .font(OPFont.number(10))
                        .foregroundStyle(OPColor.inkDim)
                    Text("\(L10n.string("apphub.install.sha")) \(digest.map { String($0.prefix(12)) } ?? L10n.na)")
                        .font(OPFont.number(10))
                        .foregroundStyle(OPColor.inkDim)
                }
                if kind.isBundle {
                    Text(L10n.string("apphub.install.bundleNote"))
                        .font(OPFont.body(10))
                        .foregroundStyle(OPColor.inkDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(OPSpace.md)
        .background(OPColor.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(OPColor.border, lineWidth: 1)
        )
    }

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: OPSpace.sm) {
            Text(L10n.string("apphub.install.options"))
                .font(OPFont.body(10))
                .foregroundStyle(OPColor.inkDim)
            optionRow("apphub.install.opt.reinstall", flag: "-r", isOn: $options.reinstall)
            optionRow("apphub.install.opt.grant", flag: "-g", isOn: $options.grantAllPermissions)
            optionRow("apphub.install.opt.downgrade", flag: "-d", isOn: $options.allowDowngrade)
            optionRow("apphub.install.opt.test", flag: "-t", isOn: $options.allowTestOnly)
            if options.grantAllPermissions {
                Text(L10n.string("apphub.install.grantWarning"))
                    .font(OPFont.body(10))
                    .foregroundStyle(OPColor.warn)
            }
        }
    }

    private func optionRow(_ key: String, flag: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: isOn) {
                Text(L10n.string(key))
                    .font(OPFont.body(11))
                    .foregroundStyle(OPColor.ink)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            Spacer()
            Text(flag)
                .font(OPFont.number(10))
                .foregroundStyle(OPColor.inkDim)
        }
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "iphone.gen3")
                    .font(.system(size: 11))
                    .foregroundStyle(OPColor.droid)
                Text(L10n.string("apphub.install.devices"))
                    .font(OPFont.body(10))
                    .foregroundStyle(OPColor.inkDim)
                Spacer()
                Text(L10n.format("apphub.install.selectedCount", targets.count))
                    .font(OPFont.number(10))
                    .foregroundStyle(OPColor.inkDim)
                Button(allSelected ? L10n.string("apphub.install.selectNone") : L10n.string("apphub.install.selectAll")) {
                    selected = allSelected ? [serial] : Set(deviceOptions.map(\.serial))
                }
                .buttonStyle(.plain)
                .font(OPFont.body(10))
                .foregroundStyle(OPColor.cta)
            }

            ForEach(deviceOptions) { target in
                Toggle(isOn: selectionBinding(target.serial)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(target.label)
                            .font(OPFont.body(11))
                            .foregroundStyle(OPColor.ink)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if target.serial != target.label {
                            Text(target.serial)
                                .font(OPFont.number(9))
                                .foregroundStyle(OPColor.inkDim)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, OPSpace.md)
        .padding(.vertical, 9)
        .background(OPColor.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(OPColor.border, lineWidth: 1)
        )
        .help(L10n.string("apphub.install.devices.help"))
    }

    private func selectionBinding(_ serial: String) -> Binding<Bool> {
        Binding(
            get: { selected.contains(serial) },
            set: { on in
                if on { selected.insert(serial) } else { selected.remove(serial) }
            }
        )
    }

    private var warning: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11))
                .foregroundStyle(OPColor.warn)
            Text(L10n.string("apphub.install.warning"))
                .font(OPFont.body(10))
                .foregroundStyle(OPColor.inkDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack {
            Button(L10n.string("alerts.note.cancel")) { dismiss() }
                .buttonStyle(.plain)
                .font(OPFont.body(11))
                .foregroundStyle(OPColor.inkDim)
            Spacer()
            if targets.count > 1 {
                Text(L10n.format("apphub.install.selectedCount", targets.count))
                    .font(OPFont.number(10))
                    .foregroundStyle(OPColor.inkDim)
            }
            Button {
                hub.install(file: fileURL, targets: targets, options: options)
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.app")
                        .font(.system(size: 10, weight: .semibold))
                    Text(L10n.string("apphub.install.start"))
                        .font(OPFont.number(11))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(targets.isEmpty ? OPColor.inkDim : OPColor.cta, in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .disabled(hub.installing || targets.isEmpty)
        }
        .padding(OPSpace.md)
    }
}
