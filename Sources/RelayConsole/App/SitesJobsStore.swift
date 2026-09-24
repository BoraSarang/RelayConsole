import Foundation

/// Sites·Jobs JSON 영구화 (EventStore 패턴)
/// Application Support/RelayConsole/{sites,jobs}.json
@MainActor
final class SitesJobsStore {
    static let shared = SitesJobsStore()

    private let sitesURL: URL
    private let jobsURL: URL
    private let queue = DispatchQueue(label: "relay.sitesjobs", qos: .utility)

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("RelayConsole", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        sitesURL = dir.appendingPathComponent("sites.json")
        jobsURL = dir.appendingPathComponent("jobs.json")
    }

    func loadSites() -> [Site] {
        guard let data = try? Data(contentsOf: sitesURL) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([Site].self, from: data)) ?? []
    }

    func saveSites(_ sites: [Site]) {
        write(sites, to: sitesURL)
    }

    func loadJobs() -> [Job] {
        guard let data = try? Data(contentsOf: jobsURL) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([Job].self, from: data)) ?? []
    }

    func saveJobs(_ jobs: [Job]) {
        write(jobs, to: jobsURL)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys]
        guard let data = try? enc.encode(value) else { return }
        let target = url
        queue.async {
            try? data.write(to: target, options: .atomic)
        }
    }
}
