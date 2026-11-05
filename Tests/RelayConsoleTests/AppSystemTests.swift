import Testing
@testable import RelayConsole

/// C 단계 — 다기기 설치 보조 로직·시스템 앱 안전장치·폴링 완화 (1.24.0)
struct AppSystemTests {
    // MARK: - 시스템 앱 adb 인자

    /// 시스템 앱 제거는 **사용자 0 에서만** — `-k` 없이 `--user 0`.
    /// `pm uninstall`(전체 제거)로 잘못 내려가면 시스템 파티션 APK 까지 지워져 복원할 수 없다.
    @Test func disableUserArgsAreScopedToUserZero() {
        #expect(AppHubLogic.disableUserArgs(package: "com.example.bloat") == [
            "shell", "pm", "uninstall", "--user", "0", "com.example.bloat"
        ])
    }

    /// 복원은 `cmd package install-existing --user 0` — 시스템 파티션의 APK 를 다시 활성화한다.
    @Test func restoreUserArgsUseInstallExisting() {
        #expect(AppHubLogic.restoreUserArgs(package: "com.example.bloat") == [
            "shell", "cmd", "package", "install-existing", "--user", "0", "com.example.bloat"
        ])
    }

    // MARK: - 복원 가능 목록

    /// `pm list packages -u -s` − 현재 설치됨 = 제거된 시스템 앱.
    /// - 제거된 것만 남고, 중복은 사라지고, 알파벳 순으로 정렬된다.
    @Test func removedSystemPackagesIsSetDifferenceSorted() {
        let removed = AppHubLogic.removedSystemPackages(
            allIncludingUninstalled: [
                "com.android.settings",
                "com.example.bloat",
                "com.example.bloat",
                "com.vendor.extra",
            ],
            installed: ["com.android.settings", "com.example.live"]
        )
        #expect(removed == ["com.example.bloat", "com.vendor.extra"])
    }

    @Test func removedSystemPackagesEmptyWhenNothingRemoved() {
        let all = ["com.android.settings", "com.example.app"]
        #expect(AppHubLogic.removedSystemPackages(allIncludingUninstalled: all, installed: all).isEmpty)
        #expect(AppHubLogic.removedSystemPackages(allIncludingUninstalled: [], installed: []).isEmpty)
    }

    // MARK: - 하드 블록

    /// 기기 핵심 구성요소 — 런처·시스템 UI·설정·설치 관리자·GMS 는 절대 막는다.
    @Test func blockedSystemPackagesCoverCoreComponents() {
        for pkg in [
            "android",
            "com.android.systemui",
            "com.android.settings",
            "com.android.packageinstaller",
            "com.google.android.packageinstaller",
            "com.google.android.gms",
            "com.android.vending",
            "com.android.launcher3",
        ] {
            #expect(AppHubLogic.isBlockedSystemPackage(pkg), "핵심 구성요소가 차단되지 않았다: \(pkg)")
        }
    }

    /// 제조사 런처·시스템 UI 변형은 접두사로 막는다 (이름이 기기마다 다르다).
    @Test func blockedSystemPrefixesCatchVendorVariants() {
        for pkg in [
            "com.sec.android.app.launcher",
            "com.miui.home",
            "com.google.android.apps.nexuslauncher",
            "com.oneplus.launcher",
            "com.oppo.launcher",
            "com.vivo.launcher",
            "com.android.systemui.plugin",
        ] {
            #expect(AppHubLogic.isBlockedSystemPackage(pkg), "접두사 차단 실패: \(pkg)")
        }
    }

    /// 일반 시스템 앱은 막지 않는다 — 2단계 확인만 거치면 비활성화할 수 있어야 한다.
    @Test func ordinarySystemAppsAreNotBlocked() {
        for pkg in [
            "com.example.bloat",
            "com.android.chrome",
            "com.google.android.youtube",
            "com.samsung.android.app.notes",
        ] {
            #expect(!AppHubLogic.isBlockedSystemPackage(pkg), "일반 시스템 앱이 차단됐다: \(pkg)")
        }
    }

    /// 대소문자·공백 방어 — 패키지명은 소문자지만 입력 경로가 하나가 아니다.
    @Test func blockedCheckIsCaseInsensitiveAndTrims() {
        #expect(AppHubLogic.isBlockedSystemPackage("  COM.ANDROID.SYSTEMUI \n"))
        #expect(AppHubLogic.isBlockedSystemPackage("COM.GOOGLE.ANDROID.GMS"))
    }

    /// 빈 값은 차단 — 패키지명 없는 액션이 adb 로 내려가지 않게.
    @Test func emptyPackageIsBlocked() {
        #expect(AppHubLogic.isBlockedSystemPackage(""))
        #expect(AppHubLogic.isBlockedSystemPackage("   "))
    }

    // MARK: - 폴링 완화

    /// 설치·백업 중에는 fast 만 — slow·sixty(무거운 덤프)는 건너뛴다.
    @Test func reducedPollingKeepsOnlyFastCommands() {
        for tick in [0, 1, 2, 3, 11, 12, 13, 24] {
            #expect(PollBatch.cmds(tickCount: tick, reduced: true) == PollBatch.fast)
        }
    }

    /// 완화 중에도 fast 는 그대로다 — 연결·배터리 감지가 끊기지 않는다.
    @Test func reducedPollingRetainsBatteryAndThermal() {
        let cmds = PollBatch.cmds(tickCount: 1, reduced: true)
        #expect(cmds.contains(.battery))
        #expect(cmds.contains(.thermal))
        #expect(cmds.contains(.loadavg))
        #expect(!cmds.contains(.meminfo))
        #expect(!cmds.contains(.activity))
    }

    /// 기본값(reduced: false)은 종전과 같다 — 회귀 방지.
    @Test func defaultPollingUnchanged() {
        #expect(PollBatch.cmds(tickCount: 0) == PollBatch.fast)
        #expect(PollBatch.cmds(tickCount: 4) == PollBatch.slow)
        #expect(PollBatch.cmds(tickCount: 13) == PollBatch.slow + PollBatch.sixty)
    }

    // MARK: - 다기기 모델

    /// 기기별 결과는 serial 기준으로 식별된다 — 같은 기기 결과가 두 번 쌓이지 않게.
    @Test func installResultIdentityIsSerial() {
        let result = DeviceInstallResult(
            serial: "R58M123ABC",
            label: "SM-G991N · R58M123ABC",
            ok: true,
            message: "설치 완료",
            packageName: "com.example.app",
            versionName: "1.2.3"
        )
        #expect(result.id == "R58M123ABC")
        #expect(result.ok)
        #expect(result.versionName == "1.2.3")
    }

    @Test func installTargetIdentityIsSerial() {
        let target = InstallTarget(serial: "10.0.0.5:5555", label: "10.0.0.5:5555")
        #expect(target.id == "10.0.0.5:5555")
    }
}
