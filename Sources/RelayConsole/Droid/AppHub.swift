import Foundation
import CryptoKit
import AppKit

/// APK 설치 옵션 — 기본값은 "덮어쓰기만" 이다.
/// `-g`(권한 일괄 허용)는 보안 영향이 있어 사용자가 명시할 때만 켠다 (DECISIONS D6).
struct AppInstallOptions: Equatable, Sendable {
    var reinstall = true
    var grantAllPermissions = false
    var allowDowngrade = false
    var allowTestOnly = false
}

/// 설치 대상 기기 — 한 번에 여러 대를 순차 설치한다 (C 단계)
struct InstallTarget: Identifiable, Equatable, Sendable {
    let serial: String
    let label: String

    var id: String { serial }
}

/// 기기별 설치 결과 — 결과표에 그대로 그린다
struct DeviceInstallResult: Identifiable, Equatable, Sendable {
    let serial: String
    let label: String
    let ok: Bool
    let message: String
    let packageName: String?
    let versionName: String?

    var id: String { serial }
}

/// 한 기기 설치의 구조화 결과 — 문구·감사 로그·결과표가 같은 값을 쓴다
struct InstallReport: Equatable, Sendable {
    var ok: Bool
    var message: String
    var detail: String
    var packageName: String?
    var version: String?
}

