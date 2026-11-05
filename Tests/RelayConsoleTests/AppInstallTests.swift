import Foundation
import Testing
@testable import RelayConsole

/// APK 설치·삭제 (1.22.0) 순수 로직 — 인자 조립·결과 해석·검증 diff
///
/// 실기기 없이도 깨져야 할 것들만 모은다. adb 출력 픽스처는 실제 `adb install` /
/// `pm uninstall` 응답을 그대로 옮긴 것이다 (버전별 성공 문구 차이 포함).
struct AppInstallTests {
    // MARK: - 인자 조립

    @Test func installArgsDefaultsToReinstallOnly() {
        #expect(AppHubLogic.installArgs(path: "/tmp/a.apk", options: AppInstallOptions()) == [
            "install", "-r", "/tmp/a.apk"
        ])
    }

    /// adb 옵션은 **경로 앞**에 온다 — 뒤에 붙이면 adb 가 파일명으로 읽는다
    @Test func installArgsOptionOrder() {
        var o = AppInstallOptions()
        o.allowDowngrade = true
        o.grantAllPermissions = true
        o.allowTestOnly = true
        #expect(AppHubLogic.installArgs(path: "/tmp/a.apk", options: o) == [
            "install", "-r", "-d", "-g", "-t", "/tmp/a.apk"
        ])
    }

    @Test func installArgsWithoutReinstall() {
        var o = AppInstallOptions()
        o.reinstall = false
        #expect(AppHubLogic.installArgs(path: "/tmp/a.apk", options: o) == ["install", "/tmp/a.apk"])
    }

    @Test func isApkFileRequiresAbsoluteApkPath() {
        #expect(AppHubLogic.isApkFile("/Users/me/Downloads/app.apk"))
        #expect(AppHubLogic.isApkFile("/tmp/APP.APK"))
        #expect(!AppHubLogic.isApkFile("relative/app.apk"))
        #expect(!AppHubLogic.isApkFile("/tmp/app.apks"))
        #expect(!AppHubLogic.isApkFile("/tmp/app.zip"))
        #expect(!AppHubLogic.isApkFile(""))
    }

    // MARK: - 설치 결과

    @Test func streamedInstallSuccess() {
        let out = AppHubLogic.parseInstallResult(
            stdout: "Performing Streamed Install\nSuccess",
            stderr: "",
            exitCode: 0,
            timedOut: false
        )
        #expect(out == .installed)
    }

    @Test func legacyInstallSuccess() {
        #expect(AppHubLogic.parseInstallResult(
            stdout: "1234 KB/s (567890 bytes in 0.400s)\n\tpkg: /data/local/tmp/app.apk\nSuccess",
            stderr: "",
            exitCode: 0,
            timedOut: false
        ) == .installed)
    }

    /// adb 는 성공해도 아무것도 출력하지 않는 경우가 있다
    @Test func silentSuccess() {
        #expect(AppHubLogic.parseInstallResult(
            stdout: "", stderr: "", exitCode: 0, timedOut: false
        ) == .installed)
    }

    /// 실패인데 exit 0 을 내는 adb 가 있다 — 종료 코드만 믿으면 성공으로 오판한다
    @Test func failureWithZeroExitCode() {
        let out = AppHubLogic.parseInstallResult(
            stdout: "Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE: Package com.x.y signatures do not match]",
            stderr: "",
            exitCode: 0,
            timedOut: false
        )
        #expect(out == .failed(code: "INSTALL_FAILED_UPDATE_INCOMPATIBLE", detail: "Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE: Package com.x.y signatures do not match]"))
    }

    @Test func failureCodeOnStderr() {
        let out = AppHubLogic.parseInstallResult(
            stdout: "",
            stderr: "adb: failed to install app.apk: Failure [INSTALL_FAILED_INSUFFICIENT_STORAGE]",
            exitCode: 1,
            timedOut: false
        )
        #expect(out == .failed(code: "INSTALL_FAILED_INSUFFICIENT_STORAGE", detail: "adb: failed to install app.apk: Failure [INSTALL_FAILED_INSUFFICIENT_STORAGE]"))
    }

    @Test func failureWithoutCodeKeepsLastLine() {
        let out = AppHubLogic.parseInstallResult(
            stdout: "adb: error: failed to get feature set: device offline",
            stderr: "",
            exitCode: 1,
            timedOut: false
        )
        #expect(out == .failed(code: nil, detail: "adb: error: failed to get feature set: device offline"))
    }

    @Test func timeoutWinsOverOutput() {
        #expect(AppHubLogic.parseInstallResult(
            stdout: "Performing Streamed Install",
            stderr: "",
            exitCode: 0,
            timedOut: true
        ) == .timedOut)
    }

    // MARK: - 삭제 결과

    @Test func uninstallSuccessAndFailure() {
        #expect(AppHubLogic.parseUninstallResult(
            stdout: "Success", stderr: "", exitCode: 0, timedOut: false
        ) == .installed)
        #expect(AppHubLogic.parseUninstallResult(
            stdout: "", stderr: "", exitCode: 0, timedOut: false
        ) == .installed)
        #expect(AppHubLogic.parseUninstallResult(
            stdout: "", stderr: "Failure [DELETE_FAILED_DEVICE_POLICY_MANAGER]", exitCode: 1, timedOut: false
        ) == .failed(code: "DELETE_FAILED_DEVICE_POLICY_MANAGER", detail: "Failure [DELETE_FAILED_DEVICE_POLICY_MANAGER]"))
    }

    // MARK: - 실패 코드 → 문구

    @Test func failureCodeParsingStopsAtDetail() {
        #expect(AppHubLogic.failureCode(in: "Failure [INSTALL_FAILED_OLDER_SDK: Requires newer sdk version #34]")
                == "INSTALL_FAILED_OLDER_SDK")
        #expect(AppHubLogic.failureCode(in: "Failure [INSTALL_PARSE_FAILED_NO_CERTIFICATES]") == "INSTALL_PARSE_FAILED_NO_CERTIFICATES")
        #expect(AppHubLogic.failureCode(in: "Success") == nil)
        #expect(AppHubLogic.failureCode(in: "Failure [") == nil)
    }

    @Test func failureKeyMapping() {
        #expect(AppHubLogic.failureKey(code: nil) == "apphub.fail.unknown")
        #expect(AppHubLogic.failureKey(code: "INSTALL_FAILED_UPDATE_INCOMPATIBLE") == "apphub.fail.updateIncompatible")
        #expect(AppHubLogic.failureKey(code: "INSTALL_FAILED_VERSION_DOWNGRADE") == "apphub.fail.versionDowngrade")
        #expect(AppHubLogic.failureKey(code: "INSTALL_FAILED_DEPRECATED_SDK_VERSION") == "apphub.fail.deprecatedSdk")
        #expect(AppHubLogic.failureKey(code: "INSTALL_FAILED_OLDER_SDK") == "apphub.fail.olderSdk")
        #expect(AppHubLogic.failureKey(code: "INSTALL_FAILED_USER_RESTRICTED") == "apphub.fail.userRestricted")
        #expect(AppHubLogic.failureKey(code: "INSTALL_FAILED_VERIFICATION_FAILURE") == "apphub.fail.verification")
        #expect(AppHubLogic.failureKey(code: "INSTALL_FAILED_INSUFFICIENT_STORAGE") == "apphub.fail.insufficientStorage")
        #expect(AppHubLogic.failureKey(code: "INSTALL_FAILED_NO_MATCHING_ABIS") == "apphub.fail.noMatchingAbis")
        #expect(AppHubLogic.failureKey(code: "INSTALL_FAILED_TEST_ONLY") == "apphub.fail.testOnly")
        #expect(AppHubLogic.failureKey(code: "INSTALL_PARSE_FAILED_NOT_APK") == "apphub.fail.invalidApk")
        #expect(AppHubLogic.failureKey(code: "INSTALL_PARSE_FAILED_NO_CERTIFICATES") == "apphub.fail.noCertificates")
        #expect(AppHubLogic.failureKey(code: "INSTALL_FAILED_ALREADY_EXISTS") == "apphub.fail.alreadyExists")
        #expect(AppHubLogic.failureKey(code: "INSTALL_FAILED_SOMETHING_NEW") == "apphub.fail.unknown")
    }

    @Test func uninstallFailureKeyMapping() {
        #expect(AppHubLogic.uninstallFailureKey(code: nil) == "apphub.fail.uninstall")
        #expect(AppHubLogic.uninstallFailureKey(code: "DELETE_FAILED_DEVICE_POLICY_MANAGER") == "apphub.fail.devicePolicy")
        #expect(AppHubLogic.uninstallFailureKey(code: "DELETE_FAILED_USER_RESTRICTED") == "apphub.fail.deleteRestricted")
        #expect(AppHubLogic.uninstallFailureKey(code: "DELETE_FAILED_INTERNAL_ERROR") == "apphub.fail.uninstall")
    }

    // MARK: - 버전 검증

    @Test func versionNameFromDumpsys() {
        let dumpsys = """
        Packages:
          Package [com.example.app] (a1b2c3):
            userId=10123
            versionCode=42 minSdk=26 targetSdk=34
            versionName=2.5.1
            firstInstallTime=2026-10-01 10:00:00
        """
        #expect(AppHubLogic.versionName(fromDumpsys: dumpsys) == "2.5.1")
        #expect(AppHubLogic.versionName(fromDumpsys: "versionName=") == nil)
        #expect(AppHubLogic.versionName(fromDumpsys: "") == nil)
    }

    @Test func parsePackageVersionCodes() {
        let text = """
        package:com.example.a versionCode:10
        package:com.example.b versionCode:200
        package:com.example.c
        noise
        """
        let map = AppHubLogic.parsePackageVersionCodes(text)
        #expect(map == ["com.example.a": Int64(10), "com.example.b": Int64(200), "com.example.c": Int64(0)])
        #expect(AppHubLogic.parsePackageVersionCodes("") == [:])
    }

    /// 설치 전 스냅샷이 비면 **전부 변경**으로 둔갑한다 — 그 경우 아무것도 보고하지 않는다
    @Test func changedPackagesEmptyBeforeIsUnknown() {
        let after: [String: Int64] = ["com.example.a": 10, "com.example.b": 20]
        #expect(AppHubLogic.changedPackages(before: [:], after: after) == [])
    }

    @Test func changedPackagesDetectsNewAndUpdated() {
        let before: [String: Int64] = ["com.example.a": 10, "com.example.b": 20]
        let after: [String: Int64] = ["com.example.a": 10, "com.example.b": 21, "com.example.c": 1]
        #expect(AppHubLogic.changedPackages(before: before, after: after) == ["com.example.b", "com.example.c"])
        #expect(AppHubLogic.changedPackages(before: before, after: before) == [])
    }

    // MARK: - 설치 단계 문구

    /// 설치 배너가 읽는 단계 키 — 하나라도 빠지면 화면에 `apphub.install.phase.*` 원문이 뜬다.
    /// (2026-11-05: 단일 APK 가 "기기 준비 중…"에 멈춰 보이던 문제로 단계를 나눴다)
    @Test func installPhaseKeysResolve() {
        let keys = [
            "apphub.install.phase.preparing",
            "apphub.install.phase.device.one",
            "apphub.install.phase.install",
            "apphub.install.phase.verify"
        ]
        for key in keys {
            let text = L10n.string(key)
            #expect(!text.isEmpty, "단계 문구가 비었다: \(key)")
            #expect(text != key, "번역 키가 그대로 노출된다: \(key)")
        }
    }

    // MARK: - 파일 메타데이터

    @Test func digestMatchesKnownSha256() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("relay-digest-\(UUID().uuidString).bin")
        try Data("abc".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(FileDigest.sizeBytes(path: url.path) == 3)
        #expect(FileDigest.sha256Hex(path: url.path)
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(FileDigest.sha256Hex(path: "/nonexistent/relay.apk") == nil)
    }
}
