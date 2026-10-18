import Foundation

/// 폰 찾기 순수 로직 — adb 인자 조립·값 검증 (테스트 대상)
///
/// **실측 근거**(`docs/plans/PLAN_find_phone_relayconsole.md`): adb 표준 표면으로는
/// 지속 벨소리·진동·손전등이 **불가**했고(`cmd vibrator`·`cmd flashlight` 부재, 오디오 재생 핸들러 없음),
/// 실제로 되는 것만 채택했다 — ① 화면 깨우기 ② 최대 밝기 ③ 알림음(시스템 알림음 채널).
/// 무음 모드에서는 소리가 나지 않는다(adb 로 ringer mode 전환이 불가 — 실측).
///
/// 화면 밝기는 **원래 값으로 되돌린다** — 찾은 뒤 폰이 최대 밝기·수동 모드로 남으면 부작용이 된다.
enum FindPhoneLogic {
    /// `input keyevent 224` = KEYCODE_WAKEUP — 화면만 켠다(잠금은 풀지 않는다)
    static let wakeKeycode = "224"
    static let brightnessMax = 255
    /// 알림 tag — 같은 tag 로 다시 게시하면 알림은 **한 건만** 남고 소리는 다시 난다
    static let defaultTag = "relay-find"
    /// 알림 반복 사이 간격(초) — 소리가 겹치지 않게
    static let repeatInterval: Double = 2.0
    /// 마지막 알림음이 끝난 뒤 밝기를 되돌리기 전 대기(초)
    static let restoreDelay: Double = 2.0

    // MARK: - 밝기 (읽기 → 적용 → 복원)

    static func brightnessModeReadArgs() -> [String] {
        ["shell", "settings", "get", "system", "screen_brightness_mode"]
    }

    static func brightnessReadArgs() -> [String] {
        ["shell", "settings", "get", "system", "screen_brightness"]
    }

    /// `settings get` 출력 → 정수. `null`·빈 값·범위 밖이면 **nil**(그 키는 복원하지 않는다)
    static func parseSetting(_ output: String) -> Int? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed), value >= 0, value <= brightnessMax else { return nil }
        return value
    }

    /// 밝기 값이 먹으려면 수동 모드여야 한다(자동 밝기가 덮어쓴다)
    static func brightnessModeArgs() -> [String] {
        ["shell", "settings", "put", "system", "screen_brightness_mode", "0"]
    }

    static func brightnessArgs(level: Int = brightnessMax) -> [String] {
        ["shell", "settings", "put", "system", "screen_brightness", String(clamp(level, 1, brightnessMax))]
    }

    static func wakeArgs() -> [String] {
        ["shell", "input", "keyevent", wakeKeycode]
    }

    /// 적용 순서 — 밝기 모드(수동) → 최대 밝기 → 깨우기
    static func applyArgs(level: Int = brightnessMax) -> [[String]] {
        [brightnessModeArgs(), brightnessArgs(level: level), wakeArgs()]
    }

    /// 복원 — **읽어 둔 값만** 되돌린다(읽기 실패·null 이면 건드리지 않는다)
    static func restoreArgs(mode: Int?, level: Int?) -> [[String]] {
        var out: [[String]] = []
        if let mode {
            out.append(["shell", "settings", "put", "system", "screen_brightness_mode", String(clamp(mode, 0, 1))])
        }
        if let level {
            out.append(["shell", "settings", "put", "system", "screen_brightness", String(clamp(level, 1, brightnessMax))])
        }
        return out
    }

    // MARK: - 알림 (소리)

    /// 알림 1건 게시 — Android 12+ `cmd notification post`(12·16 실측 통과).
    /// shell 이 만드는 채널(`shell_cmd`)은 중요도 DEFAULT + 시스템 알림음이라 소리가 난다.
    ///
    /// **인용 필수**: `adb shell` 은 인자를 **기기 셸에 문자열로 넘겨 다시 파싱**하므로
    /// 괄호·공백·`;` 같은 문자가 그대로 있으면 `sh: syntax error` 가 난다(실측).
    /// → 제목·본문은 단일 인용으로 감싼다(`safeTag` 는 영숫자·`-`·`_` 만이라 그대로).
    static func notifyArgs(tag: String = defaultTag, title: String, text: String) -> [String] {
        [
            "shell", "cmd", "notification", "post",
            "-t", shellQuoted(safe(title, fallback: "RelayConsole")),
            safeTag(tag),
            shellQuoted(safe(text, fallback: "RelayConsole")),
        ]
    }

    /// 기기 셸용 단일 인용 — 내부 `'` 는 `'\''` 로 이어 붙인다
    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// 알림 반복 — 같은 tag 라 알림은 한 건만 남고, 본문이 회차마다 달라 **다시 울린다**
    static func notifySteps(
        title: String,
        text: String,
        repeats: Int = 3,
        tag: String = defaultTag
    ) -> [[String]] {
        let count = clamp(repeats, 1, 5)
        var out: [[String]] = []
        for index in 1...count {
            let body = count > 1 ? "\(text) (\(index)/\(count))" : text
            out.append(notifyArgs(tag: tag, title: title, text: body))
        }
        return out
    }

    /// 알림 게시 단계인지 — 컨트롤러가 단계 사이에 간격을 두는 판정에 쓴다
    static func isNotificationStep(_ args: [String]) -> Bool {
        args.count > 3 && args[0] == "shell" && args[1] == "cmd" && args[2] == "notification"
    }

    static func clamp(_ value: Int, _ low: Int, _ high: Int) -> Int {
        min(max(value, low), high)
    }

    /// tag 는 영숫자·`-`·`_` 만 (adb 인자는 셸 인용이 없어 공백·특수문자를 넣지 않는다)
    static func safeTag(_ tag: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let filtered = tag.unicodeScalars
            .filter { allowed.contains($0) }
            .map(String.init)
            .joined()
        return filtered.isEmpty ? defaultTag : String(filtered.prefix(64))
    }

    /// 제어문자 제거 · 앞뒤 공백 제거 · 120자 제한 (알림 본문은 한 줄로 보낸다)
    static func safe(_ text: String, fallback: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars where !CharacterSet.controlCharacters.contains(scalar) {
            scalars.append(scalar)
        }
        let trimmed = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        return String(trimmed.prefix(120))
    }
}