/// 앱 허브 순수 로직 — 패키지 파싱·검증·검색·adb 인자·결과 해석 (테스트 대상)
enum AppHubLogic {
    /// `pm list packages` 출력 → 패키지명 목록 (순서 유지·중복 제거)
    ///
    /// `--show-versioncode` 를 붙이면 한 줄이 `package:com.foo versionCode:28` 이 된다.
    /// 접미사를 자르지 않으면 패키지명이 `"com.foo versionCode:28"` 이 되어
    /// 아이콘 조회(`pm path`)·실행·삭제가 **전부 실패**한다 (1.23.0 회귀).
    static func parsePackages(_ text: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let s = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard s.hasPrefix("package:") else { continue }
            // 패키지명에는 공백이 없다 — 첫 토큰만 취해 `versionCode:` 접미사를 버린다
            let rest = s.dropFirst("package:".count)
            let name = String(rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first ?? "")
            guard !name.isEmpty, !seen.contains(name) else { continue }
            seen.insert(name)
            out.append(name)
        }
        return out
    }

    /// 패키지명 규칙 — 영숫자·`_`·`.` · 최소 점 1개 · 접두/접미 점 금지
    static func isValidPackage(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 3, t.count <= 255 else { return false }
        guard t.contains(".") else { return false }
        guard t.first != ".", t.last != "." else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_."))
        return t.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// 부분 문자열 검색 — 대소문자 무시 · 빈 쿼리 = 전체
    static func filter(_ packages: [String], query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return packages }
        return packages.filter { $0.lowercased().contains(q) }
    }

    /// 알파벳 정렬 (대소문자 무시 안정)
    static func sort(_ packages: [String]) -> [String] {
        packages.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// `pm list packages` — includeSystem false → `-3` (서드파티)
    static func listArgs(includeSystem: Bool) -> [String] {
        includeSystem ? ["shell", "pm", "list", "packages"] : ["shell", "pm", "list", "packages", "-3"]
    }

    static func launchArgs(package: String) -> [String] {
        ["shell", "monkey", "-p", package, "-c", "android.intent.category.LAUNCHER", "1"]
    }

    static func forceStopArgs(package: String) -> [String] {
        ["shell", "am", "force-stop", package]
    }

    /// 삭제 인자 — **기본은 완전 삭제**(앱+데이터). `keepData` 일 때만 `-k`.
    /// 종전 기본값 `-k` 는 "삭제"라는 말과 결과가 달라 저장공간이 회수되지 않았다 (2026-10-24).
    static func uninstallArgs(package: String, keepData: Bool = false) -> [String] {
        var args = ["shell", "pm", "uninstall"]
        if keepData { args.append("-k") }
        args.append(package)
        return args
    }

    /// 설치 인자 — adb 옵션은 경로 앞에 온다.
    /// `-r` 은 재설치(데이터 유지), `-d` 다운그레이드, `-g` 런타임 권한 일괄 허용, `-t` 테스트 APK.
    static func installArgs(path: String, options: AppInstallOptions) -> [String] {
        ["install"] + installFlags(options) + [path]
    }

    /// 설치 옵션 → 플래그 (단일 설치·분할 설치 공통)
    static func installFlags(_ options: AppInstallOptions) -> [String] {
        var flags: [String] = []
        if options.reinstall { flags.append("-r") }
        if options.allowDowngrade { flags.append("-d") }
        if options.grantAllPermissions { flags.append("-g") }
        if options.allowTestOnly { flags.append("-t") }
        return flags
    }

    /// 분할 APK 설치 — 이미 기기로 올린 원격 경로들을 한 세션으로 설치한다
    static func installMultipleArgs(remotePaths: [String], options: AppInstallOptions) -> [String] {
        ["shell", "pm", "install-multiple"] + installFlags(options) + remotePaths
    }

    /// 설치 화면이 받아들이는 파일 종류 — A 는 `.apk`, B 부터 번들 3종 추가
    static func installKind(path: String) -> AppBundleKind? {
        let p = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty, p.hasPrefix("/") else { return nil }
        return AppBundleKind.detect(path: p)
    }

    /// A 단계 호환 — 단일 APK 만
    static func isApkFile(_ path: String) -> Bool {
        installKind(path: path) == .apk
    }

    // MARK: - 결과 해석

    enum InstallOutcome: Equatable {
        case installed
        case failed(code: String?, detail: String)
        case timedOut
    }

    /// adb install/uninstall 공통 결과 해석.
    /// 성공 판정은 **exit 0 + Success 문구**이고, 실패는 `Failure [CODE]` 를 우선한다.
    /// (일부 adb 는 실패해도 exit 0 을 낼 수 있어 종료 코드만 믿지 않는다.)
    static func parseInstallResult(
        stdout: String,
        stderr: String,
        exitCode: Int32,
        timedOut: Bool
    ) -> InstallOutcome {
        if timedOut { return .timedOut }
        let text = stdout + "\n" + stderr
        if let code = failureCode(in: text) {
            return .failed(code: code, detail: lastLine(text) ?? code)
        }
        let lower = text.lowercased()
        if exitCode == 0 && (lower.contains("success") || lower.contains("streamed install")) {
            return .installed
        }
        if exitCode == 0 {
            // adb 버전에 따라 성공 시 아무것도 출력하지 않는 경우가 있다
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return .installed }
        }
        return .failed(code: nil, detail: lastLine(text) ?? "exit \(exitCode)")
    }

    static func parseUninstallResult(
        stdout: String,
        stderr: String,
        exitCode: Int32,
        timedOut: Bool
    ) -> InstallOutcome {
        if timedOut { return .timedOut }
        let text = stdout + "\n" + stderr
        if let code = failureCode(in: text) {
            return .failed(code: code, detail: lastLine(text) ?? code)
        }
        let lower = text.lowercased()
        if exitCode == 0 && (lower.contains("success") || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            return .installed
        }
        return .failed(code: nil, detail: lastLine(text) ?? "exit \(exitCode)")
    }

    /// `Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE: ...]` → `INSTALL_FAILED_UPDATE_INCOMPATIBLE`
    static func failureCode(in text: String) -> String? {
        guard let open = text.range(of: "Failure [") else { return nil }
        let rest = text[open.upperBound...]
        guard let close = rest.firstIndex(of: "]") else { return nil }
        let inner = String(rest[..<close])
        let token = inner.split(whereSeparator: { $0 == ":" || $0 == " " || $0 == "\n" }).first
        guard let token, !token.isEmpty else { return nil }
        return String(token)
    }

    /// 설치 실패 코드 → L10n 키. 모르는 코드는 원문을 유지한 채 일반 문구로 떨어진다.
    static func failureKey(code: String?) -> String {
        guard let code else { return "apphub.fail.unknown" }
        let c = code.uppercased()
        if c.contains("UPDATE_INCOMPATIBLE") { return "apphub.fail.updateIncompatible" }
        if c.contains("VERSION_DOWNGRADE") { return "apphub.fail.versionDowngrade" }
        if c.contains("DEPRECATED_SDK") { return "apphub.fail.deprecatedSdk" }
        if c.contains("OLDER_SDK") { return "apphub.fail.olderSdk" }
        if c.contains("USER_RESTRICTED") { return "apphub.fail.userRestricted" }
        if c.contains("VERIFICATION") { return "apphub.fail.verification" }
        if c.contains("INSUFFICIENT_STORAGE") { return "apphub.fail.insufficientStorage" }
        if c.contains("NO_MATCHING_ABIS") { return "apphub.fail.noMatchingAbis" }
        if c.contains("TEST_ONLY") { return "apphub.fail.testOnly" }
        if c.contains("INVALID_APK") || c.contains("INVALID_FILE") || c.contains("NOT_APK") { return "apphub.fail.invalidApk" }
        if c.contains("NO_CERTIFICATES") || c.contains("PARSE_FAILED") { return "apphub.fail.noCertificates" }
        if c.contains("ALREADY_EXISTS") { return "apphub.fail.alreadyExists" }
        return "apphub.fail.unknown"
    }

    /// 삭제 실패 코드 → L10n 키
    static func uninstallFailureKey(code: String?) -> String {
        guard let code else { return "apphub.fail.uninstall" }
        let c = code.uppercased()
        if c.contains("DEVICE_POLICY") { return "apphub.fail.devicePolicy" }
        if c.contains("USER_RESTRICTED") { return "apphub.fail.deleteRestricted" }
        return "apphub.fail.uninstall"
    }

    /// `dumpsys package` → versionName
    static func versionName(fromDumpsys text: String) -> String? {
        for line in text.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard let r = t.range(of: "versionName=") else { continue }
            let v = String(t[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !v.isEmpty { return v }
        }
        return nil
    }

    /// `pm list packages --show-versioncode`
    /// → `package:com.foo versionCode:123` · versionCode 미지원이면 0
    static func parsePackageVersionCodes(_ text: String) -> [String: Int64] {
        var out: [String: Int64] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let s = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard s.hasPrefix("package:") else { continue }
            let parts = s.split(separator: " ", omittingEmptySubsequences: true)
            guard let first = parts.first else { continue }
            let name = String(first.dropFirst("package:".count))
            guard !name.isEmpty else { continue }
            var code: Int64 = 0
            for p in parts.dropFirst() where p.hasPrefix("versionCode:") {
                code = Int64(p.dropFirst("versionCode:".count)) ?? 0
            }
            out[name] = code
        }
        return out
    }

    /// 설치 전/후 스냅샷 비교 — 신규 + 버전코드 변경.
    /// before 가 비어 있으면(조회 실패·미지원) **아무것도 바뀐 것으로 치지 않는다**.
    /// 그렇지 않으면 전체 목록이 "변경"으로 둔갑해 엉뚱한 패키지를 설치 결과로 보고한다.
    static func changedPackages(before: [String: Int64], after: [String: Int64]) -> [String] {
        guard !before.isEmpty else { return [] }
        return after
            .filter { before[$0.key] != $0.value }
            .map(\.key)
            .sorted()
    }

    static func lastLine(_ text: String) -> String? {
        var result: String?
        for line in text.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { result = t }
        }
        return result
    }

    // MARK: - 시스템 앱 (C 단계)

    /// 사용자 0 에서 시스템 앱 제거 — **APK 는 시스템 파티션에 남는다**(복원 가능)
    static func disableUserArgs(package: String) -> [String] {
        ["shell", "pm", "uninstall", "--user", "0", package]
    }

    /// `uninstall --user 0` 복원 — 시스템 파티션의 APK 를 다시 설치 상태로 만든다
    static func restoreUserArgs(package: String) -> [String] {
        ["shell", "cmd", "package", "install-existing", "--user", "0", package]
    }

    /// 목록에서 사라진 시스템 앱 = `pm list packages -u -s` − 현재 설치된 목록.
    /// 이 집합만 복원 UI 에 보여준다(사용자가 지운 서드파티 앱은 복원 대상이 아니다).
    static func removedSystemPackages(
        allIncludingUninstalled: [String],
        installed: [String]
    ) -> [String] {
        let live = Set(installed)
        return sort(Array(Set(allIncludingUninstalled).subtracting(live)))
    }

    /// **하드 블록** — 기기 핵심 구성요소. 비활성화하면 부팅·잠금화면·설정 진입이 깨질 수 있다.
    /// 여기에 없더라도 시스템 앱은 2단계 확인을 거친다.
    static let blockedSystemPackages: Set<String> = [
        "android",
        "com.android.systemui",
        "com.android.settings",
        "com.android.shell",
        "com.android.packageinstaller",
        "com.google.android.packageinstaller",
        "com.android.permissioncontroller",
        "com.google.android.permissioncontroller",
        "com.android.phone",
        "com.android.server.telecom",
        "com.android.providers.settings",
        "com.android.providers.contacts",
        "com.android.providers.media",
        "com.google.android.gms",
        "com.google.android.gsf",
        "com.android.vending",
        "com.android.launcher3"
    ]

    /// 제조사 런처는 이름이 제각각이라 접두사로 막는다
    static let blockedSystemPrefixes: [String] = [
        "com.android.launcher",
        "com.android.systemui",
        "com.android.settings",
        "com.android.packageinstaller",
        "com.google.android.packageinstaller",
        "com.google.android.gms",
        "com.google.android.gsf",
        "com.android.vending",
        "com.sec.android.app.launcher",
        "com.sec.android.app.samsungapps",
        "com.miui.home",
        "com.google.android.apps.nexuslauncher",
        "com.oneplus.launcher",
        "com.oppo.launcher",
        "com.vivo.launcher",
        "com.transsion.XOSLauncher"
    ]

    /// 차단 여부 — 대소문자 무시(패키지명은 소문자지만 방어적으로)
    static func isBlockedSystemPackage(_ package: String) -> Bool {
        let p = package.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !p.isEmpty else { return true }
        if blockedSystemPackages.contains(p) { return true }
        return blockedSystemPrefixes.contains { p.hasPrefix($0.lowercased()) }
    }
}

