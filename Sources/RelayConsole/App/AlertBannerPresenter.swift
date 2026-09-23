import AppKit
import SwiftUI

/// 알림형 상단 배너 — 메뉴 팝오버와 별개, 시스템 알림처럼 화면 상단에 잠시 표시
@MainActor
final class AlertBannerPresenter {
    static let shared = AlertBannerPresenter()

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private var host: NSHostingView<AlertBannerView>?

    private let bannerWidth: CGFloat = 360
    private let bannerHeight: CGFloat = 72
    private let showDuration: TimeInterval = 4.0

    private init() {}

    func show(event: WatchEvent, deviceName: String) {
        hideWork?.cancel()

        let title: String
        let body: String
        if event.isClear {
            title = L10n.format("alert.banner.cleared", deviceName)
            body = event.title
        } else {
            title = L10n.format("alert.banner.notify", deviceName)
            body = event.detail.isEmpty ? event.title : "\(event.title) — \(event.detail)"
        }

        let model = AlertBannerModel(
            title: title,
            body: body,
            severity: event.severity,
            isClear: event.isClear
        )
        let view = AlertBannerView(model: model)

        if let host {
            host.rootView = view
        } else {
            let newHost = NSHostingView(rootView: view)
            newHost.frame = NSRect(x: 0, y: 0, width: bannerWidth, height: bannerHeight)
            host = newHost

            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: bannerWidth, height: bannerHeight),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.isFloatingPanel = true
            p.level = .statusBar
            p.identifier = NSUserInterfaceItemIdentifier(WindowFocus.alertBannerWindowID)
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = true
            p.isMovableByWindowBackground = true
            p.hidesOnDeactivate = false
            p.contentView = newHost
            panel = p
        }

        positionPanel()
        panel?.orderFrontRegardless()

        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.panel?.orderOut(nil)
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + showDuration, execute: work)
    }

    func dismiss() {
        hideWork?.cancel()
        panel?.orderOut(nil)
    }

    private func positionPanel() {
        guard let panel, let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let x = visible.maxX - bannerWidth - 16
        let y = visible.maxY - bannerHeight - 16
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

struct AlertBannerModel: Equatable {
    let title: String
    let body: String
    let severity: WatchSeverity
    let isClear: Bool
}

struct AlertBannerView: View {
    let model: AlertBannerModel

    private var accent: Color {
        if model.isClear { return OPColor.ok }
        switch model.severity {
        case .critical: return OPColor.bad
        case .warning: return OPColor.warn
        case .info: return OPColor.cta
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(accent)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.title)
                    .font(OPFont.body(13))
                    .foregroundStyle(OPColor.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(model.body)
                    .font(OPFont.body(11))
                    .foregroundStyle(OPColor.inkDim)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(OPSpace.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(OPColor.card.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(accent.opacity(0.55), lineWidth: 1)
        )
        .padding(4)
    }
}
