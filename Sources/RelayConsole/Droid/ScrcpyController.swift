import Foundation
import AppKit
import Combine
import SwiftUI

/// scrcpy 외부 프로세스 제어 — A안 (PLAN_v0.7) + **다중 동시 미러링** (2026-10-18 · T-2026-10-18-1)
/// PATH 탐지 · brew 원클릭 설치(사용자 확인) · **serial당 1프로세스, 기기 여러 대를 동시에**
///
/// 종전에는 프로세스 슬롯이 하나라 두 번째 기기를 누르면 첫째가 `terminate` 됐다.
/// 슬롯을 `serial → Process` 로 옮겨 **한 기기를 열어도 다른 기기 미러는 그대로**다.
/// (UI 는 원래 `isRunning(serial:)` 로 기기별 판정을 해서 화면 코드는 바꾸지 않았다)
@MainActor
final class ScrcpyController: ObservableObject {
    static let shared = ScrcpyController()

    @Published private(set) var binaryPath: String?
    @Published private(set) var isInstalling = false
    /// 미러링 중인 기기들 — **동시에 여러 대**. 버튼 상태는 기기별로 계산된다
    @Published private(set) var runningSerials: Set<String> = []
    @Published private(set) var lastError: String?
    @Published var noControl: Bool {
        didSet { UserDefaults.standard.set(noControl, forKey: "relay.scrcpy.noControl") }
    }
    @Published var customPath: String {
        didSet { UserDefaults.standard.set(customPath, forKey: "relay.scrcpy.path") }
    }
    @Published var customOpts: String {
        didSet { UserDefaults.standard.set(customOpts, forKey: "relay.scrcpy.customOpts") }
    }
    // 미러링 기본 옵션 8종 — 설정에서 조정 (빈 값이면 해당 옵션 생략)
    @Published var showTouches: Bool {
        didSet { UserDefaults.standard.set(showTouches, forKey: "relay.scrcpy.showTouches") }
    }
    @Published var stayAwake: Bool {
        didSet { UserDefaults.standard.set(stayAwake, forKey: "relay.scrcpy.stayAwake") }
    }
    @Published var legacyPaste: Bool {
        didSet { UserDefaults.standard.set(legacyPaste, forKey: "relay.scrcpy.legacyPaste") }
    }
    @Published var turnScreenOff: Bool {
        didSet { UserDefaults.standard.set(turnScreenOff, forKey: "relay.scrcpy.turnScreenOff") }
    }
    @Published var maxSize: String {
        didSet { UserDefaults.standard.set(maxSize, forKey: "relay.scrcpy.maxSize") }
    }
    @Published var videoBitRate: String {
        didSet { UserDefaults.standard.set(videoBitRate, forKey: "relay.scrcpy.videoBitRate") }
    }
    @Published var maxFps: String {
        didSet { UserDefaults.standard.set(maxFps, forKey: "relay.scrcpy.maxFps") }
    }
    @Published var screenOffTimeout: String {
        didSet { UserDefaults.standard.set(screenOffTimeout, forKey: "relay.scrcpy.screenOffTimeout") }
    }