/// 파일 메타데이터 — 확인 시트의 크기·SHA-256
enum FileDigest {
    static func sizeBytes(path: String) -> UInt64? {
        (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64) ?? nil
    }

    /// 1MB 청크 스트리밍 — 200MB APK 를 통째로 메모리에 올리지 않는다
    static func sha256Hex(path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = handle.readData(ofLength: 1 << 20)
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// 취소 가능한 프로세스 핸들 — `Process` 는 Sendable 이 아니므로 락으로 감싼다.
final class ProcessCancelHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func attach(_ p: Process) {
        lock.lock()
        process = p
        let alreadyCancelled = cancelled
        lock.unlock()
        // 취소가 먼저 눌렸으면 뜨자마자 종료한다
        if alreadyCancelled { p.terminate() }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let p = process
        lock.unlock()
        p?.terminate()
    }

    func reset() {
        lock.lock()
        process = nil
        cancelled = false
        lock.unlock()
    }
}

/// 앱 허브 컨트롤러 — adb IO (MainActor, 단일 기기 시트용)
@MainActor
final class AppHubController: ObservableObject {
    static let shared = AppHubController()

    @Published private(set) var packages: [String] = []
    @Published private(set) var loading = false
    @Published private(set) var busyPackage: String?
    @Published var lastMessage: String?
    @Published var includeSystem = false

    // 설치 상태 — UI 는 이 값만 본다
    @Published private(set) var installing = false
    @Published private(set) var installFileName: String?
    @Published private(set) var installStartedAt: Date?
    @Published private(set) var installSerial: String?
    /// 0…1 — 전송 바이트 기준. 단일 APK 는 adb 가 진행률을 주지 않아 0 에 머문다
    @Published private(set) var installProgress: Double = 0
    /// "전송 중 2/4" 처럼 단계 설명 — 진행률보다 정직한 정보
    @Published private(set) var installPhase: String?

    /// 목록의 versionCode — 아이콘 캐시 키·백업 메타에 쓴다
    @Published private(set) var versionCodes: [String: Int64] = [:]

    // ── 다기기 설치 (C) ──
    /// 이번 설치에서 기기별로 쌓인 결과 — 순차 진행 그대로 보여준다
    @Published private(set) var installResults: [DeviceInstallResult] = []
    @Published private(set) var installTotal = 0
    @Published private(set) var installCompleted = 0

    // ── 시스템 앱 (C) ──
    /// 현재 설치된 시스템 앱 (시스템 토글이 켜져 있을 때만 채워진다)
    @Published private(set) var systemPackages: Set<String> = []
    /// `--user 0` 으로 제거되어 **복원 가능한** 시스템 앱
    @Published private(set) var removedSystemPackages: [String] = []

    /// 백업 상태
    @Published private(set) var backingUp: String?
    @Published private(set) var lastBackupDir: URL?

    /// APK 전송·설치는 네트워크 ADB 에서 오래 걸린다 — 폴링 기본값(20s)과 분리한다
    /// (detached 작업에서도 읽어야 하므로 nonisolated)
    nonisolated static let installTimeout: TimeInterval = 600

