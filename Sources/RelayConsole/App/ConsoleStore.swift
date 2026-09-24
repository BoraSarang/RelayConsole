import Foundation
import Combine
import SwiftUI
import UserNotifications

/// UI 유일 read 모델 — `devices`만 읽도록 강제 (PLAN P0-a)
@MainActor
final class ConsoleStore: ObservableObject {
    static let shared = ConsoleStore()

    @Published var inventory = DeviceInventory()
    @Published var recentEvents: [String] = []
    /// 구조화 감시 이벤트 (PLAN_v0.5) — 심각도·fingerprint 보존, 팝오버 우선 표시용
    @Published private(set) var recentWatchEvents: [WatchEvent] = []
    @Published var lastError: String?
    /// serial → DroidMetrics 링 60점 (5s × 60 = 5분)
    @Published private(set) var metricsHistory: [String: DroidMetrics] = [:]
    /// 현재 선택 기기 (팝오버/대시보드 기준) — PLAN_v0.3
    @Published var selectedSerial: String?

    private let selectedKey = "relay.selectedSerial"
    private var started = false
    private var lastNetPushAt: [String: Date] = [:]
    /// fingerprint → 마지막 시스템 알림 시각 (2중 쿨다운: Gate + notify 5분)
    private var lastNotifiedAt: [String: Date] = [:]
    private let notifyCooldown: TimeInterval = 300
    private var notificationsRequested = false
    /// Phase1.5 감시 알림 토글 (relay.watch.*)
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
    /// Phase v0.9 — 카드 On/Off (대시보드·팝오버 공통, 기본 전체 ON)
    @AppStorage("relay.cards.cpu") var cardCpu = true
    @AppStorage("relay.cards.gpu") var cardGpu = true
    @AppStorage("relay.cards.memory") var cardMemory = true
    @AppStorage("relay.cards.sensors") var cardSensors = true
    @AppStorage("relay.cards.battery") var cardBattery = true
    @AppStorage("relay.cards.network") var cardNetwork = true
    @AppStorage("relay.cards.thermal") var cardThermal = true
    @AppStorage("relay.cards.storage") var cardStorage = true

    private init() {
        selectedSerial = UserDefaults.standard.string(forKey: selectedKey)
        // EventStore 1차 — 앱 시작 시 이력 복원 (JSON 영구화)
        recentWatchEvents = EventStore.shared.load()
    }

    func start() {
        guard !started else { return }
        started = true
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
        Task {
            await DeviceMonitor.shared.attach(handler)
            await DeviceMonitor.shared.attachEvent(eventHandler)
            await DeviceMonitor.shared.start()
        }
    }

    private func ingest(_ snapshot: DeviceSnapshot) {
        inventory.merge(snapshot)
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

        var netPush: Double?
        if let up = snapshot.netUpMBps, let down = snapshot.netDownMBps {
            let key = snapshot.serial
            if lastNetPushAt[key] == nil || Date().timeIntervalSince(lastNetPushAt[key]!) >= 10 {
                netPush = up + down
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

        if cpu != nil || temp != nil || level != nil || netPush != nil || diskRead != nil || diskWrite != nil || gpu != nil {
            m.push(cpu: cpu, temp: temp, level: level, net: netPush, diskRead: diskRead, diskWrite: diskWrite, gpu: gpu)
            metricsHistory[snapshot.serial] = m
        }
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

    func pushEvent(_ text: String) {
        recentEvents.insert(text, at: 0)
        if recentEvents.count > 20 { recentEvents.removeLast() }
    }

    // MARK: - Watch events (PLAN_v0.5)

    /// WatchEngine emit 수신 → 이력 + fingerprint 쿨다운 + 시스템 알림
    func ingestWatch(_ event: WatchEvent, forceNotify: Bool = false) {
        recentWatchEvents.insert(event, at: 0)
        if recentWatchEvents.count > 500 { recentWatchEvents.removeLast() }
        pushEvent(event.summary)
        EventStore.shared.save(recentWatchEvents)

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
        if watchBanner {
            let name = device(for: event.serial)?.displayName
                ?? AdbClient.displayDeviceName(deviceName: nil, model: nil, serial: event.serial)
            AlertBannerPresenter.shared.show(event: event, deviceName: name)
        }
        pruneNotifyCooldown(now: now)
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
        }
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
        for (i, e) in recentWatchEvents.enumerated() {
            guard e.severity == .critical, !e.isClear else { continue }
            let fp = e.fingerprint
            let cleared = recentWatchEvents[..<i].contains {
                $0.fingerprint == fp && $0.isClear
            }
            if !cleared { return true }
        }
        return false
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
#endif

    func markDeviceOffline(_ serial: String) {
        inventory.markOffline(serial: serial)
    }
}