    // scrcpy 5.0.1 옵션 노출 (2026-10-18 · T-2026-10-17-6 · PLAN_scrcpy_options_relayconsole)
    /// 하드웨어 디코딩 — "" = scrcpy 기본(auto, 옵션 생략) · "disabled" · "videotoolbox"(고급)
    @Published var hwdec: String {
        didSet { UserDefaults.standard.set(hwdec, forKey: "relay.scrcpy.hwdec") }
    }
    /// 영상 코덱 — "" = h264(기본, 옵션 생략) · "h265" · "av1" · "vp8" · "vp9"
    @Published var videoCodec: String {
        didSet { UserDefaults.standard.set(videoCodec, forKey: "relay.scrcpy.videoCodec") }
    }
    /// 영상 버퍼 (ms) — 빈 값·비숫자는 옵션 생략 (무선 지터 완화용)
    @Published var videoBuffer: String {
        didSet { UserDefaults.standard.set(videoBuffer, forKey: "relay.scrcpy.videoBuffer") }
    }
    @Published var disableScreensaver: Bool {
        didSet { UserDefaults.standard.set(disableScreensaver, forKey: "relay.scrcpy.disableScreensaver") }
    }
    /// 창 제목에 기기 식별 라벨(`identLabel`)을 넣는다 — [표시①] 기기 식별 (AGENTS.local §4)
    @Published var windowTitleIdent: Bool {
        didSet { UserDefaults.standard.set(windowTitleIdent, forKey: "relay.scrcpy.windowTitleIdent") }
    }
    @Published var alwaysOnTop: Bool {
        didSet { UserDefaults.standard.set(alwaysOnTop, forKey: "relay.scrcpy.alwaysOnTop") }
    }
    /// 창 여백색을 앱 배경(DESIGN v2 카드 bg)과 통일
    @Published var backgroundMatch: Bool {
        didSet { UserDefaults.standard.set(backgroundMatch, forKey: "relay.scrcpy.backgroundMatch") }
    }
    @Published var powerOffOnClose: Bool {
        didSet { UserDefaults.standard.set(powerOffOnClose, forKey: "relay.scrcpy.powerOffOnClose") }
    }

    /// 종전 코드 고정 기본값 (PLAN_v0.7 §2) — 설정 미지정 시 동일 동작
    nonisolated static let defaultShowTouches = true
    nonisolated static let defaultStayAwake = true
    nonisolated static let defaultLegacyPaste = true
    nonisolated static let defaultTurnScreenOff = true
    nonisolated static let defaultMaxSize = "1024"
    nonisolated static let defaultVideoBitRate = "2M"
    nonisolated static let defaultMaxFps = "30"
    nonisolated static let defaultScreenOffTimeout = "3600"
    /// "" = 옵션 생략(scrcpy 5.0 기본 auto). 명시하면 폴백 없이 실패할 수 있다
    nonisolated static let defaultHwdec = ""
    nonisolated static let defaultVideoCodec = ""
    nonisolated static let defaultVideoBuffer = ""
    nonisolated static let defaultDisableScreensaver = false
    nonisolated static let defaultWindowTitleIdent = true
    nonisolated static let defaultAlwaysOnTop = false
    nonisolated static let defaultBackgroundMatch = true
    nonisolated static let defaultPowerOffOnClose = false
    /// 허용 값 목록 — UI 선택 + 인자 검증(자유 입력 금지)
    nonisolated static let hwdecModes = ["", "disabled", "videotoolbox"]
    nonisolated static let videoCodecs = ["", "h265", "av1", "vp8", "vp9"]
    /// 창 여백색 — docs/DESIGN.md v2 카드 bg (`--background-color` 기본 #222 대체)
    nonisolated static let backgroundColor = "#1c1f2a"

    /// 숫자만 통과 (ms·초) — 아니면 옵션 생략
    nonisolated private static func digitsOnly(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t.allSatisfy({ $0.isNumber }) else { return "" }
        return t
    }

