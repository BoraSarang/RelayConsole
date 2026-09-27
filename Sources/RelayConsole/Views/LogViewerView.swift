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
/// `NSFileHandleDataAvailable` 알림 펌프는 알림 등록/재무장 사이의 경쟁이 있었고,
/// 알림 기반이므로 런루프 상태에 예민했다.
/// 로그 검색 — 판단 로직을 **순수 함수**로 분리한다 (2026-09-27 · PLAN_log_search)
///
/// 왜 분리했나: `LogcatStreamer` 는 싱글턴이고 `start()` 가 실제 adb 를 필요로 해서
/// "검색 중인데 0줄" 상태를 단위 테스트로 고정할 방법이 없다. 판단만 떼어 내면 고정된다.
enum LogcatFilter {
    /// 검색에 자주 쓰이는 신호 — 실패만, 상태 변화는 넣지 않는다
    /// (2026-09-27: `thermal`·`accelerometer_rotation` 같은 상태 변화는 실패 신호가 아니다)
    static let presets: [String] = ["ANR", "FATAL EXCEPTION", "has died", "dropbox"]

    /// adb `logcat --regex=<패턴>` 에 넘길 값.
    ///
    /// - 빈 검색어 → `nil` (= 기기 필터 없음)
    /// - **메타문자는 반드시 이스케이프한다** — 계약은 "단순 문자열" 이므로 `a.b` 가 `a 임의 문자 b` 로
    ///   해석돼서는 안 된다. 잘못 이스케이프를 빼면 사용자가 검색을 못 하는 것보다 나쁘다.
    /// - 대소문자 무시 → `(?i)` 접두. logcat `--regex` 는 Java `Pattern` 이므로 지원된다.
    static func pattern(for query: String, caseInsensitive: Bool) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let escaped = NSRegularExpression.escapedPattern(for: trimmed)
        return caseInsensitive ? "(?i)\(escaped)" : escaped
    }

    /// 링 버퍼 2차 필터 — adb 가 아직 따라오기 전(디바운스 중)에도 즉시 반응한다.
    /// adb `--regex` 미지원 기기에서도 여기가 최종 방어선이 된다.
    static func matches(_ text: String, query: String, caseInsensitive: Bool) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        return caseInsensitive
            ? text.lowercased().contains(trimmed.lowercased())
            : text.contains(trimmed)
    }

    /// 무관한 값을 보여주는 이유 — [표시②] 실제 상태를 구분해 그대로 말한다.
    ///
    /// 핵심 구분: **검색 중인데 0줄** 과 **데이터가 안 옴** 은 다른 상태다.
    /// 검색 중인데 "데이터 없음" 이라 하면 기기가 멀쩡한데 사용자는 오류라고 읽는다.
    /// 반대로 adb 오류(stderr)가 있으면 "일치 없음" 으로 덮지 않고 **원인을 그대로** 보여준다.
    static func silence(
        query: String,
        stderr: String?,
        isSilent: Bool,
        isStalled: Bool
    ) -> (key: String, args: [CVarArg])? {
        let hasQuery = !query.trimmingCharacters(in: .whitespaces).isEmpty
        if isSilent {
            if hasQuery {
                if let stderr, !stderr.isEmpty { return ("droid.logs.search.none.err", [stderr]) }
                return ("droid.logs.search.none", [query])
            }
            if let stderr, !stderr.isEmpty { return ("droid.logs.silent.err", [stderr]) }
            return ("droid.logs.silent", [])
        }
        if isStalled {
            if let stderr, !stderr.isEmpty { return ("droid.logs.stalled.err", [stderr]) }
            return ("droid.logs.stalled", [])
        }
        return nil
    }
}

