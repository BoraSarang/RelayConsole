import Foundation
import Testing
@testable import RelayConsole

/// scrcpy 미러링 인자 조립 — 설정값이 실제 실행 인자에 반영되는지 고정
/// 순수 static 함수만 호출하므로 UserDefaults·싱글턴을 건드리지 않는다.
struct ScrcpyMirrorArgsTests {
    private let serial = "10.0.0.1:5555"

    @Test func defaultsMatchLegacyOptsPlusAppBackground() {
        // 종전 고정 9종과 동일 순서·동일 값 + 새 기본값(창 여백색 통일)만 추가된다
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
            "--background-color=#1c1f2a",
        ])
    }

    @Test func legacyParityWhenNewOptionsOff() {
        // 새 옵션을 모두 끄면 종전과 정확히 같은 인자 — 하위 호환 계약
        let args = ScrcpyController.mirrorArgs(serial: serial, noControl: false, backgroundMatch: false)
        #expect(args == [
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

    @Test func hwdecOnlyAcceptsAllowedValues() {
        // 허용 값만 통과 — 잘못된 값은 scrcpy 를 깨뜨리지 않도록 생략한다
        #expect(ScrcpyController.mirrorArgs(serial: serial, noControl: false, hwdec: "disabled")
            .contains("--hwdec=disabled"))
        #expect(ScrcpyController.mirrorArgs(serial: serial, noControl: false, hwdec: "videotoolbox")
            .contains("--hwdec=videotoolbox"))
        #expect(!ScrcpyController.mirrorArgs(serial: serial, noControl: false, hwdec: "auto")
            .contains(where: { $0.hasPrefix("--hwdec=") }))
        #expect(!ScrcpyController.mirrorArgs(serial: serial, noControl: false, hwdec: "gpu-nonsense")
            .contains(where: { $0.hasPrefix("--hwdec=") }))
    }

    @Test func videoCodecOnlyAcceptsAllowedValues() {
        #expect(ScrcpyController.mirrorArgs(serial: serial, noControl: false, videoCodec: "h265")
            .contains("--video-codec=h265"))
        #expect(!ScrcpyController.mirrorArgs(serial: serial, noControl: false, videoCodec: "h264")
            .contains(where: { $0.hasPrefix("--video-codec=") }))
        #expect(!ScrcpyController.mirrorArgs(serial: serial, noControl: false, videoCodec: "mpeg2")
            .contains(where: { $0.hasPrefix("--video-codec=") }))
    }

    @Test func videoBufferRequiresDigits() {
        #expect(ScrcpyController.mirrorArgs(serial: serial, noControl: false, videoBuffer: " 50 ")
            .contains("--video-buffer=50"))
        #expect(!ScrcpyController.mirrorArgs(serial: serial, noControl: false, videoBuffer: "50ms")
            .contains(where: { $0.hasPrefix("--video-buffer=") }))
        #expect(!ScrcpyController.mirrorArgs(serial: serial, noControl: false, videoBuffer: "-50")
            .contains(where: { $0.hasPrefix("--video-buffer=") }))
    }

    @Test func newFlagsAreEmitted() {
        let args = ScrcpyController.mirrorArgs(
            serial: serial, noControl: false,
            disableScreensaver: true, windowTitle: "192.168.86.30:5555",
            alwaysOnTop: true, backgroundMatch: false, powerOffOnClose: true)
        #expect(args.contains("--disable-screensaver"))
        #expect(args.contains("--window-title=192.168.86.30:5555"))
        #expect(args.contains("--always-on-top"))
        #expect(args.contains("--power-off-on-close"))
        #expect(!args.contains(where: { $0.hasPrefix("--background-color=") }))
    }

    @Test func blankWindowTitleIsOmitted() {
        let args = ScrcpyController.mirrorArgs(serial: serial, noControl: false, windowTitle: "   ")
        #expect(!args.contains(where: { $0.hasPrefix("--window-title=") }))
    }

    @Test func noControlAppendedAfterDefaults() {
        let args = ScrcpyController.mirrorArgs(serial: serial, noControl: true)
        #expect(args.last == "--no-control")
    }

    @Test func disabledFlagsAreOmitted() {
        let args = ScrcpyController.mirrorArgs(
            serial: serial, noControl: false,
            showTouches: false, stayAwake: false,
            legacyPaste: false, turnScreenOff: false, backgroundMatch: false)
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