    /// scrcpy 인자 조립 — 순수 함수 (UserDefaults·싱글턴을 건드리지 않아 테스트 가능)
    nonisolated static func mirrorArgs(serial: String, noControl: Bool,
                           showTouches: Bool = defaultShowTouches,
                           stayAwake: Bool = defaultStayAwake,
                           legacyPaste: Bool = defaultLegacyPaste,
                           turnScreenOff: Bool = defaultTurnScreenOff,
                           maxSize: String = defaultMaxSize,
                           videoBitRate: String = defaultVideoBitRate,
                           maxFps: String = defaultMaxFps,
                           screenOffTimeout: String = defaultScreenOffTimeout,
                           hwdec: String = defaultHwdec,
                           videoCodec: String = defaultVideoCodec,
                           videoBuffer: String = defaultVideoBuffer,
                           disableScreensaver: Bool = defaultDisableScreensaver,
                           windowTitle: String = "",
                           alwaysOnTop: Bool = defaultAlwaysOnTop,
                           backgroundMatch: Bool = defaultBackgroundMatch,
                           powerOffOnClose: Bool = defaultPowerOffOnClose,
                           customOpts: String = "") -> [String] {
        var args: [String] = ["-s", serial]
        if showTouches { args.append("--show-touches") }
        if stayAwake { args.append("--stay-awake") }
        if legacyPaste { args.append("--legacy-paste") }
        let size = maxSize.trimmingCharacters(in: .whitespaces)
        if !size.isEmpty { args.append("--max-size=\(size)") }
        let rate = videoBitRate.trimmingCharacters(in: .whitespaces)
        if !rate.isEmpty { args.append("--video-bit-rate=\(rate)") }
        let fps = maxFps.trimmingCharacters(in: .whitespaces)
        if !fps.isEmpty { args.append("--max-fps=\(fps)") }
        let timeout = screenOffTimeout.trimmingCharacters(in: .whitespaces)
        if !timeout.isEmpty { args.append("--screen-off-timeout=\(timeout)") }
        if turnScreenOff { args.append("--turn-screen-off") }
        // scrcpy 5.0.1 노출 옵션 — 허용 값·숫자만 통과 (자유 입력으로 scrcpy를 깨뜨리지 않는다)
        if hwdecModes.contains(hwdec), !hwdec.isEmpty { args.append("--hwdec=\(hwdec)") }
        if videoCodecs.contains(videoCodec), !videoCodec.isEmpty { args.append("--video-codec=\(videoCodec)") }
        let buffer = digitsOnly(videoBuffer)
        if !buffer.isEmpty { args.append("--video-buffer=\(buffer)") }
        if disableScreensaver { args.append("--disable-screensaver") }
        let title = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { args.append("--window-title=\(title)") }
        if alwaysOnTop { args.append("--always-on-top") }
        if backgroundMatch { args.append("--background-color=\(backgroundColor)") }
        if powerOffOnClose { args.append("--power-off-on-close") }
        if noControl {
            args.append("--no-control")
        }
        if !customOpts.isEmpty {
            args += customOpts.split(separator: " ").map(String.init)
        }
        return args
    }

    /// 미러링 중인 scrcpy 프로세스 — **기기별 1개, 동시에 여러 대**
    private var processes: [String: Process] = [:]
    private var findCache: String?
    private var refreshTimer: Timer?

    private init() {
        let d = UserDefaults.standard
        customPath = d.string(forKey: "relay.scrcpy.path") ?? ""
        customOpts = d.string(forKey: "relay.scrcpy.customOpts") ?? ""
        noControl = d.bool(forKey: "relay.scrcpy.noControl")
        // Bool은 미지정 시 false를 반환하므로 object 존재 여부로 기본값(true) 구분
        showTouches = d.object(forKey: "relay.scrcpy.showTouches") as? Bool ?? Self.defaultShowTouches
        stayAwake = d.object(forKey: "relay.scrcpy.stayAwake") as? Bool ?? Self.defaultStayAwake
        legacyPaste = d.object(forKey: "relay.scrcpy.legacyPaste") as? Bool ?? Self.defaultLegacyPaste
        turnScreenOff = d.object(forKey: "relay.scrcpy.turnScreenOff") as? Bool ?? Self.defaultTurnScreenOff
        maxSize = d.string(forKey: "relay.scrcpy.maxSize") ?? Self.defaultMaxSize
        videoBitRate = d.string(forKey: "relay.scrcpy.videoBitRate") ?? Self.defaultVideoBitRate
        maxFps = d.string(forKey: "relay.scrcpy.maxFps") ?? Self.defaultMaxFps
        screenOffTimeout = d.string(forKey: "relay.scrcpy.screenOffTimeout") ?? Self.defaultScreenOffTimeout
        hwdec = d.string(forKey: "relay.scrcpy.hwdec") ?? Self.defaultHwdec
        videoCodec = d.string(forKey: "relay.scrcpy.videoCodec") ?? Self.defaultVideoCodec
        videoBuffer = d.string(forKey: "relay.scrcpy.videoBuffer") ?? Self.defaultVideoBuffer
        disableScreensaver = d.object(forKey: "relay.scrcpy.disableScreensaver") as? Bool ?? Self.defaultDisableScreensaver
        windowTitleIdent = d.object(forKey: "relay.scrcpy.windowTitleIdent") as? Bool ?? Self.defaultWindowTitleIdent
        alwaysOnTop = d.object(forKey: "relay.scrcpy.alwaysOnTop") as? Bool ?? Self.defaultAlwaysOnTop
        backgroundMatch = d.object(forKey: "relay.scrcpy.backgroundMatch") as? Bool ?? Self.defaultBackgroundMatch
        powerOffOnClose = d.object(forKey: "relay.scrcpy.powerOffOnClose") as? Bool ?? Self.defaultPowerOffOnClose
        refresh()
        armTimer()
    }

