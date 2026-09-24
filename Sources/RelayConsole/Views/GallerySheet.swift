import SwiftUI
import AppKit

/// A4 갤러리 시트 — 로컬 스크랩북 그리드 · 현재 스샷 저장 · 기기 Screenshots pull
struct GallerySheet: View {
    var serial: String?
    @ObservedObject private var store = GalleryStore.shared
    @ObservedObject private var ctl = GalleryController.shared
    @State private var query = ""
    @State private var mode: Mode = .local
    @State private var confirmDelete: GalleryEntry?

    enum Mode: String, CaseIterable {
        case local
        case remote
    }

    private let columns = [
        GridItem(.adaptive(minimum: 110), spacing: 10)
    ]

    private var localVisible: [GalleryEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return store.entries }
        return store.entries.filter {
            $0.id.lowercased().contains(q)
                || ($0.serial ?? "").lowercased().contains(q)
                || $0.source.lowercased().contains(q)
        }
    }

    private var remoteVisible: [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return ctl.remoteNames }
        return ctl.remoteNames.filter { $0.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(OPColor.border)
            toolbar
            Divider().overlay(OPColor.border)

            if mode == .local {
                if localVisible.isEmpty {
                    empty(L10n.string("gallery.empty"))
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(localVisible) { entry in
                                localCell(entry)
                            }
                        }
                        .padding(OPSpace.md)
                    }
                }
            } else {
                if ctl.loading && ctl.remoteNames.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if remoteVisible.isEmpty {
                    empty(ctl.lastMessage ?? L10n.string("gallery.emptyRemote"))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(remoteVisible, id: \.self) { name in
                                remoteRow(name)
                                if name != remoteVisible.last {
                                    Divider().overlay(OPColor.border)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Divider().overlay(OPColor.border)
            statusLine
        }
        .frame(minWidth: 560, minHeight: 420)
        .background(Color(hex: 0x0F111A))
        .preferredColorScheme(.dark)
        .onAppear {
            store.reload()
            if mode == .remote, let s = serial { ctl.listRemote(serial: s) }
        }
        .confirmationDialog(
            L10n.format("gallery.confirm.delete", confirmDelete?.id ?? ""),
            isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
            )
        ) {
            Button(L10n.string("gallery.action.delete"), role: .destructive) {
                if let e = confirmDelete { store.delete(e) }
                confirmDelete = nil
            }
            Button(L10n.string("alerts.note.cancel"), role: .cancel) {
                confirmDelete = nil
            }
        }
    }

    private var header: some View {
        HStack {
            Text(L10n.string("gallery.title"))
                .font(OPFont.title(14))
                .foregroundStyle(OPColor.ink)
            Spacer()
            Picker("", selection: $mode) {
                Text(L10n.string("gallery.mode.local")).tag(Mode.local)
                Text(L10n.string("gallery.mode.remote")).tag(Mode.remote)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .labelsHidden()
            Button {
                store.openRoot()
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(OPColor.cta)
                    .frame(width: 24, height: 24)
                    .background(OPColor.cta.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help(L10n.string("gallery.action.openFolder"))
        }
        .padding(OPSpace.md)
        .onChange(of: mode) { _, m in
            if m == .remote, let s = serial {
                ctl.listRemote(serial: s)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(OPColor.inkDim)
            TextField(L10n.string("gallery.search"), text: $query)
                .textFieldStyle(.plain)
                .font(OPFont.body(12))
                .foregroundStyle(OPColor.ink)
            Text(L10n.format(
                "gallery.count",
                mode == .local ? "\(localVisible.count)" : "\(remoteVisible.count)"
            ))
            .font(OPFont.number(11))
            .foregroundStyle(OPColor.inkDim)

            Spacer()

            if mode == .local {
                Button {
                    if let s = serial { ctl.saveCurrent(serial: s) }
                } label: {
                    actionLabel("camera", L10n.string("gallery.action.saveCurrent"))
                }
                .buttonStyle(.plain)
                .disabled(serial == nil)
                .help(L10n.string("gallery.action.saveCurrent.help"))
            } else {
                Button {
                    if let s = serial { ctl.listRemote(serial: s) }
                } label: {
                    actionLabel("arrow.clockwise", L10n.string("gallery.action.refresh"))
                }
                .buttonStyle(.plain)
                .disabled(ctl.loading || serial == nil)
            }
        }
        .padding(.horizontal, OPSpace.md)
        .padding(.vertical, 8)
    }

    private func actionLabel(_ icon: String, _ title: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(OPFont.number(10))
        }
        .foregroundStyle(OPColor.cta)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(OPColor.cta.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(OPColor.cta.opacity(0.35), lineWidth: 1))
        .contentShape(Rectangle())
    }

    private func localCell(_ entry: GalleryEntry) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.45))
                if let img = NSImage(contentsOf: entry.url) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(OPColor.inkDim)
                }
            }
            .frame(height: 96)
            .clipped()
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(OPColor.border, lineWidth: 1)
            )

            HStack {
                Text(entry.createdAt, style: .date)
                    .font(OPFont.number(9))
                    .foregroundStyle(OPColor.inkDim)
                    .lineLimit(1)
                Spacer()
                Button {
                    store.reveal(entry)
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(OPColor.cta)
                }
                .buttonStyle(.plain)
                .help(L10n.string("gallery.action.reveal"))
                Button {
                    confirmDelete = entry
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(OPColor.bad)
                }
                .buttonStyle(.plain)
                .help(L10n.string("gallery.action.delete"))
            }
        }
        .contextMenu {
            Button(L10n.string("gallery.action.reveal")) { store.reveal(entry) }
            Button(L10n.string("gallery.action.delete"), role: .destructive) {
                confirmDelete = entry
            }
        }
    }

    private func remoteRow(_ name: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 11))
                .foregroundStyle(OPColor.inkDim)
            Text(name)
                .font(OPFont.body(12))
                .foregroundStyle(OPColor.ink)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if ctl.busyFile == name {
                ProgressView().controlSize(.mini)
            } else {
                Button {
                    if let s = serial { ctl.pullRemote(serial: s, file: name) }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(OPColor.ok)
                        .frame(width: 22, height: 22)
                        .background(OPColor.ok.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help(L10n.string("gallery.action.pull"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .font(OPFont.body(12))
            .foregroundStyle(OPColor.inkDim)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusLine: some View {
        Text(ctl.lastMessage ?? " ")
            .font(OPFont.body(11))
            .foregroundStyle(OPColor.inkDim)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(OPSpace.sm)
    }
}
