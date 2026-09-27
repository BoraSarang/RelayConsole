import SwiftUI
import AppKit
import Combine

/// logcat 실시간 스트림 — 창 id:"logs" (PLAN_v0.7)
///
/// ## 왜 이렇게 생겼나 (2026-09-27)
///
/// 종전 구현은 "초록 LIVE 인디케이터만 켜지고 줄이 영영 나오지 않는" 상태로 고착돼 있었다.
/// 근본 원인은 **stderr 미배출**이었다.
///
/// 1. **stderr 교착** — `proc.standardError = Pipe()` 만 해놓고 읽지 않았다. 파이프 버퍼(64KB)가
///    차면 adb 가 `write()` 에서 블로킹되고 **stdout 생산이 멈춘다**. 프로세스는 종료도 하지
///    않으니 `terminationHandler` 도 안 불린다. = 초록 점 + 빈 화면이 영구 지속.
///    (`ProcessRunner.swift` 가 같은 함정을 이미 문서화했다 — 스트리밍 경로만 빠진 상태였다)
/// 2. **LIVE 거짓말** — `isRunning` 이 `proc.run()` 성공에서만 켜졌다. "프로세스 기동됨"과
///    "데이터가 흐르는 중"을 구분하지 않았다. [AGENTS.local §4 표시②] 위반.
/// 3. **볼륨** — 이 기기는 6초에 20MB(약 3만 줄/초)를 뱉는다. 200줄 링은 **약 7ms 분량**이라
///    사람이 읽을 수 있는 정보가 전혀 없었다. 기본을 `W 이상`으로 좁히고 필터를 제공한다.
///
/// 배수는 `readabilityHandler`(전용 백그라운드 스레드)로 통일했다. 종전의
/// `NSFileHandleDataAvailable` 알림 펌프는 알림 注册/재무장 사이의 경쟁이 있었고,
/// 알림 기반이므로 런루프 상태에 예민했다.
@MainActor
final class LogcatStreamer: ObservableObject {
    static let shared = LogcatStreamer()

    /// 링 버퍼 한 줄 — SwiftUI 가 `offset` 를 id 로 쓰면 플러시마다 전 줄이 재렌더된다.
    /// 안정 id 를 부여해 스크롤·색칠이 유지되게 한다.
    struct Line: Identifiable, Equatable {
        let id: UInt64
        let text: String
    }

    /// 최소 레벨 필터 — 관제 기본은 `W` (D/I 는 초당 수만 줄이라 사람이 못 본다)
    enum MinLevel: String, CaseIterable, Identifiable, Sendable {
        case debug = "D", info = "I", warning = "W", error = "E"
        var id: String { rawValue }
        /// adb logcat 필터식 — `*:W` 형태
        var filterSpec: String { "*:\(rawValue)" }
    }

    @Published private(set) var lines: [Line] = []
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?
    /// 마지막으로 **실제 바이트**가 들어온 시각 — LIVE 표시의 진실
    @Published private(set) var lastDataAt: Date?
    /// 프로세스 기동 이후 받은 총 줄 수 (링 잘려도 실측량으로 남는다)
    @Published private(set) var totalLines: Int = 0
    /// 필터 변경 시 스트림을 다시 튼다 (이 값을 바꾸면 `restartOnLevelChange` 참조)
    @Published var minLevel: MinLevel = .warning

    /// `isLive` 판정용 틱 — 시간이 지나면 스스로 갱신되어야 "정지"를 감지한다
    @Published private var tick = Date()

    private var process: Process?
    private var tickTask: Task<Void, Never>?
    private let stderrTail = StderrTail()
    private var nextID: UInt64 = 0
    /// 링 버퍼 상한
    private let maxLines = 2000
    /// 이만큼 넘게 바이트가 없으면 "살아 있지만 멈춤" 으로 본다
    static let staleAfter: TimeInterval = 3

    private init() {}

