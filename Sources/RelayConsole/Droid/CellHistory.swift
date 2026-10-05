import Foundation

/// 서빙셀 변경 이력 — 셀 변경(핸드오버) 추적용 (PLAN_auto_diagnose Phase 3)
///
/// 폴링에서 셀이 바뀔 때만 기록한다 (5초 틱마다 쓰지 않음).
/// 기기당 최대 200건 — 오래된 것부터 버린다.
/// 영속: Application Support/RelayConsole/cell-history.json
struct CellSample: Codable, Equatable, Sendable {
    var at: Date
    var ci: Int
    var pci: Int
    var rsrp: Int?
}

final class CellHistory: @unchecked Sendable {
    static let shared = CellHistory()
    static let maxPerSerial = 200

    private let lock = NSLock()
    private var samples: [String: [CellSample]] = [:]
    private let url: URL
    private var saveWork: DispatchWorkItem?

    /// 셀 변경 판정 — 순수 함수 (테스트 고정)
    /// ci/pci 둘 다 있어야 비교한다. 하나라도 없으면 "모른다" → 기록 안 함.
    static func isCellChange(last: CellSample?, ci: Int?, pci: Int?) -> Bool {
        guard let ci, let pci else { return false }
        guard let last else { return true }
        return last.ci != ci || last.pci != pci
    }

    init(url: URL? = nil) {
        if let url {
            self.url = url
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let dir = base.appendingPathComponent("RelayConsole", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.url = dir.appendingPathComponent("cell-history.json")
        }
        samples = loadFromDisk()
    }

    /// 폴링에서 호출 — 바뀔 때만 저장한다
    static func record(serial: String, ci: Int?, pci: Int?, rsrp: Int?, at: Date = .now) {
        shared.record(serial: serial, ci: ci, pci: pci, rsrp: rsrp, at: at)
    }

    func record(serial: String, ci: Int?, pci: Int?, rsrp: Int?, at: Date = .now) {
        guard let ci, let pci else { return }
        lock.lock()
        var list = samples[serial] ?? []
        let changed = list.last.map { $0.ci != ci || $0.pci != pci } ?? true
        if changed {
            list.append(CellSample(at: at, ci: ci, pci: pci, rsrp: rsrp))
            if list.count > Self.maxPerSerial {
                list.removeFirst(list.count - Self.maxPerSerial)
            }
            samples[serial] = list
            lock.unlock()
            scheduleSave()
        } else {
            lock.unlock()
        }
    }

    func history(serial: String) -> [CellSample] {
        lock.lock()
        defer { lock.unlock() }
        return samples[serial] ?? []
    }

    /// 변경 횟수 revision — Insights 캐시 무효화용
    var revision: Int {
        lock.lock()
        defer { lock.unlock() }
        return samples.values.reduce(0) { $0 + $1.count }
    }

    private func loadFromDisk() -> [String: [CellSample]] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: [CellSample]].self, from: data)) ?? [:]
    }

    private func scheduleSave() {
        lock.lock()
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let snap = self.samples
            self.lock.unlock()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            if let data = try? encoder.encode(snap) {
                try? data.write(to: self.url, options: .atomic)
            }
        }
        saveWork = work
        lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2, execute: work)
    }
}
