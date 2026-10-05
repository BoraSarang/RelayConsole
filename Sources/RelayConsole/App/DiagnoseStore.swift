import Foundation

/// 크래시 진단 결과 영속 — Application Support/RelayConsole/diagnoses.json
/// Alerts는 EventStore에서 다시 읽으므로 메모리만이면 재시작 시 진단이 사라진다.
@MainActor
final class DiagnoseStore {
    static let shared = DiagnoseStore()

    private let url: URL
    private let queue = DispatchQueue(label: "relay.diagnose", qos: .utility)
    private(set) var diagnoses: [String: CrashDiagnose] = [:]

    private init() {
        self.url = Self.defaultURL()
        diagnoses = loadFromDisk()
    }

    /// 테스트 전용 — 실제 사용자 데이터를 건드리지 않도록 파일 위치를 주입한다
    init(url: URL) {
        self.url = url
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        diagnoses = loadFromDisk()
    }

    static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("RelayConsole", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("diagnoses.json")
    }

    private func loadFromDisk() -> [String: CrashDiagnose] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: CrashDiagnose].self, from: data)) ?? [:]
    }

    func put(_ diagnose: CrashDiagnose) {
        diagnoses[diagnose.fingerprint] = diagnose
        save()
    }

    func get(fingerprint: String) -> CrashDiagnose? {
        diagnoses[fingerprint]
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(diagnoses) else { return }
        let target = url
        queue.async {
            try? data.write(to: target, options: .atomic)
        }
    }
}
