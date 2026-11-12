import Foundation
import Combine

// MARK: - 순수 로직

/// 부팅 후 첫 연결 훅 — 판정만 담당 (IO 없음 · 테스트 고정)
///
/// ## 왜 `adb root`인가 — 그리고 무엇을 하지 않는가
/// `adb root`는 **5555를 열지 않는다.** adbd를 root로 재시작할 뿐이고, 그 순간
/// 전송이 한 번 끊긴다. 재부팅 뒤 `:5555`가 열리는 근거는 폰의
/// `persist.adb.tcp.port=5555`다. 이 훅은 그 위에서 ① root 승격 ② 웨이크락
/// ③ 끊긴 전송 재연결을 자동화한다. S22/A90 같은 `user` 빌드는 대상이 아니다.
enum PostBootHookLogic {
    static let enabledKey = "relay.postBootHook"
    static let wakeLockName = "relayconsole"
    static let wakeLockPath = "/sys/power/wake_lock"
    static let handledKeyPrefix = "relay.postBoot.boot."
    /// 실패 재시도 — 부팅당 최대 3회, 10분 간격
    static let retryCooldown: TimeInterval = 600
    static let maxAttempts = 3
    static let tcpPort = 5555
    /// adbd 재시작 뒤 재연결 상한
    static let reconnectTimeout: TimeInterval = 20
    /// 부팅 토큰 캐시 수명 — Mac이 잠든 사이 폰이 재부팅해도 새 boot_id를 다시 읽는다
    static let bootTokenCacheTTL: TimeInterval = 60
    /// 부팅 직후 Wi-Fi 국가 코드 갱신이 연결을 한 번 끊는다.
    /// 화면이 꺼져 있으면 자동 재연결이 지연되므로, 화면을 이 시간만큼 켜 둔다.
    static let settleDuration: TimeInterval = 90
    static let settleScreenTimeoutMS = 120_000
    static let screenOffKeyPrefix = "relay.postBoot.screenOff."
    static let screenOffAtKeyPrefix = "relay.postBoot.screenOffAt."
    /// 이 시간이 지난 복구 예약은 사용자가 그 사이 바꿨을 수 있으므로 복구하지 않는다
    static let screenOffRestoreWindow: TimeInterval = 600

    /// `adb root` 출력 판정 — adb는 실패해도 exit 0을 반환할 수 있다
    enum RootOutcome: Equatable, Sendable {
        case alreadyRoot
        case restarted
        case unsupported
        case unknown
    }

    static func rootOutcome(_ output: String) -> RootOutcome {
        let text = output.lowercased()
        if text.contains("cannot run as root") || text.contains("production build") {
            return .unsupported
        }
        if text.contains("already running as root") {
            return .alreadyRoot
        }
        if text.contains("restarting adbd as root") {
            return .restarted
        }
        return .unknown
    }

    /// root 가능 기기인가 — `ro.debuggable=1`(userdebug) 또는 이미 root인 adbd
    static func isRootCapable(debuggable: String?, uid: String?) -> Bool {
        if trimmed(uid) == "0" { return true }
        return trimmed(debuggable) == "1"
    }

    /// 이 부팅을 아직 처리하지 않았는가
    static func shouldHandle(enabled: Bool, bootToken: String?, handledToken: String?) -> Bool {
        guard enabled else { return false }
        let token = trimmed(bootToken)
        guard !token.isEmpty else { return false }
        return token != trimmed(handledToken)
    }

    /// 부팅 식별자 — `boot_id` 우선, `/proc/stat`의 `btime` 폴백
    ///
    /// `boot_id`는 부팅마다 새 UUID라 앱 재시작과 무관하게 "이번 부팅"을 구분한다.
    static func bootToken(bootID: String?, procStat: String?) -> String? {
        let id = trimmed(bootID)
        if !id.isEmpty {
            return "id:\(id)"
        }
        if let btime = parseBootTime(procStat) {
            return "btime:\(btime)"
        }
        return nil
    }

