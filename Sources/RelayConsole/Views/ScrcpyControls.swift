import SwiftUI
import AppKit
import Combine

/// 헤더용 scrcpy 버튼 + 미설치 시 설치 시트 (PLAN_v0.7 A안)
struct ScrcpyHeaderButton: View {
    let serial: String
    @ObservedObject private var scrcpy = ScrcpyController.shared
    @State private var showInstall = false
    @State private var showError = false
    @State private var tick = Date()

    var body: some View {
        Button(action: tap) {
            HStack(spacing: 4) {
                if scrcpy.isInstalling {
                    ProgressView()
                        .controlSize(.mini)
                        .padding(.trailing, 2)
                } else {
                    Image(systemName: state == .running ? "rectangle.fill.on.rectangle.fill" : "rectangle.on.rectangle")
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(label)
                    .font(OPFont.number(10))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(background, in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!serial.isEmpty && scrcpy.isInstalling)
        .help(help)
        .onAppear { scrcpy.refresh() }
        .onReceive(ScrcpyController.shared.objectWillChange) { _ in
            tick = Date()
        }
        // borderless NSPanel(.nonactivating)에선 .sheet가 붙지 않음 — 팝오버로 통일
        .popover(isPresented: $showInstall, arrowEdge: .bottom) {
            ScrcpyInstallSheet(onDone: {
                showInstall = false
                scrcpy.refresh()
                if scrcpy.binaryPath != nil, !serial.isEmpty {
                    scrcpy.launch(serial: serial)
                }
            })
        }
        .popover(isPresented: $showError, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.string("scrcpy.error.title"))
                    .font(OPFont.body(12))
                    .foregroundStyle(OPColor.ink)
                Text(scrcpy.lastError ?? "")
                    .font(OPFont.body(11))
                    .foregroundStyle(OPColor.bad)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L10n.string("scrcpy.error.dismiss")) {
                    scrcpy.clearError()
                    showError = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(OPColor.cta)
            }
            .padding(14)
            .frame(width: 260, alignment: .leading)
            .background(OPColor.popBG)
            .preferredColorScheme(ThemeManager.shared.mode.preferred)
            .onDisappear { scrcpy.clearError() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .scrcpyInstalled)) { _ in
            scrcpy.refresh()
        }
        .onChange(of: scrcpy.isInstalling) { _, installing in
            if !installing, scrcpy.binaryPath != nil, showInstall {
                showInstall = false
                if !serial.isEmpty { scrcpy.launch(serial: serial) }
            }
        }
        // launch/toggle 실패(미설치·프로세스 기동 실패) 시 오류를 그대로 방치하지 않음
        .onChange(of: scrcpy.lastError) { _, err in
            guard let err, !err.isEmpty,
                  !scrcpy.isInstalling,
                  !showInstall else { return }
            showError = true
        }
    }

    private var state: ScrcpyButtonState {
        scrcpy.buttonState(serial: serial)
    }

    private var label: String {
        switch state {
        case .missing: return L10n.string("scrcpy.button.install")
        case .installing: return L10n.string("scrcpy.button.installing")
        case .ready: return L10n.string("scrcpy.button.open")
        case .running: return L10n.string("scrcpy.button.running")
        }
    }

    private var foreground: Color {
        switch state {
        case .running: return OPColor.ok
        case .missing: return OPColor.warn
        default: return OPColor.cta
        }
    }

    private var background: Color {
        switch state {
        case .running: return OPColor.ok.opacity(0.15)
        case .missing: return OPColor.warn.opacity(0.12)
        default: return OPColor.card
        }
    }

    private var border: Color {
        switch state {
        case .running: return OPColor.ok.opacity(0.4)
        case .missing: return OPColor.warn.opacity(0.4)
        default: return OPColor.border
        }
    }

    private var help: String {
        switch state {
        case .missing: return L10n.string("scrcpy.install.body")
        case .running: return L10n.string("scrcpy.button.runningHint")
        default: return L10n.string("scrcpy.button.openHint")
        }
    }

    private func tap() {
        switch state {
        case .missing:
            showInstall = true
        case .installing:
            break
        case .ready:
            guard !serial.isEmpty else { return }
            scrcpy.launch(serial: serial)
        case .running:
            // 실행 중 클릭 = 창 앞으로 (정지 아님 — scrcpy 창 닫기)
            scrcpy.toggle(serial: serial)
        }
    }
}

/// 미설치 안내 — brew 원클릭 (사용자 확인 1회) · 터미널 · 나중에
struct ScrcpyInstallSheet: View {
    var onDone: () -> Void
    @ObservedObject private var scrcpy = ScrcpyController.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(OPColor.cta)
                Text(L10n.string("scrcpy.install.title"))
                    .font(OPFont.title(14))
                    .foregroundStyle(OPColor.ink)
            }
            Text(L10n.string("scrcpy.install.body"))
                .font(OPFont.body(12))
                .foregroundStyle(OPColor.inkDim)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)

            if let err = scrcpy.lastError {
                Text(err)
                    .font(OPFont.body(11))
                    .foregroundStyle(OPColor.bad)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if scrcpy.isInstalling {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.string("scrcpy.button.installing"))
                        .font(OPFont.body(12))
                        .foregroundStyle(OPColor.inkDim)
                }
            } else {
                VStack(spacing: 8) {
                    Button {
                        scrcpy.installViaBrew()
                    } label: {
                        Text(L10n.string("scrcpy.install.brew"))
                            .font(OPFont.body(12))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(OPColor.cta.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(OPColor.cta, lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 8) {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("brew install scrcpy", forType: .string)
                            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
                        } label: {
                            Text(L10n.string("scrcpy.install.terminal"))
                                .font(OPFont.body(11))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(OPColor.card, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(OPColor.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        Button {
                            dismiss()
                            onDone()
                        } label: {
                            Text(L10n.string("scrcpy.install.later"))
                                .font(OPFont.body(11))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(OPColor.card, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(OPColor.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text(L10n.string("scrcpy.install.policy"))
                .font(OPFont.number(10))
                .foregroundStyle(OPColor.inkDim.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 360)
        .background(OPColor.popBG)
        .preferredColorScheme(ThemeManager.shared.mode.preferred)
        .onReceive(NotificationCenter.default.publisher(for: .scrcpyInstalled)) { _ in
            scrcpy.refresh()
            if scrcpy.binaryPath != nil {
                dismiss()
                onDone()
            }
        }
    }
}
