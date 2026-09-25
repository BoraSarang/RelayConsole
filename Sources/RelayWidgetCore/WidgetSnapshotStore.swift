import Foundation

/// App Group 공유 저장소 — 앱(비샌드박스)이 쓰고 위젯(샌드박스 appex)이 읽음
/// 저장 형식은 JSON 파일 (UserDefaults suite 대비 sandbox 경계에서 경로 예측 가능 — 가이드 §2.2 App Group 패턴의 파일 구현체)
public enum WidgetSnapshotStore {
    /// App Group — 팀 ID 6GPJQ7BQC9 (가이드 `TEAMID.bundleid` 형식)
    public static let groupID = "6GPJQ7BQC9.com.borasarang.relayconsole"
    /// WidgetKit kind — 위젯 `StaticConfiguration(kind:)`와 반드시 동일
    public static let widgetKind = "RelayStatusWidget"
    public static let fileName = "widget-snapshot.json"

    /// 그룹 컨테이너 루트 — sandboxed 위젯은 containerURL, 비샌드박스 앱은 동일 경로 폴백
    public static func containerDir(fileManager: FileManager = .default) -> URL? {
        if let url = fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
            return url
        }
        let dir = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/\(groupID)", isDirectory: true)
        if fileManager.fileExists(atPath: dir.path) { return dir }
        do {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        } catch {
            return nil
        }
    }

    public static func fileURL(in dir: URL) -> URL {
        dir.appendingPathComponent(fileName, isDirectory: false)
    }

    /// 기록 — 실패 false (호출 측 DebugLogger 기록 · [표시②] 조용한 성공 금지)
    @discardableResult
    public static func write(_ snapshot: WidgetSnapshot, fileManager: FileManager = .default, baseDir: URL? = nil) -> Bool {
        guard let dir = baseDir ?? containerDir(fileManager: fileManager) else { return false }
        do {
            if !fileManager.fileExists(atPath: dir.path) {
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL(in: dir), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// 읽기 — 파일 없음/디코드 실패/미래스키마는 전부 nil (위젯은 빈 상태로 대체)
    public static func read(fileManager: FileManager = .default, baseDir: URL? = nil) -> WidgetSnapshot? {
        guard let dir = baseDir ?? containerDir(fileManager: fileManager) else { return nil }
        guard let data = try? Data(contentsOf: fileURL(in: dir)) else { return nil }
        guard let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return nil }
        guard snapshot.schema <= WidgetSnapshot.currentSchema else { return nil }
        return snapshot
    }
}
