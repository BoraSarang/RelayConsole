import Foundation

/// 기기 일자 롤업 JSON 영구화 — Application Support/RelayConsole/device-daily.json
/// 키: "\(serial)|\(dayKey)"
@MainActor
final class DeviceDailyStore {
    static let shared = DeviceDailyStore()

    static let debounceSeconds: TimeInterval = 60

    private let url: URL
    private let writer: CoalescingWriter<[String: DeviceDaily]>
    /// serial|dayKey → DeviceDaily
    private(set) var map: [String: DeviceDaily] = [:]
    /// serial → 마지막 저장 시각 (1분 디바운스)
    private var lastFlushAt: [String: Date] = [:]
    private var pending: Set<String> = []

    /// 저장 실패 사유 (nil 이면 정상)
    var lastSaveError: String? { writer.lastError }

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("RelayConsole", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent("device-daily.json")
        url = target
        map = Self.loadFromDisk(target)
        writer = CoalescingWriter(url: target, name: "DeviceDailyStore", queueLabel: "relay.devicedailystore") { value in
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            enc.outputFormatting = [.sortedKeys]
            return try enc.encode(value)
        }
    }

    private static func loadFromDisk(_ url: URL) -> [String: DeviceDaily] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: DeviceDaily].self, from: data)) ?? [:]
    }

    /// 저장 — 인코딩·쓰기 모두 백그라운드, 대기 쓰기는 합쳐진다
    func save() {
        pending.removeAll()
        writer.submit(map)
    }

    /// 진행 중 쓰기를 동기 완료 — 앱 종료 전에 호출
    func flushSync() {
        writer.flushSync()
    }

    // MARK: - API

    private func key(serial: String, dayKey: String) -> String {
        "\(serial)|\(dayKey)"
    }

    func current(serial: String, now: Date = .now) -> DeviceDaily {
        let day = DeviceDailyLogic.dayKey(for: now)
        let k = key(serial: serial, dayKey: day)
        if let existing = map[k] { return existing }
        return DeviceDaily(serial: serial, dayKey: day)
    }

    /// 샘플 주입 — 메모리 즉시 반영, 디스크 1분 디바운스
    func ingest(serial: String, sample: DeviceDailySample, forceFlush: Bool = false) {
        let day = DeviceDailyLogic.dayKey(for: sample.at)
        let k = key(serial: serial, dayKey: day)
        var daily = map[k] ?? DeviceDaily(serial: serial, dayKey: day)
        DeviceDailyLogic.merge(into: &daily, sample: sample)
        map[k] = daily

        let now = sample.at
        let shouldFlush: Bool
        if forceFlush {
            shouldFlush = true
        } else if let last = lastFlushAt[serial] {
            shouldFlush = now.timeIntervalSince(last) >= Self.debounceSeconds
        } else {
            shouldFlush = true
        }
        if shouldFlush {
            lastFlushAt[serial] = now
            save()
        } else {
            pending.insert(serial)
        }
    }

    /// 이벤트 카운트 (Alerts ingest)
    func countEvent(serial: String, kind: WatchKind, isClear: Bool, at: Date = .now) {
        guard !isClear else { return }
        // 연결/해제/사이트 등은 device daily crash/anr/warn 집계 제외 대상만 카운트하지 않음 — DeviceDailyLogic이 필터
        let day = DeviceDailyLogic.dayKey(for: at)
        let k = key(serial: serial, dayKey: day)
        var daily = map[k] ?? DeviceDaily(serial: serial, dayKey: day)
        DeviceDailyLogic.countEvent(into: &daily, kind: kind, isClear: isClear)
        map[k] = daily
        pending.insert(serial)
        if let last = lastFlushAt[serial], at.timeIntervalSince(last) >= Self.debounceSeconds {
            save()
        }
    }

    /// 디바운스 대기 중인 것들 강제 저장
    func flushPending(force: Bool = false) {
        guard force || !pending.isEmpty else { return }
        let now = Date()
        for serial in pending {
            if force, lastFlushAt[serial] == nil || now.timeIntervalSince(lastFlushAt[serial]!) >= Self.debounceSeconds {
                lastFlushAt[serial] = now
            }
        }
        if force || !pending.isEmpty {
            save()
        }
    }

    func day(serial: String, dayKey: String) -> DeviceDaily? {
        map[key(serial: serial, dayKey: dayKey)]
    }

    func days(for serial: String) -> [DeviceDaily] {
        map.values
            .filter { $0.serial == serial }
            .sorted { $0.dayKey > $1.dayKey }
    }

    func allDayKeys() -> [String] {
        Set(map.values.map(\.dayKey)).sorted(by: >)
    }

    func prune(retentionDays: Int, now: Date = .now) {
        if DeviceDailyLogic.prune(&map, retentionDays: retentionDays, now: now) > 0 {
            save()
        }
    }

    func clear() {
        map = [:]
        pending.removeAll()
        lastFlushAt.removeAll()
        save()
    }
}