/// 기동 중인 프로세스 **한 개의 자리** — 종료 알림이 "이전 프로세스" 것인지 판별한다.
///
/// ## 왜 이 클래스가 있나 (2026-09-27 실측)
///
/// `Process.terminationHandler` 는 `Task { @MainActor }` 로 **나중에** 실행된다.
/// 필터를 바꿀 때마다 일어나는 실제 순서는 이렇다:
///
/// ```
/// stop()  → 이전 프로세스 terminate() → 이전 프로세스 죽음 → 슬롯 비움
///                                                          └─ 이 알림이 메인액터에 **큐잉**
/// start() → 새 프로세스 run() → 슬롯에 새 프로세스 adopt
///                       ... 잠시 후 ...
///                  이전 프로세스 알림 도착 → 슬롯을 비워버림
/// ```
///
/// 마지막 한 줄이 범인이다. **살아 있는 새 프로세스의 참조가 사라져** 다음 필터 전환 때
/// `stop()` 이 그 프로세스를 죽이지 못하고, adb logcat 가 전환 횟수만큼 **누적된다**.
/// 실측: 필터 4회 전환 → adb logcat 4개가 동시 생존(규칙은 최대 1개).
/// 셸에서 `kill -TERM` 은 즉시 죽으므로 adb 문제는 아니었다 — 참조가 사라진 것이 원인.
final class LogcatProcessSlot {
    /// 현재 기동 중(또는 기동 대상)인 프로세스
    private(set) var current: Process?

    func adopt(_ process: Process?) { current = process }

