import SwiftUI
import AppKit

/// 앱(패키지)별 네트워크 사용량 목록 — `dumpsys netstats detail` delta (MB/s)
/// 메뉴바/플로팅에서 열리는 독립 창 · 대시보드에서는 시트로도 사용
struct AppNetworkContent: View {
    @ObservedObject var store: ConsoleStore
    var onClose: (() -> Void)?
    /// true: 독립 창 — 시스템 타이틀바가 제목/닫기를 담당
    var windowMode: Bool = false

    private enum SortKey: String, CaseIterable {
        case total, down, up, name
    }

    @State private var sortKey: SortKey = .total

    private var device: DeviceSnapshot? { store.selectedDevice }
    private var rates: [AppNetRate] { device?.appNetRates ?? [] }
    private var totals: [Int: AppNetStat] {
        Dictionary((device?.appNetStats ?? []).map { ($0.uid, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private var sorted: [AppNetRate] {
        switch sortKey {
        case .total:
            return rates.sorted { $0.totalMBps > $1.totalMBps }
        case .down:
            return rates.sorted { $0.downMBps > $1.downMBps }
        case .up:
            return rates.sorted { $0.upMBps > $1.upMBps }
        case .name:
            return rates.sorted {
                ($0.packageName ?? "uid \($0.uid)")
                    .localizedCaseInsensitiveCompare($1.packageName ?? "uid \($1.uid)") == .orderedAscending
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(OPColor.border)
            columnHeader
            Divider().overlay(OPColor.border)

            if sorted.isEmpty {
                VStack(spacing: 8) {
                    Text(L10n.string("droid.appnet.empty"))
                        .font(OPFont.body(12))
                        .foregroundStyle(OPColor.inkDim)
                    Text(L10n.string("droid.appnet.emptyHint"))
                        .font(OPFont.number(10))
                        .foregroundStyle(OPColor.inkDim.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(OPSpace.lg)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, row in
                            rowView(idx: idx, row: row)
                        }
                    }
                }
            }

            Divider().overlay(OPColor.border)
            Text(L10n.string("droid.appnet.hint"))
                .font(OPFont.number(10))
                .foregroundStyle(OPColor.inkDim)
                .padding(OPSpace.sm)
        }
        .frame(minWidth: 520, minHeight: 420)
        .background(OPColor.popBG)
        .preferredColorScheme(ThemeManager.shared.mode.preferred)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if !windowMode {
                Text(L10n.format("droid.appnet.title", device?.displayName ?? L10n.na))
                    .font(OPFont.title(14))
                    .foregroundStyle(OPColor.ink)
                    .lineLimit(1)
            } else if let name = device?.displayName {
                Text(name)
                    .font(OPFont.number(12))
                    .foregroundStyle(OPColor.inkDim)
                    .lineLimit(1)
            }
            Spacer()
            if onClose != nil {
                Button(L10n.string("droid.process.close")) { onClose?() }
                    .buttonStyle(.plain)
                    .foregroundStyle(OPColor.inkDim)
            }
        }
        .padding(OPSpace.md)
    }

    private var columnHeader: some View {
        HStack(spacing: 8) {
            headerButton(L10n.string("droid.appnet.col.app"), key: .name)
                .frame(maxWidth: .infinity, alignment: .leading)
            headerButton(L10n.string("droid.appnet.col.up"), key: .up)
                .frame(width: 90, alignment: .trailing)
            headerButton(L10n.string("droid.appnet.col.down"), key: .down)
                .frame(width: 90, alignment: .trailing)
            headerButton(L10n.string("droid.appnet.col.total"), key: .total)
                .frame(width: 90, alignment: .trailing)
            Text(L10n.string("droid.appnet.col.cumulative"))
                .font(OPFont.body(11))
                .foregroundStyle(OPColor.inkDim)
                .frame(width: 96, alignment: .trailing)
        }
        .padding(.horizontal, OPSpace.md)
        .padding(.vertical, 8)
    }

    private func rowView(idx: Int, row: AppNetRate) -> some View {
        HStack(spacing: 8) {
            Text(row.packageName ?? "uid \(row.uid)")
                .font(OPFont.number(11))
                .foregroundStyle(OPColor.ink)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(row.packageName ?? String(row.uid))
            rateCell(row.upMBps)
                .frame(width: 90, alignment: .trailing)
            rateCell(row.downMBps)
                .frame(width: 90, alignment: .trailing)
            rateCell(row.totalMBps)
                .frame(width: 90, alignment: .trailing)
            Text(cumulative(row.uid))
                .font(OPFont.number(11))
                .foregroundStyle(OPColor.inkDim)
                .frame(width: 96, alignment: .trailing)
        }
        .padding(.horizontal, OPSpace.md)
        .padding(.vertical, 5)
        .background(idx % 2 == 1 ? OPColor.card.opacity(0.35) : Color.clear)
    }

    private func rateCell(_ mbps: Double) -> some View {
        let f = AdbClient.formatNetRate(mbps)
        return Text(f.unit.isEmpty ? f.value : "\(f.value) \(f.unit)")
            .font(OPFont.number(11))
            .foregroundStyle(mbps > 0 ? OPColor.ok : OPColor.inkDim)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }

    private func cumulative(_ uid: Int) -> String {
        totals[uid].map { AdbClient.formatBytes($0.totalBytes) } ?? L10n.na
    }

    private func headerButton(_ title: String, key: SortKey) -> some View {
        Button {
            sortKey = key
        } label: {
            HStack(spacing: 3) {
                Text(title)
                    .font(OPFont.body(11))
                if sortKey == key {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .foregroundStyle(sortKey == key ? OPColor.cta : OPColor.inkDim)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 시트용 래퍼 (대시보드 네트워크 카드 더보기)
struct AppNetworkSheet: View {
    @ObservedObject var store: ConsoleStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AppNetworkContent(store: store) { dismiss() }
    }
}

/// 독립 윈도우 — 시스템 타이틀바(제목·닫기) 사용
struct AppNetworkWindowView: View {
    @ObservedObject var store: ConsoleStore

    var body: some View {
        AppNetworkContent(store: store, windowMode: true)
            .background(WindowAccessor { w in
                w.identifier = NSUserInterfaceItemIdentifier("appnetwork")
            })
    }
}
