import SwiftUI
import AppKit

/// ADB 파일 탐색기 콘텐츠 — 사이드바 즐겨찾기 · 컬럼 목록 · 드래그 전송
/// UI 형식: `RESEARCH_adb_file_browser` §7 (운영체제 탐색기 컬럼형)
struct FileBrowserContent: View {
    @ObservedObject var store: ConsoleStore
    @ObservedObject private var ctl = FileBrowserController.shared

    @State private var selection: Set<String> = []
    @State private var pathInput: String = FileBrowserController.shared.path
    @State private var query: String = ""
    @State private var sortKey: FileBrowserLogic.SortKey = .name
    @State private var sortAscending = true

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private var visible: [FileBrowserLogic.Item] {
        FileBrowserLogic.sort(
            FileBrowserLogic.filter(ctl.items, query: query),
            by: sortKey,
            ascending: sortAscending
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(OPColor.border)
            pathBar
            Divider().overlay(OPColor.border)
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 172)
                Divider().overlay(OPColor.border)
                listArea
            }
            Divider().overlay(OPColor.border)
            statusBar
        }
        .frame(minWidth: 760, minHeight: 480)
        .background(OPColor.popBG)
        .preferredColorScheme(ThemeManager.shared.mode.preferred)
        .onAppear {
            pathInput = ctl.path
            if ctl.serial.isEmpty, let serial = store.selectedSerial {
                ctl.open(serial: serial)
            }
        }
        .onChange(of: ctl.path) { _, newPath in
            pathInput = newPath
            selection = []
        }
    }

    // MARK: 툴바 — [표시①] 기기 ident · 가져오기 폴더 · 가져오기 실행

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text(L10n.string("files.title"))
                .font(OPFont.title(14))
                .foregroundStyle(OPColor.ink)
            if let d = store.selectedDevice {
                Text(d.identLabel)
                    .font(OPFont.number(10))
                    .foregroundStyle(OPColor.inkDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            if ctl.serial.isEmpty {
                Text(L10n.string("droid.empty.noDevice"))
                    .font(OPFont.number(10))
                    .foregroundStyle(OPColor.bad)
            }
            Spacer()
            Button {
                ctl.chooseDestDir()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                    Text((ctl.destDir as NSString).lastPathComponent)
                }
                .font(OPFont.body(11))
                .foregroundStyle(OPColor.inkDim)
                .lineLimit(1)
            }
            .buttonStyle(.plain)
            .help(L10n.format("files.dest.title", ctl.destDir))
            Button(L10n.string("files.pull.button")) {
                ctl.pull(selection: selection)
            }
            .buttonStyle(.plain)
            .font(OPFont.body(11))
            .foregroundStyle(selection.isEmpty ? OPColor.inkDim : OPColor.cta)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(selection.isEmpty ? OPColor.card : OPColor.cta.opacity(0.16), in: Capsule())
            .overlay(Capsule().stroke(selection.isEmpty ? OPColor.border : OPColor.cta, lineWidth: 1))
            .disabled(selection.isEmpty || ctl.busy || ctl.loading)
        }
        .padding(.horizontal, OPSpace.md)
        .padding(.vertical, 8)
    }

    // MARK: 경로 입력 · 검색 · 새로고침

    private var pathBar: some View {
        HStack(spacing: 6) {
            iconButton("chevron.up", help: L10n.string("files.nav.up")) { ctl.up() }
            TextField("", text: $pathInput)
                .textFieldStyle(.plain)
                .font(OPFont.number(11))
                .foregroundStyle(OPColor.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(OPColor.card, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(OPColor.border, lineWidth: 1))
                .onSubmit { ctl.navigate(to: pathInput) }
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(OPColor.inkDim)
                TextField("", text: $query)
                    .textFieldStyle(.plain)
                    .font(OPFont.body(11))
                    .foregroundStyle(OPColor.ink)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(OPColor.card, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(OPColor.border, lineWidth: 1))
            .frame(maxWidth: 180)
            iconButton("arrow.clockwise", help: L10n.string("files.nav.refresh")) { ctl.refresh() }
            Text("\(visible.count)")
                .font(OPFont.number(10))
                .foregroundStyle(OPColor.inkDim)
        }
        .padding(.horizontal, OPSpace.md)
        .padding(.vertical, 6)
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(OPColor.inkDim)
                .frame(width: 26, height: 26)
                .background(OPColor.card, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(OPColor.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: 사이드바 — 즐겨찾기

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(FileBrowserLogic.favorites.enumerated()), id: \.offset) { _, fav in
                    Button {
                        ctl.navigate(to: fav.path)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: iconFor(fav.label))
                                .font(.system(size: 11))
                                .frame(width: 14)
                            Text(fav.label)
                                .font(OPFont.body(11))
                                .lineLimit(1)
                            Spacer()
                        }
                        .foregroundStyle(ctl.path.hasPrefix(fav.path) ? OPColor.cta : OPColor.inkDim)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(
                        ctl.path.hasPrefix(fav.path)
                            ? OPColor.cta.opacity(0.14) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                }
            }
            .padding(OPSpace.sm)
        }
        .background(OPColor.card.opacity(0.35))
    }

    private func iconFor(_ label: String) -> String {
        switch label {
        case "Download": return "arrow.down.circle"
        case "DCIM": return "camera"
        case "Documents": return "doc.text"
        case "Movies": return "film"
        case "Pictures": return "photo"
        case "tmp": return "wrench.and.screwdriver"
        default: return "folder"
        }
    }

    // MARK: 목록

    private var listArea: some View {
        VStack(spacing: 0) {
            columnHeader
            Divider().overlay(OPColor.border)
            if ctl.loading && ctl.items.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visible.isEmpty {
                Text(L10n.string("files.empty"))
                    .font(OPFont.body(12))
                    .foregroundStyle(OPColor.inkDim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(visible.enumerated()), id: \.element.id) { idx, item in
                            rowView(idx: idx, item: item)
                        }
                    }
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            ctl.push(urls: urls)
            return true
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 8) {
            headerButton(L10n.string("files.column.name"), key: .name)
                .frame(maxWidth: .infinity, alignment: .leading)
            headerButton(L10n.string("files.column.size"), key: .size)
                .frame(width: 84, alignment: .trailing)
            headerButton(L10n.string("files.column.modified"), key: .modified)
                .frame(width: 132, alignment: .trailing)
        }
        .padding(.horizontal, OPSpace.md)
        .padding(.vertical, 7)
    }

    private func headerButton(_ title: String, key: FileBrowserLogic.SortKey) -> some View {
        Button {
            if sortKey == key {
                sortAscending.toggle()
            } else {
                sortKey = key
                sortAscending = true
            }
        } label: {
            HStack(spacing: 3) {
                Text(title)
                    .font(OPFont.body(11))
                if sortKey == key {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .foregroundStyle(sortKey == key ? OPColor.cta : OPColor.inkDim)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func rowView(idx: Int, item: FileBrowserLogic.Item) -> some View {
        let isSelected = selection.contains(item.id)
        return HStack(spacing: 8) {
            Image(systemName: item.isDir ? "folder.fill" : fileIcon(item))
                .font(.system(size: 12))
                .foregroundStyle(item.isDir ? OPColor.cta : OPColor.inkDim)
                .frame(width: 16)
            Text(item.name)
                .font(OPFont.number(11))
                .foregroundStyle(OPColor.ink)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(item.isDir ? "—" : FileBrowserLogic.formatSize(item.size))
                .font(OPFont.number(10))
                .foregroundStyle(OPColor.inkDim)
                .frame(width: 84, alignment: .trailing)
            Text(item.modified.map { Self.dateFmt.string(from: $0) } ?? "—")
                .font(OPFont.number(10))
                .foregroundStyle(OPColor.inkDim)
                .frame(width: 132, alignment: .trailing)
        }
        .padding(.horizontal, OPSpace.md)
        .padding(.vertical, 5)
        .background(
            isSelected ? OPColor.cta.opacity(0.18)
                : (idx % 2 == 1 ? OPColor.card.opacity(0.35) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            ctl.openItem(item)
        }
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.command) {
                if isSelected {
                    selection.remove(item.id)
                } else {
                    selection.insert(item.id)
                }
            } else {
                selection = [item.id]
            }
        }
        .contextMenu {
            Button(L10n.string("files.action.open")) { ctl.openItem(item) }
            Button(L10n.string("files.pull.button")) { ctl.pull(selection: [item.id]) }
        }
    }

    private func fileIcon(_ item: FileBrowserLogic.Item) -> String {
        switch (item.name as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "gif", "heic", "webp": return "photo.fill"
        case "mp4", "mkv", "mov", "avi": return "film.fill"
        case "mp3", "wav", "flac", "m4a": return "music.note"
        case "apk": return "app.fill"
        case "pdf": return "doc.richtext.fill"
        case "zip", "7z", "rar", "tar", "gz": return "archivebox.fill"
        default: return "doc.fill"
        }
    }

    // MARK: 상태줄 — [표시②] 실제 원인 노출

    private var statusBar: some View {
        HStack(spacing: 8) {
            if ctl.loading || ctl.busy {
                ProgressView()
                    .controlSize(.mini)
                Text(ctl.statusMessage ?? L10n.string("files.status.listing"))
                    .font(OPFont.number(10))
                    .foregroundStyle(OPColor.inkDim)
                    .lineLimit(1)
            } else {
                Text(ctl.statusMessage ?? L10n.string("files.hint.drop"))
                    .font(OPFont.number(10))
                    .foregroundStyle(ctl.statusMessage == nil ? OPColor.inkDim : OPColor.bad)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
                Spacer()
                Text(ctl.destDir)
                    .font(OPFont.number(10))
                    .foregroundStyle(OPColor.inkDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(L10n.format("files.dest.title", ctl.destDir))
            }
        }
        .padding(OPSpace.sm)
    }
}

/// 파일 탐색기 독립 윈도우 — 시스템 타이틀바 (WindowFocus 식별자 보강 포함)
struct FileBrowserWindowView: View {
    @ObservedObject var store: ConsoleStore

    var body: some View {
        FileBrowserContent(store: store)
            .background(WindowAccessor { w in
                w.identifier = NSUserInterfaceItemIdentifier("files")
            })
    }
}
