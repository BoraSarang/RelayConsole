import Foundation

/// 크래시 진단 결과 영속 — Application Support/RelayConsole/diagnoses.json
/// Alerts는 EventStore에서 다시 읽으므로 메모리만이면 재시작 시 진단이 사라진다.
@MainActor
final class DiagnoseStore {
    static let shared = DiagnoseStore()

    /// 영속 봉투 — 크래시+발열 (구형 [String: CrashDiagnose] 파일은 읽어서 이관)
    struct DiagnoseFile: Codable {
        var crash: [String: CrashDiagnose] = [:]
        var throttling: [String: ThermalDiagnose] = [:]
    }

    private let url: URL
    private let queue = DispatchQueue(label: "relay.diagnose", qos: .utility)
    private(set) var diagnoses: [String: CrashDiagnose] = [:]
    private(set) var thermal: [String: ThermalDiagnose] = [:]

    private init() {
        self.url = Self.defaultURL()
        let file = loadFromDisk()
        diagnoses = file.crash
        thermal = file.throttling
    }

    /// 테스트 전용 — 실제 사용자 데이터를 건드리지 않도록 파일 위치를 주입한다
    init(url: URL) {
        self.url = url
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let file = loadFromDisk()
        diagnoses = file.crash
        thermal = file.throttling
    }

    static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("RelayConsole", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("diagnoses.json")
    }

    private func loadFromDisk() -> DiagnoseFile {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return DiagnoseFile()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // 기본값이 있어 합성 Decodable가 구파일을 "빈 신형"으로 오인한다 — 키로 먼저 가른다
        if obj.keys.contains("crash") || obj.keys.contains("throttling"),
           let file = try? decoder.decode(DiagnoseFile.self, from: data) {
            return file
        }
        // 구형형 ([String: CrashDiagnose]) — Phase 1 파일을 이관한다
        if let legacy = try? decoder.decode([String: CrashDiagnose].self, from: data) {
            return DiagnoseFile(crash: legacy)
        }
        return DiagnoseFile()
    }

    func put(_ diagnose: CrashDiagnose) {
        diagnoses[diagnose.fingerprint] = diagnose
        save()
    }

    func get(fingerprint: String) -> CrashDiagnose? {
        diagnoses[fingerprint]
    }

    func putThermal(_ diagnose: ThermalDiagnose) {
        thermal[diagnose.fingerprint] = diagnose
        save()
    }

    func getThermal(fingerprint: String) -> ThermalDiagnose? {
        thermal[fingerprint]
    }

    private func save() {
        let file = DiagnoseFile(crash: diagnoses, throttling: thermal)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(file) else { return }
        let target = url
        queue.async {
            try? data.write(to: target, options: .atomic)
        }
    }
}