    // MARK: - 상태 판정 (LIVE 표시의 정직한 정의)

    /// 프로세스도 살아 있고 데이터도 흐르는 중
    var isLive: Bool {
        guard isRunning, let at = lastDataAt else { return false }
        return Date().timeIntervalSince(at) < Self.staleAfter
    }

    /// 기동은 됐지만 아직 한 줄도 오지 않음 — 교착·오류 후보
    var isSilent: Bool { isRunning && lastDataAt == nil }

    /// 기동됐지만 데이터가 멈춤
    var isStalled: Bool {
        guard isRunning, let at = lastDataAt else { return false }
        return Date().timeIntervalSince(at) >= Self.staleAfter
    }

    /// 왜 안 나오는지 — [표시②] 실제 원인을 그대로 노출한다
    var silenceReason: String? {
        let tail = stderrTail.lastMeaningful
        if isSilent, let tail { return L10n.format("droid.logs.silent.err", tail) }
        if isSilent { return L10n.string("droid.logs.silent") }
        if isStalled, let tail { return L10n.format("droid.logs.stalled.err", tail) }
        if isStalled { return L10n.string("droid.logs.stalled") }
        return nil
    }

    // MARK: - 수명 주기

    func start(serial: String, adbPath: String?) {
        stop()
        guard let adb = adbPath, !serial.isEmpty else {
            lastError = ErrorCode.adbBinaryMissing.koMessage
            return
        }
        lastError = nil
        stderrTail.reset()
        lines.removeAll()
        nextID = 0
        totalLines = 0
        lastDataAt = nil
        tick = .now

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: adb)
        // 레벨 필터를 adb 쪽에서 적용 — 이 기기는 무필터 시 초당 3만 줄이라
        // 파이프가 살아 있어도 사람이 읽을 수 없다.
        proc.arguments = ["-s", serial, "logcat", "-v", "time", minLevel.filterSpec]
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        proc.terminationHandler = { [weak self] proc in
            let reason = Self.terminationReason(proc)
            Task { @MainActor in
                guard let self else { return }
                self.isRunning = false
                self.process = nil
                // 프로세스가 죽은 것은 실패다 — 원인을 남긴다 ([표시②])
                if proc.terminationStatus != 0 || proc.terminationReason == .uncaughtSignal {
                    self.lastError = reason
                }
            }
        }

        do {
            try proc.run()
        } catch {
            lastError = ErrorCode.adbConnectFailed.koMessage
            return
        }
        process = proc
        isRunning = true

        // ① stderr **배수** — 이것이 교착의 근본 해법이다. 64KB 버퍼가 차면
        //    adb 가 stdout 생산까지 멈춘다. 읽지 않으면 초록 점 + 빈 화면이 고착된다.
        let errHandle = err.fileHandleForReading
        errHandle.readabilityHandler = { [self] h in
            let data = h.availableData
            if data.isEmpty {
                h.readabilityHandler = nil
                return
            }
            stderrTail.append(String(decoding: data, as: UTF8.self))
        }

        // ② stdout 배수 — 알림 펌프 대신 전용 스레드 핸들러 (경합 없음).
        //    핸들러는 파일 핸들 전용 스레드에서 **직렬** 호출되므로 공유 버퍼가 필요 없다.
        let outHandle = out.fileHandleForReading
        outHandle.readabilityHandler = { [self] h in
            let data = h.availableData
            if data.isEmpty {
                h.readabilityHandler = nil
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            let batch = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard !batch.isEmpty else { return }
            Task { @MainActor in
                self.append(batch)
            }
        }

        // ③ 틱 — isLive/isStalled 는 시간 경과에 따라 스스로 갱신되어야 한다.
        //    값이 바뀌면 objectWillChange 가 울려 바디가 재평가되므로
        //    "3초 넘게 데이터 없음" 이 화면에도 반영된다.
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(700))
                guard let self else { return }
                self.tick = .now
            }
        }
    }

    func stop() {
        tickTask?.cancel()
        tickTask = nil
        if let p = process, p.isRunning {
            p.terminate()
        }
        process = nil
        isRunning = false
        lastDataAt = nil
    }

    // MARK: - 내부

    private func append(_ batch: [String]) {
        var next = lines
        for text in batch {
            next.append(Line(id: nextID, text: text))
            nextID &+= 1
        }
        totalLines &+= batch.count
        lastDataAt = .now
        if next.count > maxLines {
            next.removeFirst(next.count - maxLines)
        }
        lines = next
    }

    nonisolated private static func terminationReason(_ proc: Process) -> String {
        let status = proc.terminationStatus
        if proc.terminationReason == .uncaughtSignal {
            return L10n.format("droid.logs.term.signal", status)
        }
        return L10n.format("droid.logs.term.exit", status)
    }
}