    // MARK: - Detect

    func refresh() {
        if let p = findScrcpy() {
            findCache = p
            if binaryPath != p { binaryPath = p }
        } else {
            findCache = nil
            binaryPath = nil
        }
        // 외부에서 종료된 경우 상태 복귀 — **기기별로** 정리한다 (한 기기가 죽어도 나머지는 유지)
        for (serial, p) in processes where p.isRunning != true {
            processes.removeValue(forKey: serial)
            runningSerials.remove(serial)
        }
    }

    /// 5초 주기 타이머 — scrcpy 탐색 + 죽은 프로세스 상태 정리
    private func armTimer() {
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    /// 미러가 **하나도 없을 때만** 타이머를 멈춘다 — 살아 있는 미러가 있는데 멈추면
    /// 그 프로세스가 죽어도 `runningSerials` 가 영구히 어긋난다. (정지 후 `launch` 가 다시 무장시킨다)
    private func stopTimerIfAllStopped() {
        guard processes.isEmpty else { return }
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func findScrcpy() -> String? {
        if !customPath.isEmpty,
           FileManager.default.isExecutableFile(atPath: customPath) {
            return customPath
        }
        if let cached = findCache,
           FileManager.default.isExecutableFile(atPath: cached) {
            return cached
        }
        let candidates = [
            "/opt/homebrew/bin/scrcpy",
            "/usr/local/bin/scrcpy",
            "/usr/bin/scrcpy",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in pathEnv.split(separator: ":") {
            let p = "\(dir)/scrcpy"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    // MARK: - Install (사용자 확인 1회 brew — 자동 다운로드 금지 유지)

    /// 범용 brew install (libimobiledevice 등) — completion은 메인에서
    func runBrew(_ args: [String], completion: @escaping @MainActor (Bool) -> Void) {
        let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew", "/usr/bin/brew"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let brewPath = brew else {
            lastError = ErrorCode.scrcpyBrewMissing.koMessage
            completion(false)
            return
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: brewPath)
        proc.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "")
        proc.environment = env
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        proc.terminationHandler = { p in
            Task { @MainActor in
                if p.terminationStatus == 0 {
                    completion(true)
                } else {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let text = String(decoding: data, as: UTF8.self)
                    self.lastError = text.split(separator: "\n").last.map(String.init)
                        ?? ErrorCode.appleInstallFailed.koMessage
                    completion(false)
                }
            }
        }
        do {
            try proc.run()
        } catch {
            lastError = ErrorCode.appleInstallFailed.koMessage
            completion(false)
        }
    }

    func installViaBrew() {
        guard !isInstalling else { return }
        isInstalling = true
        lastError = nil

        let brew = [" /opt/homebrew/bin/brew", "/usr/local/bin/brew", "/usr/bin/brew"]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { FileManager.default.isExecutableFile(atPath: $0) }

        guard let brewPath = brew else {
            isInstalling = false
            lastError = ErrorCode.scrcpyBrewMissing.koMessage
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: brewPath)
        proc.arguments = ["install", "scrcpy"]
        var env = ProcessInfo.processInfo.environment
        let path = env["PATH"] ?? ""
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + path
        proc.environment = env
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        proc.terminationHandler = { [weak self] p in
            Task { @MainActor in
                guard let self else { return }
                self.isInstalling = false
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(decoding: data, as: UTF8.self)
                if p.terminationStatus == 0 {
                    self.findCache = nil
                    self.refresh()
                    if self.binaryPath != nil {
                        NotificationCenter.default.post(name: .scrcpyInstalled, object: nil)
                    } else {
                        self.lastError = ErrorCode.scrcpyInstallFailed.koMessage
                    }
                } else {
                    self.lastError = text.split(separator: "\n").last.map(String.init)
                        ?? ErrorCode.scrcpyInstallFailed.koMessage
                }
            }
        }
        do {
            try proc.run()
        } catch {
            isInstalling = false
            lastError = ErrorCode.scrcpyInstallFailed.koMessage
        }
    }

    // MARK: - Launch / stop

    /// 실행 중이면 그 기기의 창 앞으로, 아니면 실행 (헤더 토글)
    /// 종료는 scrcpy 창 닫기 — Relay 쪽 토글은 포커스 전용
    /// **기기별 독립** — 두 기기를 동시에 미러링해도 각자 창이 앞으로 올라온다
    func toggle(serial: String) {
        if let p = processes[serial], p.isRunning {
            bringToFront(pid: p.processIdentifier, attempts: 5)
        } else {
            launch(serial: serial)
        }
    }

    /// 실행 중이면 그 기기의 창 앞으로, 아니면 실행.
    /// **다른 기기의 미러는 끊지 않는다** (동시 미러링 · 2026-10-18) —
    /// 두 번째 기기를 열어도 첫 번째 창이 그대로 남는다.
    func launch(serial: String) {
        guard let path = findScrcpy() else {
            lastError = ErrorCode.scrcpyBinaryMissing.koMessage
            return
        }
        if let p = processes[serial], p.isRunning {
            bringToFront(pid: p.processIdentifier, attempts: 5)
            return
        }
        // 같은 serial 의죽은 잔해만 교체한다 — 다른 serial 은 건드리지 않는다
        processes.removeValue(forKey: serial)

        let args = Self.mirrorArgs(serial: serial, noControl: noControl,
                                     showTouches: showTouches, stayAwake: stayAwake,
                                     legacyPaste: legacyPaste, turnScreenOff: turnScreenOff,
                                     maxSize: maxSize, videoBitRate: videoBitRate,
                                     maxFps: maxFps, screenOffTimeout: screenOffTimeout,
                                     hwdec: hwdec, videoCodec: videoCodec, videoBuffer: videoBuffer,
                                     disableScreensaver: disableScreensaver,
                                     // 창 제목 = 기기 식별 라벨 원문 ([표시①] — 모델명은 같은 기종을 구분하지 못한다)
                                     windowTitle: windowTitleIdent
                                        ? ConsoleStore.shared.identLabel(for: serial) : "",
                                     alwaysOnTop: alwaysOnTop, backgroundMatch: backgroundMatch,
                                     powerOffOnClose: powerOffOnClose,
                                     customOpts: customOpts)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        var env = ProcessInfo.processInfo.environment
        let pathEnv = env["PATH"] ?? ""
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + pathEnv
        proc.environment = env
        // scrcpy stderr 수집 — 실제 실패 원인을 화면에 노출 (AGENTS.local §4 [표시②])
        let errPipe = Pipe()
        proc.standardError = errPipe
        proc.terminationHandler = { [weak self] p in
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errText = String(decoding: errData, as: UTF8.self)
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .last ?? ""
            Task { @MainActor in
                guard let self else { return }
                // 프로세스 identity로만 판정한다. serial 비교를 포함하면
                // launch → stop → 즉시 launch(같은 serial) 시 옛 프로세스의 핸들러가
                // 새 프로세스 상태를 nil로 덮어써 "실행 중인데 미실행"으로 표시된다.
                // 자기 기기의 프로세스만 지운다 — **동시 미러링 중인 다른 기기는 그대로**다.
                if self.processes[serial] === p {
                    self.processes.removeValue(forKey: serial)
                    self.runningSerials.remove(serial)
                    if p.terminationStatus != 0 && p.terminationStatus != 15 {
                        let base = ErrorCode.scrcpyLaunchFailed.koMessage
                        self.lastError = errText.isEmpty
                            ? "\(base) (exit \(p.terminationStatus))"
                            : "\(base) — \(errText)"
                    }
                }
            }
        }
        do {
            try proc.run()
            processes[serial] = proc
            runningSerials.insert(serial)
            lastError = nil
            armTimer()   // 정지 후 다시 열면 타이머가 이미 꺼져 있을 수 있다 — 재무장
            // SDL 창 생성 지연 → 리트라이로 앞으로
            let pid = proc.processIdentifier
            scheduleBringToFront(pid: pid)
        } catch {
            lastError = ErrorCode.scrcpyLaunchFailed.koMessage
        }
    }

    /// 런치 직후: 0.35s / 0.9s / 1.8s / 3s 재시도 (창 뜨는 타이밍 불규칙)
    private func scheduleBringToFront(pid: Int32) {
        let delays: [TimeInterval] = [0.35, 0.9, 1.8, 3.0]
        for (i, d) in delays.enumerated() {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(d * 1_000_000_000))
                guard let self, self.isPidLive(pid) else { return }
                self.bringToFront(pid: pid, attempts: i == delays.count - 1 ? 3 : 1)
            }
        }
    }

    /// 예약된 앞세우기가 아직 유효한지 — 그 pid 의 scrcpy 가 살아 있는지 (기기별 관리라 전역 슬롯 조회 불가)
    private func isPidLive(_ pid: Int32) -> Bool {
        processes.values.contains { $0.processIdentifier == pid && $0.isRunning }
    }

    /// NSRunningApplication.activate → 실패 시 System Events frontmost
    /// LSUIElement 부모에서 spawn된 CLI GUI는 activate만으로 안 켜질 수 있음
    func bringToFront(pid: Int32, attempts: Int) {
        guard attempts > 0 else { return }
        let activateOnce: () -> Bool = {
            guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
            app.unhide()
            return app.activate()
        }
        if activateOnce() {
            // 한 번 더 (포커스 경합 대응)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                _ = NSRunningApplication(processIdentifier: pid)?.activate()
            }
            setFrontmostViaSystemEvents(pid: pid)
            return
        }
        setFrontmostViaSystemEvents(pid: pid)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.bringToFront(pid: pid, attempts: attempts - 1)
        }
    }

    private func setFrontmostViaSystemEvents(pid: Int32) {
        let script = """
        tell application "System Events"
            set p to first process whose unix id is \(pid)
            set frontmost of p to true
        end tell
        """
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
        // err 무시 — 보안 허용 전까지 조용히 스킵
    }

    /// 전체 종료 — 앱 종료 정리(`ConsoleStore.shutdown`)에서 고아 scrcpy 를 남기지 않기 위함.
    /// (기기별 개별 정지는 없다 — 미러 종료는 scrcpy 창을 닫는 경로이며 죽으면 핸들러가 상태를 비운다)
    func stopAll() {
        for p in processes.values { p.terminate() }
        processes.removeAll()
        runningSerials.removeAll()
        stopTimerIfAllStopped()
    }

    /// 기기별 실행 여부 — UI 버튼 상태도 여기서 나온다 (동시 미러링에서도 기기마다 정확)
    func isRunning(serial: String) -> Bool {
        processes[serial]?.isRunning == true
    }

    /// 오류 표시 해제 — 사용자가 오류 팝오버를 닫은 뒤 재시도할 때
    func clearError() {
        lastError = nil
    }

    func buttonState(serial: String) -> ScrcpyButtonState {
        if isInstalling { return .installing }
        if isRunning(serial: serial) { return .running }
        if binaryPath != nil { return .ready }
        return .missing
    }
}

enum ScrcpyButtonState {
    case missing
    case installing
    case ready
    case running
}

extension Notification.Name {
    static let scrcpyInstalled = Notification.Name("relay.scrcpy.installed")
    static let adbPathReady = Notification.Name("relay.adb.pathReady")
}
