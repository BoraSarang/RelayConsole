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

    @Test func forceStopAndUninstallArgs() {
        #expect(AppHubLogic.forceStopArgs(package: "com.x.y") == ["shell", "am", "force-stop", "com.x.y"])
        #expect(AppHubLogic.uninstallArgs(package: "com.x.y") == ["shell", "pm", "uninstall", "-k", "com.x.y"])
    }
}