    /// 종료 알림을 반영한다 — **내가 지금 들고 있는 그 프로세스** 일 때만 정리하고 `true`.
    /// 이전 프로세스의 알림이면 아무것도 하지 않고 `false` (아래가 그 회귀 테스트의 대상).
    @discardableResult
    func release(_ dead: Process) -> Bool {
        guard current === dead else { return false }
        current = nil
        return true
    }
}

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
    /// 검색어 — 로컬 2차 필터는 **즉시** 반영, adb 1차 필터는 디바운스 뒤 반영된다
    @Published var query: String = ""
    /// 대소문자 무시
    @Published var caseInsensitive: Bool = false

    /// `isLive` 판정용 틱 — 시간이 지나면 스스로 갱신되어야 "정지"를 감지한다
    @Published private var tick = Date()

    /// 기동 중인 프로세스의 자리 — 종료 알림이 **이전 프로세스** 것인지 판별한다
    private let slot = LogcatProcessSlot()
    private var tickTask: Task<Void, Never>?
    /// adb 1차 필터 재기동 대기 — 입력 중 adb 를 새로 띄우지 않기 위한 디바운스
    private var searchTask: Task<Void, Never>?
    private let stderrTail = StderrTail()
    private var nextID: UInt64 = 0
    /// 링 버퍼 상한
    private let maxLines = 2000
    /// 2차 필터 메모 키 — 링이 같은 상태 + 같은 검색 조건일 때만 재계산한다
    private struct FilterKey: Equatable {
        let count: Int
        let first: UInt64?
        let last: UInt64?
        let query: String
        let caseInsensitive: Bool
    }
    private var filterCache: (key: FilterKey, value: [Line])?
    /// 이만큼 넘게 바이트가 없으면 "살아 있지만 멈춤" 으로 본다
    static let staleAfter: TimeInterval = 3
    /// 검색어 입력 → adb 재기동 대기 — 사람 속도(초당 3~5자)면 한 번만 재기동된다
    static let searchDebounce: TimeInterval = 0.3

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
        guard let s = LogcatFilter.silence(
            query: query,
            stderr: stderrTail.lastMeaningful,
            isSilent: isSilent,
            isStalled: isStalled
        ) else { return nil }
        return L10n.format(s.key, s.args)
    }

    /// 지금 adb 에 실제로 적용된 검색 패턴 — "기기 필터" 배지에 쓴다
    private(set) var appliedPattern: String?

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
        // 파이프가 살아 있어도 사람이 못 본다.
        //
        // 검색도 **adb(기기) 쪽**에서 거른다. 이 기기는 초당 1.4만 줄이라 클라이언트에서만
        // 거르면 0.14초분밖에 볼 수 없다 — 볼륨 자체를 줄여야 검색이 산다.
        // Process 배열 인자라 셸 인용 위험이 없다(패턴에 공백이 있어도 한 인자로 전달된다).
        let pattern = LogcatFilter.pattern(for: query, caseInsensitive: caseInsensitive)
        appliedPattern = pattern
        var args = ["-s", serial, "logcat", "-v", "time", minLevel.filterSpec]
        if let pattern { args.append("--regex=\(pattern)") }
        proc.arguments = args
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        proc.terminationHandler = { [weak self] proc in
            let reason = Self.terminationReason(proc)
            Task { @MainActor in
                guard let self else { return }
                // 알림은 `Task { @MainActor }` 로 **나중에** 도착한다. 그 사이에 필터를 바꿔
                // 새 프로세스가 이미 자리를 잡았을 수 있다 — 이때 이전 프로세스 알림이
                // 자리를 비우면 **살아 있는 새 프로세스의 참조가 사라져** adb 가 누적된다.
                // `release` 는 내가 아직 들고 있는 그 프로세스일 때만 정리한다 (2026-09-27 실측).
                guard self.slot.release(proc) else { return }
                self.isRunning = false
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
        slot.adopt(proc)
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
        searchTask?.cancel()
        searchTask = nil
        if let p = slot.current, p.isRunning {
            p.terminate()
        }
        slot.adopt(nil)
        isRunning = false
        lastDataAt = nil
        appliedPattern = nil
        filterCache = nil
    }

    /// 검색어 변경 — **로컬 필터는 즉시**(2차), **adb 재기동은 디바운스 뒤**(1차)
    ///
    /// 디바운스가 없으면 한 단어마다 adb 를 새로 띄우게 되고, 게다가 재기동 사이에는
    /// 이전 스트림이 살아 있으므로 **"일치 없음" 문구가 깜빡인다.** 기다리는 동안은
    /// 이전 스트림이 계속 채우므로 사용자는 즉시 결과를 본다.
    func searchChanged(serial: String, adbPath: String?) {
        filterCache = nil
        guard !serial.isEmpty else { return }
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(Self.searchDebounce))
            guard !Task.isCancelled else { return }
            self.searchTask = nil
            self.start(serial: serial, adbPath: adbPath)
        }
    }

    // MARK: - 내부

    /// 화면에 **보여줄** 줄 — 링 버퍼에서 검색어를 2차로 거른 것
    ///
    /// adb 필터가 아직 따라오지 않은 **디바운스 사이**에도 즉시 반응해야 하므로 로컬에서도 거른다.
    /// `body` 는 초당 수십 번 평가되므로 **여기서 다시 계산하면 안 된다** — 키가 같으면 메모를 돌려준다.
    var visibleLines: [Line] {
        let key = FilterKey(
            count: lines.count,
            first: lines.first?.id,
            last: lines.last?.id,
            query: query,
            caseInsensitive: caseInsensitive
        )
        if let cache = filterCache, cache.key == key { return cache.value }
        let value: [Line]
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            value = lines
        } else {
            value = lines.filter { LogcatFilter.matches($0.text, query: query, caseInsensitive: caseInsensitive) }
        }
        filterCache = (key, value)
        return value
    }

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

    /// 종료 사유 — `%@` 에 숫자를 넣으면 크래시한다 (2026-09-27 `EXC_BAD_ACCESS` 0x8ad).
    /// 키는 `%d` 다 — 기기 뽑으면 adb 가 0 으로 끝나므로 **정상 경로에서도 이 문구가 나온다.**
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
            searchBar

            if streamer.lastError != nil || serial.isEmpty {
                notice(
                    streamer.lastError ?? L10n.string("droid.logs.noDevice"),
                    icon: "exclamationmark.triangle",
                    tint: OPColor.warn
                )
            } else if let reason = streamer.silenceReason {
                notice(reason, icon: "pause.circle", tint: OPColor.warn)
            } else if streamer.visibleLines.isEmpty {
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
                    ForEach(streamer.visibleLines) { line in
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
            .onChange(of: streamer.visibleLines.last?.id) { _, _ in
                guard follow, let last = streamer.visibleLines.last else { return }
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

    // MARK: - 검색 (PLAN_log_search)

    /// 검색바 — 로컬 필터는 즉시, adb 재기동은 디바운스 뒤.
    /// "기기 필터" 배지로 **어디서 거르는지** 밝힌다: 필터 중에는 이전 구간이 되돌아오지 않는다.
    private var searchBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(OPColor.inkDim)
                TextField(L10n.string("droid.logs.search.placeholder"), text: $streamer.query)
                    .textFieldStyle(.plain)
                    .font(OPFont.body(12))
                    .foregroundStyle(OPColor.ink)
                    .onSubmit { streamer.searchChanged(serial: serial, adbPath: adbPath) }
                if !streamer.query.isEmpty {
                    Button {
                        streamer.query = ""
                        streamer.searchChanged(serial: serial, adbPath: adbPath)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(OPColor.inkDim)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.string("droid.logs.search.clear"))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(OPColor.card, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(OPColor.border, lineWidth: 1))
            .onChange(of: streamer.query) { _, _ in
                streamer.searchChanged(serial: serial, adbPath: adbPath)
            }
            .onChange(of: streamer.caseInsensitive) { _, _ in
                streamer.searchChanged(serial: serial, adbPath: adbPath)
            }

            HStack(spacing: 6) {
                ForEach(LogcatFilter.presets, id: \.self) { preset in
                    presetChip(preset)
                }
                Toggle(isOn: $streamer.caseInsensitive) {
                    Text("Aa")
                        .font(OPFont.number(11))
                }
                .toggleStyle(.checkbox)
                .help(L10n.string("droid.logs.search.ci"))
            }
        }
        .padding(.horizontal, OPSpace.md)
        .padding(.vertical, 6)
    }

    /// 프리셋 칩 — 실패 신호만 넣었다 (상태 변화 태그는 실패가 아니다 · 2026-09-27 교훈)
    private func presetChip(_ preset: String) -> some View {
        let active = streamer.query == preset
        return Button {
            streamer.query = active ? "" : preset
            streamer.searchChanged(serial: serial, adbPath: adbPath)
        } label: {
            Text(preset)
                .font(OPFont.number(10))
                .foregroundStyle(active ? OPColor.ink : OPColor.inkDim)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(OPColor.card, in: Capsule())
                .overlay(Capsule().stroke(active ? OPColor.cta : OPColor.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
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
                // 줄 수는 숫자다 — 키는 `%d`. `%@` 에 Int 를 넣으면 이 자리에서 SIGSEGV 났다
                // (2026-09-27 · `RelayConsole-2026-09-27-170630.ips` far=0x8ad=2221줄)
                Text(L10n.format("droid.logs.count", streamer.totalLines))
                    .font(OPFont.number(10))
                    .foregroundStyle(OPColor.inkDim)
            }
            // 검색 중이면 "무엇이 몇 줄 남았는지" 를 함께 보여준다 (링은 잘리므로 실측 아님)
            if !streamer.query.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(L10n.format("droid.logs.matched", streamer.visibleLines.count))
                    .font(OPFont.number(10))
                    .foregroundStyle(OPColor.cta)
            }
            if onClose != nil {
                Button(L10n.string("droid.logs.close")) { onClose?() }
                    .buttonStyle(.plain)
                    .foregroundStyle(OPColor.inkDim)
            }
        }
        .padding(OPSpace.md)
    }

    /// 링 설명 — 검색 중이면 "기기가 얼마나 걸렀다" 를 함께 밝힌다
    private var ringLabel: String {
        guard streamer.appliedPattern != nil else { return L10n.string("droid.logs.ring") }
        return L10n.format("droid.logs.ring.filtered", streamer.query)
    }

    private var footer: some View {        HStack(spacing: 12) {
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
            // "어디서 거르는가" 를 숨기지 않는다 — adb 측 필터는 **기기에서** 걸러온 결과다
            // (필터 중에는 그 이전 구간이 되돌아오지 않는다)
            Text(ringLabel)
                .font(OPFont.number(10))
                .foregroundStyle(streamer.appliedPattern == nil ? OPColor.inkDim : OPColor.cta)
                .lineLimit(1)
                .truncationMode(.middle)
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
