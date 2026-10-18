import Foundation

/// 번들 내보내기 — 순수 IO (테스트 대상)
///
/// ## 왜 "폴더 복사" 인가
///
/// 번들 = `manifest.json`(JSON) + logcat·dropbox(텍스트) + `screenshot.png`(이미지).
/// 내보내기의 목적은 **다른 곳에서 열어보는 것**이므로 원본 파일 그대로가 가장 정직하다
/// (다시 인코딩하면 무엇이 원본인지 흐려진다).
///
/// 단일 아카이브(zip)는 시스템 `ditto` 같은 **새 외부 프로세스**를 부려야 해서 의도적으로 뺐다 —
/// 이 앱의 외부 프로세스는 adb·scrcpy 둘로 못 박혀 있고, 그 목록은 공격면이기도 하다.
enum IncidentBundleExport {
    enum Failure: Error, Equatable {
        /// 대상 경로에 이미 뭔가 있다 (파일이든 디렉터리든) — **덮어쓰지 않는다**
        case destinationExists
        /// 내보낼 파일이 없다 (빈 디렉터리)
        case noFiles
    }

    /// 번들 디렉터리 → 대상 경로에 **폴더를 새로 만들어** 파일을 복사한다
    ///
    /// - Returns: 복사한 파일 이름 (정렬)
    /// - Throws: `Failure.destinationExists` · `Failure.noFiles` · 파일 IO 오류
    @discardableResult
    static func export(entry: IncidentBundleEntry, to destination: URL) throws -> [String] {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path) else { throw Failure.destinationExists }

        let names = ((try? fm.contentsOfDirectory(atPath: entry.url.path)) ?? [])
            .filter { !$0.hasPrefix(".") }
            .filter { name in
                var isDir: ObjCBool = false
                let path = entry.url.appendingPathComponent(name).path
                guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return false }
                return !isDir.boolValue
            }
            .sorted()
        guard !names.isEmpty else { throw Failure.noFiles }

        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        for name in names {
            try fm.copyItem(
                at: entry.url.appendingPathComponent(name),
                to: destination.appendingPathComponent(name)
            )
        }
        return names
    }
}