    /// 단계 로그용 경과 시간 — 화면의 초 표시와 같은 기준
    nonisolated static func elapsedMillis(since start: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(start) * 1000))
    }

    private let installHandle = ProcessCancelHandle()
    private var installCancelled = false

    private init() {}

    // MARK: - 목록

    /// 목록 재조회.
    /// `clearMessage: false` 는 **방금 끝난 작업의 결과 문구를 지우지 않기** 위한 것이다
    /// (설치 완료 직후의 재조회가 "설치 완료"를 즉시 지워 버리던 문제).
    func refresh(serial: String, clearMessage: Bool = true) {
        guard !serial.isEmpty, !loading else { return }
        guard let adb = DeviceMonitor.adbPathNow() else {
            lastMessage = ErrorCode.adbBinaryMissing.koMessage
            return
        }
        loading = true
        if clearMessage { lastMessage = nil }
        let system = includeSystem
        Task.detached(priority: .utility) {
            let base = ["-s", serial] + AppHubLogic.listArgs(includeSystem: system)
            var out = try? ProcessRunner.capture(
                adb,
                base + ["--show-versioncode"],
                timeout: ProcessRunner.pollTimeout
            )
            let codes = out.flatMap {
                $0.exitCode == 0 && !$0.timedOut
                    ? AppHubLogic.parsePackageVersionCodes($0.stdout)
                    : [:]
            } ?? [:]
            // 구형 pm 은 `--show-versioncode` 를 모른다 → 플래그 없이 한 번 더
            if codes.isEmpty {
                out = try? ProcessRunner.capture(adb, base, timeout: ProcessRunner.pollTimeout)
            }
            var list: [String] = []
            var failure: String?
            if let out, out.exitCode == 0, !out.timedOut {
                list = AppHubLogic.sort(AppHubLogic.parsePackages(out.stdout))
            } else {
                let cause = out?.cause ?? ""
                failure = ErrorCode.adbConnectFailed.koMessage + (cause.isEmpty ? "" : " — \(cause)")
            }

            // 시스템 앱 복원 목록 — `-u -s`(제거 포함 시스템) − 현재 설치됨
            var installedSystem: Set<String> = []
            var removedSystem: [String] = []
            if system, failure == nil {
                let u = try? ProcessRunner.capture(
                    adb,
                    ["-s", serial, "shell", "pm", "list", "packages", "-u", "-s"],
                    timeout: ProcessRunner.pollTimeout
                )
                if let u, u.exitCode == 0, !u.timedOut {
                    let all = AppHubLogic.parsePackages(u.stdout)
                    removedSystem = AppHubLogic.removedSystemPackages(
                        allIncludingUninstalled: all,
                        installed: list
                    )
                    installedSystem = Set(all).subtracting(removedSystem)
                }
            }

            await MainActor.run {
                self.loading = false
                if let failure {
                    self.lastMessage = failure
                } else {
                    self.packages = list
                    self.versionCodes = codes
                    self.systemPackages = installedSystem
                    self.removedSystemPackages = removedSystem
                    if list.isEmpty {
                        self.lastMessage = L10n.string("apphub.status.empty")
                    }
                }
            }
        }
    }

    // MARK: - 앱 액션

    func launch(serial: String, package: String) {
        runPackageAction(
            serial: serial,
            package: package,
            adbArgs: ["-s", serial] + AppHubLogic.launchArgs(package: package),
            okKey: "apphub.status.launched",
            removeAfter: false,
            logKind: IssueLog.Kind.appLaunch
        )
    }

    func forceStop(serial: String, package: String) {
        runPackageAction(
            serial: serial,
            package: package,
            adbArgs: ["-s", serial] + AppHubLogic.forceStopArgs(package: package),
            okKey: "apphub.status.stopped",
            removeAfter: false,
            logKind: IssueLog.Kind.appForceStop
        )
    }

    /// 시스템 앱을 **사용자 0 에서만** 제거한다 — 시스템 파티션의 APK 는 남아 복원할 수 있다.
    /// 하드 블록 패키지는 호출 전에 UI 가 막지만, 여기서도 한 번 더 거른다(방어).
    func disableSystemApp(serial: String, package: String) {
        guard !AppHubLogic.isBlockedSystemPackage(package) else {
            lastMessage = L10n.format("apphub.system.blocked.body", package)
            return
        }
        runPackageAction(
            serial: serial,
            package: package,
            adbArgs: ["-s", serial] + AppHubLogic.disableUserArgs(package: package),
            okKey: "apphub.system.disabled",
            removeAfter: true,
            logKind: IssueLog.Kind.appSystemDisable,
            refreshAfter: true
        )
    }

    /// `pm uninstall --user 0` 복원 — `cmd package install-existing --user 0`
    func restoreSystemApp(serial: String, package: String) {
        runPackageAction(
            serial: serial,
            package: package,
            adbArgs: ["-s", serial] + AppHubLogic.restoreUserArgs(package: package),
            okKey: "apphub.system.restored",
            removeAfter: false,
            logKind: IssueLog.Kind.appSystemRestore,
            refreshAfter: true
        )
    }

    /// 기본은 **앱+데이터 완전 삭제**. `keepData` 는 사용자가 명시적으로 고를 때만.
    func uninstall(serial: String, package: String, keepData: Bool = false) {
        runPackageAction(
            serial: serial,
            package: package,
            adbArgs: ["-s", serial] + AppHubLogic.uninstallArgs(package: package, keepData: keepData),
            okKey: keepData ? "apphub.uninstall.keepData.done" : "apphub.uninstall.done",
            removeAfter: true,
            logKind: IssueLog.Kind.appUninstall
        )
    }

    // MARK: - 설치

    /// 단일 기기 편의 진입점 — 확인 시트는 다기기 목록을 넘긴다
    func install(serial: String, apk: URL, options: AppInstallOptions) {
        install(file: apk, targets: [InstallTarget(serial: serial, label: serial)], options: options)
    }

    /// **여러 대에 순차 설치** — 기기별 결과를 `installResults` 에 쌓아 결과표로 보여준다.
    ///
    /// 번들은 기기 특성(ABI·밀도·언어)마다 골라야 하는 APK 가 다르므로 **프로필별로 한 번만**
    /// 풀고 재사용한다. 같은 프로필의 기기 2대면 추출은 1회다.
    func install(file: URL, targets: [InstallTarget], options: AppInstallOptions) {
        guard !targets.isEmpty, !installing else { return }
        let path = file.path
        guard let kind = AppHubLogic.installKind(path: path) else {
            lastMessage = L10n.string("apphub.install.invalidFile")
            return
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
            lastMessage = L10n.string("apphub.install.notFound")
            return
        }
        guard let size = FileDigest.sizeBytes(path: path), size > 0 else {
            lastMessage = L10n.string("apphub.install.notFound")
            return
        }
        guard let adb = DeviceMonitor.adbPathNow() else {
            lastMessage = ErrorCode.adbBinaryMissing.koMessage
            return
        }

        let fileName = file.lastPathComponent
        installing = true
        // 설치 중에는 새 아이콘 pull 을 멈춘다 — 같은 네트워크 ADB 대역폭을 나눠 쓰면
        // APK 전송이 느려져 "설치가 안 끝나는 것처럼" 보인다 (2026-11-05 사용자 신고)
        AppIconStore.shared.suspend()
        installCancelled = false
        installHandle.reset()
        installFileName = fileName
        installStartedAt = .now
        installSerial = targets.first?.serial
        installProgress = 0
        installPhase = L10n.string("apphub.install.phase.preparing")
        installTotal = targets.count
        installCompleted = 0
        installResults = []
        lastMessage = targets.count > 1
            ? L10n.format("apphub.install.many.running", fileName, targets.count)
            : L10n.format("apphub.install.running", fileName)

        let installClock = Date()
        let flags = AppHubLogic.installFlags(options)
        DebugLogger.shared.info(
            "AppHub",
            "[INFO] 설치 시작 — \(fileName) (\(size) bytes) · \(targets.count)대 · 옵션 \(flags.isEmpty ? "없음" : flags.joined(separator: " "))"
        )

        Task {
            defer { AppIconStore.shared.resume() }
            let shaClock = Date()
            let sha = await Task.detached(priority: .utility) {
                FileDigest.sha256Hex(path: path) ?? "-"
            }.value
            // 지문 계산은 큰 APK 에서 수 초 걸린다 — 단계 문구가 "준비 중…"에 머무는 이유를 로그로 남긴다
            DebugLogger.shared.info(
                "AppHub",
                "[INFO] 지문 — \(fileName) \(sha.prefix(16)) · \(Self.elapsedMillis(since: shaClock))ms"
            )

            // 번들 추출물은 프로필별 1회 — 여러 기기가 같은 ABI·밀도면 재사용한다
            let tempRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("relay-install-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: tempRoot) }
            var cache: [String: PreparedBundle] = [:]

            for (index, target) in targets.enumerated() {
                if installCancelled { break }
                installSerial = target.serial
                installProgress = 0
                installPhase = targets.count == 1
                    ? L10n.string("apphub.install.phase.device.one")
                    : L10n.format("apphub.install.phase.device", index + 1, targets.count)

                // 설치 전 스냅샷 — 성공 후 어느 패키지가 새로 생겼/바뀌었는지 찾기 위한 원재료
                let targetClock = Date()
                let before = await Self.versionCodesAsync(adb: adb, serial: target.serial)
                DebugLogger.shared.info(
                    "AppHub",
                    "[INFO] 설치 전 확인 — \(target.serial) 서드파티 \(before.count)개 · \(Self.elapsedMillis(since: targetClock))ms"
                )

                var report: InstallReport
                if kind == .apk {
                    report = await self.runSingleInstall(
                        adb: adb,
                        serial: target.serial,
                        path: path,
                        options: options,
                        before: before
                    )
                } else {
                    do {
                        let profile = await Self.deviceProfileAsync(adb: adb, serial: target.serial)
                        let key = "\(profile.abis.joined(separator: ","))|\(profile.density)|\(profile.languages.joined(separator: ","))"
                        let prepared: PreparedBundle
                        if let hit = cache[key] {
                            prepared = hit
                        } else {
                            installPhase = L10n.string("apphub.install.phase.preparing")
                            let dir = tempRoot.appendingPathComponent("p\(cache.count)", isDirectory: true)
                            prepared = try await Task.detached(priority: .userInitiated) {
                                try BundleInstaller.prepare(url: file, kind: kind, profile: profile, into: dir)
                            }.value
                            cache[key] = prepared
                        }
                        report = try await self.runBundleInstall(
                            adb: adb,
                            serial: target.serial,
                            prepared: prepared,
                            options: options,
                            before: before
                        )
                    } catch let error as BundleInstallError {
                        report = InstallReport(
                            ok: false,
                            message: error.message,
                            detail: "bundle \(error.detail)",
                            packageName: nil,
                            version: nil
                        )
                    } catch {
                        report = InstallReport(
                            ok: false,
                            message: L10n.string("apphub.install.failedGeneric"),
                            detail: "\(error)",
                            packageName: nil,
                            version: nil
                        )
                    }
                }

                self.installResults.append(DeviceInstallResult(
                    serial: target.serial,
                    label: target.label,
                    ok: report.ok,
                    message: report.message,
                    packageName: report.packageName,
                    versionName: report.version
                ))
                self.installCompleted = index + 1

                IssueLog.append(
                    IssueLog.Entry(
                        kind: IssueLog.Kind.appInstall,
                        detail: "file=\(fileName) sha256=\(sha) \(report.detail)",
                        serial: target.serial,
                        package: report.packageName,
                        ok: report.ok
                    ),
                    name: "apphub"
                )
                if report.ok {
                    DebugLogger.shared.info(
                        "AppHub",
                        "[INFO] 설치 — \(target.serial) \(report.detail) · \(Self.elapsedMillis(since: targetClock))ms"
                    )
                } else {
                    DebugLogger.shared.error(
                        "AppHub",
                        "[ERROR] E-MAC-ADB-0007 설치 실패 — \(target.serial) \(report.detail) · \(Self.elapsedMillis(since: targetClock))ms"
                    )
                }
            }

            if self.installCancelled {
                DebugLogger.shared.warn(
                    "AppHub",
                    "[WARN] 설치 취소 — \(fileName) · \(Self.elapsedMillis(since: installClock))ms"
                )
            }

            self.installing = false
            self.installFileName = nil
            self.installStartedAt = nil
            self.installSerial = nil
            self.installProgress = 0
            self.installPhase = nil
            self.installHandle.reset()
            self.installCancelled = false

            let okCount = self.installResults.filter(\.ok).count
            if self.installResults.count == 1, let only = self.installResults.first {
                self.lastMessage = only.message
            } else if self.installCancelled || self.installResults.count < targets.count {
                self.lastMessage = L10n.format("apphub.install.many.partial", okCount, targets.count)
            } else {
                self.lastMessage = L10n.format("apphub.install.many.result", okCount, targets.count)
            }
            // 목록은 **한 대일 때만** 여기서 갱신한다. 여러 대면 시트가 자기 기기만 새로고침한다
            if targets.count == 1, let serial = targets.first?.serial {
                // 결과 문구를 지우지 않도록 clearMessage: false
                self.refresh(serial: serial, clearMessage: false)
            }
        }
    }

    func cancelInstall() {
        guard installing else { return }
        installCancelled = true
        installHandle.cancel()
    }

    /// 결과표 닫기 — 설치 중에는 지우지 않는다(진행 중인 결과를 잃지 않게)
    func clearInstallResults() {
        guard !installing else { return }
        installResults = []
        installTotal = 0
        installCompleted = 0
    }

    /// 단일 APK — `adb install` (A 단계 경로 그대로)
    private func runSingleInstall(
        adb: String,
        serial: String,
        path: String,
        options: AppInstallOptions,
        before: [String: Int64]
    ) async -> InstallReport {
        // adb 는 설치 중 진행률을 주지 않는다. 그래도 **무엇을 하는 중인지**는 말해야 한다
        // (종전에는 "기기 준비 중…"에 멈춰 있어 24초짜리 설치가 멈춘 것처럼 보였다 — 2026-11-05)
        installPhase = L10n.string("apphub.install.phase.install")
        let clock = Date()
        let out = await Self.captureAsync(
            adb,
            ["-s", serial] + AppHubLogic.installArgs(path: path, options: options),
            timeout: Self.installTimeout,
            handle: installHandle
        )
        let outcome = out.map { $0.timedOut ? "timeout" : "exit=\($0.exitCode)" } ?? "실행 실패"
        DebugLogger.shared.info(
            "AppHub",
            "[INFO] adb install — \(serial) \(outcome) · \(Self.elapsedMillis(since: clock))ms"
        )
        let report = await applyInstallResult(
            out: out,
            adb: adb,
            serial: serial,
            before: before,
            cancelled: installCancelled
        )
        // 진행률 막대를 끝까지 채운 뒤 배너가 사라진다 (0 에 머물다 툭 사라지지 않게)
        if report.ok { installProgress = 1 }
        return report
    }

    /// 번들(.apks/.xapk/.apkm) — push → `pm install-multiple` → OBB (추출은 호출측이 끝냈다)
    private func runBundleInstall(
        adb: String,
        serial: String,
        prepared: PreparedBundle,
        options: AppInstallOptions,
        before: [String: Int64]
    ) async throws -> InstallReport {
        guard let pkg = prepared.packageHint, AppHubLogic.isValidPackage(pkg) else {
            throw BundleInstallError.metadata
        }

        let remoteDir = "/data/local/tmp/relay-install-\(UUID().uuidString.prefix(8).lowercased())"
        _ = await Self.captureAsync(adb, ["-s", serial, "shell", "mkdir", "-p", remoteDir], timeout: 30)
        // 원격 잔여물은 성공·실패와 무관하게 지운다 (기기에 임시 파일을 남기지 않는다)
        let cleanupAdb = adb
        let cleanupSerial = serial
        defer {
            Task.detached(priority: .utility) {
                _ = try? ProcessRunner.capture(
                    cleanupAdb,
                    ["-s", cleanupSerial, "shell", "rm", "-rf", remoteDir],
                    timeout: 30
                )
            }
        }

        var sent: UInt64 = 0
        var remotePaths: [String] = []
        for (index, file) in prepared.apkFiles.enumerated() {
            if installCancelled {
                return InstallReport(
                    ok: false,
                    message: L10n.string("apphub.install.cancelled"),
                    detail: "cancelled",
                    packageName: pkg,
                    version: nil
                )
            }
            installPhase = L10n.format("apphub.install.phase.push", index + 1, prepared.apkFiles.count)
            let remote = remoteDir + "/" + file.lastPathComponent
            let pushed = await pushWithProgress(
                adb: adb,
                serial: serial,
                local: file,
                remote: remote,
                base: sent,
                total: prepared.totalBytes
            )
            guard let pushed, pushed.exitCode == 0, !pushed.timedOut else {
                if installCancelled {
                    return InstallReport(
                        ok: false,
                        message: L10n.string("apphub.install.cancelled"),
                        detail: "cancelled",
                        packageName: pkg,
                        version: nil
                    )
                }
                return InstallReport(
                    ok: false,
                    message: L10n.string("apphub.install.pushFailed"),
                    detail: "push failed: \(pushed?.cause ?? "nil")",
                    packageName: pkg,
                    version: nil
                )
            }
            sent += FileDigest.sizeBytes(path: file.path) ?? 0
            if prepared.totalBytes > 0 {
                installProgress = min(0.94, Double(sent) / Double(prepared.totalBytes) * 0.94)
            }
            remotePaths.append(remote)
        }

        installPhase = L10n.string("apphub.install.phase.install")
        let out = await Self.captureAsync(
            adb,
            ["-s", serial] + AppHubLogic.installMultipleArgs(remotePaths: remotePaths, options: options),
            timeout: Self.installTimeout,
            handle: installHandle
        )
        var report = await applyInstallResult(
            out: out,
            adb: adb,
            serial: serial,
            before: before,
            cancelled: installCancelled
        )

        // OBB 는 앱 설치가 성공한 뒤에만 — 실패한 설치의 부산물을 기기에 남기지 않는다
        if report.ok, !prepared.obbFiles.isEmpty {
            installPhase = L10n.string("apphub.install.phase.obb")
            for item in prepared.obbFiles {
                let dest = BundleInstaller.obbDestination(relativePath: item.relativePath, package: pkg)
                let dir = (dest as NSString).deletingLastPathComponent
                _ = await Self.captureAsync(adb, ["-s", serial, "shell", "mkdir", "-p", dir], timeout: 30)
                let pushed = await pushWithProgress(
                    adb: adb,
                    serial: serial,
                    local: item.url,
                    remote: dest,
                    base: 0,
                    total: 0
                )
                if pushed?.exitCode != 0 {
                    report.message = report.message + " · " + L10n.string("apphub.install.obbFailed")
                    report.detail = report.detail + " obb-failed"
                }
            }
        }
        installProgress = 1
        if report.packageName == nil { report.packageName = pkg }
        return report
    }

    /// push 한 파일 — 전송 중에는 원격 파일 크기를 폴링해 진행률을 만든다
    private func pushWithProgress(
        adb: String,
        serial: String,
        local: URL,
        remote: String,
        base: UInt64,
        total: UInt64
    ) async -> ProcessRunner.Output? {
        let flag = OnceFlag()
        let handle = installHandle
        let task = Task.detached(priority: .userInitiated) { () -> ProcessRunner.Output? in
            defer { flag.set() }
            return try? ProcessRunner.capture(
                adb,
                ["-s", serial, "push", local.path, remote],
                timeout: 900,
                onStart: { p in handle.attach(p) }
            )
        }
        let expected = FileDigest.sizeBytes(path: local.path) ?? 0
        while !flag.isSet {
            if installCancelled { break }
            if total > 0,
               let size = await Self.remoteSizeAsync(adb: adb, serial: serial, path: remote) {
                let done = base + min(size, expected)
                installProgress = min(0.94, Double(done) / Double(total) * 0.94)
            }
            try? await Task.sleep(for: .milliseconds(600))
        }
        return await task.value
    }

    /// 설치 결과 해석 + 버전 검증 (단일·번들 공통)
    private func applyInstallResult(
        out: ProcessRunner.Output?,
        adb: String,
        serial: String,
        before: [String: Int64],
        cancelled: Bool
    ) async -> InstallReport {
        let parsed = out.map {
            AppHubLogic.parseInstallResult(
                stdout: $0.stdout,
                stderr: $0.stderr,
                exitCode: $0.exitCode,
                timedOut: $0.timedOut
            )
        }
        // 취소가 이겼더라도 adb 가 이미 `Success` 를 냈으면 성공으로 기록한다 —
        // "취소했다"는 표시와 실제 설치 결과가 어긋나면 감사 로그가 거짓이 된다.
        if cancelled, parsed != .installed {
            return InstallReport(
                ok: false,
                message: L10n.string("apphub.install.cancelled"),
                detail: "cancelled",
                packageName: nil,
                version: nil
            )
        }
        guard let parsed else {
            return InstallReport(
                ok: false,
                message: ErrorCode.adbBinaryMissing.koMessage,
                detail: "adb missing",
                packageName: nil,
                version: nil
            )
        }
        switch parsed {
        case .installed:
            // 설치는 끝났지만 **어떤 패키지가 바뀌었는지** 확인하는 단계가 남아 있다.
            // 이 문구가 없으면 마지막 몇 초가 다시 "멈춘 화면"처럼 보인다.
            installPhase = L10n.string("apphub.install.phase.verify")
            let verifyClock = Date()
            let after = await Self.versionCodesAsync(adb: adb, serial: serial)
            let changed = AppHubLogic.changedPackages(before: before, after: after)
            var version: String?
            if changed.count == 1, let pkg = changed.first {
                version = await Self.versionNameAsync(adb: adb, serial: serial, package: pkg)
            }
            let versionNote = version.map { " v\($0)" } ?? ""
            DebugLogger.shared.info(
                "AppHub",
                "[INFO] 설치 확인 — \(serial) 변경 \(changed.count)개\(versionNote) · \(Self.elapsedMillis(since: verifyClock))ms"
            )
            if changed.count == 1, let pkg = changed.first {
                return InstallReport(
                    ok: true,
                    message: L10n.format("apphub.install.done.version", pkg, version ?? L10n.na),
                    detail: "ok pkg=\(pkg) version=\(version ?? "?")",
                    packageName: pkg,
                    version: version
                )
            }
            // 동일 버전 재설치 등 — 확인할 수 없는 것을 확인한 척하지 않는다
            return InstallReport(
                ok: true,
                message: L10n.string("apphub.install.done"),
                detail: "ok (version unverified, changed=\(changed.count))",
                packageName: changed.first,
                version: nil
            )
        case .timedOut:
            return InstallReport(
                ok: false,
                message: L10n.format("apphub.install.timedOut", Int(Self.installTimeout)),
                detail: "timeout",
                packageName: nil,
                version: nil
            )
        case .failed(let code, let d):
            let hint = L10n.string(AppHubLogic.failureKey(code: code))
            let tail = code ?? (d.isEmpty ? L10n.string("apphub.status.failed") : d)
            return InstallReport(
                ok: false,
                message: "\(hint) — \(tail)",
                detail: "fail code=\(code ?? "-") \(d)",
                packageName: nil,
                version: nil
            )
        }
    }

    // MARK: - APK 백업

    /// 설치된 APK 를 `~/Downloads/RelayConsole/APKs/<pkg>/<버전>/` 로 복사한다.
    /// **앱 데이터는 포함되지 않는다** — meta.json 에도 그렇게 적는다.
    func backup(serial: String, package: String) {
        guard !serial.isEmpty, backingUp == nil else { return }
        guard AppHubLogic.isValidPackage(package) else {
            lastMessage = L10n.string("apphub.status.invalid")
            return
        }
        guard let adb = DeviceMonitor.adbPathNow() else {
            lastMessage = ErrorCode.adbBinaryMissing.koMessage
            return
        }
        backingUp = package
        lastBackupDir = nil
        lastMessage = L10n.format("apphub.backup.running", package)

        Task {
            let paths = await Self.packagePathsAsync(adb: adb, serial: serial, package: package)
            guard !paths.isEmpty else {
                self.backingUp = nil
                self.lastMessage = L10n.string("apphub.backup.noApk")
                return
            }
            let versionName = await Self.versionNameAsync(adb: adb, serial: serial, package: package) ?? "unknown"
            let versionCode = (await Self.versionCodesAsync(adb: adb, serial: serial))[package]
            let dir = Self.uniqueBackupDir(package: package, version: versionName)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            var files: [BackupManifest.File] = []
            for remote in paths {
                let name = (remote as NSString).lastPathComponent
                let dest = dir.appendingPathComponent(BundleInstaller.safeName(name))
                let pulled = await Self.captureAsync(
                    adb,
                    ["-s", serial, "pull", remote, dest.path],
                    timeout: 300
                )
                guard let pulled, pulled.exitCode == 0, !pulled.timedOut else { continue }
                let bytes = FileDigest.sizeBytes(path: dest.path) ?? 0
                let sha = await Task.detached(priority: .utility) {
                    FileDigest.sha256Hex(path: dest.path)
                }.value
                files.append(BackupManifest.File(name: dest.lastPathComponent, bytes: Int64(bytes), sha256: sha))
            }

            let manifest = BackupManifest(
                package: package,
                versionName: versionName,
                versionCode: versionCode,
                serial: serial,
                savedAt: ISO8601DateFormatter().string(from: .now),
                files: files,
                note: "APK only — app data is not included"
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(manifest) {
                try? data.write(to: dir.appendingPathComponent("meta.json"), options: .atomic)
            }

            IssueLog.append(
                IssueLog.Entry(
                    kind: IssueLog.Kind.appBackup,
                    detail: "version=\(versionName) files=\(files.count)/\(paths.count) dir=\(dir.path)",
                    serial: serial,
                    package: package,
                    ok: files.count == paths.count
                ),
                name: "apphub"
            )

            self.backingUp = nil
            if files.isEmpty {
                self.lastMessage = L10n.string("apphub.backup.failed")
                try? FileManager.default.removeItem(at: dir)
            } else {
                self.lastBackupDir = dir
                self.lastMessage = files.count == paths.count
                    ? L10n.format("apphub.backup.done", package, versionName)
                    : L10n.format("apphub.backup.partial", files.count, paths.count)
            }
        }
    }

    func revealBackup() {
        guard let dir = lastBackupDir else { return }
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }

    // MARK: - 공통 액션

    private func runPackageAction(
        serial: String,
        package: String,
        adbArgs: [String],
        okKey: String,
        removeAfter: Bool,
        logKind: String,
        refreshAfter: Bool = false
    ) {
        guard !serial.isEmpty, busyPackage == nil else { return }
        guard AppHubLogic.isValidPackage(package) else {
            lastMessage = L10n.string("apphub.status.invalid")
            return
        }
        guard let adb = DeviceMonitor.adbPathNow() else {
            lastMessage = ErrorCode.adbBinaryMissing.koMessage
            return
        }
        busyPackage = package
        Task.detached(priority: .userInitiated) {
            let out = try? ProcessRunner.capture(adb, adbArgs, timeout: 60)
            var ok = false
            var message: String?
            if let out {
                if out.timedOut {
                    message = L10n.string("apphub.status.timeout")
                } else {
                    let text = out.stdout + "\n" + out.stderr
                    let lower = text.lowercased()
                    // monkey: "Events injected" · pm: "Success" · am force-stop: 출력 없음
                    ok = out.exitCode == 0 && (
                        lower.contains("success")
                        || lower.contains("events injected")
                        || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    if !ok {
                        if let code = AppHubLogic.failureCode(in: text) {
                            let key = logKind == IssueLog.Kind.appUninstall
                                ? AppHubLogic.uninstallFailureKey(code: code)
                                : AppHubLogic.failureKey(code: code)
                            message = "\(L10n.string(key)) — \(code)"
                        } else {
                            message = ProcessRunner.lastMeaningfulLine(text)
                                ?? "\(L10n.string("apphub.status.failed")) (exit \(out.exitCode))"
                        }
                    }
                }
            } else {
                message = ErrorCode.adbConnectFailed.koMessage
            }

            IssueLog.append(
                IssueLog.Entry(
                    kind: logKind,
                    detail: message ?? "ok",
                    serial: serial,
                    package: package,
                    ok: ok
                ),
                name: "apphub"
            )
            if !ok {
                await DebugLogger.shared.error(
                    "AppHub",
                    "[ERROR] \(logKind == IssueLog.Kind.appUninstall ? "E-MAC-ADB-0008" : "E-MAC-ADB-0002") \(package) — \(message ?? "?")"
                )
            }

            await MainActor.run {
                self.busyPackage = nil
                if ok {
                    self.lastMessage = L10n.format(okKey, package)
                    if removeAfter {
                        self.packages.removeAll { $0 == package }
                    }
                    // 시스템 앱 제거/복원은 두 목록(설치됨·복원 가능)이 함께 바뀐다
                    if refreshAfter {
                        self.refresh(serial: serial, clearMessage: false)
                    }
                } else {
                    self.lastMessage = message ?? L10n.string("apphub.status.failed")
                }
            }
        }
    }

    // MARK: - 검증 보조

    private nonisolated static func versionCodesAsync(adb: String, serial: String) async -> [String: Int64] {
        await Task.detached(priority: .utility) {
            let args = [
                "-s", serial,
                "shell", "pm", "list", "packages", "-3", "--show-versioncode"
            ]
            guard let out = try? ProcessRunner.capture(adb, args, timeout: ProcessRunner.pollTimeout),
                  out.exitCode == 0, !out.timedOut else { return [:] }
            return AppHubLogic.parsePackageVersionCodes(out.stdout)
        }.value
    }

    private nonisolated static func versionNameAsync(adb: String, serial: String, package: String) async -> String? {
        await Task.detached(priority: .utility) {
            guard let out = try? ProcessRunner.capture(
                adb,
                ["-s", serial, "shell", "dumpsys", "package", package],
                timeout: ProcessRunner.pollTimeout
            ), out.exitCode == 0 else { return nil }
            return AppHubLogic.versionName(fromDumpsys: out.stdout)
        }.value
    }

    /// 설치된 APK 경로들 (`pm path`) — split 포함
    private nonisolated static func packagePathsAsync(adb: String, serial: String, package: String) async -> [String] {
        await Task.detached(priority: .utility) {
            guard let out = try? ProcessRunner.capture(
                adb,
                ["-s", serial, "shell", "pm", "path", package],
                timeout: ProcessRunner.pollTimeout
            ), out.exitCode == 0, !out.timedOut else { return [] }
            return out.stdout
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("package:") }
                .map { String($0.dropFirst("package:".count)) }
                .filter { !$0.isEmpty }
        }.value
    }

    private nonisolated static func remoteSizeAsync(adb: String, serial: String, path: String) async -> UInt64? {
        await Task.detached(priority: .utility) {
            guard let out = try? ProcessRunner.capture(
                adb,
                ["-s", serial, "shell", "wc", "-c", "<", path],
                timeout: 10
            ), out.exitCode == 0, !out.timedOut else { return nil }
            return UInt64(out.stdout.filter(\.isNumber))
        }.value
    }

    /// 기기 특성 — 분할 선택(ABI·밀도·언어)의 원재료
    private nonisolated static func deviceProfileAsync(adb: String, serial: String) async -> DeviceProfile {
        await Task.detached(priority: .utility) {
            var profile = DeviceProfile()

            func shell(_ args: [String]) -> String? {
                guard let out = try? ProcessRunner.capture(
                    adb,
                    ["-s", serial, "shell"] + args,
                    timeout: ProcessRunner.pollTimeout
                ), out.exitCode == 0, !out.timedOut else { return nil }
                return out.stdout
            }

            if let list = shell(["getprop", "ro.product.cpu.abilist"]) {
                profile.abis = list
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                    .filter { !$0.isEmpty }
            }
            if profile.abis.isEmpty, let abi = shell(["getprop", "ro.product.cpu.abi"]) {
                let value = abi.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !value.isEmpty { profile.abis = [value] }
            }
            if let density = shell(["wm", "density"]) {
                let line = density
                    .split(separator: "\n")
                    .first { $0.lowercased().contains("density") }
                let digits = (line ?? "").filter(\.isNumber)
                profile.density = Int(digits) ?? 0
            }
            let locale = (shell(["getprop", "persist.sys.locale"])
                ?? shell(["getprop", "ro.product.locale"])
                ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !locale.isEmpty {
                let lang = locale.split(separator: "-").first.map(String.init) ?? locale
                profile.languages = [locale.replacingOccurrences(of: "-", with: "_"), lang]
            }
            return profile
        }.value
    }

    nonisolated static func captureAsync(
        _ path: String,
        _ args: [String],
        timeout: TimeInterval,
        handle: ProcessCancelHandle? = nil
    ) async -> ProcessRunner.Output? {
        await Task.detached(priority: .userInitiated) {
            try? ProcessRunner.capture(
                path,
                args,
                timeout: timeout,
                onStart: handle.map { h in { p in h.attach(p) } }
            )
        }.value
    }

    // MARK: - 백업 경로

    nonisolated static var backupRoot: URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
        return downloads
            .appendingPathComponent("RelayConsole", isDirectory: true)
            .appendingPathComponent("APKs", isDirectory: true)
    }

    /// 같은 패키지·버전을 다시 백업하면 `-2`, `-3` … — 덮어쓰지 않는다
    nonisolated static func uniqueBackupDir(package: String, version: String) -> URL {
        let safeVersion = BundleInstaller.safeName(version)
        let base = backupRoot
            .appendingPathComponent(BundleInstaller.safeName(package), isDirectory: true)
            .appendingPathComponent(safeVersion, isDirectory: true)
        var candidate = base
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = base.deletingLastPathComponent()
                .appendingPathComponent("\(safeVersion)-\(index)", isDirectory: true)
            index += 1
            if index > 99 { break }
        }
        return candidate
    }
}

/// 백업 폴더의 `meta.json` — 나중에 "이 APK 가 무엇이었는지" 를 복원 없이 확인할 수 있게
struct BackupManifest: Codable, Equatable, Sendable {
    struct File: Codable, Equatable, Sendable {
        let name: String
        let bytes: Int64
        let sha256: String?
    }

    let package: String
    let versionName: String?
    let versionCode: Int64?
    let serial: String
    let savedAt: String
    let files: [File]
    let note: String
}