/// stderr 스니펫 — 교착이 원인이면 **그 원인이 stderr 에 있다.**
/// 전체를 보관하지 않고 의미 있는 마지막 줄만 유지한다 (AGENTS.local §4 [표시②]).
private final class StderrTail: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    private var latest: String?

    func append(_ text: String) {
        lock.lock()
        buffer.append(text)
        // 상한 — adb 가 폭주해도 무한히 쌓지 않는다
        if buffer.count > 8192 { buffer = String(buffer.suffix(4096)) }
        if let line = ProcessRunner.lastMeaningfulLine(buffer) { latest = line }
        lock.unlock()
    }

    var lastMeaningful: String? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    func reset() {
        lock.lock()
        buffer = ""
        latest = nil
        lock.unlock()
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
                notice(
                    streamer.lastError ?? L10n.string("droid.logs.noDevice"),
                    icon: "exclamationmark.triangle",
                    tint: OPColor.warn
                )
            } else if let reason = streamer.silenceReason {
                notice(reason, icon: "pause.circle", tint: OPColor.warn)
            } else if streamer.lines.isEmpty {
                notice(L10n.string("droid.logs.empty"), icon: "clock", tint: OPColor.inkDim)
            } else {
                stream
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

    private var stream: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(streamer.lines) { line in
                        Text(line.text)
                            .font(OPFont.number(11))
                            .foregroundStyle(color(for: line.text))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .id(line.id)
                    }
                }
                .padding(OPSpace.sm)
            }
            .onChange(of: streamer.lines.last?.id) { _, _ in
                guard follow, let last = streamer.lines.last else { return }
                proxy.scrollTo(last.id, anchor: .bottom)
            }
            .onChange(of: serial) { _, s in
                restart(s)
            }
        }
    }

    private func notice(_ text: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(tint)
            Text(text)
                .font(OPFont.body(12))
                .foregroundStyle(OPColor.inkDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            // LIVE 는 **데이터가 흐르는 중** 일 때만 — 프로세스 기동이 아니고
            let live = streamer.isLive
            Circle().fill(live ? OPColor.ok : (streamer.isRunning ? OPColor.warn : OPColor.inkDim))
                .frame(width: 6, height: 6)
            Text(live
                 ? L10n.string("droid.logs.live")
                 : L10n.string("droid.logs.connecting"))
                .font(OPFont.number(10))
                .foregroundStyle(live ? OPColor.ok : OPColor.inkDim)
            if streamer.totalLines > 0 {
                Text(L10n.format("droid.logs.count", streamer.totalLines))
                    .font(OPFont.number(10))
                    .foregroundStyle(OPColor.inkDim)
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

            // 레벨 필터 — 무필터는 초당 3만 줄이라 사람이 볼 수 없다
            Picker("", selection: $streamer.minLevel) {
                ForEach(LogcatStreamer.MinLevel.allCases) { lv in
                    Text(lv.rawValue).tag(lv)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 132)
            .onChange(of: streamer.minLevel) { _, _ in
                streamer.start(serial: serial, adbPath: adbPath)
            }

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
