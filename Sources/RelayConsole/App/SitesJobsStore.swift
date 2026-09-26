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
        guard let data = try? Data(contentsOf: sitesURL) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([Site].self, from: data)) ?? []
    }

    func saveSites(_ sites: [Site]) {
        sitesWriter.submit(sites)
    }

    func loadJobs() -> [Job] {
        guard let data = try? Data(contentsOf: jobsURL) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([Job].self, from: data)) ?? []
    }

    func saveJobs(_ jobs: [Job]) {
        jobsWriter.submit(jobs)
    }

    /// 진행 중 쓰기를 동기 완료 — 앱 종료 전에 호출
    func flushSync() {
        sitesWriter.flushSync()
        jobsWriter.flushSync()
    }
}
