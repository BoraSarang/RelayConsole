import Foundation
import Combine
import SwiftUI
import UserNotifications

/// UI 유일 read 모델 — `devices`만 읽도록 강제 (PLAN P0-a)
@MainActor
final class ConsoleStore: ObservableObject {
    static let shared = ConsoleStore()

    @Published var inventory = DeviceInventory()
    /// 구조화 감시 이벤트 (PLAN_v0.5) — 심각도·fingerprint 보존, 팝오버 우선 표시용
    @Published private(set) var recentWatchEvents: [WatchEvent] = []

    /// 감시 이벤트 보관 상한 (EventStore.maxEvents 와 동일)
    nonisolated static let maxWatchEvents = 500
    @Published var lastError: String?
    /// serial → DroidMetrics 링 60점 (5s × 60 = 5분)
    @Published private(set) var metricsHistory: [String: DroidMetrics] = [:]
    /// 현재 선택 기기 (팝오버/대시보드 기준) — PLAN_v0.3
    @Published var selectedSerial: String?
    /// 위젯 딥링크가 요청한 콘솔 탭 — ConsoleView가 수신 후 nil로 회수 (PLAN_widget)
    @Published var pendingConsoleSection: ConsoleSection?
    /// Apple Phase1 — Trust-only 기기 목록·선택
    @Published private(set) var appleDevices: [AppleSnapshot] = []
    @Published var selectedAppleUdid: String?
    /// Apple 오류 배너 — E-MAC-APL 문구 (오프라인 육안용)
    @Published var appleLastError: String?

    private let selectedKey = "relay.selectedSerial"
    private let selectedAppleKey = "relay.selectedAppleUdid"
    private var started = false
    private var lastNetPushAt: [String: Date] = [:]
    /// fingerprint → 마지막 시스템 알림 시각 (2중 쿨다운: Gate + notify 5분)
    private var lastNotifiedAt: [String: Date] = [:]
    /// fingerprint → 마지막 incident 번들 캡처 (S4)
    private var incidentBundleLastAt: [String: Date] = [:]
    private let notifyCooldown: TimeInterval = 300
    private var notificationsRequested = false
    private var storeHealthTask: Task<Void, Never>?
    /// 감시 알림 토글 (relay.watch.*)
    @AppStorage("relay.watch.throttling") var watchThrottling = true
    @AppStorage("relay.watch.charge") var watchCharge = true
    @AppStorage("relay.watch.protection") var watchProtection = true
    @AppStorage("relay.watch.lowPower") var watchLowPower = true
    @AppStorage("relay.watch.battery") var watchBattery = true
    /// Phase2 A5 — PSI / load / MemAvailable
    @AppStorage("relay.watch.psi") var watchPsi = true
    @AppStorage("relay.watch.load") var watchLoad = true
    @AppStorage("relay.watch.memory") var watchMemory = true
    /// Phase v0.7 — Bsoh / RSRP / 복구 알림
    @AppStorage("relay.watch.bsoh") var watchBsoh = true
    @AppStorage("relay.watch.rsrp") var watchRsrp = true
    @AppStorage("relay.watch.recovery") var watchRecovery = true
    @AppStorage("relay.watch.notifications") var watchNotifications = true
    /// Phase v0.8 — ANR / 크래시 logcat
    @AppStorage("relay.watch.anr") var watchAnr = true
    @AppStorage("relay.watch.crash") var watchCrash = true
    /// 알림형 상단 배너 (메뉴 팝오버 아님) — 기본 ON
    @AppStorage("relay.watch.banner") var watchBanner = true
    /// 외부 알림 채널 (PLAN_notify_channels · relay.notify.*)
    @AppStorage("relay.notify.ntfy") var notifyNtfy = false
    @AppStorage("relay.notify.ntfy.server") var notifyNtfyServer = ""
    @AppStorage("relay.notify.ntfy.topic") var notifyNtfyTopic = ""
    @AppStorage("relay.notify.ntfy.token") var notifyNtfyToken = ""
    @AppStorage("relay.notify.slack") var notifySlack = false
    @AppStorage("relay.notify.slack.webhook") var notifySlackWebhook = ""
    /// `warning` | `critical`
    @AppStorage("relay.notify.minSeverity") var notifyMinSeverity = "warning"
    @AppStorage("relay.notify.recovery") var notifyRecovery = false
    /// 설정 → 연동 · 테스트 전송 결과 (nil = 미실행) — 성공/실패 원인을 UI에 노출 (AGENTS.local §4 [표시②])
    @Published var notifyTestResult: String?
    @Published var notifyTestIsError = false
    /// Phase v0.9 — 카드 On/Off (대시보드·팝오버 공통, 기본 전체 ON)
    @AppStorage("relay.cards.cpu") var cardCpu = true
    @AppStorage("relay.cards.gpu") var cardGpu = true
    @AppStorage("relay.cards.memory") var cardMemory = true
    @AppStorage("relay.cards.sensors") var cardSensors = true
    @AppStorage("relay.cards.battery") var cardBattery = true
    @AppStorage("relay.cards.network") var cardNetwork = true
    @AppStorage("relay.cards.thermal") var cardThermal = true
    @AppStorage("relay.cards.storage") var cardStorage = true
    /// S2 Device Health Score 카드
    @AppStorage("relay.cards.health") var cardHealth = true
    /// 아침 브리핑 한 줄 (PLAN_briefing · S1)
    @AppStorage("relay.briefing.enabled") var briefingEnabled = true
    /// 앱 언어 — "system"(기기 추종, 기본) | "ko" | "en". 바꾸면 전 화면이 다시 그려진다
    @AppStorage(L10n.languageKey) var appLanguage = "system"
    /// S4 Incident Bundle 자동 캡처
    @AppStorage("relay.incident.auto") var incidentAuto = true
    /// 인사이트·보관 (Phase1) — 30/60/90/0(무제한), 기본 30
    @AppStorage(InsightSettings.retentionKey) var retentionDays = InsightSettings.defaultRetentionDays
    /// 패턴 판정 임계값 (테스트기/안정기 전환용)
    @AppStorage(PatternThresholds.keys.repeatingDays) var patternRepeatingDays = PatternThresholds.default.repeatingDays
    @AppStorage(PatternThresholds.keys.repeatingCount) var patternRepeatingCount = PatternThresholds.default.repeatingCount
    @AppStorage(PatternThresholds.keys.resolvedQuietDays) var patternResolvedQuietDays = PatternThresholds.default.resolvedQuietDays
    @AppStorage(PatternThresholds.keys.dormantQuietDays) var patternDormantQuietDays = PatternThresholds.default.dormantQuietDays

