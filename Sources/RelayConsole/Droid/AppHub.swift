import Foundation

/// 앱 허브 순수 로직 — 패키지 파싱·검증·검색·adb 인자 (테스트 대상)
enum AppHubLogic {
    /// `pm list packages` 출력 → 패키지명 목록 (순서 유지·중복 제거)
    static func parsePackages(_ text: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let s = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard s.hasPrefix("package:") else { continue }
            let name = String(s.dropFirst("package:".count))
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

    static func uninstallArgs(package: String) -> [String] {
        ["shell", "pm", "uninstall", "-k", package]
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

    private init() {}

    func refresh(serial: String) {
        guard !serial.isEmpty, !loading else { return }
        loading = true
        lastMessage = nil
        let system = includeSystem
        let adb = DeviceMonitor.adbPathNow()
        Task.detached(priority: .utility) {
            let result: Result<[String], ErrorCode>
            if let adb {
                let args = ["-s", serial] + AppHubLogic.listArgs(includeSystem: system)
                if let text = Self.run(adb: adb, args: args) {
                    result = .success(AppHubLogic.sort(AppHubLogic.parsePackages(text)))
                } else {
                    result = .failure(.adbConnectFailed)
                }
            } else {
                result = .failure(.adbBinaryMissing)
            }
            await MainActor.run {
                self.loading = false
                switch result {
                case .success(let list):
                    self.packages = list
                    if list.isEmpty {
                        self.lastMessage = L10n.string("apphub.status.empty")
                    }
                case .failure(let code):
                    self.lastMessage = code.koMessage
                }
            }
        }
    }

    func launch(serial: String, package: String) {
        runPackageAction(serial: serial, package: package, adbArgs: ["-s", serial] + AppHubLogic.launchArgs(package: package), okKey: "apphub.status.launched")
    }

    func forceStop(serial: String, package: String) {
        runPackageAction(serial: serial, package: package, adbArgs: ["-s", serial] + AppHubLogic.forceStopArgs(package: package), okKey: "apphub.status.stopped")
    }

    func uninstall(serial: String, package: String) {
        runPackageAction(
            serial: serial,
            package: package,
            adbArgs: ["-s", serial] + AppHubLogic.uninstallArgs(package: package),
            okKey: "apphub.status.uninstalled",
            removeAfter: true
        )
    }

    private func runPackageAction(
        serial: String,
        package: String,
        adbArgs: [String],
        okKey: String,
        removeAfter: Bool = false
    ) {
        guard !serial.isEmpty, busyPackage == nil else { return }
        guard AppHubLogic.isValidPackage(package) else {
            lastMessage = L10n.string("apphub.status.invalid")
            return
        }
        busyPackage = package
        let adb = DeviceMonitor.adbPathNow()
        Task.detached(priority: .userInitiated) {
            var message: String?
            var ok = false
            if let adb, let out = Self.run(adb: adb, args: adbArgs) {
                // monkey은 exit 0 + "Events injected" · pm uninstall은 "Success"
                let lower = out.lowercased()
                ok = lower.contains("success") || lower.contains("events injected") || out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if !ok {
                    message = out.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else {
                message = L10n.string("apphub.status.failed")
            }
            await MainActor.run {
                self.busyPackage = nil
                if ok {
                    self.lastMessage = L10n.format(okKey, package)
                    if removeAfter {
                        self.packages.removeAll { $0 == package }
                    }
                } else {
                    self.lastMessage = message ?? L10n.string("apphub.status.failed")
                }
            }
        }
    }

    nonisolated private static func run(adb: String, args: [String]) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: adb)
        proc.arguments = args
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
