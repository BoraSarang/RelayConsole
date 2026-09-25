import SwiftUI
import AppKit
import Combine

/// logcat 실시간 스트림 — 창 id:"logs" (PLAN_v0.7)
@MainActor
final class LogcatStreamer: ObservableObject {
    static let shared = LogcatStreamer()

    @Published private(set) var lines: [String] = []
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?

    private var process: Process?
    private var readTask: Task<Void, Never>?
    private let maxLines = 200

    private init() {}

    func start(serial: String, adbPath: String?) {
        stop()
        guard let adb = adbPath, !serial.isEmpty else {
            lastError = ErrorCode.adbBinaryMissing.koMessage
            return
        }
        lastError = nil
        lines.removeAll()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: adb)
        proc.arguments = ["-s", serial, "logcat", "-v", "time"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.isRunning = false
                self?.process = nil
            }
        }

        do {
            try proc.run()
            process = proc
            isRunning = true
        } catch {
            lastError = ErrorCode.adbConnectFailed.koMessage
            return
        }

        let handle = out.fileHandleForReading
        readTask = Task { [weak self] in
            handle.waitForDataInBackgroundAndNotify()
            for await note in NotificationCenter.default.notifications(named: .NSFileHandleDataAvailable, object: handle) {
                guard !Task.isCancelled else { break }
                let data = note.userInfo?[NSFileHandleNotificationDataItem] as? Data ?? Data()
                if data.isEmpty {
                    // EOF — 프로세스 종료 대기
                    if let self, self.process == nil { break }
                    handle.waitForDataInBackgroundAndNotify()
                    continue
                }
                let text = String(decoding: data, as: UTF8.self)
                if let self {
                    await MainActor.run { self.append(text) }
                }
                handle.waitForDataInBackgroundAndNotify()
            }
        }
    }

    func stop() {
        readTask?.cancel()
        readTask = nil
        process?.terminate()
        process = nil
        isRunning = false
    }

    private func append(_ chunk: String) {
        let parts = chunk.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty else { return }
        lines.append(contentsOf: parts)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }
}

/// 로그 뷰어 콘텐츠 — 시트/윈도우 공용
struct LogViewerContent: View {
    @ObservedObject private var streamer = LogcatStreamer.shared
    @ObservedObject var store: ConsoleStore
    var onClose: (() -> Void)?
    /// true: 독립 창 — 시스템 타이틀바가 제목/닫기를 담당
    var windowMode: Bool = false

    @State private var follow = true

    private var serial: String { store.selectedSerial ?? "" }
    private var adbPath: String? { DeviceMonitor.adbPathNow() }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(OPColor.border)

            if streamer.lastError != nil || serial.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(OPColor.warn)
                    Text(streamer.lastError ?? L10n.string("droid.logs.noDevice"))
                        .font(OPFont.body(12))
                        .foregroundStyle(OPColor.inkDim)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if streamer.lines.isEmpty {
                Text(L10n.string("droid.logs.empty"))
                    .font(OPFont.body(12))
                    .foregroundStyle(OPColor.inkDim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(streamer.lines.enumerated()), id: \.offset) { idx, line in
                                Text(line)
                                    .font(OPFont.number(11))
                                    .foregroundStyle(color(for: line))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                    .id(idx)
                            }
                        }
                        .padding(OPSpace.sm)
                    }
                    .onChange(of: streamer.lines.count) { _, c in
                        guard follow, c > 0 else { return }
                        proxy.scrollTo(c - 1, anchor: .bottom)
                    }
                    .onChange(of: serial) { _, s in
                        restart(s)
                    }
                }
            }

            Divider().overlay(OPColor.border)
            footer
        }
        .frame(minWidth: 640, minHeight: 420)
        .background(OPColor.popBG)
        .preferredColorScheme(ThemeManager.shared.mode.preferred)
        .onAppear { restart(serial) }
        .onDisappear { streamer.stop() }
    }

    private func restart(_ s: String) {
        guard !s.isEmpty else { streamer.stop(); return }
        streamer.start(serial: s, adbPath: adbPath)
    }

    private func color(for line: String) -> Color {
        if line.contains(" E/") || line.contains(" E ") { return OPColor.bad }
        if line.contains(" W/") || line.contains(" W ") { return OPColor.warn }
        return OPColor.inkDim
    }

    private var header: some View {
        HStack {
            if windowMode {
                if let name = store.selectedDevice?.displayName {
                    Text(name)
                        .font(OPFont.number(12))
                        .foregroundStyle(OPColor.inkDim)
                        .lineLimit(1)
                }
            } else {
                Text(L10n.format("droid.logs.title", store.selectedDevice?.displayName ?? L10n.na))
                    .font(OPFont.title(14))
                    .foregroundStyle(OPColor.ink)
                    .lineLimit(1)
            }
            Spacer()
            if streamer.isRunning {
                Circle().fill(OPColor.ok).frame(width: 6, height: 6)
                Text(L10n.string("droid.logs.live"))
                    .font(OPFont.number(10))
                    .foregroundStyle(OPColor.ok)
            }
            if onClose != nil {
                Button(L10n.string("droid.logs.close")) { onClose?() }
                    .buttonStyle(.plain)
                    .foregroundStyle(OPColor.inkDim)
            }
        }
        .padding(OPSpace.md)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                if streamer.isRunning {
                    streamer.stop()
                } else {
                    restart(serial)
                }
            } label: {
                Text(streamer.isRunning
                    ? L10n.string("droid.logs.stop")
                    : L10n.string("droid.logs.start"))
                    .font(OPFont.body(11))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(OPColor.card, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(OPColor.border, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Toggle(L10n.string("droid.logs.follow"), isOn: $follow)
                .toggleStyle(.checkbox)
                .font(OPFont.body(11))

            Spacer()
            Text(L10n.string("droid.logs.ring"))
                .font(OPFont.number(10))
                .foregroundStyle(OPColor.inkDim)
        }
        .padding(OPSpace.sm)
    }
}

struct LogViewerSheet: View {
    @ObservedObject var store: ConsoleStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        LogViewerContent(store: store) { dismiss() }
    }
}

struct LogViewerWindowView: View {
    @ObservedObject var store: ConsoleStore
    var body: some View {
        LogViewerContent(store: store, windowMode: true)
            .background(WindowAccessorLogs { w in
                w.identifier = NSUserInterfaceItemIdentifier("logs")
            })
    }
}

private struct WindowAccessorLogs: NSViewRepresentable {
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