    /// 보관 정리 대상 공통 스케줄
    private var retentionSweepTask: Task<Void, Never>?
    /// 메트릭 1분 롤업 디바운스 (serial → 마지막 수집 시각)
    private var lastDailyIngestAt: [String: Date] = [:]
    private let dailyIngestDebounce: TimeInterval = 60

    /// 카드 On/Off 조회 — DashboardLayout 표시 순서와 1:1 (대시보드·팝오버 공용)
    func cardEnabled(_ card: DashboardCard) -> Bool {
        switch card {
        case .cpu: return cardCpu
        case .gpu: return cardGpu
        case .memory: return cardMemory
        case .sensors: return cardSensors
        case .battery: return cardBattery
        case .network: return cardNetwork
        case .thermal: return cardThermal
        case .storage: return cardStorage
        case .health: return cardHealth
        }
    }

    private init() {
        selectedSerial = UserDefaults.standard.string(forKey: selectedKey)
        selectedAppleUdid = UserDefaults.standard.string(forKey: selectedAppleKey)
        // 기기 식별 라벨 해석기 주입 — WatchEngine 알림 detail이 인벤토리 기반으로 표시되도록 (AGENTS.local §4)
        let identResolver: @MainActor (String) -> String = { [weak self] serial in
            self?.identLabel(for: serial) ?? serial
        }
        WatchEngine.shared.ident = identResolver
        // EventStore 1차 — 앱 시작 시 이력 복원 (JSON 영구화)
        //
        // [표시②] 종전엔 로드 실패가 빈 배열로 조용히 대체됐다. 그 상태로 다음 저장이
        // 일어나면 **기존 데이터가 전부 덮어써져 복구 불가**가 된다.
        // 파일은 남겨 두고(백업) 실패 사실만 노출한다 — 파괴적 자동 복구는 하지 않는다.
        recentWatchEvents = EventStore.shared.load()
        if EventStore.shared.loadFailed {
            recordStoreProblem(.readFailed(ErrorCode.storeReadFailed))
        }
        diagnoses = DiagnoseStore.shared.diagnoses
        // Phase1 스토어 로드
        _ = ConnectionSessionStore.shared
        _ = DeviceDailyStore.shared
        // 기존 메모리 이력으로 일자 롤업 보강 + retention 정리
        migrateDailyFromMemory()
        pruneAllStores()
        startRetentionSweep()
    }

    // MARK: - Phase1 인사이트 스토어

    private func migrateDailyFromMemory() {
        // 메모리 ring에만 있던 값을 첫 실행 때 일자 bucket으로 승격
        for (serial, metrics) in metricsHistory {
            guard !metrics.cpuHistory.isEmpty else { continue }
            let sample = DeviceDailySample(
                cpu: metrics.cpuHistory.last,
                temp: metrics.tempHistory.last,
                batteryLevel: metrics.levelHistory.last.map(Int.init),
                gpu: metrics.gpuHistory.last,
                at: .now
            )
            DeviceDailyStore.shared.ingest(serial: serial, sample: sample, forceFlush: true)
        }
    }

    /// retention 변경/시작 시 정리
    func pruneAllStores(now: Date = .now) {
        let days = retentionDays
        DeviceDailyStore.shared.prune(retentionDays: days, now: now)
        ConnectionSessionStore.shared.prune(retentionDays: days, now: now)
        pruneEventStoreRetention(days: now, retentionDays: days)
    }

