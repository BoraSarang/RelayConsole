import Foundation
import AppKit
import Combine
import SwiftUI

/// scrcpy 외부 프로세스 제어 — A안 (PLAN_v0.7)
/// PATH 탐지 · brew 원클릭 설치(사용자 확인) · serial당 1프로세스
@MainActor
final class ScrcpyController: ObservableObject {
    static let shared = ScrcpyController()

    @Published private(set) var binaryPath: String?
    @Published private(set) var isInstalling = false
    @Published private(set) var runningSerial: String?
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

    /// 사용자 스크립트 기본 8종 (PLAN_v0.7 §2)
    static let defaultOpts = [
        "--show-touches",
        "--stay-awake",
        "--legacy-paste",
        "--max-size=1024",
        "--video-bit-rate=2M",
        "--max-fps=30",
        "--screen-off-timeout=3600",
        "--turn-screen-off",
    ]

    private var process: Process?
    private var findCache: String?
    private var refreshTimer: Timer?

    private init() {
        let d = UserDefaults.standard
        customPath = d.string(forKey: "relay.scrcpy.path") ?? ""
        customOpts = d.string(forKey: "relay.scrcpy.customOpts") ?? ""
        noControl = d.bool(forKey: "relay.scrcpy.noControl")
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
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
        // 외부에서 종료된 경우 상태 복귀
        if let serial = runningSerial, process?.isRunning != true {
            runningSerial = nil
            process = nil
            _ = serial
        }
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

    /// 실행 중이면 창 앞으로, 아니면 실행 (헤더 토글)
    /// 종료는 scrcpy 창 닫기 — Relay 쪽 토글은 포커스 전용
    func toggle(serial: String) {
        if runningSerial == serial, let p = process, p.isRunning {
            bringToFront(pid: p.processIdentifier, attempts: 5)
        } else {
            launch(serial: serial)
        }
    }

    func launch(serial: String) {
        guard let path = findScrcpy() else {
            lastError = ErrorCode.scrcpyBinaryMissing.koMessage
            return
        }
        if let p = process, p.isRunning, runningSerial == serial {
            bringToFront(pid: p.processIdentifier, attempts: 5)
            return
        }
        if process?.isRunning == true { stop() }

        var args: [String] = ["-s", serial]
        args += Self.defaultOpts
        if noControl {
            args.append("--no-control")
        }
        if !customOpts.isEmpty {
            args += customOpts.split(separator: " ").map(String.init)
        }

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
                if self.process === p {
                    self.process = nil
                    self.runningSerial = nil
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
            process = proc
            runningSerial = serial
            lastError = nil
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
                guard let self, self.process?.processIdentifier == pid,
                      self.process?.isRunning == true else { return }
                self.bringToFront(pid: pid, attempts: i == delays.count - 1 ? 3 : 1)
            }
        }
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

    func stop() {
        process?.terminate()
        process = nil
        runningSerial = nil
    }

    func isRunning(serial: String) -> Bool {
        runningSerial == serial && process?.isRunning == true
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
