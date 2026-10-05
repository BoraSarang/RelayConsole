import Foundation

/// 크래시 자동 진단 — 순수 파서 + 결과 모델 (PLAN_auto_diagnose Phase 1)
///
/// 실행(Runner)은 ConsoleStore가 트리거하고, 여기서 판단·파싱한다.
/// 원칙: package·exception이 없으면 진단하지 않는다 (추측 금지).
/// 무거운 명령(`dumpsys dropbox`)은 진단 시 1회만, 출력은 tail 8KB로 자른다.
struct DropboxCrash: Equatable, Sendable {
    /// `2026-10-05 01:23:06` (헤더 줄 원문)
    var at: String
    var package: String
    var foreground: Bool?
    /// `java.lang.RuntimeException: ...` 첫 줄 (120자 상한은 표시 측)
    var exceptionHead: String?
}

/// `dumpsys dropbox --print data_app_crash` 파서 — tail에서 최신순으로 뽑는다
enum CrashDropboxParser {
    /// 엔트리 헤더: `2026-10-05 01:23:06 data_app_crash (text, 2348 bytes)`
    static func parse(_ text: String) -> [DropboxCrash] {
        var out: [DropboxCrash] = []
        var cur: DropboxCrash?
        var exceptionFound = false

        func flush() {
            if let c = cur { out.append(c) }
            cur = nil
            exceptionFound = false
        }

        for raw in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.contains("data_app_crash (text,") && line.prefix(4).allSatisfy(\.isNumber) {
                flush()
                let stamp = line.components(separatedBy: " data_app_crash").first ?? ""
                cur = DropboxCrash(at: stamp, package: "", foreground: nil, exceptionHead: nil)
                continue
            }
            guard cur != nil else { continue }
            if line.hasPrefix("Package: ") {
                let rest = line.dropFirst("Package: ".count)
                cur?.package = rest.split(separator: " ").first.map(String.init) ?? ""
            } else if line.hasPrefix("Foreground: ") {
                cur?.foreground = line.dropFirst("Foreground: ".count) == "Yes"
            } else if !exceptionFound, looksLikeException(line) {
                cur?.exceptionHead = String(line.prefix(240))
                exceptionFound = true
            }
        }
        flush()
        return out.filter { !$0.package.isEmpty }
    }

    /// `com.foo.BarException: ...` / `...Error: ...` 첫 줄 판정
    static func looksLikeException(_ line: String) -> Bool {
        guard line.contains(":") else { return false }
        let head = line.prefix(while: { $0 != ":" })
        // `at android.app...` 스택 줄 제외 — `at ` 으로 시작하면 스택이다
        guard !line.hasPrefix("at ") else { return false }
        return head.contains(".") && (head.hasSuffix("Exception") || head.hasSuffix("Error") || head.hasSuffix("Throwable"))
    }
}

/// 진단 결과 — 지문 키로 DiagnoseStore에 영속, Alerts "진단" 섹션이 표시
struct CrashDiagnose: Codable, Equatable, Sendable {
    var fingerprint: String
    var package: String
    var exception: String
    var foreground: Bool?
    /// 7일 내 동일 패키지+예외 건수 (이번 포함)
    var count7d: Int
    /// dropbox 동일 패키지 최신 건 시각 원문 (없으면 nil — "없다"고 지어내지 않음)
    var dropboxAt: String?
    var diagnosedAt: Date
}

/// 빈도 집계 — 순수 함수 (메모리 이벤트 기준)
enum CrashFrequency {
    static func summarize(
        events: [WatchEvent],
        package: String,
        exception: String,
        now: Date = .now
    ) -> (count: Int, first: Date?) {
        let weekAgo = now.addingTimeInterval(-7 * 24 * 3600)
        let hits = events.filter {
            $0.kind == .crash && !$0.isClear
                && $0.packageName == package
                && ($0.exceptionClass ?? "") == exception
                && $0.at >= weekAgo
        }
        return (hits.count, hits.map(\.at).min())
    }
}
