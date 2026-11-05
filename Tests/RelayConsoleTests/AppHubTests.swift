import Testing
@testable import RelayConsole

struct AppHubTests {
    // MARK: - parsePackages

    @Test func parsePackagesStripsPrefixAndKeepsOrder() {
        let text = """
        package:com.example.a
        package:com.example.b
        package:com.example.a
        package:org.other.c
        """
        #expect(AppHubLogic.parsePackages(text) == ["com.example.a", "com.example.b", "org.other.c"])
    }

    @Test func parsePackagesIgnoresEmptyAndNoise() {
        let text = """

        package:
        garbage line
        package:ok.pkg
        """
        #expect(AppHubLogic.parsePackages(text) == ["ok.pkg"])
    }

    @Test func parsePackagesEmptyInput() {
        #expect(AppHubLogic.parsePackages("") == [])
        #expect(AppHubLogic.parsePackages("\n\n") == [])
    }

    /// 2026-10-24 회귀 — `--show-versioncode` 를 붙이면 `package:com.foo versionCode:28`.
    /// 접미사를 자르지 않으면 패키지명이 `"com.foo versionCode:28"` 이 되어
    /// 아이콘 조회(`pm path`)·실행·삭제가 **전부** 실패한다.
    @Test func parsePackagesStripsVersionCodeSuffix() {
        let text = """
        package:com.example.a versionCode:28
        package:com.example.b versionCode:336015805
        package:com.example.a versionCode:28
        package:org.plain
        """
        #expect(AppHubLogic.parsePackages(text) == ["com.example.a", "com.example.b", "org.plain"])
    }

    /// 목록 이름과 versionCode 맵의 키가 **같은 문자열**이어야 아이콘 캐시·백업 메타가 맞는다.
    @Test func parsePackagesAlignsWithVersionCodeMap() {
        let text = "package:com.example.a versionCode:28"
        let names = AppHubLogic.parsePackages(text)
        let codes = AppHubLogic.parsePackageVersionCodes(text)
        #expect(names == ["com.example.a"])
        #expect(codes[names[0]] == 28)
    }

    // MARK: - isValidPackage

    @Test func isValidPackageAcceptsTypicalIds() {
        #expect(AppHubLogic.isValidPackage("com.example.app"))
        #expect(AppHubLogic.isValidPackage("org.mozilla.firefox"))
        #expect(AppHubLogic.isValidPackage("a.b"))
    }

    @Test func isValidPackageRejectsBadIds() {
        #expect(!AppHubLogic.isValidPackage(""))
        #expect(!AppHubLogic.isValidPackage("nodots"))
        #expect(!AppHubLogic.isValidPackage(".leading"))
        #expect(!AppHubLogic.isValidPackage("trailing."))
        #expect(!AppHubLogic.isValidPackage("has space.com"))
        #expect(!AppHubLogic.isValidPackage("evil;rm.com"))
        #expect(!AppHubLogic.isValidPackage("a/b.c"))
    }

    // MARK: - filter / sort

    @Test func filterIsCaseInsensitiveSubstring() {
        let pkgs = ["com.Example.App", "org.other.tool", "net.foo.bar"]
        #expect(AppHubLogic.filter(pkgs, query: "example") == ["com.Example.App"])
        #expect(AppHubLogic.filter(pkgs, query: "  ORG  ") == ["org.other.tool"])
        #expect(AppHubLogic.filter(pkgs, query: "").count == 3)
        #expect(AppHubLogic.filter(pkgs, query: "zzz") == [])
    }

    @Test func sortIsAlphabetical() {
        let pkgs = ["z.app", "A.app", "m.app"]
        #expect(AppHubLogic.sort(pkgs) == ["A.app", "m.app", "z.app"])
    }

    // MARK: - args

    @Test func listArgsThirdPartyByDefault() {
        #expect(AppHubLogic.listArgs(includeSystem: false) == ["shell", "pm", "list", "packages", "-3"])
        #expect(AppHubLogic.listArgs(includeSystem: true) == ["shell", "pm", "list", "packages"])
    }

    @Test func launchArgsShape() {
        #expect(AppHubLogic.launchArgs(package: "com.x.y") == [
            "shell", "monkey", "-p", "com.x.y", "-c", "android.intent.category.LAUNCHER", "1"
        ])
    }

    @Test func forceStopArgsShape() {
        #expect(AppHubLogic.forceStopArgs(package: "com.x.y") == ["shell", "am", "force-stop", "com.x.y"])
    }

    /// 2026-10-24 의미 교정 — 기본은 **앱+데이터 완전 삭제**(`-k` 없음).
    /// `-k`(데이터 유지)는 사용자가 명시적으로 고를 때만 붙는다.
    @Test func uninstallArgsDefaultIsFullRemoval() {
        #expect(AppHubLogic.uninstallArgs(package: "com.x.y") == ["shell", "pm", "uninstall", "com.x.y"])
        #expect(AppHubLogic.uninstallArgs(package: "com.x.y", keepData: false) == ["shell", "pm", "uninstall", "com.x.y"])
        #expect(AppHubLogic.uninstallArgs(package: "com.x.y", keepData: true) == ["shell", "pm", "uninstall", "-k", "com.x.y"])
    }
}
