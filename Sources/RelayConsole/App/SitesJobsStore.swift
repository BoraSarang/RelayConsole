import Foundation

/// Sites·Jobs JSON 영구화 (EventStore 패턴)
/// Application Support/RelayConsole/{sites,jobs}.json
@MainActor
final class SitesJobsStore {
    static let shared = SitesJobsStore()

    private let sitesURL: URL
    private let jobsURL: URL
    private let sitesWriter: CoalescingWriter<[Site]>
    private let jobsWriter: CoalescingWriter<[Job]>

    /// 저장 실패 사유 (nil 이면 정상)
    var lastSaveError: String? { sitesWriter.lastError ?? jobsWriter.lastError }

    /// **로드** 실패한 파일의 에러 코드 — 파일이 있는데 읽기/디코딩이 실패한 경우만.
    /// 조용히 빈 배열이 되면 다음 저장에서 기존 데이터를 덮어쓴다([표시②]).
    private(set) var loadFailed: ErrorCode?

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("RelayConsole", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let sURL = dir.appendingPathComponent("sites.json")
        let jURL = dir.appendingPathComponent("jobs.json")
        sitesURL = sURL
        jobsURL = jURL
        // 사이트 체크 1회마다 전체(각각 이력 300건)를 다시 썼다 — 실측 8×300 = 288KB, 2.4ms.
        // 인코딩을 큐로 옮기고 대기 쓰기를 합쳐 MainActor 비용과 쓰기 증폭을 함께 없앤다.
        sitesWriter = CoalescingWriter(url: sURL, name: "SitesJobsStore.sites", queueLabel: "relay.sitesjobs.sites") { value in
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            enc.outputFormatting = [.sortedKeys]
            return try enc.encode(value)
        }
        jobsWriter = CoalescingWriter(url: jURL, name: "SitesJobsStore.jobs", queueLabel: "relay.sitesjobs.jobs") { value in
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            enc.outputFormatting = [.sortedKeys]
            return try enc.encode(value)
        }
    }

    func loadSites() -> [Site] {
        guard FileManager.default.fileExists(atPath: sitesURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: sitesURL)
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            let v = try dec.decode([Site].self, from: data)
            loadFailed = nil
            return v
        } catch {
            loadFailed = .storeReadFailed
            DebugLogger.shared.error(
                "Store",
                "[ERROR] \(ErrorCode.storeReadFailed.rawValue) 사이트 읽기 실패: \(error.localizedDescription)"
            )
            return []
        }
    }

    /// 로드 실패로 **빈 배열**이 된 상태에서 저장하면 기존 파일이 통째로 덮어써진다.
    /// 손상된 원본을 `.corrupt-<ts>` 로 먼저 보존해 복구 가능성을 지킨다.
    /// (파괴적 자동 복구는 하지 않는다 — 사용자가 확인해야 한다)
    private func preserveCorruptOriginal(_ url: URL) {
        guard loadFailed != nil else { return }
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        let backup = url
            .deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).corrupt-\(f.string(from: .now))")
        try? FileManager.default.copyItem(at: url, to: backup)
        DebugLogger.shared.warn(
            "Store",
            "[WARN] 손상된 원본 보존: \(backup.lastPathComponent)"
        )
        loadFailed = nil     // 1회만 보존 (매 저장마다 백업 생기지 않도록)
    }

    func saveSites(_ sites: [Site]) {
        preserveCorruptOriginal(sitesURL)
        sitesWriter.submit(sites)
    }
    func loadJobs() -> [Job] {
        guard FileManager.default.fileExists(atPath: jobsURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: jobsURL)
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            let v = try dec.decode([Job].self, from: data)
            if loadFailed != .storeReadFailed { loadFailed = nil }
            return v
        } catch {
            loadFailed = .storeReadFailed
            DebugLogger.shared.error(
                "Store",
                "[ERROR] \(ErrorCode.storeReadFailed.rawValue) 작업 읽기 실패: \(error.localizedDescription)"
            )
            return []
        }
    }

    func saveJobs(_ jobs: [Job]) {
        preserveCorruptOriginal(jobsURL)
        jobsWriter.submit(jobs)
    }

    /// 진행 중 쓰기를 동기 완료 — 앱 종료 전에 호출
    func flushSync() {
        sitesWriter.flushSync()
        jobsWriter.flushSync()
    }
}
