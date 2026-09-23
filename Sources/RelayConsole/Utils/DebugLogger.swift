import Foundation
import Combine

enum DebugLogLevel: String {
    case action = "ACTION"
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"
    case system = "SYSTEM"
    case perf = "PERF"
    case cache = "CACHE"
}

struct DebugLogEntry: Identifiable {
    let id = UUID()
    let timestamp: String
    let level: DebugLogLevel
    let platform: String
    let category: String
    let message: String
    let meta: String?
}

@MainActor
final class DebugLogger: ObservableObject {
    static let shared = DebugLogger()
    @Published var logs: [DebugLogEntry] = []
    private let maxLogs = 5000

    private init() {}

    private func push(_ level: DebugLogLevel, category: String, message: String, meta: Any? = nil) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let entry = DebugLogEntry(
            timestamp: formatter.string(from: Date()),
            level: level,
            platform: "MACOS",
            category: category,
            message: message,
            meta: meta.map { "\($0)" }
        )
        #if DEBUG
        DispatchQueue.main.async {
            self.logs.append(entry)
            if self.logs.count > self.maxLogs { self.logs.removeFirst() }
        }
        #endif
        let metaStr = entry.meta.map { " | meta=\($0)" } ?? ""
        print("[\(entry.timestamp)] [\(entry.level.rawValue)] [\(entry.platform)] [\(entry.category)] \(message)\(metaStr)")
    }

    func action(_ category: String, _ message: String, meta: Any? = nil) { push(.action, category: category, message: message, meta: meta) }
    func info(_ category: String, _ message: String, meta: Any? = nil) { push(.info, category: category, message: message, meta: meta) }
    func warn(_ category: String, _ message: String, meta: Any? = nil) { push(.warn, category: category, message: message, meta: meta) }
    func error(_ category: String, _ message: String, meta: Any? = nil) { push(.error, category: category, message: message, meta: meta) }
    func system(_ category: String, _ message: String, meta: Any? = nil) { push(.system, category: category, message: message, meta: meta) }
    func perf(_ category: String, _ message: String, meta: Any? = nil) { push(.perf, category: category, message: message, meta: meta) }

    func clear() { logs.removeAll() }
}
