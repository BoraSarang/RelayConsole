import SwiftUI
import AppKit

/// 프로세스 목록 — 이름 · PID · CPU · RAM · 경로 (정렬 테이블)
/// 메뉴바: 독립 윈도우 (팝오버 시트 닫힘 방지) · 대시보드: 시트 공용
struct ProcessListContent: View {
    @ObservedObject var store: ConsoleStore
    var onClose: (() -> Void)?
    /// true: 독립 창 — 시스템 타이틀바가 제목/닫기를 담당 (콘텐츠 헤더 제목 생략)
    var windowMode: Bool = false

    private enum SortKey: String, CaseIterable {
        case cpu, rss, name, pid, path
    }

    @State private var sortKey: SortKey = .cpu

    private var device: DeviceSnapshot? { store.selectedDevice }
    private var rows: [ProcessRow] { device?.processList ?? [] }

    private var sorted: [ProcessRow] {
        switch sortKey {
        case .cpu:
            return rows.sorted {
                let a = $0.cpuPercent ?? -1
                let b = $1.cpuPercent ?? -1
                if a != b { return a > b }
                return ($0.rssMB ?? 0) > ($1.rssMB ?? 0)
            }
        case .rss:
            return rows.sorted { ($0.rssMB ?? 0) > ($1.rssMB ?? 0) }
        case .name:
            return rows.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .pid:
            return rows.sorted { ($0.pid ?? -1) < ($1.pid ?? -1) }
        case .path:
            return rows.sorted {
                ($0.path ?? "").localizedCaseInsensitiveCompare($1.path ?? "") == .orderedAscending
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
                Text(L10n.string("droid.process.empty"))
                    .font(OPFont.body(12))
                    .foregroundStyle(OPColor.inkDim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            Text(L10n.string("droid.process.hint"))
                .font(OPFont.number(10))
                .foregroundStyle(OPColor.inkDim)
                .padding(OPSpace.sm)
        }
        .frame(minWidth: 560, minHeight: 480)
        .background(OPColor.popBG)
        .preferredColorScheme(ThemeManager.shared.mode.preferred)
    }

    private var header: some View {
        HStack {
            if !windowMode {
                Text(L10n.format("droid.process.title", device?.displayName ?? L10n.na))
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
            headerButton(L10n.string("droid.process.col.name"), key: .name)
                .frame(maxWidth: .infinity, alignment: .leading)
            headerButton(L10n.string("droid.process.col.pid"), key: .pid)
                .frame(width: 52, alignment: .trailing)
            headerButton(L10n.string("droid.process.col.cpu"), key: .cpu)
                .frame(width: 52, alignment: .trailing)
            headerButton(L10n.string("droid.process.col.ram"), key: .rss)
                .frame(width: 60, alignment: .trailing)
            headerButton(L10n.string("droid.process.col.path"), key: .path)
                .frame(width: 200, alignment: .leading)
        }
        .padding(.horizontal, OPSpace.md)
        .padding(.vertical, 8)
    }

    private func rowView(idx: Int, row: ProcessRow) -> some View {
        HStack(spacing: 8) {
            Text(row.name)
                .font(OPFont.number(11))
                .foregroundStyle(OPColor.ink)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.pid.map(String.init) ?? L10n.na)
                .font(OPFont.number(10))
                .foregroundStyle(OPColor.inkDim)
                .frame(width: 52, alignment: .trailing)
            Text(row.cpuPercent.map { String(format: "%.1f%%", $0) } ?? L10n.na)
                .font(OPFont.number(11))
                .foregroundStyle(row.cpuPercent.map { $0 >= 50 ? OPColor.bad : OPColor.cta } ?? OPColor.inkDim)
                .frame(width: 52, alignment: .trailing)
            Text(row.rssMB.map { String(format: "%.0f MB", $0) } ?? L10n.na)
                .font(OPFont.number(11))
                .foregroundStyle(OPColor.inkDim)
                .frame(width: 60, alignment: .trailing)
            Text(displayCommand(row.path))
                .font(OPFont.number(10))
                .foregroundStyle(OPColor.inkDim)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 200, alignment: .leading)
                .help(row.path ?? "")
                .textSelection(.enabled)
        }
        .padding(.horizontal, OPSpace.md)
        .padding(.vertical, 5)
        .background(idx % 2 == 1 ? OPColor.card.opacity(0.35) : Color.clear)
    }

    /// ARGS 표시 — 패키지 ID는 그대로, 긴 경로는 말줄임 (호버 툴팁 전체)
    private func displayCommand(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return L10n.na }
        return raw
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

/// 시트용 래퍼 (대시보드)
struct ProcessListSheet: View {
    @ObservedObject var store: ConsoleStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ProcessListContent(store: store) { dismiss() }
    }
}

/// 메뉴바용 독립 윈도우 — 시스템 타이틀바(제목·닫기) 사용, 콘텐츠 헤더 제목 제거
struct ProcessListWindowView: View {
    @ObservedObject var store: ConsoleStore

    var body: some View {
        ProcessListContent(store: store, windowMode: true)
            .background(WindowAccessor { w in
                w.identifier = NSUserInterfaceItemIdentifier("processes")
            })
    }
}

/// 윈도우 identifier 보강 — WindowFocus.present(sceneID:) 매칭용
private struct WindowAccessor: NSViewRepresentable {
    var configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            if let w = v.window { configure(w) }
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let w = nsView.window { configure(w) }
        }
    }
}