/// 폰 찾기 컨트롤러 — adb IO (MainActor)
@MainActor
final class FindPhoneController: ObservableObject {
    static let shared = FindPhoneController()

    /// 진행 중인 시리얼 — 같은 기기 중복 탭을 막고 아이콘 상태를 바꾼다
    @Published private(set) var busySerials: Set<String> = []
    @Published var lastMessage: String?

    private init() {}

    func isBusy(_ serial: String) -> Bool {
        busySerials.contains(serial)
    }

    /// 화면 깨우기 + 최대 밝기 + 알림음 3회 → **밝기 원복** (실측으로 검증된 표면만)
    func find(serial: String, repeats: Int = 3) {
        guard !serial.isEmpty, !busySerials.contains(serial) else { return }
        guard let adb = DeviceMonitor.adbPathNow() else {
            lastMessage = ErrorCode.adbBinaryMissing.koMessage
            return
        }
        let title = L10n.string("findphone.notify.title")
        let text = L10n.string("findphone.notify.text")
        let steps = FindPhoneLogic.notifySteps(title: title, text: text, repeats: repeats)
        busySerials.insert(serial)
        lastMessage = nil

        Task.detached(priority: .userInitiated) {
            let run: ([String]) -> String? = { args in
                Self.run(adb: adb, args: ["-s", serial] + args)
            }
            // 1) 원래 밝기 기억 — 읽기 실패(null)면 그 키는 복원하지 않는다
            let modeBefore = run(FindPhoneLogic.brightnessModeReadArgs())
                .flatMap(FindPhoneLogic.parseSetting)
            let levelBefore = run(FindPhoneLogic.brightnessReadArgs())
                .flatMap(FindPhoneLogic.parseSetting)

            // 2) 화면 준비 + 깨우기
            var anySucceeded = false
            for step in FindPhoneLogic.applyArgs() where run(step) != nil {
                anySucceeded = true
            }

            // 3) 알림 반복 — 소리
            var sent = 0
            for step in steps {
                if sent > 0 {
                    try? await Task.sleep(
                        nanoseconds: UInt64(FindPhoneLogic.repeatInterval * 1_000_000_000)
                    )
                }
                sent += 1
                if run(step) != nil {
                    anySucceeded = true
                }
            }

            // 4) 밝기 원복 — 폰을 찾은 뒤 화면 설정이 남지 않게
            try? await Task.sleep(
                nanoseconds: UInt64(FindPhoneLogic.restoreDelay * 1_000_000_000)
            )
            for step in FindPhoneLogic.restoreArgs(mode: modeBefore, level: levelBefore) {
                _ = run(step)
            }

            await MainActor.run {
                self.busySerials.remove(serial)
                self.lastMessage = anySucceeded
                    ? L10n.string("findphone.status.sent")
                    : L10n.string("findphone.status.failed")
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
