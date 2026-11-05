import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 앱 관리 시트 — 목록·검색·런치·강제종료·삭제·설치·백업 (1.24.0)
struct AppHubSheet: View {
    let serial: String
    let ident: String

    @ObservedObject private var hub = AppHubController.shared
    @ObservedObject private var icons = AppIconStore.shared
    @State private var query = ""
    @State private var confirmUninstall: String?
    @State private var pendingInstall: PendingInstall?
    /// 시스템 앱 2단계 확인 시트 대상
    @State private var systemDisable: SystemDisableTarget?
    /// 하드 블록 패키지를 눌렀을 때 이유를 알려주는 알림
    @State private var blockedNotice: String?
    /// 시스템 앱 목록의 두 번째 탭 — `--user 0` 으로 제거되어 복원 가능한 앱
    @State private var showRemovable = false

    private struct PendingInstall: Identifiable {
        let id = UUID()
        let url: URL
    }

    private struct SystemDisableTarget: Identifiable {
        let package: String
        var id: String { package }
    }

    private var showingRemovable: Bool {
        hub.includeSystem && showRemovable
    }

    private var sourcePackages: [String] {
        showingRemovable ? hub.removedSystemPackages : hub.packages
    }

    /// 검색은 **패키지명 + 앱 이름** 둘 다 본다 — 사용자는 `카카오톡` 으로 찾는다.
    private var visible: [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return sourcePackages }
        return sourcePackages.filter { pkg in
            pkg.lowercased().contains(q)
                || (icons.labels[pkg]?.lowercased().contains(q) ?? false)
        }
    }

    /// 행의 첫 줄 — 이름을 알면 이름, 아직 모르면 패키지명
    private func displayName(_ pkg: String) -> String {
        icons.labels[pkg] ?? pkg
    }

    private var busy: Bool { hub.installing || hub.backingUp != nil }

    /// 다른 기기의 시트에 지난 설치 결과를 끌고 오지 않는다.
    /// 다기기 설치는 대상이 여러 대이므로 그대로 보여준다.
    private var showsInstallResults: Bool {
        guard !hub.installResults.isEmpty else { return false }
        return hub.installResults.count > 1 || hub.installResults.first?.serial == serial
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(OPColor.border)
            if hub.installing {
                installBanner
                Divider().overlay(OPColor.border)
            } else if showsInstallResults {
                installResultsBar
                Divider().overlay(OPColor.border)
            }
            searchRow
            Divider().overlay(OPColor.border)
            if hub.includeSystem {
                systemTabRow
                Divider().overlay(OPColor.border)
            }
            if showingRemovable {
                Text(L10n.string("apphub.system.removed.note"))
                    .font(OPFont.body(10))
                    .foregroundStyle(OPColor.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, OPSpace.md)
                    .padding(.vertical, 7)
                    .background(OPColor.warn.opacity(0.06))
                Divider().overlay(OPColor.border)
            }

            if hub.loading && hub.packages.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visible.isEmpty {
                Text(emptyText)
                    .font(OPFont.body(12))
                    .foregroundStyle(OPColor.inkDim)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(OPSpace.lg)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visible, id: \.self) { pkg in
                            if showingRemovable {
                                restoreRow(pkg)
                            } else {
                                row(pkg)
                            }
                            if pkg != visible.last {
                                Divider().overlay(OPColor.border).padding(.leading, 42)
                            }
                        }
                    }
                }
            }

            Divider().overlay(OPColor.border)
            statusLine
        }
        .frame(minWidth: 580, minHeight: 500)
        .background(OPColor.popBG)
        .preferredColorScheme(ThemeManager.shared.mode.preferred)
        .onAppear { hub.refresh(serial: serial) }
        .onChange(of: hub.includeSystem) { _, on in
            if !on { showRemovable = false }
            hub.refresh(serial: serial)
        }
        // 다기기 설치는 컨트롤러가 목록을 갱신하지 않는다 — 뷰가 현재 기기만 다시 읽는다.
        // 결과 문구를 지우지 않도록 clearMessage: false.
        .onChange(of: hub.installing) { wasInstalling, nowInstalling in
            guard wasInstalling, !nowInstalling else { return }
            hub.refresh(serial: serial, clearMessage: false)
        }
        .onChange(of: icons.enabled) { _, on in
            guard on else { return }
            for pkg in visible {
                icons.request(serial: serial, package: pkg, versionCode: hub.versionCodes[pkg] ?? 0)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { AppHubLogic.installKind(path: $0.path) != nil }) else {
                hub.lastMessage = L10n.string("apphub.install.invalidFile")
                return false
            }
            pendingInstall = PendingInstall(url: url)
            return true
        }
        .sheet(item: $pendingInstall) { pending in
            AppInstallConfirmView(serial: serial, ident: ident, fileURL: pending.url)
        }
        .sheet(item: $systemDisable) { target in
            SystemAppDisableConfirmView(serial: serial, package: target.package)
        }
        .alert(
            L10n.string("apphub.system.blocked.title"),
            isPresented: Binding(
                get: { blockedNotice != nil },
                set: { if !$0 { blockedNotice = nil } }
            )
        ) {
            Button("OK", role: .cancel) { blockedNotice = nil }
        } message: {
            Text(L10n.format("apphub.system.blocked.body", blockedNotice ?? ""))
        }
        .confirmationDialog(
            L10n.format("apphub.uninstall.confirm", confirmUninstall ?? ""),
            isPresented: Binding(
                get: { confirmUninstall != nil },
                set: { if !$0 { confirmUninstall = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.string("apphub.uninstall.full"), role: .destructive) {
                if let pkg = confirmUninstall {
                    hub.uninstall(serial: serial, package: pkg, keepData: false)
                }
                confirmUninstall = nil
            }
            Button(L10n.string("apphub.uninstall.keepData")) {
                if let pkg = confirmUninstall {
                    hub.uninstall(serial: serial, package: pkg, keepData: true)
                }
                confirmUninstall = nil
            }
            Button(L10n.string("alerts.note.cancel"), role: .cancel) {
                confirmUninstall = nil
            }
        } message: {
            Text(L10n.string("apphub.uninstall.note"))
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text(L10n.string("apphub.title"))
                .font(OPFont.title(14))
                .foregroundStyle(OPColor.ink)
            Spacer(minLength: 8)

            Button {
                pickPackage()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "plus.app")
                        .font(.system(size: 10, weight: .semibold))
                    Text(L10n.string("apphub.install.button"))
                        .font(OPFont.number(10))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(OPColor.cta, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help(L10n.string("apphub.install.title"))
            .disabled(busy || hub.loading)

            Toggle(L10n.string("apphub.icons"), isOn: $icons.enabled)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(OPFont.body(11))
                .help(L10n.string("apphub.icons.help"))

            Toggle(L10n.string("apphub.system"), isOn: $hub.includeSystem)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(OPFont.body(11))
                .disabled(busy)

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
            .disabled(hub.loading || busy)
        }
        .padding(OPSpace.md)
    }

    private var installBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 3) {
                Text(hub.installFileName ?? "")
                    .font(OPFont.body(11))
                    .monospaced()
                    .foregroundStyle(OPColor.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    if hub.installTotal > 1 {
                        Text(L10n.format("apphub.install.many.progress", hub.installCompleted, hub.installTotal))
                            .font(OPFont.number(10))
                            .foregroundStyle(OPColor.cta)
                    }
                    if let phase = hub.installPhase {
                        Text(phase)
                            .font(OPFont.number(10))
                            .foregroundStyle(OPColor.inkDim)
                            .lineLimit(1)
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(elapsedText(context.date))
                            .font(OPFont.number(10))
                            .foregroundStyle(OPColor.inkDim)
                    }
                }
                if hub.installProgress > 0 {
                    ProgressView(value: min(max(hub.installProgress, 0), 1))
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                        .frame(maxWidth: 260)
                } else {
                    // 단일 APK 는 adb 가 진행률을 주지 않는다 — 숫자 대신 **진행 중** 막대를 보여
                    // "멈춘 화면"으로 보이지 않게 한다 (2026-11-05)
                    ProgressView()
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                        .frame(maxWidth: 260)
                }
            }
            Spacer(minLength: 8)
            Button(L10n.string("apphub.install.cancel")) {
                hub.cancelInstall()
            }
            .buttonStyle(.plain)
            .font(OPFont.body(11))
            .foregroundStyle(OPColor.bad)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(OPColor.bad.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            .help(L10n.string("apphub.install.cancel.help"))
        }
        .padding(.horizontal, OPSpace.md)
        .padding(.vertical, 8)
        .background(OPColor.cta.opacity(0.08))
    }

    private func elapsedText(_ now: Date) -> String {
        guard let start = hub.installStartedAt else { return "" }
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return L10n.format("apphub.install.elapsed", seconds)
    }

    /// 기기별 결과표 — 설치가 끝난 뒤에도 남겨 두고 사용자가 닫을 때만 지운다
    private var installResultsBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(L10n.string("apphub.install.results"))
                    .font(OPFont.body(10))
                    .foregroundStyle(OPColor.inkDim)
                Spacer()
                Button(L10n.string("apphub.install.results.clear")) {
                    hub.clearInstallResults()
                }
                .buttonStyle(.plain)
                .font(OPFont.body(10))
                .foregroundStyle(OPColor.inkDim)
            }
            ForEach(hub.installResults) { result in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: result.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(result.ok ? OPColor.ok : OPColor.bad)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(result.label)
                                .font(OPFont.body(10))
                                .foregroundStyle(OPColor.ink)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if let version = result.versionName {
                                Text("v\(version)")
                                    .font(OPFont.number(9))
                                    .foregroundStyle(OPColor.ok)
                            }
                        }
                        Text(result.message)
                            .font(OPFont.number(9))
                            .foregroundStyle(OPColor.inkDim)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, OPSpace.md)
        .padding(.vertical, 7)
        .background(OPColor.cta.opacity(0.06))
    }

    // MARK: - Search

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

    /// 시스템 앱 모드에서만 — 설치됨 / 복원 가능
    private var systemTabRow: some View {
        Picker("", selection: $showRemovable) {
            Text(L10n.format("apphub.system.tab.installed", hub.packages.count)).tag(false)
            Text(L10n.format("apphub.system.tab.removed", hub.removedSystemPackages.count)).tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .padding(.horizontal, OPSpace.md)
        .padding(.vertical, 6)
    }

    private var emptyText: String {
        if showingRemovable {
            return hub.lastMessage ?? L10n.string("apphub.system.removed.empty")
        }
        return hub.lastMessage ?? L10n.string("apphub.empty")
    }

    // MARK: - Row

    private func row(_ pkg: String) -> some View {
        HStack(spacing: 8) {
            iconView(pkg)
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName(pkg))
                    .font(OPFont.body(12))
                    .foregroundStyle(OPColor.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if icons.labels[pkg] != nil {
                    Text(pkg)
                        .font(OPFont.number(9))
                        .monospaced()
                        .foregroundStyle(OPColor.inkDim)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
            if hub.busyPackage == pkg || hub.backingUp == pkg {
                ProgressView().controlSize(.mini)
            } else {
                actionButton("play.fill", tint: OPColor.ok, help: "apphub.action.launch", disabled: busy) {
                    hub.launch(serial: serial, package: pkg)
                }
                actionButton("stop.fill", tint: OPColor.warn, help: "apphub.action.stop", disabled: busy) {
                    hub.forceStop(serial: serial, package: pkg)
                }
                actionButton("arrow.down.to.line", tint: OPColor.cta, help: "apphub.backup.action", disabled: busy) {
                    hub.backup(serial: serial, package: pkg)
                }
                actionButton("trash", tint: OPColor.bad, help: "apphub.action.uninstall", disabled: busy) {
                    confirmUninstall = pkg
                }
                if hub.includeSystem && hub.systemPackages.contains(pkg) {
                    if AppHubLogic.isBlockedSystemPackage(pkg) {
                        Button {
                            blockedNotice = pkg
                        } label: {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(OPColor.inkDim)
                                .frame(width: 22, height: 22)
                                .background(OPColor.inkDim.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                        .help(L10n.string("apphub.system.blocked.help"))
                    } else {
                        actionButton("eye.slash", tint: OPColor.warn, help: "apphub.system.disable.action", disabled: busy) {
                            systemDisable = SystemDisableTarget(package: pkg)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .onAppear {
            icons.request(serial: serial, package: pkg, versionCode: hub.versionCodes[pkg] ?? 0)
        }
        .contextMenu {
            Button(L10n.string("apphub.action.launch")) { hub.launch(serial: serial, package: pkg) }
            Button(L10n.string("apphub.action.stop")) { hub.forceStop(serial: serial, package: pkg) }
            Button(L10n.string("apphub.backup.action")) { hub.backup(serial: serial, package: pkg) }
            Divider()
            Button(role: .destructive) {
                hub.uninstall(serial: serial, package: pkg, keepData: false)
            } label: {
                Text(L10n.string("apphub.uninstall.full"))
            }
            Button {
                hub.uninstall(serial: serial, package: pkg, keepData: true)
            } label: {
                Text(L10n.string("apphub.uninstall.keepData"))
            }
            if hub.includeSystem && hub.systemPackages.contains(pkg) {
                Divider()
                if AppHubLogic.isBlockedSystemPackage(pkg) {
                    Button {
                        blockedNotice = pkg
                    } label: {
                        Text(L10n.string("apphub.system.blocked.help"))
                    }
                } else {
                    Button {
                        systemDisable = SystemDisableTarget(package: pkg)
                    } label: {
                        Text(L10n.string("apphub.system.disable.action"))
                    }
                }
            }
        }
    }

    /// 복원 가능한 시스템 앱 행 — `cmd package install-existing --user 0`
    private func restoreRow(_ pkg: String) -> some View {
        HStack(spacing: 8) {
            iconView(pkg)
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName(pkg))
                    .font(OPFont.body(12))
                    .foregroundStyle(OPColor.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(pkg)
                    .font(OPFont.number(9))
                    .monospaced()
                    .foregroundStyle(OPColor.inkDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(L10n.string("apphub.system.restore.help"))
                    .font(OPFont.body(9))
                    .foregroundStyle(OPColor.inkDim)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if hub.busyPackage == pkg {
                ProgressView().controlSize(.mini)
            } else {
                Button {
                    hub.restoreSystemApp(serial: serial, package: pkg)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 9, weight: .semibold))
                        Text(L10n.string("apphub.system.restore"))
                            .font(OPFont.number(10))
                    }
                    .foregroundStyle(OPColor.cta)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(OPColor.cta.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .onAppear {
            icons.request(serial: serial, package: pkg, versionCode: 0)
        }
        .contextMenu {
            Button {
                hub.restoreSystemApp(serial: serial, package: pkg)
            } label: {
                Text(L10n.string("apphub.system.restore"))
            }
        }
    }

    /// 아이콘 — 캐시에 있으면 이미지, 없으면 결정적 색 + 이니셜 타일 (빈칸 금지)
    @ViewBuilder
    private func iconView(_ pkg: String) -> some View {
        if let image = icons.images[pkg] {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            RoundedRectangle(cornerRadius: 5)
                .fill(placeholderColor(pkg))
                .frame(width: 22, height: 22)
                .overlay(
                    Text(placeholderLetter(pkg))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                )
                .help(icons.enabled
                    ? L10n.string("apphub.icons.loading")
                    : L10n.string("apphub.icons.off"))
        }
    }

    private func placeholderLetter(_ pkg: String) -> String {
        let last = pkg.split(separator: ".").last.map(String.init) ?? pkg
        return last.first.map { String($0).uppercased() } ?? "?"
    }

    private func placeholderColor(_ pkg: String) -> Color {
        var hash: UInt64 = 5381
        for byte in pkg.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        let hue = Double(hash % 360) / 360
        return Color(hue: hue, saturation: 0.38, brightness: 0.52)
    }

    private func actionButton(
        _ icon: String,
        tint: Color,
        help: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(disabled ? OPColor.inkDim : tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(disabled ? 0.05 : 0.12), in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help(L10n.string(help))
        .disabled(disabled)
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            Text(hub.lastMessage ?? " ")
                .font(OPFont.body(11))
                .foregroundStyle(OPColor.inkDim)
                .lineLimit(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if hub.lastBackupDir != nil {
                Button {
                    hub.revealBackup()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "folder")
                            .font(.system(size: 9, weight: .semibold))
                        Text(L10n.string("apphub.backup.reveal"))
                            .font(OPFont.body(10))
                    }
                    .foregroundStyle(OPColor.cta)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(OPSpace.sm)
    }

    // MARK: - Pick

    private func pickPackage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["apk", "apks", "xapk", "apkm"]
            .compactMap { UTType(filenameExtension: $0) }
        if panel.allowedContentTypes.isEmpty { panel.allowedContentTypes = [.data] }
        panel.prompt = L10n.string("apphub.install.choose")
        panel.message = L10n.string("apphub.install.chooseMessage")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard AppHubLogic.installKind(path: url.path) != nil else {
            hub.lastMessage = L10n.string("apphub.install.invalidFile")
            return
        }
        pendingInstall = PendingInstall(url: url)
    }
}

/// 시스템 앱 비활성화 2단계 확인 — 체크박스 두 개를 모두 켜야 실행된다.
/// `--user 0` 제거는 시스템 파티션의 APK 를 지우지 않으므로 복원할 수 있지만,
/// 이 사용자에게서는 앱·데이터가 사라진다 (DECISIONS D8).
struct SystemAppDisableConfirmView: View {
    let serial: String
    let package: String

    @ObservedObject private var hub = AppHubController.shared
    @Environment(\.dismiss) private var dismiss

    @State private var understandsRemoval = false
    @State private var understandsRestore = false

    private var canRun: Bool {
        understandsRemoval && understandsRestore
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L10n.string("apphub.system.disable.title"))
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
            Divider().overlay(OPColor.border)

            VStack(alignment: .leading, spacing: OPSpace.md) {
                Text(package)
                    .font(OPFont.body(12))
                    .monospaced()
                    .foregroundStyle(OPColor.ink)
                    .textSelection(.enabled)

                Text(L10n.format("apphub.system.disable.body", package))
                    .font(OPFont.body(11))
                    .foregroundStyle(OPColor.inkDim)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundStyle(OPColor.warn)
                    Text(L10n.string("apphub.system.disable.warning"))
                        .font(OPFont.body(10))
                        .foregroundStyle(OPColor.inkDim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle(L10n.string("apphub.system.disable.check1"), isOn: $understandsRemoval)
                    .toggleStyle(.checkbox)
                    .font(OPFont.body(11))
                    .foregroundStyle(OPColor.ink)
                Toggle(L10n.string("apphub.system.disable.check2"), isOn: $understandsRestore)
                    .toggleStyle(.checkbox)
                    .font(OPFont.body(11))
                    .foregroundStyle(OPColor.ink)
            }
            .padding(OPSpace.lg)

            Divider().overlay(OPColor.border)
            HStack {
                Button(L10n.string("alerts.note.cancel")) { dismiss() }
                    .buttonStyle(.plain)
                    .font(OPFont.body(11))
                    .foregroundStyle(OPColor.inkDim)
                Spacer()
                Button {
                    hub.disableSystemApp(serial: serial, package: package)
                    dismiss()
                } label: {
                    Text(L10n.string("apphub.system.disable.confirm"))
                        .font(OPFont.number(11))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(canRun ? OPColor.bad : OPColor.inkDim, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .disabled(!canRun)
            }
            .padding(OPSpace.md)
        }
        .frame(width: 470)
        .background(OPColor.popBG)
        .preferredColorScheme(ThemeManager.shared.mode.preferred)
    }
}
