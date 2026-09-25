import SwiftUI

/// 신호 품질 5단계 — RSRP / RSRQ / SINR 실측 구간 기준
enum SignalGrade: String, CaseIterable, Sendable, Equatable {
    case excellent
    case good
    case fair
    case poor
    case bad

    /// 종합 점수(1…5) → 등급 (범위 밖은 양끝으로 클램프)
    static func from(score: Int) -> SignalGrade {
        if score >= 5 { return .excellent }
        switch score {
        case 4: return .good
        case 3: return .fair
        case 2: return .poor
        default: return .bad
        }
    }

    // MARK: - 개별 지표 구간 (1…5)

    static func rsrpScore(_ v: Int) -> Int {
        if v >= -80 { return 5 }
        if v >= -90 { return 4 }
        if v >= -100 { return 3 }
        if v >= -110 { return 2 }
        return 1
    }

    static func rsrqScore(_ v: Int) -> Int {
        if v >= -8 { return 5 }
        if v >= -10 { return 4 }
        if v >= -12 { return 3 }
        if v >= -15 { return 2 }
        return 1
    }

    static func sinrScore(_ v: Int) -> Int {
        if v >= 15 { return 5 }
        if v >= 8 { return 4 }
        if v >= 0 { return 3 }
        if v >= -5 { return 2 }
        return 1
    }

    // MARK: - 종합

    /// 가중 종합 = round((SINR×2 + RSRP + RSRQ) / 4)
    /// 실측 RSRP -99 / RSRQ -12 / SINR 4 → round((6+3+3)/4) = 3 → fair(보통)
    static func overall(rsrp: Int?, rsrq: Int?, sinr: Int?) -> SignalGrade? {
        guard let rsrp, let rsrq, let sinr else { return nil }
        let weighted = sinrScore(sinr) * 2 + rsrpScore(rsrp) + rsrqScore(rsrq)
        let mean = Double(weighted) / 4.0
        return from(score: Int(mean.rounded()))
    }

    var l10nKey: String { "signal.grade.\(rawValue)" }

    var label: String { L10n.string(l10nKey) }

    var color: Color {
        switch self {
        case .excellent, .good: return OPColor.ok
        case .fair: return OPColor.warn
        case .poor: return OPColor.thermal
        case .bad: return OPColor.bad
        }
    }
}

/// 네트워크 카드 제목 우측 등급칩 — 탭 시 진단 팝오버
struct SignalGradeChip: View {
    let device: DeviceSnapshot?
    @State private var showing = false

    private var grade: SignalGrade? {
        SignalGrade.overall(rsrp: device?.rsrp, rsrq: device?.rsrq, sinr: device?.sinr)
    }

    var body: some View {
        let tint = grade?.color ?? OPColor.inkDim
        Button {
            showing = true
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                Text(grade?.label ?? L10n.na)
                    .font(OPFont.body(9))
                    .foregroundStyle(tint)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.14)))
            .overlay(Capsule().stroke(tint.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(L10n.string("signal.diagnose.help"))
        .popover(isPresented: $showing) {
            SignalDiagnosePanel(device: device)
        }
    }
}

/// 진단 팝오버 본문 — 종합 등급 + 지표별 점수 + 접속망/밴드/CA
struct SignalDiagnosePanel: View {
    let device: DeviceSnapshot?

    var body: some View {
        let d = device
        let grade = SignalGrade.overall(rsrp: d?.rsrp, rsrq: d?.rsrq, sinr: d?.sinr)
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("signal.diagnose.title"))
                .font(OPFont.body(12))
                .foregroundStyle(OPColor.ink)

            SignalDiagnoseRow(
                title: L10n.string("signal.diagnose.overall"),
                value: nil,
                grade: grade
            )
            Divider().overlay(OPColor.border)
            scoreRow("RSRP", d?.rsrp) { SignalGrade.rsrpScore($0) }
            scoreRow("RSRQ", d?.rsrq) { SignalGrade.rsrqScore($0) }
            scoreRow("SINR", d?.sinr) { SignalGrade.sinrScore($0) }
            Divider().overlay(OPColor.border)
            metaRow(L10n.string("signal.diagnose.rat"), d?.signalRat ?? L10n.na)
            metaRow(L10n.string("signal.diagnose.band"), d?.signalBands ?? L10n.na)
            metaRow(
                L10n.string("signal.diagnose.ca"),
                d?.signalCA == nil
                    ? L10n.na
                    : (d?.signalCA == true
                        ? L10n.string("signal.diagnose.ca.on")
                        : L10n.string("signal.diagnose.ca.off"))
            )
        }
        .padding(16)
        .frame(width: 260, alignment: .leading)
        .background(OPColor.popBG)
    }

    private func scoreRow(_ title: String, _ raw: Int?, _ score: (Int) -> Int) -> some View {
        SignalDiagnoseRow(
            title: title,
            value: raw.map(String.init),
            grade: raw.map { SignalGrade.from(score: score($0)) }
        )
    }

    private func metaRow(_ title: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(OPFont.body(11))
                .foregroundStyle(OPColor.inkDim)
            Spacer()
            Text(value)
                .font(OPFont.number(11))
                .foregroundStyle(OPColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

/// 신호 진단 행 — 지표명 / 원시값(선택) / 등급
struct SignalDiagnoseRow: View {
    let title: String
    let value: String?
    let grade: SignalGrade?

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(OPFont.body(11))
                .foregroundStyle(OPColor.inkDim)
            Spacer()
            if let value {
                Text(value)
                    .font(OPFont.number(11))
                    .foregroundStyle(OPColor.ink)
            }
            Text(grade?.label ?? L10n.na)
                .font(OPFont.body(9))
                .foregroundStyle(grade?.color ?? OPColor.inkDim)
                .frame(minWidth: 44, alignment: .trailing)
        }
    }
}
