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

/// 5분 링 히스토리 라인 (DroidMetrics 60점) — solid only, material 없음
struct OPSparkline: View {
    let points: [Double]
    var color: Color = OPColor.cta
    var height: CGFloat = 18
    var lineWidth: CGFloat = 1.5

    var body: some View {
        Group {
            if points.count >= 2 {
                GeometryReader { geo in
                    let minV = points.min() ?? 0
                    let maxV = points.max() ?? 1
                    ZStack {
                        // baseline — 데이터 부족 시에도 영역 유지
                        Rectangle()
                            .fill(color.opacity(0.2))
                            .frame(height: 1)
                        Path { path in
                            let rawRange = maxV - minV
                            let flat = rawRange < 0.0001
                            for (i, v) in points.enumerated() {
                                let x = geo.size.width * CGFloat(i) / CGFloat(points.count - 1)
                                // 상수 구간: 중앙 평선 (min==max → 하단 고정 방지)
                                let y: CGFloat = flat
                                    ? geo.size.height * 0.5
                                    : geo.size.height * (1 - CGFloat((v - minV) / rawRange))
                                if i == 0 {
                                    path.move(to: CGPoint(x: x, y: y))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                        }
                        .stroke(color, lineWidth: lineWidth)
                    }
                }
                .frame(height: height)
                .clipped()
            } else {
                // 점 1개 이하: 가로 baseline 유지 (레이아웃 깨짐 방지)
                Rectangle()
                    .fill(color.opacity(0.25))
                    .frame(height: 2)
                    .frame(height: height)
            }
        }
    }
}
