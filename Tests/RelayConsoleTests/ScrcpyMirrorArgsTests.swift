import Foundation
import Testing
@testable import RelayConsole

/// scrcpy 미러링 인자 조립 — 설정값이 실제 실행 인자에 반영되는지 고정
/// 순수 static 함수만 호출하므로 UserDefaults·싱글턴을 건드리지 않는다.
struct ScrcpyMirrorArgsTests {
    private let serial = "10.0.0.1:5555"

    @Test func defaultsMatchLegacyEightOpts() {
        // 종전 코드 고정 8종과 동일 순서·동일 값이어야 한다
        #expect(ScrcpyController.mirrorArgs(serial: serial, noControl: false) == [
            "-s", serial,
            "--show-touches",
            "--stay-awake",
            "--legacy-paste",
            "--max-size=1024",
            "--video-bit-rate=2M",
            "--max-fps=30",
            "--screen-off-timeout=3600",
            "--turn-screen-off",
        ])
    }

    @Test func noControlAppendedAfterDefaults() {
        let args = ScrcpyController.mirrorArgs(serial: serial, noControl: true)
        #expect(args.last == "--no-control")
    }

    @Test func disabledFlagsAreOmitted() {
        let args = ScrcpyController.mirrorArgs(
            serial: serial, noControl: false,
            showTouches: false, stayAwake: false,
            legacyPaste: false, turnScreenOff: false)
        #expect(args == ["-s", serial,
                         "--max-size=1024",
                         "--video-bit-rate=2M",
                         "--max-fps=30",
                         "--screen-off-timeout=3600"])
    }

    @Test func emptyValueOmitsThatOpt() {
        // 비우면 scrcpy 기본값에 맡긴다 — 빈 `--max-size=` 을 넘기지 않는다
        let args = ScrcpyController.mirrorArgs(serial: serial, noControl: false, maxSize: "  ")
        #expect(!args.contains(where: { $0.hasPrefix("--max-size=") }))
        #expect(args.contains("--video-bit-rate=2M"))
    }

    @Test func customValuesAreReflected() {
        let args = ScrcpyController.mirrorArgs(
            serial: serial, noControl: false,
            maxSize: "800", videoBitRate: "1M", maxFps: "15",
            screenOffTimeout: "600", customOpts: "--record=file.mp4")
        #expect(args.contains("--max-size=800"))
        #expect(args.contains("--video-bit-rate=1M"))
        #expect(args.contains("--max-fps=15"))
        #expect(args.contains("--screen-off-timeout=600"))
        #expect(args.last == "--record=file.mp4")
    }
}
