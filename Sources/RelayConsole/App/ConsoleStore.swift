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
    /// Apple Phase1 — Trust-only 기기 목록·선택
    @Published private(set) var appleDevices: [AppleSnapshot] = []
    @Published var selectedAppleUdid: String?
    /// Apple 오류 배너 — E-MAC-APL 문구 (오프라인 육안용)
    @Published var appleLastError: String?
    /// Sites·Jobs (PLAN_sites_jobs)
    @Published private(set) var sites: [Site] = []
    @Published private(set) var jobs: [Job] = []
    /// 하트비트 서버 오류 (E-MAC-JOB-0001)
    @Published var heartbeatLastError: String?
    @Published private(set) var heartbeatPort: UInt16 = 8787

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
    /// Sites 체크 루프 / Job overdue 추적
    private var sitesCheckTask: Task<Void, Never>?
    private var jobsSweepTask: Task<Void, Never>?
    private var lastSiteUp: [UUID: Bool] = [:]
    private var lastJobOverdue: [UUID: Bool] = [:]
    /// SSL 만료 경고 전이 (A5) — true면 경고 중
    private var lastSslWarn: [UUID: Bool] = [:]
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
    /// Sites SSL 경고 D-day (A5)
    @AppStorage("relay.sites.sslWarnDays") var sslWarnDays = 14
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
    /// S4 Incident Bundle 자동 캡처
    @AppStorage("relay.incident.auto") var incidentAuto = true

    private init() {
        selectedSerial = UserDefaults.standard.string(forKey: selectedKey)
        selectedAppleUdid = UserDefaults.standard.string(forKey: selectedAppleKey)
        // EventStore 1차 — 앱 시작 시 이력 복원 (JSON 영구화)
        recentWatchEvents = EventStore.shared.load()
        sites = SitesJobsStore.shared.loadSites()
        jobs = SitesJobsStore.shared.loadJobs()
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
        startSitesJobs()
    }

    // MARK: - Sites · Jobs (PLAN_sites_jobs)

    /// 체크 루프 + 하트비트 서버 시작
    private func startSitesJobs() {
        startSiteChecks()
        startJobSweep()
        let port = UserDefaults.standard.object(forKey: "relay.hb.port") as? UInt16 ?? 8787
        heartbeatPort = port
        HeartbeatServer.shared.start(
            port: port,
            onBeat: { [weak self] token in
                Task { @MainActor in
                    self?.handleHeartbeat(token: token)
                }
            },
            onBindError: { [weak self] code in
                Task { @MainActor in
                    self?.heartbeatLastError = code
                    DebugLogger.shared.error("HB", "[ERROR] \(code) 하트비트 서버 시작 실패")
                }
            }
        )
    }

    /// 사이트 주기 체크 — enabled만, interval 과거 지났으면 1건씩
    private func startSiteChecks() {
        sitesCheckTask?.cancel()
        sitesCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let now = Date()
                var due: [Site] = []
                for site in self.sites where site.enabled {
                    let last = site.history.last?.at ?? .distantPast
                    if now.timeIntervalSince(last) >= Double(site.intervalSec) {
                        due.append(site)
                    }
                }
                for site in due.prefix(SiteChecker.maxConcurrent) {
                    await self.runSiteCheck(site)
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    /// Job overdue 주기 스윕 (30초)
    private func startJobSweep() {
        jobsSweepTask?.cancel()
        jobsSweepTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.sweepJobOverdue(now: .now)
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    /// 단건 체크 (DEBUG/수동 즉시 실행용)
    func runSiteCheck(_ site: Site) async {
        guard let idx = sites.firstIndex(where: { $0.id == site.id }) else { return }
        let check = await SiteChecker.shared.check(sites[idx])
        sites[idx].appendCheck(check)
        if let exp = check.sslExpiresAt {
            sites[idx].sslExpiresAt = exp
        }
        SitesJobsStore.shared.saveSites(sites)
        emitSiteTransition(site: sites[idx], check: check)
        emitSslTransition(site: sites[idx])
    }

    /// down/up 전이 → WatchEvent — effectiveUp (연속 failThreshold) 기준
    private func emitSiteTransition(site: Site, check: SiteCheck) {
        let after = site.effectiveUp()
        let before = lastSiteUp[site.id]
        lastSiteUp[site.id] = after
        guard let tr = SitesJobsLogic.siteTransition(before: before, after: after) else { return }
        let event: WatchEvent
        switch tr {
        case .down:
            event = WatchEvent(
                kind: .siteDown,
                severity: .critical,
                serial: site.serialKey,
                title: site.name,
                detail: check.detail ?? L10n.string("event.site.down"),
                source: nil
            )
        case .up:
            event = WatchEvent(
                kind: .siteUp,
                severity: .info,
                serial: site.serialKey,
                title: site.name,
                detail: L10n.string("event.site.up"),
                isClear: true,
                source: nil
            )
        }
        ingestWatch(event, forceNotify: tr == .down)
    }

    /// SSL 만료 임박 전이 → WatchEvent.sslExpiring (A5)
    private func emitSslTransition(site: Site) {
        guard site.enabled, site.probe == .http, site.target.lowercased().hasPrefix("https") else {
            lastSslWarn[site.id] = false
            return
        }
        let should = SslAssertLogic.sslShouldWarn(
            expiresAt: site.sslExpiresAt,
            warnDays: sslWarnDays
        )
        let before = lastSslWarn[site.id]
        lastSslWarn[site.id] = should
        if let before {
            guard before != should else { return }
            emitSslEvent(site: site, entering: should)
        } else if should {
            emitSslEvent(site: site, entering: true)
        }
    }

    private func emitSslEvent(site: Site, entering: Bool) {
        if entering {
            let days = SslAssertLogic.daysRemaining(expiresAt: site.sslExpiresAt) ?? sslWarnDays
            let detail = days < 0
                ? L10n.string("event.site.sslExpired")
                : L10n.format("event.site.sslExpiring", max(0, days))
            let event = WatchEvent(
                kind: .sslExpiring,
                severity: days < 0 ? .critical : .warning,
                serial: site.serialKey,
                title: site.name,
                detail: detail,
                source: nil
            )
            ingestWatch(event, forceNotify: true)
        } else {
            let event = WatchEvent(
                kind: .sslExpiring,
                severity: .info,
                serial: site.serialKey,
                title: site.name,
                detail: L10n.string("event.site.sslClear"),
                isClear: true,
                source: nil
            )
            ingestWatch(event, forceNotify: false)
        }
    }

    /// overdue 전이 → WatchEvent
    private func sweepJobOverdue(now: Date) {
        for i in jobs.indices {
            guard jobs[i].enabled else { continue }
            let after = jobs[i].isOverdue(now: now)
            let before = lastJobOverdue[jobs[i].id]
            if let after { lastJobOverdue[jobs[i].id] = after }
            guard let tr = SitesJobsLogic.jobTransition(before: before, after: after) else { continue }
            let job = jobs[i]
            let event: WatchEvent
            switch tr {
            case .overdue:
                event = WatchEvent(
                    kind: .jobOverdue,
                    severity: .warning,
                    serial: job.serialKey,
                    title: job.name,
                    detail: L10n.string("event.job.overdue"),
                    at: now,
                    source: nil
                )
            case .recovered:
                event = WatchEvent(
                    kind: .jobRecovered,
                    severity: .info,
                    serial: job.serialKey,
                    title: job.name,
                    detail: L10n.string("event.job.recovered"),
                    at: now,
                    isClear: true,
                    source: nil
                )
            }
            ingestWatch(event, forceNotify: tr == .overdue)
        }
    }

    /// 하트비트 토큰 매칭 → beat + overdue 해제
    func handleHeartbeat(token: String, at: Date = .now) {
        guard let idx = jobs.firstIndex(where: { $0.token.lowercased() == token.lowercased() }) else {
            DebugLogger.shared.warn("HB", "[WARN] E-MAC-JOB-0002 알 수 없는 토큰")
            return
        }
        guard jobs[idx].enabled else { return }
        jobs[idx].beat(at: at, ok: true)
        lastJobOverdue[jobs[idx].id] = false
        SitesJobsStore.shared.saveJobs(jobs)
        // overdue였다면 복구 clear
        if let i = recentWatchEvents.first(where: { $0.serial == jobs[idx].serialKey && $0.kind == .jobOverdue && !$0.isClear }) {
            _ = i
            ingestWatch(
                WatchEvent(
                    kind: .jobRecovered,
                    severity: .info,
                    serial: jobs[idx].serialKey,
                    title: jobs[idx].name,
                    detail: L10n.string("event.job.recovered"),
                    at: at,
                    isClear: true,
                    source: nil
                ),
                forceNotify: false
            )
        }
        pushEvent("HB \(jobs[idx].name) @ \(at.formatted(date: .omitted, time: .shortened))")
    }

    // MARK: - Sites CRUD

    func addSite(
        name: String,
        target: String,
        probe: SiteProbe,
        intervalSec: Int,
        failThreshold: Int = 2,
        assertBody: String? = nil,
        tags: [String] = []
    ) {
        let site = Site(
            name: name,
            target: SitesJobsLogic.sanitizeTarget(target, probe: probe),
            probe: probe,
            intervalSec: intervalSec,
            failThreshold: failThreshold,
            assertBody: assertBody?.isEmpty == true ? nil : assertBody,
            tags: tags
        )
        sites.append(site)
        SitesJobsStore.shared.saveSites(sites)
        DebugLogger.shared.info("Sites", "[INFO] [FEATURE] 사이트 추가 \(site.name)")
        Task { await runSiteCheck(site) }
    }

    func removeSite(id: UUID) {
        sites.removeAll { $0.id == id }
        lastSiteUp[id] = nil
        SitesJobsStore.shared.saveSites(sites)
    }

    func toggleSite(id: UUID, enabled: Bool) {
        guard let i = sites.firstIndex(where: { $0.id == id }) else { return }
        sites[i].enabled = enabled
        SitesJobsStore.shared.saveSites(sites)
    }

    /// 사이트 수정 (이름·대상·probe·주기·임계값·assertion) — 대상 변경 시 즉시 재체크
    func updateSite(
        id: UUID,
        name: String,
        target: String,
        probe: SiteProbe,
        intervalSec: Int,
        failThreshold: Int,
        assertBody: String?,
        tags: [String]? = nil
    ) {
        guard let i = sites.firstIndex(where: { $0.id == id }) else { return }
        let clean = SitesJobsLogic.sanitizeTarget(target, probe: probe)
        let targetChanged = sites[i].target != clean || sites[i].probe != probe
        sites[i].name = name
        sites[i].target = clean
        sites[i].probe = probe
        sites[i].intervalSec = max(10, intervalSec)
        sites[i].failThreshold = min(5, max(1, failThreshold))
        sites[i].assertBody = assertBody?.isEmpty == true ? nil : assertBody
        if let tags {
            sites[i].tags = tags
        }
        SitesJobsStore.shared.saveSites(sites)
        DebugLogger.shared.info("Sites", "[INFO] [FEATURE] 사이트 수정 \(name)")
        if targetChanged {
            Task { await runSiteCheck(sites[i]) }
        }
    }

    func clearSiteHistory(id: UUID) {
        guard let i = sites.firstIndex(where: { $0.id == id }) else { return }
        sites[i].history.removeAll()
        lastSiteUp[id] = nil
        SitesJobsStore.shared.saveSites(sites)
    }

    // MARK: - Jobs CRUD

    @discardableResult
    func addJob(name: String, expectEverySec: Int, token: String? = nil) -> Job {
        let job: Job
        if let token, !token.isEmpty {
            job = Job(name: name, token: token.lowercased(), expectEverySec: expectEverySec)
        } else {
            job = Job(name: name, expectEverySec: expectEverySec)
        }
        jobs.append(job)
        SitesJobsStore.shared.saveJobs(jobs)
        DebugLogger.shared.info("Jobs", "[INFO] [FEATURE] 작업 추가 \(job.name) token=\(job.token)")
        return job
    }

    func removeJob(id: UUID) {
        jobs.removeAll { $0.id == id }
        lastJobOverdue[id] = nil
        SitesJobsStore.shared.saveJobs(jobs)
    }

    func toggleJob(id: UUID, enabled: Bool) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[i].enabled = enabled
        SitesJobsStore.shared.saveJobs(jobs)
    }

    /// 하트비트 포트 재설정 (설정에서)
    func restartHeartbeat(port: UInt16) {
        heartbeatPort = port
        UserDefaults.standard.set(port, forKey: "relay.hb.port")
        heartbeatLastError = nil
        HeartbeatServer.shared.start(
            port: port,
            onBeat: { [weak self] token in
                Task { @MainActor in
                    self?.handleHeartbeat(token: token)
                }
            },
            onBindError: { [weak self] code in
                Task { @MainActor in
                    self?.heartbeatLastError = code
                }
            }
        )
    }

    /// DEBUG: 사이트 체크 결과 주입 (실제 네트워크 없이)
    /// down 주입은 failThreshold만큼 연속 실패를 넣어 전이를 보장
    func debugInjectSiteCheck(id: UUID, ok: Bool, detail: String? = nil) {
        guard let i = sites.firstIndex(where: { $0.id == id }) else { return }
        let rounds = ok ? 1 : max(1, sites[i].failThreshold)
        for _ in 0..<rounds {
            let check = SiteCheck(ok: ok, latencyMs: ok ? Int.random(in: 12...180) : nil, detail: detail)
            sites[i].appendCheck(check)
            emitSiteTransition(site: sites[i], check: check)
        }
        SitesJobsStore.shared.saveSites(sites)
    }

    /// DEBUG: 하트비트 주입
    func debugInjectBeat(id: UUID) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        handleHeartbeat(token: jobs[i].token)
    }

    /// DEBUG: Sites·Jobs 비우기
    func clearSitesJobsDebug() {
        sites = []
        jobs = []
        lastSiteUp = [:]
        lastJobOverdue = [:]
        SitesJobsStore.shared.saveSites(sites)
        SitesJobsStore.shared.saveJobs(jobs)
    }

    /// stop 스레드 (앱 종료 시)
    func stopSitesJobs() {
        sitesCheckTask?.cancel()
        jobsSweepTask?.cancel()
        HeartbeatServer.shared.stop()
    }

    /// 앱 종료 정리 — applicationWillTerminate에서 호출
    func shutdown() {
        stopSitesJobs()
        ScrcpyController.shared.stop()
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
        _ = group.wait(timeout: .now() + 0.5)
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
        maybeCaptureIncident(event)

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
        if watchBanner {
            let name = device(for: event.serial)?.displayName
                ?? AdbClient.displayDeviceName(deviceName: nil, model: nil, serial: event.serial)
            AlertBannerPresenter.shared.show(event: event, deviceName: name)
        }
        pruneNotifyCooldown(now: now)
    }

    /// S4 — ANR/crash/siteDown 자동 번들 (fingerprint 5분 쿨다운)
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
            performNotify(req, channel: "ntfy")
        }
        if config.slackReady, let req = NotifyChannel.slackRequest(event: event, config: config) {
            performNotify(req, channel: "slack")
        }
    }

    /// 순수 필터 — 테스트 대상
    static func shouldSendExternal(_ event: WatchEvent, config: NotifyConfig) -> Bool {
        NotifyChannel.shouldSend(event, config: config)
    }

    private func performNotify(_ request: URLRequest, channel: String) {
        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            Task { @MainActor in
                if let error {
                    DebugLogger.shared.error(
                        "Notify",
                        "[ERROR] \(ErrorCode.notifyPublishFailed.rawValue) \(channel) 전송 실패: \(error.localizedDescription)"
                    )
                    return
                }
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    DebugLogger.shared.error(
                        "Notify",
                        "[ERROR] \(ErrorCode.notifyPublishFailed.rawValue) \(channel) HTTP \(http.statusCode)"
                    )
                } else {
                    DebugLogger.shared.info("Notify", "[INFO] \(channel) 외부 알림 전송 완료")
                }
            }
        }
        task.resume()
    }

    /// 설정 → 연동 · 테스트 전송 (성공/실패 로그)
    func sendNotifyTest() {
        let config = notifyConfig()
        let event = WatchEvent(
            kind: .siteDown,
            severity: .critical,
            serial: "TEST",
            title: L10n.string("notify.test.title"),
            detail: L10n.string("notify.test.detail")
        )
        guard config.anyReady else {
            DebugLogger.shared.warn("Notify", "[WARN] 테스트 전송 불가 — 채널이 비활성입니다")
            return
        }
        sendExternalNotify(for: event, force: true)
        DebugLogger.shared.action("Notify", "[ACTION] 외부 알림 테스트 전송 요청")
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
        case .siteDown, .siteUp, .jobOverdue, .jobRecovered: return watchNotifications
        case .sslExpiring: return watchNotifications
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

    /// 아침 브리핑 스냅숏 — 팝오버 헤더 한 줄 (PLAN_briefing)
    func makeBriefing(now: Date = .now) -> BriefingSnapshot {
        let android = inventory.devices
        let apples = appleDevices
        return BriefingLogic.snapshot(
            sites: sites,
            jobs: jobs,
            androidOnline: android.filter(\.isOnline).count,
            androidTotal: android.count,
            appleOnline: apples.filter(\.isOnline).count,
            appleTotal: apples.count,
            events: recentWatchEvents,
            now: now
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
        recentWatchEvents.insert(event, at: 0)
        if recentWatchEvents.count > 500 { recentWatchEvents.removeLast() }
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

    func markDeviceOffline(_ serial: String) {
        inventory.markOffline(serial: serial)
    }
}