    /// `/proc/stat`의 `btime <epoch>` 파싱
    static func parseBootTime(_ procStat: String?) -> String? {
        guard let procStat else { return nil }
        for raw in procStat.split(separator: "\n") {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("btime ") else { continue }
            let value = String(line.dropFirst("btime ".count))
                .trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty, value.allSatisfy(\.isNumber) else { continue }
            return value
        }
        return nil
    }

    /// 물리 기기 고유값 — 빈 값·에러 문구는 nil (추측으로 채우지 않는다)
    static func validPhysicalId(_ raw: String?) -> String? {
        let value = trimmed(raw)
        guard !value.isEmpty, value.count <= 64,
              !value.contains("not found"),
              !value.lowercased().contains("error") else { return nil }
        return value
    }

    static func handledKey(physicalId: String) -> String {
        "\(handledKeyPrefix)\(physicalId)"
    }

    /// 부팅 토큰 캐시가 아직 믿을 만한가 — 같은 serial로 재부팅한 경우를 놓치지 않기 위함
    static func cacheIsFresh(
        cachedAt: Date?,
        now: Date,
        ttl: TimeInterval = bootTokenCacheTTL
    ) -> Bool {
        guard let cachedAt else { return false }
        return now.timeIntervalSince(cachedAt) < ttl
    }

    /// `persist.adb.tcp.port`가 5555가 아니면 1회 설정 대상
    static func needsPersistPort(_ raw: String?) -> Bool {
        trimmed(raw) != String(tcpPort)
    }

    // MARK: 부팅 직후 화면 유지 (Wi-Fi 재연결 창)

    /// `settings get system screen_off_timeout` 값 — -1(항상 켜짐) 또는 양수만 인정
    static func screenTimeoutMS(_ raw: String?) -> Int? {
        let text = trimmed(raw)
        guard let value = Int(text), value == -1 || value > 0 else { return nil }
        return value
    }

    /// 90초 창을 확보하되 사용자의 더 긴 설정은 줄이지 않는다
    static func temporaryScreenTimeoutMS(original: Int?) -> Int? {
        guard let original else { return nil }
        if original == -1 { return -1 }
        return max(original, settleScreenTimeoutMS)
    }

    static func screenOffKey(physicalId: String) -> String {
        "\(screenOffKeyPrefix)\(physicalId)"
    }

    static func screenOffAtKey(physicalId: String) -> String {
        "\(screenOffAtKeyPrefix)\(physicalId)"
    }

    /// 이전 실행이 중단됐을 때 복구해도 되는 예약인가
    static func screenOffRestoreIsFresh(savedAt: Date?, now: Date) -> Bool {
        guard let savedAt else { return false }
        return now.timeIntervalSince(savedAt) < screenOffRestoreWindow
    }

    /// `/sys/power/wake_lock` 내용에 우리 이름이 있는가
    static func isWakeLockHeld(_ raw: String?) -> Bool {
        guard let raw else { return false }
        return raw.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .map(String.init)
            .contains(wakeLockName)
    }

    static func wakeLockCommand() -> String {
        "echo \(wakeLockName) > \(wakeLockPath)"
    }

    /// 실패 재시도 허용 — 부팅당 3회, 10분 쿨다운
    static func retryAllowed(
        attempts: Int,
        lastAttemptAt: Date?,
        now: Date,
        cooldown: TimeInterval = retryCooldown
    ) -> Bool {
        if attempts <= 0 { return true }
        guard attempts < maxAttempts else { return false }
        guard let lastAttemptAt else { return true }
        return now.timeIntervalSince(lastAttemptAt) >= cooldown
    }

    /// mDNS 자동 연결 serial — 여기서 root를 재시작하면 새 포트를 다시 찾아야 하므로
    /// `:5555`/USB 전송이 처리한다.
    static func isMdnsSerial(_ serial: String) -> Bool {
        AdbClient.isMdnsSerial(serial)
    }