    /// WatchEvent 보관 — retention 경과분 제거 (EventStore 저장 경로와 동일 500 cap 유지)
    private func pruneEventStoreRetention(days now: Date, retentionDays: Int) {
        guard retentionDays > 0 else { return }
        guard let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -retentionDays,
            to: Calendar.current.startOfDay(for: now)
        ) else { return }
        let before = recentWatchEvents.count
        recentWatchEvents.removeAll { $0.at < cutoff }
        if recentWatchEvents.count != before {
            EventStore.shared.save(recentWatchEvents)
        }
    }

    private func startRetentionSweep() {
        retentionSweepTask?.cancel()
        retentionSweepTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_600_000_000_000) // 1시간
                guard let self else { return }
                self.pruneAllStores()
                DeviceDailyStore.shared.flushPending(force: true)
            }
        }
    }

    /// 설정에서 retention 즉시 적용
    func applyRetentionNow() {
        pruneAllStores()
    }

    /// 현재 패턴 임계값 (InsightLogic 주입용)
    func patternThresholds() -> PatternThresholds {
        PatternThresholds(
            repeatingDays: max(1, patternRepeatingDays),
            repeatingCount: max(1, patternRepeatingCount),
            resolvedQuietDays: max(1, patternResolvedQuietDays),
            dormantQuietDays: max(1, patternDormantQuietDays)
        )
    }

    // MARK: - S3 관제 규칙 (로컬 YAML)

    /// 규칙 파일 위치 — **설정 화면에서 경로를 보여 준다** ("여기서 고치지?" 를 없애기 위해)
    var rulesConfigPath: String { RulesConfig.defaultURL.path }

    /// 규칙 설정 문제 (nil 이면 정상) — **파일에 문제가 있다는 사실 자체**를 사용자에게 알린다
    @Published private(set) var rulesProblem: String?

    /// 규칙을 1회 읽어 `WatchEngine` 에 넣는다
    ///
    /// - **파일이 없으면 아무것도 하지 않는다** (선택 사항 · 없는 것은 오류가 아니다)
    /// - **문제가 있으면 적용하지 않고 사유를 남긴다** — 조용히 기본값으로 대체하지 않는다 [표시②]
    ///   사용자가 고쳐도 안 바뀌는 상태를 "적용됨" 으로 말하는 것이 더 나쁘다
    private func loadRules() {
        switch RulesConfig.load() {
        case .missing:
            rulesProblem = nil
            applyRules(.builtInConfig, applied: 0, rejected: 0, note: "rules.yaml 없음 — 내장 기본값 사용")
        case .ok(let config):
            applyRules(config, applied: config.overrides.count, rejected: config.rejected.count)
        case .failed(let why):
            rulesProblem = why
            applyRules(.builtInConfig, applied: 0, rejected: 0, note: "rules.yaml 읽기 실패 — \(why)")
        }
    }

    /// 규칙을 **실제로 적용하는 단일 지점** — 엔진과 방치 트래커가 여기서 함께 움직인다
    ///
    /// ## 왜 한 곳에 모았는가
    /// 처음엔 `WatchEngine.setRules` 만 불렀다. 그랬더니 `battery: { neglectPercent }` 가
    /// **파싱만 되고 아무 효과가 없었다** — 사용자가 고른 값이 조용히 버려지는 최악의 형태.
    /// 두 적용 지점이 따로 놀면 **반쪽만 적용되는 상태**가 반드시 생긴다.
    private func applyRules(
        _ config: RulesConfig, applied: Int, rejected: Int, note: String? = nil
    ) {
        WatchEngine.shared.setRules(config)
        // 방치 임계가 바뀌면 **지금까지 잰 시간이 다른 뜻**이 된다 → 계측을 다시 시작한다
        BatteryNeglectTracker.shared.setThreshold(config.safeBattery().neglectPercent)

        if config.rejected.isEmpty, let note {
            rulesProblem = nil
            DebugLogger.shared.info("Rules", "[INFO] [RULES] \(note)")
        } else if config.rejected.isEmpty {
            rulesProblem = nil
            DebugLogger.shared.info(
                "Rules", "[INFO] [RULES] rules.yaml 적용",
                meta: "rules=\(applied) neglect=\(config.safeBattery().neglectPercent)%")
        } else {
            // 항목별로 걸린 것과 **적용된 것**을 함께 남긴다
            let why = config.rejected.joined(separator: " · ")
            rulesProblem = why
            DebugLogger.shared.error(
                "Rules",
                "[ERROR] [RULES] rules.yaml 일부 무시 — 사유: \(why)",
                meta: "applied=\(applied) rejected=\(rejected)")
        }
    }

    func start() {
        guard !started else { return }
        started = true
        loadRules()
        DebugLogger.shared.info("Store", "[INFO] [FEATURE] ConsoleStore 시작 (relay.*)", meta: "keyPrefix=relay.")
        let handler: @Sendable (DeviceSnapshot) -> Void = { [weak self] snapshot in
            Task { @MainActor in
                self?.ingest(snapshot)
            }
        }
        let eventHandler: @Sendable (String) -> Void = { [weak self] text in
            Task { @MainActor in
                self?.pushEvent(text)
            }
        }
        let appleHandler: @Sendable (AppleSnapshot) -> Void = { [weak self] snap in
            Task { @MainActor in
                self?.ingestApple(snap)
            }
        }
        let appleEventHandler: @Sendable (String) -> Void = { [weak self] text in
            Task { @MainActor in
                self?.pushEvent(text)
            }
        }
        Task {
            await DeviceMonitor.shared.attach(handler)
            await DeviceMonitor.shared.attachEvent(eventHandler)
            await DeviceMonitor.shared.start()
            await AppleDeviceMonitor.shared.attach(appleHandler)
            await AppleDeviceMonitor.shared.attachEvent(appleEventHandler)
            await AppleDeviceMonitor.shared.start()
        }
        startStoreHealthCheck()
    }

    /// `/metrics` 본문 — **MainActor 밖에서 호출되므로** 한 번 옮겨 타야 한다
    ///
    /// 서버는 store 를 모른다. 스냅숿을 만들고 텍스트로 굽는 것까지만 여기서 하고,
    /// 판정은 전부 기존 로직(`activeCriticalCount`)에 맡긴다 —
    /// 같은 값을 두 군데서 계산하면 **어느 쪽이 맞는지 알 수 없다.**
    func renderMetrics() -> String {
        MetricsTextBuilder.render(makeMetricsSnapshot())
    }

    func makeMetricsSnapshot(now: Date = .now) -> MetricsSnapshot {
        MetricsSnapshotBuilder.make(
            devices: inventory.devices,
            events: recentWatchEvents,
            now: now,
            // 방치 시간은 트래커가 들고 있다 (폴링이 먹고, 여기서 읽는다)
            neglect: BatteryNeglectTracker.shared.snapshot(now: now)
        )
    }

    /// 저장 실패 감시 (2분 주기) — 조용한 저장 실패를 사용자에게 노출한다.
    ///
    /// [HARD]/[표시②] 디스크가 가득 차면 UI 는 정상 반영되지만 재시작 시 전부 소실된다.
    /// `E-MAC-STORE-0002` 가 정의돼 있었으나 미사용이었다.
    private func startStoreHealthCheck() {
        storeHealthTask?.cancel()
        storeHealthTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 120_000_000_000)   // 2분
                guard !Task.isCancelled, let self else { return }
                let writers = [
                    EventStore.shared.lastSaveError,
                    DeviceDailyStore.shared.lastSaveError,
                ]
                let failed = writers.contains { $0 != nil }
                if failed {
                    // 같은 문제를 반복 기록하지 않는다 (경보가 사라지므로)
                    if self.storeProblem != .writeFailed(.storeWriteFailed) {
                        self.recordStoreProblem(.writeFailed(.storeWriteFailed))
                    }
                } else if case .writeFailed = self.storeProblem {
                    // 복구되면 해제 — 배너가 계속 남지 않게
                    self.storeProblem = nil
                }
            }
        }
    }

    /// 앱 종료 정리 — applicationWillTerminate에서 호출
    func shutdown() {
        storeHealthTask?.cancel()
        ScrcpyController.shared.stop()
        DeviceDailyStore.shared.flushPending(force: true)
        ConnectionSessionStore.shared.flush()
        // CoalescingWriter 는 대기 중인 쓰기를 **대체**하므로, 종료 전에 진행 중 쓰기를
        // 반드시 동기 로 끝내야 마지막 상태가 기록된다. (기다리는 쓰기는 의도적으로 버린다)
        EventStore.shared.flushSync()
        DeviceDailyStore.shared.flushSync()
        let group = DispatchGroup()
        group.enter()
        Task.detached {
            await DeviceMonitor.shared.stop()
            group.leave()
        }
        group.enter()
        Task.detached {
            await AppleDeviceMonitor.shared.stop()
            group.leave()
        }
        // 종료를 0.5초까지 **메인 스레드에서 대기**하고 있다가 포기했는데,
        // 결과를 버려서 "모니터가 정지했는지"를 알 수 없었다.
        // timeout 이면 조용히 넘어가지 않고 로그로 남긴다([표시②] — 조용한 실패 금지).
        if group.wait(timeout: .now() + 0.5) == .timedOut {
            let msg = L10n.string("shutdown.monitorTimeout")
            DebugLogger.shared.warn("Store", "[WARN] \(msg)")
        }
        DebugLogger.shared.info("Store", "[INFO] ConsoleStore shutdown 완료")
    }

    /// Apple 스냅샷 반영 — 목록 갱신 + 온라인 자동 선택
    private func ingestApple(_ snap: AppleSnapshot) {
        if let idx = appleDevices.firstIndex(where: { $0.udid == snap.udid }) {
            appleDevices[idx] = snap
        } else {
            appleDevices.append(snap)
            appleDevices.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        }
        if selectedAppleUdid == nil || appleDevices.contains(where: { $0.udid == selectedAppleUdid && $0.isOnline }) == false {
            let online = appleDevices.first(where: \.isOnline) ?? appleDevices.first
            if let pick = online {
                selectedAppleUdid = pick.udid
                UserDefaults.standard.set(pick.udid, forKey: selectedAppleKey)
            }
        }
    }

    var selectedAppleDevice: AppleSnapshot? {
        guard let udid = selectedAppleUdid else { return nil }
        return appleDevices.first(where: { $0.udid == udid }) ?? appleDevices.first
    }

    /// 도구/연결 오류 반영 — 배너 표시 (성공 시 clear)
    func setAppleError(_ message: String?) {
        appleLastError = message
    }

    func clearAppleError() {
        appleLastError = nil
    }

    private func ingest(_ snapshot: DeviceSnapshot) {
        inventory.merge(snapshot)
        // 오래 오프라인인 기기는 목록에서 제거한다.
        // 종전엔 한번 연결된 기기가 영구히 남아(무선 ADB 는 IP 변경 시 새 항목 추가)
        // 메뉴바 아이콘이 기기 0대인데 Online로 표시되고 기기 수 비율이 무의미해졌다.
        inventory.pruneOffline(olderThan: Self.offlineRetention, now: .now)
        // 선택 따라가기 — 선택 endpoint 가 오프라인이면 같은 물리 기기의 온라인 endpoint로.
        // USB 를 뽑아도 선택이 오프라인 USB 에 박히면, 같은 폰이 IP 로 온라인인데 "연결 끊김" 이 보인다.
        if let next = DeviceInventory.followSerial(devices: inventory.devices, selected: selectedSerial) {
            selectedSerial = next
            UserDefaults.standard.set(next, forKey: selectedKey)
        }
        guard snapshot.isOnline else { return }

        // 선택 기기 없으면 첫 온라인 자동 선택
        if selectedSerial == nil || inventory.device(serial: selectedSerial ?? "") == nil {
            selectedSerial = snapshot.serial
            UserDefaults.standard.set(snapshot.serial, forKey: selectedKey)
        }

        var m = metricsHistory[snapshot.serial] ?? DroidMetrics()
        let temp = snapshot.deviceTempC ?? snapshot.batteryTempC
        let level = snapshot.batteryLevel.map(Double.init)
        let cpu = snapshot.cpuUsePercent

        var netUpPush: Double?
        var netDownPush: Double?
        if let up = snapshot.netUpMBps, let down = snapshot.netDownMBps {
            let key = snapshot.serial
            if lastNetPushAt[key] == nil || Date().timeIntervalSince(lastNetPushAt[key]!) >= 10 {
                netUpPush = up
                netDownPush = down
                lastNetPushAt[key] = Date()
            }
        }

        var diskRead: Double?
        var diskWrite: Double?
        if snapshot.diskReadMBps != nil || snapshot.diskWriteMBps != nil {
            diskRead = snapshot.diskReadMBps
            diskWrite = snapshot.diskWriteMBps
        }

        let gpu = snapshot.gpuUtilPercent

        if cpu != nil || temp != nil || level != nil || netUpPush != nil || diskRead != nil || diskWrite != nil || gpu != nil {
            m.push(
                cpu: cpu,
                temp: temp,
                level: level,
                netUp: netUpPush,
                netDown: netDownPush,
                diskRead: diskRead,
                diskWrite: diskWrite,
                gpu: gpu
            )
            metricsHistory[snapshot.serial] = m
        }

        // Phase1 — 1분 디바운스 일자 롤업
        ingestDailyRollup(snapshot)
    }

    /// 메트릭 → DeviceDailyStore (1분 디바운스)
    private func ingestDailyRollup(_ snapshot: DeviceSnapshot) {
        let now = Date()
        if let last = lastDailyIngestAt[snapshot.serial],
           now.timeIntervalSince(last) < dailyIngestDebounce {
            return
        }
        lastDailyIngestAt[snapshot.serial] = now

        let temp = snapshot.deviceTempC ?? snapshot.batteryTempC
        var memPct: Double?
        if let used = snapshot.memoryUsedGB, let total = snapshot.memoryTotalGB, total > 0 {
            memPct = used / total * 100.0
        }
        // netUp/Down은 MB/s → 1분 분량 근사
        let sample = DeviceDailySample(
            cpu: snapshot.cpuUsePercent,
            temp: temp,
            batteryLevel: snapshot.batteryLevel,
            isCharging: snapshot.isCharging,
            netUpMB: snapshot.netUpMBps.map { $0 * 60 },
            netDownMB: snapshot.netDownMBps.map { $0 * 60 },
            diskReadMBps: snapshot.diskReadMBps,
            diskWriteMBps: snapshot.diskWriteMBps,
            gpu: snapshot.gpuUtilPercent,
            memUsedPct: memPct,
            psi: snapshot.memPressurePct,
            rsrp: snapshot.rsrp,
            at: now
        )
        DeviceDailyStore.shared.ingest(serial: snapshot.serial, sample: sample)
    }

    // MARK: - Selection (PLAN_v0.3)

    /// 기기 선택 + persist (`relay.selectedSerial`)
    func select(_ serial: String) {
        guard !serial.isEmpty else { return }
        selectedSerial = serial
        UserDefaults.standard.set(serial, forKey: selectedKey)
    }

    /// 선택 기기 스냅샷 — nil이면 첫 장치 폴백
    var selectedDevice: DeviceSnapshot? {
        if let s = selectedSerial, let d = inventory.device(serial: s) {
            return d
        }
        return inventory.devices.first
    }

    func device(for serial: String) -> DeviceSnapshot? {
        inventory.device(serial: serial)
    }

    /// 기기 식별 라벨 — 화면·알림·내보내기 공통 진입점 (마스킹 금지 · AGENTS.local §4)
    func identLabel(for serial: String) -> String {
        guard !serial.isEmpty else { return serial }
        if let d = inventory.device(serial: serial) { return d.identLabel }
        if let a = appleDevices.first(where: { $0.udid == serial }) { return a.identLabel }
        return serial
    }

    /// 기기 선택 후 콘솔 열기 — openConsole 콜백이 App 측 주입
    func openConsoleAfterSelect(serial: String, open: () -> Void) {
        select(serial)
        open()
    }

    func metrics(for serial: String) -> DroidMetrics {
        metricsHistory[serial] ?? DroidMetrics()
    }

    func metricsForSelected() -> DroidMetrics? {
        selectedDevice.map { metrics(for: $0.serial) }
    }

    /// 최근 로그 한 줄 추가 — `RecentEventsStore` 로 분리했다(2026-09-28).
    /// 알림 유입(`ingestWatch`)이 `ConsoleStore` 를 무효화하지 않게 하려는 것이라
    /// 시그니처는 유지한다. `DeviceMonitor` 폴링 경로가 이 메서드를 호출한다.
    func pushEvent(_ text: String) {
        RecentEventsStore.shared.push(text)
    }

    // MARK: - Watch events (PLAN_v0.5)

    /// WatchEngine emit 수신 → 이력 + fingerprint 쿨다운 + 시스템 알림
    func ingestWatch(_ event: WatchEvent, forceNotify: Bool = false) {
        // @Published 는 대입마다 objectWillChange 를 발화하므로,
        // insert 와 trim 을 나눠 하면 **상한(501건)을 넘긴 중간 상태**가 관측된다.
        // (그 상태로 렌더되면 대시보드/인사이트가 전부 다시 계산된다 — 비용이 배수로 붙는다)
        var next = recentWatchEvents
        next.insert(event, at: 0)
        if next.count > Self.maxWatchEvents {
            next.removeLast(next.count - Self.maxWatchEvents)
        }
        recentWatchEvents = next
        pushEvent(event.summary)
        EventStore.shared.save(recentWatchEvents)
        maybeCaptureIncident(event)
        maybeDiagnoseCrash(event)
        // Phase1 — 일자 이벤트 카운트 (crash/anr/warn)
        DeviceDailyStore.shared.countEvent(
            serial: event.serial,
            kind: event.kind,
            isClear: event.isClear,
            at: event.at
        )
        // 연결 세션 추적 (Android)
        trackConnectionSession(event)

        if !forceNotify {
            guard watchEnabled(for: event.kind), watchNotifications else { return }
            // clear = 복구 알림 — 별도 토글
            if event.isClear {
                guard watchRecovery else { return }
            } else {
                guard event.severity >= .warning else { return }
            }
        }

        let now = Date()
        // enter/clear 분리 — 같은 serial:kind라도 해제는 별도 쿨다운
        let fp = "\(event.fingerprint):\(event.isClear ? "clear" : "enter")"
        if !forceNotify, let last = lastNotifiedAt[fp], now.timeIntervalSince(last) < notifyCooldown {
            return
        }
        lastNotifiedAt[fp] = now
        postSystemNotification(for: event)
        sendExternalNotify(for: event)
        IssueLog.append(
            IssueLog.Entry(
                kind: IssueLog.Kind.notifySystem,
                detail: event.summary,
                serial: event.serial,
                package: event.packageName,
                ok: true
            ),
            name: "notify"
        )
        if watchBanner {
            let name = device(for: event.serial)?.displayName
                ?? AdbClient.displayDeviceName(deviceName: nil, model: nil, serial: event.serial)
            AlertBannerPresenter.shared.show(event: event, deviceName: name)
        }
        pruneNotifyCooldown(now: now)
    }

    /// Android 연결 WatchEvent → ConnectionSessionStore open/close
    private func trackConnectionSession(_ event: WatchEvent) {
        guard event.sourceOrDefault == .android else { return }
        switch event.kind {
        case .androidConnected:
            let kind = AdbClient.parseConnection(event.serial).kind
            ConnectionSessionStore.shared.open(serial: event.serial, kind: kind, at: event.at)
            IssueLog.append(
                IssueLog.Entry(
                    kind: IssueLog.Kind.androidConnected,
                    detail: event.summary,
                    serial: event.serial,
                    at: event.at
                ),
                name: "device"
            )
        case .androidDisconnected:
            ConnectionSessionStore.shared.close(serial: event.serial, at: event.at)
            IssueLog.append(
                IssueLog.Entry(
                    kind: IssueLog.Kind.androidDisconnected,
                    detail: event.summary,
                    serial: event.serial,
                    at: event.at
                ),
                name: "device"
            )
        default:
            break
        }
    }

    /// S4 — ANR/crash 자동 번들 (fingerprint 5분 쿨다운)
    private func maybeCaptureIncident(_ event: WatchEvent) {
        guard incidentAuto, !event.isClear else { return }
        guard IncidentBundleLogic.captures(kind: event.kind) else { return }
        let fp = "\(event.fingerprint):bundle"
        guard IncidentBundleLogic.shouldAutoCapture(fingerprint: fp, lastAt: incidentBundleLastAt) else {
            return
        }
        incidentBundleLastAt[fp] = .now
        IncidentBundleStore.shared.capture(
            event: event,
            adbPath: DeviceMonitor.adbPathNow()
        )
    }

    // MARK: - 자동 진단 (PLAN_auto_diagnose Phase 1 · 크래시)

    /// 크래시 진단 결과 — Alerts "진단" 섹션이 읽는다 (DiagnoseStore 영속 + 메모리 미러)
    @Published private(set) var diagnoses: [String: CrashDiagnose] = [:]

    func diagnosis(for event: WatchEvent) -> CrashDiagnose? {
        if let fp = event.errorFingerprint, let d = diagnoses[fp] { return d }
        return diagnoses[event.fingerprint]
    }

    private func setDiagnosis(_ result: CrashDiagnose) {
        var next = diagnoses
        next[result.fingerprint] = result
        diagnoses = next
        DiagnoseStore.shared.put(result)
    }

    /// 크래시 자동 진단 — 지문당 1회, 백그라운드 (PLAN_auto_diagnose)
    /// package·exception이 없으면 진단하지 않는다 (추측 금지).
    /// adb 호출은 detached로 — MainActor를 붙잡지 않는다 (R4 교훈).
    private func maybeDiagnoseCrash(_ event: WatchEvent) {
        guard event.kind == .crash, !event.isClear,
              let pkg = event.packageName, !pkg.isEmpty,
              let exc = event.exceptionClass, !exc.isEmpty,
              let fp = event.errorFingerprint,
              diagnoses[fp] == nil else { return }
        guard let adb = DeviceMonitor.adbPathNow() else { return }
        let serial = event.serial
        let snapshotEvents = recentWatchEvents
        let at = event.at
        Task.detached { [fp, pkg, exc, serial, snapshotEvents, at] in
            let dropbox = await Self.fetchCrashDropbox(adb: adb, serial: serial, package: pkg)
            let freq = CrashFrequency.summarize(events: snapshotEvents, package: pkg, exception: exc, now: at)
            let result = CrashDiagnose(
                fingerprint: fp,
                package: pkg,
                exception: exc,
                foreground: dropbox?.foreground,
                count7d: freq.count,
                dropboxAt: dropbox?.at,
                diagnosedAt: .now
            )
            await MainActor.run {
                ConsoleStore.shared.setDiagnosis(result)
                DebugLogger.shared.info("Diagnose", "[INFO] 크래시 진단 완료 \(pkg)")
            }
        }
    }

    /// dropbox 최신 data_app_crash 중 해당 패키지 1건 — tail 8KB만 전송 (상한)
    nonisolated static func fetchCrashDropbox(adb: String, serial: String, package: String) async -> DropboxCrash? {
        guard let out = try? await ProcessRunner.captureAsync(
            adb,
            ["-s", serial, "shell", "dumpsys dropbox --print data_app_crash | tail -c 8192"],
            timeout: 20
        ), !out.timedOut else { return nil }
        let matches = CrashDropboxParser.parse(out.stdout).filter { $0.package == package }
        // --print는 오래된 순이므로 마지막 매칭이 최신
        return matches.last
    }

    // MARK: - 외부 알림 채널 (PLAN_notify_channels)

    /// UserDefaults 기반 현재 외부 채널 설정
    func notifyConfig() -> NotifyConfig {
        NotifyConfig(
            ntfyEnabled: notifyNtfy,
            ntfyServer: notifyNtfyServer,
            ntfyTopic: notifyNtfyTopic,
            ntfyToken: notifyNtfyToken,
            slackEnabled: notifySlack,
            slackWebhook: notifySlackWebhook,
            minSeverity: notifyMinSeverity == "critical" ? .critical : .warning,
            sendRecovery: notifyRecovery
        )
    }

    /// 시스템 알림 경로 통과분만 외부 전송 (fire-and-forget)
    func sendExternalNotify(for event: WatchEvent, force: Bool = false) {
        let config = notifyConfig()
        guard force || Self.shouldSendExternal(event, config: config) else { return }
        if config.ntfyReady, let req = NotifyChannel.ntfyRequest(event: event, config: config) {
            performNotify(req, channel: "ntfy", event: event)
        }
        if config.slackReady, let req = NotifyChannel.slackRequest(event: event, config: config) {
            performNotify(req, channel: "slack", event: event)
        }
    }

    /// 순수 필터 — 테스트 대상
    static func shouldSendExternal(_ event: WatchEvent, config: NotifyConfig) -> Bool {
        NotifyChannel.shouldSend(event, config: config)
    }

    /// 전송 실측 결과 — IssueLog에 ok/실패 원인을 **응답 후** 기록 (AGENTS.local §4 [표시②])
    private func performNotify(_ request: URLRequest, channel: String, event: WatchEvent) {
        let kind = channel == "slack" ? IssueLog.Kind.notifySlack : IssueLog.Kind.notifyNtfy
        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            Task { @MainActor in
                if let error {
                    let reason = "\(channel) \(error.localizedDescription)"
                    DebugLogger.shared.error(
                        "Notify",
                        "[ERROR] \(ErrorCode.notifyPublishFailed.rawValue) \(reason)"
                    )
                    IssueLog.append(
                        IssueLog.Entry(kind: kind, detail: "\(event.summary) — \(reason)", serial: event.serial, ok: false),
                        name: "notify"
                    )
                    return
                }
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    let reason = "\(channel) HTTP \(http.statusCode)"
                    DebugLogger.shared.error(
                        "Notify",
                        "[ERROR] \(ErrorCode.notifyPublishFailed.rawValue) \(reason)"
                    )
                    IssueLog.append(
                        IssueLog.Entry(kind: kind, detail: "\(event.summary) — \(reason)", serial: event.serial, ok: false),
                        name: "notify"
                    )
                } else {
                    DebugLogger.shared.info("Notify", "[INFO] \(channel) 외부 알림 전송 완료")
                    IssueLog.append(
                        IssueLog.Entry(kind: kind, detail: event.summary, serial: event.serial, ok: true),
                        name: "notify"
                    )
                }
            }
        }
        task.resume()
    }

    /// 설정 → 연동 · 테스트 전송 — 발송 요청·응답 전부 `notifyTestResult`에 노출
    func sendNotifyTest() {
        let config = notifyConfig()
        let event = WatchEvent(
            kind: .throttling,
            severity: .critical,
            serial: "TEST",
            title: L10n.string("notify.test.title"),
            detail: L10n.string("notify.test.detail")
        )
        var requests: [(request: URLRequest, channel: String)] = []
        if config.ntfyReady, let r = NotifyChannel.ntfyRequest(event: event, config: config) {
            requests.append((r, "ntfy"))
        }
        if config.slackReady, let r = NotifyChannel.slackRequest(event: event, config: config) {
            requests.append((r, "slack"))
        }
        guard !requests.isEmpty else {
            notifyTestIsError = true
            notifyTestResult = L10n.string("notify.test.noChannel")
            DebugLogger.shared.warn("Notify", "[WARN] 테스트 전송 불가 — 채널이 비활성입니다")
            return
        }
        notifyTestIsError = false
        notifyTestResult = L10n.string("notify.test.sending")
        DebugLogger.shared.action("Notify", "[ACTION] 외부 알림 테스트 전송 요청")
        Task { @MainActor [weak self] in
            var failures: [String] = []
            for item in requests {
                do {
                    let (_, resp) = try await URLSession.shared.data(for: item.request)
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    if !(200...299).contains(code) {
                        failures.append("\(item.channel) HTTP \(code)")
                    }
                } catch {
                    failures.append("\(item.channel) \(error.localizedDescription)")
                }
            }
            if failures.isEmpty {
                self?.notifyTestIsError = false
                self?.notifyTestResult = L10n.string("notify.test.sent")
            } else {
                self?.notifyTestIsError = true
                self?.notifyTestResult = L10n.format("notify.test.failed", failures.joined(separator: ", "))
            }
        }
    }

    private func watchEnabled(for kind: WatchKind) -> Bool {
        switch kind {
        case .throttling: return watchThrottling
        case .chargeChanged: return watchCharge
        case .protectionChanged: return watchProtection
        case .lowPowerChanged: return watchLowPower
        case .batteryThreshold: return watchBattery
        case .psiPressure: return watchPsi
        case .loadSpike: return watchLoad
        case .memoryLow: return watchMemory
        case .bsohDrop: return watchBsoh
        case .signalDrop: return watchRsrp
        case .anr: return watchAnr
        case .crash: return watchCrash
        case .appleConnected, .appleDisconnected: return watchNotifications
        case .androidConnected, .androidDisconnected: return watchNotifications
        // 탐지(설정 변경·logcat) — severity .info라 시스템 알림은 자동 차단, 이력·표시만 유지
        case .settingsChanged, .logcatHits: return watchNotifications
        }
    }

    // MARK: - Alerts (PLAN_alerts)

    /// Alerts 탭 필터 조회 (메모리 기준 · now 주입 가능)
    func filteredWatchEvents(_ filter: AlertsFilter, now: Date = .now) -> [WatchEvent] {
        WatchEventAlerts.filter(recentWatchEvents, by: filter, now: now)
    }

    /// 탭 카운트 — base 필터(severity/기간 등)에서 state만 무시
    func alertsStateCounts(base: AlertsFilter, now: Date = .now) -> [AlertsState: Int] {
        WatchEventAlerts.counts(recentWatchEvents, filteredBy: base, now: now)
    }

    /// ack / note / mute 갱신 → EventStore 저장
    /// set* 플래그 false면 해당 필드 유지 (nil 전달 시 해제)
    @discardableResult
    func updateWatchEvent(
        id: UUID,
        ackAt: Date? = nil,
        setAck: Bool = false,
        note: String? = nil,
        setNote: Bool = false,
        mutedUntil: Date? = nil,
        setMute: Bool = false
    ) -> Bool {
        guard let idx = recentWatchEvents.firstIndex(where: { $0.id == id }) else { return false }
        recentWatchEvents[idx] = recentWatchEvents[idx].updating(
            ackAt: ackAt,
            setAck: setAck,
            note: note,
            setNote: setNote,
            mutedUntil: mutedUntil,
            setMute: setMute
        )
        EventStore.shared.save(recentWatchEvents)
        return true
    }

    /// 확인 처리
    func ackWatchEvent(id: UUID, at: Date = .now) {
        updateWatchEvent(id: id, ackAt: at, setAck: true)
    }

    /// fatal 이벤트 보강 (앱 버전 등) — 같은 id 교체 후 저장
    func refreshWatchEvent(_ updated: WatchEvent) {
        guard let idx = recentWatchEvents.firstIndex(where: { $0.id == updated.id }) else { return }
        recentWatchEvents[idx] = updated
        EventStore.shared.save(recentWatchEvents)
    }

    /// 메모 저장 (nil = 해제)
    func setWatchNote(id: UUID, note: String?) {
        updateWatchEvent(id: id, note: note?.isEmpty == true ? nil : note, setNote: true)
    }

    /// 무음 (nil = 해제) · 만료 후 Alerts 상태는 자동 active
    func muteWatchEvent(id: UUID, until: Date?) {
        updateWatchEvent(id: id, mutedUntil: until, setMute: true)
    }

    func exportWatchEventsJSON(_ events: [WatchEvent]? = nil) -> Data? {
        WatchEventAlerts.exportJSON(events ?? recentWatchEvents)
    }

    func exportWatchEventsCSV(_ events: [WatchEvent]? = nil) -> String {
        WatchEventAlerts.exportCSV(events ?? recentWatchEvents)
    }

    /// 스로틀링 등 미해결 진입 이벤트 — 후속 조치 가이드용
    /// fingerprint별 **최신** 이벤트가 clear면 숨김 · enter 후 30분 TTL
    var activeRemediationEvents: [WatchEvent] {
        Self.activeRemediation(from: recentWatchEvents, now: Date())
    }

    /// 순수 판정 — 테스트용 (now 주입)
    static func activeRemediation(
        from events: [WatchEvent],
        now: Date,
        ttl: TimeInterval = 1800
    ) -> [WatchEvent] {
        var latest: [String: WatchEvent] = [:]
        for e in events {
            if let cur = latest[e.fingerprint], cur.at >= e.at { continue }
            latest[e.fingerprint] = e
        }
        return latest.values
            .filter { !$0.isClear && $0.severity >= .warning && now.timeIntervalSince($0.at) < ttl }
            .sorted { $0.at > $1.at }
    }

    private func pruneNotifyCooldown(now: Date) {
        lastNotifiedAt = lastNotifiedAt.filter { now.timeIntervalSince($0.value) < notifyCooldown * 2 }
    }

    private func postSystemNotification(for event: WatchEvent) {
        requestNotificationPermissionOnce()
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.detail
        content.interruptionLevel = event.severity == .critical ? .timeSensitive : .active
        switch event.severity {
        case .critical: content.sound = .default
        case .warning: content.sound = nil
        case .info: content.sound = nil
        }
        let req = UNNotificationRequest(
            identifier: event.id.uuidString,
            content: content,
            trigger: nil
        )
        center.add(req) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in
                DebugLogger.shared.error("Watch", "[ERROR] 알림 발송 실패: \(error.localizedDescription)")
                _ = self
            }
        }
    }

    private func requestNotificationPermissionOnce() {
        guard !notificationsRequested else { return }
        notificationsRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// critical 미해결 존재 여부 — 메뉴바 배지용
    /// 같은 fingerprint의 clear가 더 최신이면 해제로 간주
    var hasActiveCritical: Bool {
        BriefingLogic.activeCriticalCount(recentWatchEvents) > 0
    }

    /// 아침 브리핑 스냅숏 — 팝오버 헤더 한 줄 (기기 전용)
    func makeBriefing(now: Date = .now) -> BriefingSnapshot {
        let android = inventory.devices
        let apples = appleDevices
        return BriefingLogic.snapshot(
            androidOnline: android.filter(\.isOnline).count,
            androidTotal: android.count,
            appleOnline: apples.filter(\.isOnline).count,
            appleTotal: apples.count,
            events: recentWatchEvents
        )
    }

#if DEBUG
    /// 합성 감시 이벤트 주입 — 실기기 발열 없이 Gate→알림→팝오버→배지 경로 육안 확인용
    func debugInjectSynthetic(
        kind: WatchKind,
        severity: WatchSeverity,
        title: String,
        detail: String,
        isClear: Bool = false,
        resetCooldown: Bool = true
    ) {
        let serial = selectedSerial ?? "DEBUG-SERIAL"
        let event = WatchEvent(
            kind: kind,
            severity: severity,
            serial: serial,
            title: title,
            detail: detail,
            isClear: isClear
        )
        if resetCooldown {
            lastNotifiedAt.removeValue(forKey: "\(event.fingerprint):\(event.isClear ? "clear" : "enter")")
        }
        DebugLogger.shared.info(
            "Watch",
            "[DEBUG] 합성 주입 \(event.kind.rawValue) sev=\(event.severity.rawValue) \(event.summary)"
        )
        // 디버그 주입은 토글/심각도/쿨다운 무시 — 육안·알림 즉시 확인용
        ingestWatch(event, forceNotify: true)
    }

    /// 알림·배너 없이 이력만 주입 — 단위 테스트(UN 미사용 환경)용
    func debugIngestWatchQuietly(_ event: WatchEvent) {
        // 실제 `ingestWatch` 와 **같은 1회 대입 패턴**으로 통일(2026-09-28).
        // in-place 변이를 쓰면 링이 가득 찬 상태에서 `removeLast()` 가 두 번째
        // `objectWillChange` 를 만들고, 상한을 넘긴 중간 상태(501건)도 관측된다.
        // → DebugPanel 로 알림을 몰아넣어 체감 검증할 때 **실제보다 나쁜 경로**를 재게 된다.
        var next = recentWatchEvents
        next.insert(event, at: 0)
        if next.count > Self.maxWatchEvents {
            next.removeLast(next.count - Self.maxWatchEvents)
        }
        recentWatchEvents = next
        pushEvent(event.summary)
        EventStore.shared.save(recentWatchEvents)
    }

    /// critical 배지 해제용 (최신 critical clear로 덮어쓰기)
    func debugClearCriticalBadge() {
        guard let idx = recentWatchEvents.firstIndex(where: { $0.severity == .critical && !$0.isClear }) else {
            return
        }
        var cleared = recentWatchEvents[idx]
        cleared = WatchEvent(
            kind: cleared.kind,
            severity: .info,
            serial: cleared.serial,
            title: cleared.title,
            detail: cleared.detail,
            isClear: true
        )
        recentWatchEvents[idx] = cleared
    }

    // MARK: - Apple 오프라인 UI 주입 (USB 불필요 육안)

    /// 합성 iPad 온라인 — 카드 그리드·헤더 초록 점 확인용
    func debugInjectAppleOnline() {
        let snap = AppleSnapshot(
            udid: "DEBUG-APPLE-ONLINE-0001",
            isOnline: true,
            deviceName: "iPad Pro (DEBUG)",
            productType: "iPad14,3",
            productVersion: "18.1",
            batteryLevel: 72,
            isCharging: true,
            batteryHealthPct: 94,
            cycleCount: 186,
            storageUsedGB: 148.2,
            storageTotalGB: 256.0,
            thermalState: "fair",
            at: .now
        )
        ingestApple(snap)
        appleLastError = nil
        DebugLogger.shared.info("Apple", "[DEBUG] Apple 온라인 스냅샷 주입 \(snap.displayName)")
    }

    /// 합성 오프라인 — 빨강 점·연결 끊김 문구 확인용
    func debugInjectAppleOffline() {
        var snap = debugAppleBase(online: false)
        snap.batteryLevel = 41
        snap.isCharging = false
        snap.thermalState = nil
        snap.storageUsedGB = nil
        snap.storageTotalGB = nil
        ingestApple(snap)
        appleLastError = nil
        DebugLogger.shared.info("Apple", "[DEBUG] Apple 오프라인 스냅샷 주입")
    }

    /// E-MAC-APL 오류 배너 — 코드+문구 육안 확인용
    func debugInjectAppleError(_ code: ErrorCode) {
        appleLastError = "[\(code.rawValue)] \(code.koMessage)"
        DebugLogger.shared.warn("Apple", "[DEBUG] \(appleLastError ?? "")")
    }

    /// 주입 기기 제거 — 빈 상태 복귀
    func debugClearApple() {
        appleDevices.removeAll { $0.udid.hasPrefix("DEBUG-APPLE") }
        if selectedAppleUdid?.hasPrefix("DEBUG-APPLE") == true {
            selectedAppleUdid = nil
            UserDefaults.standard.removeObject(forKey: selectedAppleKey)
            if let next = appleDevices.first {
                selectedAppleUdid = next.udid
                UserDefaults.standard.set(next.udid, forKey: selectedAppleKey)
            }
        }
        appleLastError = nil
        DebugLogger.shared.info("Apple", "[DEBUG] Apple 주입 스냅샷 제거")
    }

    private func debugAppleBase(online: Bool) -> AppleSnapshot {
        AppleSnapshot(
            udid: "DEBUG-APPLE-OFFLINE-0001",
            isOnline: online,
            deviceName: "iPad Air (DEBUG)",
            productType: "iPad13,16",
            productVersion: "17.6",
            batteryLevel: 41,
            isCharging: false,
            at: .now
        )
    }
#endif

    /// 저장소 문제 (읽기/쓰기 실패) — [표시②] 조용한 실패 금지
    enum StoreProblem: Equatable {
        case readFailed(ErrorCode)
        case writeFailed(ErrorCode)
    }

    /// 감시 대상 저장소 문제 (nil 이면 정상)
    @Published private(set) var storeProblem: StoreProblem?

    /// 저장소 문제를 기록하고 로그로 남긴다 — 파일은 지우지 않는다(복구 가능성 보존)
    private func recordStoreProblem(_ problem: StoreProblem) {
        storeProblem = problem
        switch problem {
        case .readFailed(let code):
            DebugLogger.shared.error("Store", "[ERROR] \(code.rawValue) \(code.koMessage)")
        case .writeFailed(let code):
            DebugLogger.shared.error("Store", "[ERROR] \(code.rawValue) \(code.koMessage)")
        }
    }

    /// 오프라인 기기 보관 기간 — 이만큼 지나도 안 reconnect 되면 목록에서 제거
    /// (충분히 길게 잡아 USB 허브 일시적 떨림으로 기기가 사라지지 않게 한다)
    private static let offlineRetention: TimeInterval = 60 * 30   // 30분

    /// 기기 해제 처리 — 오프라인 표시 + **serial 키 자료구조 정리**
    ///
    /// 종전엔 inventory 의 플래그만 바뀌고 serial 키 딕셔너리들은 그대로 남았다.
    /// 네트워크 ADB 는 serial 이 `IP:PORT` 라 DHCP 가 바뀌면(192.168.0.11 → .12)
    /// 새 키가 생겨 이전 키가 영구 잔류했다. 상시 실행 앱이므로 시간이 갈수록
    /// `metricsHistory`(기기당 60×8 Double 링)와 throttle/daily 딕셔너리가 무한 증가했다.
    func markDeviceOffline(_ serial: String) {
        inventory.markOffline(serial: serial)
        releaseDeviceState(for: serial)
    }

    /// 기기 고유 상태 정리 — 링 버퍼와 throttle/daily 키를 함께 해제한다.
    /// 이벤트·일일 집계(과거 기록)는 지우지 않는다 — 분석 가치가 있는 영구 데이터다.
    private func releaseDeviceState(for serial: String) {
        metricsHistory[serial] = nil
        lastNetPushAt[serial] = nil
        lastDailyIngestAt[serial] = nil
    }
}
