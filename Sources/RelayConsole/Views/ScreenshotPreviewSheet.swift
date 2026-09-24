import SwiftUI
import AppKit

/// A안 — 헤더 미니 썸네일 제거 · 📷 → 세로 폰 미리보기 시트
struct ScreenshotPreviewSheet: View {
    let serial: String
    @ObservedObject private var shots = ScreenshotService.shared
    @ObservedObject private var scrcpy = ScrcpyController.shared
    @Environment(\.dismiss) private var dismiss

    private var image: NSImage? { shots.images[serial] }
    private var updatedAt: Date? { shots.updatedAt[serial] }
    private var loading: Bool { shots.loadingSerials.contains(serial) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(OPColor.cta)
                Text(L10n.string("scrcpy.thumb.title"))
                    .font(OPFont.title(14))
                    .foregroundStyle(OPColor.ink)
                Spacer()
                if let at = updatedAt {
                    Text(at, style: .time)
                        .font(OPFont.number(11))
                        .foregroundStyle(OPColor.inkDim)
                }
            }

            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(OPColor.border, lineWidth: 1)
                    )

                if let img = image {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(6)
                } else if loading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(L10n.string("scrcpy.thumb.empty"))
                        .font(OPFont.body(12))
                        .foregroundStyle(OPColor.inkDim)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 400)

            HStack(spacing: 8) {
                Button {
                    shots.refresh(serial: serial, adbPath: DeviceMonitor.adbPathNow())
                } label: {
                    HStack(spacing: 4) {
                        if loading {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        Text(L10n.string("scrcpy.thumb.refresh"))
                            .font(OPFont.body(11))
                    }
                    .foregroundStyle(OPColor.cta)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(OPColor.card, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(OPColor.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(loading)

                Button {
                    dismiss()
                    scrcpy.launch(serial: serial)
                } label: {
                    Text(L10n.string("scrcpy.button.open"))
                        .font(OPFont.body(11))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(OPColor.cta.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(OPColor.cta, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(width: 300)
        .background(Color(hex: 0x0F111A))
        .preferredColorScheme(.dark)
        .onAppear {
            shots.refresh(serial: serial, adbPath: DeviceMonitor.adbPathNow())
        }
    }
}
