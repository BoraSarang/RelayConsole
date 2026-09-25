import Foundation
import Combine
import WidgetKit
import RelayWidgetCore

/// 위젯 스냅샷 동기화 — ConsoleStore 변경을 60s 스로틀로 App Group에 기록하고 타임라인을 리로드
@MainActor
final class WidgetSnapshotSync {
    static let shared = WidgetSnapshotSync()
    private var bag = Set<AnyCancellable>()
    private var attached = false

    func attach(_ store: ConsoleStore) {
        guard !attached else { return }
        attached = true
        // ConsoleStore @Published 전부 (objectWillChange) + @AppStorage 변경(UserDefaults 공지) → 60s 스로틀
        Publishers.Merge(
            store.objectWillChange.map { _ in () },
            NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).map { _ in () }
        )
        .throttle(for: .seconds(60), scheduler: DispatchQueue.main, latest: true)
        .sink { [weak store] _ in
            // 스로틀 스케줄러는 main이지만 타입 체커가 nonisolated로 볼 수 있음 — 명시적 hop
            Task { @MainActor in Self.write(store) }
        }
        .store(in: &bag)
        // 초기 1회 — 위젯이 앱 기동 직후 데이터를 갖도록
        Self.write(store)
    }

    /// 종료 직전 동기화 flush (applicationWillTerminate)
    func flush(_ store: ConsoleStore) {
        Self.write(store)
    }

    static func snapshot(from store: ConsoleStore, now: Date = .now) -> WidgetSnapshot {
        let briefing: String?
        if store.briefingEnabled {
            let b = store.makeBriefing(now: now)
            briefing = L10n.format(
                "briefing.line",
                b.upSites,
                b.totalSites,
                b.overdueJobs,
                b.onlinePhones,
                b.totalPhones,
                b.activeCriticals
            )
        } else {
            briefing = nil
        }
        return WidgetSnapshotBuilder.build(
            briefing: briefing,
            android: store.inventory.devices,
            apple: store.appleDevices,
            selectedSerial: store.selectedSerial,
            selectedAppleUdid: store.selectedAppleUdid,
            sites: store.sites,
            jobs: store.jobs,
            events: store.recentWatchEvents,
            ident: { store.identLabel(for: $0) },
            now: now
        )
    }

    static func write(_ store: ConsoleStore?) {
        guard let store else { return }
        let snapshot = snapshot(from: store)
        if WidgetSnapshotStore.write(snapshot) {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshotStore.widgetKind)
            DebugLogger.shared.info(
                "Widget",
                "[INFO] 위젯 스냅샷 기록",
                meta: "devices=\(snapshot.devices.count) sites=\(snapshot.siteTotal) critical=\(snapshot.critical)"
            )
        } else {
            DebugLogger.shared.error(
                "Widget",
                "[ERROR] 위젯 스냅샷 기록 실패 — App Group 컨테이너 접근 불가 ([표시②] 원인 노출)",
                meta: "group=\(WidgetSnapshotStore.groupID)"
            )
        }
    }
}

/// 순수 스냅샷 빌더 — 도메인 모델 → 위젯 DTO (테스트 대상 · [표시①] ident는 identLabel 원문 사용)
enum WidgetSnapshotBuilder {
    static let maxDevices = 4
    static let maxSites = 6
    static let maxEvents = 3

    static func build(
        briefing: String?,
        android: [DeviceSnapshot],
        apple: [AppleSnapshot],
        selectedSerial: String?,
        selectedAppleUdid: String?,
        sites: [Site],
        jobs: [Job],
        events: [WatchEvent],
        ident: (String) -> String,
        now: Date = .now
    ) -> WidgetSnapshot {
        var devices: [WidgetDevice] = android.map { d in
            WidgetDevice(
                ident: d.identLabel,
                online: d.isOnline,
                batteryPct: d.batteryLevel,
                charging: d.isCharging,
                thermalAlert: d.isThermalAlert,
                selected: selectedSerial != nil && d.serial == selectedSerial
            )
        } + apple.map { a in
            let thermal = ["serious", "critical"].contains((a.thermalState ?? "").lowercased())
            return WidgetDevice(
                ident: a.identLabel,
                online: a.isOnline,
                batteryPct: a.batteryLevel,
                charging: a.isCharging,
                thermalAlert: thermal,
                selected: selectedAppleUdid != nil && a.udid == selectedAppleUdid
            )
        }
        // 선택 기기 1대를 맨 앞으로 — 나머지는 원래 순서 유지 (결정적)
        if let idx = devices.firstIndex(where: \.selected), idx != 0 {
            devices.insert(devices.remove(at: idx), at: 0)
        }
        devices = Array(devices.prefix(maxDevices))

        let enabledSites = sites.filter(\.enabled)
        let siteRows: [WidgetSite] = enabledSites.prefix(maxSites).map { s in
            let state: WidgetSiteState
            switch s.effectiveUp() {
            case .some(true): state = .up
            case .some(false): state = .down
            case nil: state = .unknown
            }
            return WidgetSite(
                name: s.name,
                state: state,
                uptime7dPct: s.uptimePercent(since: now.addingTimeInterval(-7 * 24 * 3600))
            )
        }

        let enabledJobs = jobs.filter(\.enabled)
        let overdue = enabledJobs.filter { $0.isOverdue(now: now) == true }.count

        let eventRows: [WidgetEvent] = events.prefix(maxEvents).map { e in
            WidgetEvent(at: e.at, severity: e.severity.rawValue, title: e.title, ident: ident(e.serial))
        }

        return WidgetSnapshot(
            updatedAt: now,
            briefing: briefing,
            critical: BriefingLogic.activeCriticalCount(events),
            devices: devices,
            sites: siteRows,
            siteUp: enabledSites.filter { $0.effectiveUp() == true }.count,
            siteDown: enabledSites.filter { $0.effectiveUp() == false }.count,
            siteTotal: enabledSites.count,
            jobsTotal: enabledJobs.count,
            jobsOverdue: overdue,
            events: eventRows
        )
    }
}