    private static func trimmed(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Controller (IO)

/// 부팅 후 첫 연결 훅 — 설정 토글 · 부팅당 1회 · 결과 표시
///
/// 호출은 `DeviceMonitor.resolveDevices()`가 매 틱 한다. 새 연결뿐 아니라
/// **연결 중인 모든 기기**를 넘기므로 미러링 보류·앱 재시작 후 첫 틱을 모두 커버한다.
@MainActor
final class PostBootHookController: ObservableObject {
    static let shared = PostBootHookController()

    @Published private(set) var lastMessage: String?
    @Published private(set) var lastMessageIsError = false

    private var inFlight: Set<String> = []
    private var bootTokenCache: [String: String] = [:]
    private var bootTokenCacheAt: [String: Date] = [:]
    private var physicalIdCache: [String: String] = [:]
    private var attempts: [String: Int] = [:]
    private var attemptBootToken: [String: String] = [:]
    private var lastAttemptAt: [String: Date] = [:]

    private init() {}

    /// 매 틱 호출 — 설정 OFF면 아무것도 하지 않는다.
    func consider(serials: [String]) {
        guard UserDefaults.standard.object(forKey: PostBootHookLogic.enabledKey) as? Bool ?? false else {
            return
        }
        for serial in serials.sorted(by: { preference($0) < preference($1) }) {
            guard !PostBootHookLogic.isMdnsSerial(serial) else { continue }
            guard !inFlight.contains(serial) else { continue }
            inFlight.insert(serial)
            Task { [weak self] in
                await self?.runIfNeeded(serial: serial)
                self?.inFlight.remove(serial)
            }
        }
    }

    /// 연결이 끊기면 부팅 토큰 캐시를 지운다 — 재부팅 뒤 새 boot_id를 다시 읽기 위함
    func forget(serial: String) {
        bootTokenCache.removeValue(forKey: serial)
        bootTokenCacheAt.removeValue(forKey: serial)
        physicalIdCache.removeValue(forKey: serial)
    }

    // MARK: 실행

    private func runIfNeeded(serial: String) async {
        guard UserDefaults.standard.object(forKey: PostBootHookLogic.enabledKey) as? Bool ?? false else {
            return
        }
        // adb root는 adbd를 재시작해 scrcpy를 죽인다 — 미러링이 끝날 때까지 보류
        guard !ScrcpyController.shared.isRunning(serial: serial) else { return }
        guard let adb = DeviceMonitor.adbPathNow() else {
            present(L10n.string("postboot.status.adbMissing"), isError: true)
            return
        }

        guard let token = await bootToken(serial: serial, adb: adb) else { return }
        let physicalId = await physicalId(serial: serial, adb: adb)
        let handledKey = PostBootHookLogic.handledKey(physicalId: physicalId)
        let handled = UserDefaults.standard.string(forKey: handledKey)
        guard PostBootHookLogic.shouldHandle(enabled: true, bootToken: token, handledToken: handled) else {
            return
        }

        // 새 부팅이면 재시도 횟수 초기화
        if attemptBootToken[physicalId] != token {
            attemptBootToken[physicalId] = token
            attempts[physicalId] = 0
        }
        let attempt = attempts[physicalId] ?? 0
        let now = Date()
        guard PostBootHookLogic.retryAllowed(
            attempts: attempt,
            lastAttemptAt: lastAttemptAt[physicalId],
            now: now
        ) else { return }

        attempts[physicalId] = attempt + 1
        lastAttemptAt[physicalId] = now

        let ident = ConsoleStore.shared.identLabel(for: serial)
        present(L10n.format("postboot.status.running", ident), isError: false)
        DebugLogger.shared.info("PostBoot", "[INFO] [FEATURE] 부팅 후 훅 시작 \(serial)")

        let debuggable = await shellText(adb, serial: serial, command: "getprop ro.debuggable")
        let uid = await shellText(adb, serial: serial, command: "id -u")
        guard PostBootHookLogic.isRootCapable(debuggable: debuggable, uid: uid) else {
            markHandled(handledKey: handledKey, token: token, physicalId: physicalId)
            present(L10n.format("postboot.status.skipped", ident), isError: false)
            DebugLogger.shared.info(
                "PostBoot",
                "[INFO] [POSTBOOT] root 불가 — \(serial) (debuggable=\(debuggable ?? "?") uid=\(uid ?? "?"))"
            )
            IssueLog.append(
                IssueLog.Entry(
                    kind: IssueLog.Kind.postBootHook,
                    detail: "건너뜀 — root 불가 (debuggable=\(debuggable ?? "?") uid=\(uid ?? "?"))",
                    serial: serial,
                    ok: true
                ),
                name: "device"
            )
            return
        }

        // adb root — 출력으로 성공 판정 (exit 0을 믿지 않는다)
        // persist 설정보다 **먼저** root가 되어야 한다 — userdebug의 기본 adbd(shell)는
        // persist 속성을 쓸 권한이 없다.
        let rootOut = await shellOutput(adb, serial: serial, command: nil, args: ["root"], timeout: 10)
        let rootText = "\(rootOut?.stdout ?? "")\n\(rootOut?.stderr ?? "")"
        let outcome = PostBootHookLogic.rootOutcome(rootText)
        if outcome == .unsupported {
            markHandled(handledKey: handledKey, token: token, physicalId: physicalId)
            present(L10n.format("postboot.status.skipped", ident), isError: false)
            DebugLogger.shared.info("PostBoot", "[INFO] [POSTBOOT] adb root 불가 — \(serial)")
            IssueLog.append(
                IssueLog.Entry(
                    kind: IssueLog.Kind.postBootHook,
                    detail: "건너뜀 — adb root 불가",
                    serial: serial,
                    ok: true
                ),
                name: "device"
            )
            return
        }

        let needsReconnect = outcome == .restarted || outcome == .unknown
        if needsReconnect {
            present(L10n.format("postboot.status.reconnecting", ident), isError: false)
            DebugLogger.shared.info("PostBoot", "[INFO] [POSTBOOT] adbd 재시작 — 재연결 대기 \(serial)")
            let ok = await waitForRoot(adb: adb, serial: serial)
            guard ok else {
                fail(
                    ident: ident,
                    serial: serial,
                    physicalId: physicalId,
                    handledKey: handledKey,
                    token: token,
                    message: L10n.format(
                        "postboot.status.failed",
                        ident,
                        L10n.string("postboot.error.reconnect")
                    ),
                    code: ErrorCode.adbRootFailed,
                    detail: "adbd 재시작 뒤 root 재연결 실패"
                )
                return
            }
        }

        // 5555 영속 — root가 된 뒤에 쓴다. 이미 5555면 건드리지 않는다.
        // 이 속성은 다음 부팅부터 adbd 리스닝 포트로 쓰인다.
        var persistNote = "유지"
        let persistBefore = await shellText(adb, serial: serial, command: "getprop persist.adb.tcp.port")
        if PostBootHookLogic.needsPersistPort(persistBefore) {
            let out = await shellOutput(
                adb,
                serial: serial,
                command: "setprop persist.adb.tcp.port \(PostBootHookLogic.tcpPort)"
            )
            if isFailure(out) {
                persistNote = "실패"
                DebugLogger.shared.warn(
                    "PostBoot",
                    "[WARN] \(ErrorCode.postBootPersistFailed.rawValue) 5555 영속 설정 실패 — \(cause(out))"
                )
            } else {
                persistNote = "5555 설정"
                DebugLogger.shared.info("PostBoot", "[INFO] [POSTBOOT] persist.adb.tcp.port=5555 설정")
            }
        }

        // 웨이크락 1회 — root adbd에서만 성공한다
        let wakeOut = await shellOutput(
            adb,
            serial: serial,
            command: PostBootHookLogic.wakeLockCommand(),
            timeout: 5
        )
        if isFailure(wakeOut) {
            fail(
                ident: ident,
                serial: serial,
                physicalId: physicalId,
                handledKey: handledKey,
                token: token,
                message: L10n.format(
                    "postboot.status.failed",
                    ident,
                    L10n.string("postboot.error.wakeLock")
                ),
                code: ErrorCode.wakeLockFailed,
                detail: "웨이크락 기록 실패 — \(cause(wakeOut))"
            )
            return
        }
        let held = await shellText(
            adb,
            serial: serial,
            command: "cat \(PostBootHookLogic.wakeLockPath)",
            timeout: 5
        )
        var wakeNote = "held"
        if !PostBootHookLogic.isWakeLockHeld(held) {
            // write는 성공했는데 cat이 비어 있는 커널도 있다 — 실패로 단정하지 않고 경고만
            wakeNote = "검증 공백"
            DebugLogger.shared.warn(
                "PostBoot",
                "[WARN] [POSTBOOT] 웨이크락 기록 후 검증 공백 — \(serial)"
            )
        }

        // 부팅 직후 Wi-Fi 국가 코드 갱신이 연결을 한 번 끊는다. 화면이 꺼져 있으면
        // Android가 자동 재연결을 미루므로, 화면을 90초 켜 둬 재연결 창을 만든다.
        let settleNote = await settleAfterBoot(
            adb: adb,
            serial: serial,
            physicalId: physicalId,
            ident: ident
        )

        markHandled(handledKey: handledKey, token: token, physicalId: physicalId)
        if persistNote == "실패" {
            present(
                L10n.format("postboot.status.donePersistFailed", ident, L10n.string("postboot.error.persist")),
                isError: true
            )
        } else {
            present(L10n.format("postboot.status.done", ident), isError: false)
        }
        DebugLogger.shared.info(
            "PostBoot",
            "[INFO] [POSTBOOT] 완료 — \(serial) root=\(outcome) persist=\(persistNote) wake=\(wakeNote) settle=\(settleNote)"
        )
        IssueLog.append(
            IssueLog.Entry(
                kind: IssueLog.Kind.postBootHook,
                detail: "root=\(outcome) · persist=\(persistNote) · wake=\(wakeNote) · settle=\(settleNote)",
                serial: serial,
                ok: persistNote != "실패"
            ),
            name: "device"
        )
    }

    // MARK: adb helpers

    /// 부팅 토큰 — serial별 1회만 읽는다 (재부팅은 `forget`이 캐시를 지운다)
    private func bootToken(serial: String, adb: String) async -> String? {
        if let cached = bootTokenCache[serial],
           PostBootHookLogic.cacheIsFresh(cachedAt: bootTokenCacheAt[serial], now: Date()) {
            return cached
        }
        let idOut = await shellOutput(
            adb,
            serial: serial,
            command: "cat /proc/sys/kernel/random/boot_id",
            timeout: 5
        )
        var token = PostBootHookLogic.bootToken(
            bootID: idOut?.exitCode == 0 ? idOut?.stdout : nil,
            procStat: nil
        )
        if token == nil {
            let statOut = await shellOutput(adb, serial: serial, command: "cat /proc/stat", timeout: 5)
            token = PostBootHookLogic.bootToken(
                bootID: nil,
                procStat: statOut?.exitCode == 0 ? statOut?.stdout : nil
            )
        }
        if let token {
            bootTokenCache[serial] = token
            bootTokenCacheAt[serial] = Date()
        }
        return token
    }

    /// 물리 ID — 실패하면 serial 폴백 (같은 폰의 IP 변경에도 같은 토큰 키를 쓰기 위함)
    private func physicalId(serial: String, adb: String) async -> String {
        if let cached = physicalIdCache[serial] { return cached }
        let raw = await shellText(adb, serial: serial, command: "getprop ro.boot.serialno")
        guard let id = PostBootHookLogic.validPhysicalId(raw) else { return serial }
        physicalIdCache[serial] = id
        return id
    }

    /// adbd 재시작 뒤 root 확인 — `id -u == 0`이 될 때까지 폴링
    ///
    /// 네트워크 전송은 `adb root`가 TCP 연결을 닫으므로 disconnect/connect로 다시 잇는다.
    /// USB는 adb 서버가 재열거를 처리하므로 get-state/id만 본다.
    private func waitForRoot(adb: String, serial: String) async -> Bool {
        let isNetwork = serial.contains(":")
        let deadline = Date().addingTimeInterval(PostBootHookLogic.reconnectTimeout)
        var attempt = 0
        while Date() < deadline {
            attempt += 1
            if let out = await shellOutput(adb, serial: serial, command: "id -u", timeout: 3),
               out.exitCode == 0,
               out.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "0" {
                return true
            }
            // 2초마다 한 번만 connect를 시도한다 — 무의미한 connect 폭주 방지
            if isNetwork, attempt % 4 == 1 {
                _ = await shellOutput(adb, serial: serial, command: nil, args: ["disconnect", serial], timeout: 3)
                _ = await shellOutput(adb, serial: serial, command: nil, args: ["connect", serial], timeout: 5)
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return false
    }

    /// 부팅 직후 화면 유지 — Wi-Fi 국가 코드 갱신 뒤 자동 재연결 창
    ///
    /// `settings put system screen_off_timeout`으로 90초 창을 만들고 원래 값으로 복구한다.
    /// 앱이 중단되면 UserDefaults 예약을 다음 실행에서 복구한다(10분 이내만).
    private func settleAfterBoot(
        adb: String,
        serial: String,
        physicalId: String,
        ident: String
    ) async -> String {
        await restorePendingScreenTimeout(adb: adb, serial: serial, physicalId: physicalId)

        let originalRaw = await shellText(
            adb,
            serial: serial,
            command: "settings get system screen_off_timeout"
        )
        guard let original = PostBootHookLogic.screenTimeoutMS(originalRaw),
              let temporary = PostBootHookLogic.temporaryScreenTimeoutMS(original: original) else {
            DebugLogger.shared.warn(
                "PostBoot",
                "[WARN] [POSTBOOT] 화면 꺼짐 시간 확인 실패 — 화면 유지 생략 \(serial)"
            )
            return "건너뜀"
        }

        if temporary != original {
            UserDefaults.standard.set(
                original,
                forKey: PostBootHookLogic.screenOffKey(physicalId: physicalId)
            )
            UserDefaults.standard.set(
                Date(),
                forKey: PostBootHookLogic.screenOffAtKey(physicalId: physicalId)
            )
            let out = await shellOutput(
                adb,
                serial: serial,
                command: "settings put system screen_off_timeout \(temporary)",
                timeout: 5
            )
            if isFailure(out) {
                DebugLogger.shared.warn(
                    "PostBoot",
                    "[WARN] [POSTBOOT] 화면 꺼짐 시간 변경 실패 — \(cause(out))"
                )
                UserDefaults.standard.removeObject(
                    forKey: PostBootHookLogic.screenOffKey(physicalId: physicalId)
                )
                UserDefaults.standard.removeObject(
                    forKey: PostBootHookLogic.screenOffAtKey(physicalId: physicalId)
                )
                return "건너뜀"
            }
        }

        // 화면이 꺼져 있으면 깨운다 — 국가 코드 갱신이 화면 꺼짐과 겹치지 않게
        _ = await shellOutput(adb, serial: serial, command: "input keyevent 224", timeout: 5)
        present(L10n.format("postboot.status.settling", ident), isError: false)
        DebugLogger.shared.info(
            "PostBoot",
            "[INFO] [POSTBOOT] 화면 유지 \(Int(PostBootHookLogic.settleDuration))초 — Wi-Fi 재연결 대기 \(serial)"
        )
        try? await Task.sleep(for: .seconds(PostBootHookLogic.settleDuration))
        await restorePendingScreenTimeout(adb: adb, serial: serial, physicalId: physicalId)
        return "\(Int(PostBootHookLogic.settleDuration))초"
    }

    /// 화면 꺼짐 시간 복구 — 실패하면 예약을 남겨 다음 실행에서 다시 시도
    private func restorePendingScreenTimeout(
        adb: String,
        serial: String,
        physicalId: String
    ) async {
        let key = PostBootHookLogic.screenOffKey(physicalId: physicalId)
        let atKey = PostBootHookLogic.screenOffAtKey(physicalId: physicalId)
        guard UserDefaults.standard.object(forKey: key) != nil else {
            UserDefaults.standard.removeObject(forKey: atKey)
            return
        }
        let value = UserDefaults.standard.integer(forKey: key)
        let savedAt = UserDefaults.standard.object(forKey: atKey) as? Date
        guard PostBootHookLogic.screenOffRestoreIsFresh(savedAt: savedAt, now: Date()) else {
            UserDefaults.standard.removeObject(forKey: key)
            UserDefaults.standard.removeObject(forKey: atKey)
            return
        }
        let out = await shellOutput(
            adb,
            serial: serial,
            command: "settings put system screen_off_timeout \(value)",
            timeout: 5
        )
        if isFailure(out) {
            DebugLogger.shared.warn(
                "PostBoot",
                "[WARN] [POSTBOOT] 화면 꺼짐 시간 복구 실패 — 다음 실행에서 재시도 \(serial)"
            )
            return
        }
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: atKey)
    }

    /// `adb -s <serial> shell <command>` — 실패도 Output으로 받아 원인을 보존한다
    private func shellOutput(
        _ adb: String,
        serial: String,
        command: String?,
        args: [String] = [],
        timeout: TimeInterval = 8
    ) async -> ProcessRunner.Output? {
        let fullArgs = ["-s", serial] + (command.map { ["shell", $0] } ?? args)
        return try? await ProcessRunner.captureAsync(adb, fullArgs, timeout: timeout)
    }

    /// 성공한 shell의 stdout만 — 실패는 nil
    private func shellText(
        _ adb: String,
        serial: String,
        command: String,
        timeout: TimeInterval = 8
    ) async -> String? {
        guard let out = await shellOutput(adb, serial: serial, command: command, timeout: timeout),
              !isFailure(out) else { return nil }
        return out.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 실패 판정 — exit code + 실제 stderr 문구 (무음 실패 금지)
    private func isFailure(_ out: ProcessRunner.Output?) -> Bool {
        guard let out else { return true }
        if out.timedOut || out.exitCode != 0 { return true }
        let text = "\(out.stdout)\n\(out.stderr)".lowercased()
        for needle in ["permission denied", "no such file", "read-only file system",
                       "failed to set", "not allowed", "operation not permitted"] {
            if text.contains(needle) { return true }
        }
        return false
    }

    private func cause(_ out: ProcessRunner.Output?) -> String {
        guard let out else { return L10n.string("postboot.error.noResponse") }
        let text = "\(out.stdout)\n\(out.stderr)".trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? L10n.string("postboot.error.noResponse") : text
    }

    // MARK: 상태

    private func fail(
        ident: String,
        serial: String,
        physicalId: String,
        handledKey: String,
        token: String,
        message: String,
        code: ErrorCode,
        detail: String
    ) {
        let tried = attempts[physicalId] ?? 1
        if tried >= PostBootHookLogic.maxAttempts {
            markHandled(handledKey: handledKey, token: token, physicalId: physicalId)
        }
        present(message, isError: true)
        DebugLogger.shared.error("PostBoot", "[ERROR] \(code.rawValue) \(detail)")
        IssueLog.append(
            IssueLog.Entry(
                kind: IssueLog.Kind.postBootHook,
                detail: "\(code.rawValue) \(detail) (시도 \(tried)/\(PostBootHookLogic.maxAttempts))",
                serial: serial,
                ok: false
            ),
            name: "device"
        )
    }

    private func markHandled(handledKey: String, token: String, physicalId: String) {
        UserDefaults.standard.set(token, forKey: handledKey)
        attempts.removeValue(forKey: physicalId)
        lastAttemptAt.removeValue(forKey: physicalId)
    }

    private func present(_ message: String, isError: Bool) {
        lastMessage = message
        lastMessageIsError = isError
    }

    /// 같은 부팅에서 `:5555`/USB를 mDNS보다 먼저 고른다
    private func preference(_ serial: String) -> Int {
        if serial.contains(":") { return 0 }
        return PostBootHookLogic.isMdnsSerial(serial) ? 2 : 1
    }
}
