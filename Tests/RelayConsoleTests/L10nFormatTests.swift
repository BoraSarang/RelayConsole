import Foundation
import Testing
@testable import RelayConsole

/// L10n 포맷 인자 정합 — 2026-09-27 로그 창 크래시 회귀
///
/// ## 사건
/// 로그 창을 열면 **즉시 크래시**했다. 크래시 리포트의 스택이 그대로 답이었다.
/// ```
/// RelayConsole-2026-09-27-170630.ips
///   exception  : EXC_BAD_ACCESS · KERN_INVALID_ADDRESS at 0x8ad
///   faulting   : com.apple.main-thread · far = 2221 (= 받은 줄 수)
///   frames     : objc_opt_respondsToSelector
///                ← _NSDescriptionWithStringProxyFunc
///                ← __CFStringAppendFormatCore
///                ← static L10n.format(_:_:)
///                ← closure #1 in LogViewerContent.header.getter
/// ```
/// 원인은 `"수신 %@줄"` 에 `Int` 를 넣은 한 줄이었다. `%@` 는 객체를 요구하는데
/// CFString 포맷터는 정수를 **포인터로** 읽었고, 2221(=0x8ad) 에 `objc_msgSend` 가 날아갔다.
///
/// 이 테스트는 ① 그 자리를 고친 상태를 ② 호출부 전수 스캔으로 지킨다.
struct L10nFormatTests {
    // MARK: - ① 크래시 회귀 (그 자리 그대로)

    @Test func intOnObjectPlaceholderDoesNotCrash() {
        let s = L10n.format("droid.logs.count", 2221)
        // 로케일 천단위 구분자("2,221")가 붙을 수 있으므로 숫자만 떼어 본다
        #expect(s.filter(\.isNumber) == "2221", "줄 수가 화면에 그대로 보여야 한다: \(s)")
    }

    @Test func int32OnObjectPlaceholderDoesNotCrash() {
        // 기기를 뽑으면 adb 가 0 으로 끝난다 — 정상 경로에서 이 자리가 계속 쓰인다
        #expect(L10n.format("droid.logs.term.exit", Int32(0)).contains("0"))
        #expect(L10n.format("droid.logs.term.signal", Int32(9)).contains("9"))
    }

    /// 숫자 자리는 `%d` 다 — `%@` 로 되돌리면 크래시가 되살아난다
    @Test func logNumberKeysUseNumericPlaceholders() {
        for key in ["droid.logs.count", "droid.logs.term.exit", "droid.logs.term.signal"] {
            #expect(L10n.string(key).contains("%d"), "숫자 키는 %d 여야 한다: \(key)")
            #expect(!L10n.string(key).contains("%@"), "'%@' 는 숫자를 담지 못한다: \(key)")
        }
    }

    // MARK: - ② 안전망 (호출부가 또 실수해도 죽지 않는다)

    @Test func stringOnNumericPlaceholderPrintsText() {
        // "HTTP %d" 에 문자열 → 화면에 주소값이 찍힌다 (크래시는 아니다)
        #expect(L10n.format("sites.fail.http", "timeout") == "HTTP timeout")
    }

    @Test func alignedConvertsPerArgumentType() {
        #expect(L10n.aligned("a %@ b", args: [1]) == "a %d b")
        #expect(L10n.aligned("a %@ b", args: [1.5]) == "a %f b")
        #expect(L10n.aligned("a %d b", args: ["x"]) == "a %@ b")
        #expect(L10n.aligned("a %s b", args: [7]) == "a %d b")
        #expect(L10n.aligned("a %f b", args: [7]) == "a %d b")
    }

    @Test func alignedKeepsWidthAndPrecision() {
        #expect(L10n.aligned("[%5@]", args: [42]) == "[%5d]")
        #expect(L10n.aligned("%.1f%%", args: [1.25]) == "%.1f%%")
    }

    @Test func barePercentIsLiteralAndEatsNoArgument() {
        #expect(L10n.aligned("50% 이상", args: [1]) == "50% 이상")
        #expect(L10n.aligned("100%%", args: [1]) == "100%%")
        #expect(L10n.conversions(of: "50% 이상") == [])
        #expect(L10n.conversions(of: "100%%") == [])
    }

    @Test func missingArgumentIsDroppedNotOverread() {
        // va_list 를 넘겨 읽지 않는다 — 개수 불일치는 아래 전수 스캔이 잡는다
        #expect(L10n.aligned("a %@ b %@ c", args: ["only"]) == "a %@ b  c")
        #expect(L10n.aligned("%@%@", args: []) == "")
    }

    @Test func formatWithoutArgsKeepsPlaceholders() {
        #expect(L10n.format("droid.logs.count") == L10n.string("droid.logs.count"))
    }

    // MARK: - ③ 전수 스캔 (호출부 ↔ 문자열 대조)

    /// 소스 위치 — `Tests/RelayConsoleTests/<파일>` 에서 3단계 위 = 저장소 루트
    private static var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// en/ko 문자열 표 — **다른 테스트도 재사용한다** (같은 파서를 두 번 쓰면 표가 갈라진다)
    static func stringsTable(_ lproj: String) throws -> [String: String] {
        let url = root
            .appendingPathComponent("Sources/RelayConsole/Resources")
            .appendingPathComponent("\(lproj).lproj/Localizable.strings")
        var table: [String: String] = [:]
        for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("\""), let eq = t.range(of: "\" = \"") else { continue }
            let key = String(t[t.index(t.startIndex, offsetBy: 1)..<eq.lowerBound])
            let rest = t[eq.upperBound...]
            guard rest.hasSuffix("\";") else { continue }
            table[key] = String(rest.dropLast(2))
        }
        return table
    }

    private static func swiftSources() throws -> [URL] {
        let fm = FileManager.default
        let dir = root.appendingPathComponent("Sources")
        guard let walker = fm.enumerator(at: dir, includingPropertiesForKeys: nil) else { return [] }
        var out: [URL] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            out.append(url)
        }
        return out
    }

    /// `L10n.format("키"[, 인자…])` 호출부를 훑는다 — 스프레드(`…인자`) 호출은 건너뛴다
    private static func formatCalls(in src: String) -> [(key: String, args: [String], line: Int)] {
        // 주석 줄에 적힌 예시는 호출부가 아니다 — `/// L10n.format("briefing.line", …)`
        var scan = ""
        var isFirst = true
        for line in src.split(separator: "\n", omittingEmptySubsequences: false) {
            scan += isFirst ? "" : "\n"
            isFirst = false
            scan += line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
                ? String(repeating: " ", count: line.count)
                : String(line)
        }
        func trimmed(_ range: Range<String.Index>) -> String {
            String(scan[range].trimmingCharacters(in: .whitespacesAndNewlines))
        }
        var out: [(key: String, args: [String], line: Int)] = []
        var search = scan.startIndex
        while let open = scan.range(of: "L10n.format(", range: search..<scan.endIndex) {
            search = open.upperBound
            var i = open.upperBound
            while i < scan.endIndex, scan[i].isWhitespace { i = scan.index(after: i) }
            guard i < scan.endIndex, scan[i] == "\"" else { continue }   // 키가 문자열이 아니면 무시
            var key = ""
            i = scan.index(after: i)
            while i < scan.endIndex, scan[i] != "\"" {
                key.append(scan[i])
                i = scan.index(after: i)
            }
            guard i < scan.endIndex else { continue }                     // 닫는 따옴표 없음
            i = scan.index(after: i)
            while i < scan.endIndex, scan[i].isWhitespace { i = scan.index(after: i) }
            guard i < scan.endIndex, scan[i] == "," else { continue }      // 인자 없는 호출
            var args: [String] = []
            var last = scan.index(after: i)
            var depth = 0
            var j = last
            while j < scan.endIndex {
                let c = scan[j]
                if "([{".contains(c) {
                    depth += 1
                } else if ")]}".contains(c) {
                    if depth == 0 { break }                               // 호출 닫는 괄호
                    depth -= 1
                } else if c == ",", depth == 0 {
                    args.append(trimmed(last..<j))
                    last = scan.index(after: j)
                }
                j = scan.index(after: j)
            }
            guard depth == 0, j < scan.endIndex else { continue }         // 괄호가 안 닫힘
            args.append(trimmed(last..<j))
            if args.contains(where: { $0.hasPrefix("...") }) { continue }  // 스프레드는 개수를 알 수 없다
            out.append((key, args, scan[..<open.lowerBound].split(separator: "\n").count + 1))
        }
        return out
    }

    /// en 과 ko 의 변환자 나열이 같아야 한다 — 한쪽만 고치면 그 로케일에서 크래시가 되살아난다
    @Test func enAndKoPlaceholdersAreIdentical() throws {
        let ko = try Self.stringsTable("ko")
        let en = try Self.stringsTable("en")
        for (key, koValue) in ko {
            let enValue = try #require(en[key], "en 키 누락: \(key)")
            let a = L10n.conversions(of: koValue)
            let b = L10n.conversions(of: enValue)
            #expect(a == b, "\(key) 변환자 불일치 — ko \(a) vs en \(b)")
        }
    }

    @Test func everyFormatCallArityMatchesPlaceholders() throws {
        let ko = try Self.stringsTable("ko")
        var checked = 0
        var violations: [String] = []
        for url in try Self.swiftSources() {
            let src = try String(contentsOf: url, encoding: .utf8)
            let rel = url.path.replacingOccurrences(of: Self.root.path + "/", with: "")
            for call in Self.formatCalls(in: src) {
                guard let value = ko[call.key] else { continue }
                let need = L10n.conversions(of: value).count
                if call.args.count != need {
                    violations.append("\(rel):\(call.line) \(call.key) — 인자 \(call.args.count)개 / 변환자 \(need)개")
                }
                checked += 1
            }
        }
        #expect(checked > 50, "호출부를 제대로 못 찾았다: \(checked)건")
        #expect(violations.isEmpty, "인자 개수 불일치:\n\(violations.joined(separator: "\n"))")
    }

    /// `%@` 자리에 숫자가 들어가면 크래시 — 인자가 숫자처럼 보이는 표현이면 잡아낸다
    @Test func objectPlaceholdersNeverReceiveNumericLookingArgs() throws {
        let ko = try Self.stringsTable("ko")
        // 숫자임이 확실한 이름만 — 추측으로 넓히면 오탐이 늘어난다
        let numericNames: Set<String> = ["count", "totalLines", "rawValue", "status"]
        var violations: [String] = []
        for url in try Self.swiftSources() {
            let src = try String(contentsOf: url, encoding: .utf8)
            let rel = url.path.replacingOccurrences(of: Self.root.path + "/", with: "")
            for call in Self.formatCalls(in: src) {
                guard let value = ko[call.key] else { continue }
                let convs = L10n.conversions(of: value)
                for (i, arg) in call.args.enumerated() {
                    guard i < convs.count, convs[i] == "@" else { continue }
                    let head = arg.split(separator: ".").last.map(String.init) ?? arg
                    let numeric = !arg.isEmpty && (numericNames.contains(head) || arg.allSatisfy(\.isNumber))
                    if numeric {
                        violations.append("\(rel):\(call.line) \(call.key) — '%@' 에 \(arg)")
                    }
                }
            }
        }
        #expect(
            violations.isEmpty,
            "'%@' 는 객체를 읽는다 — 숫자를 넣으면 SIGSEGV:\n\(violations.joined(separator: "\n"))"
        )
    }
}

/// 앱 언어 결정 — 기본 시스템 추종, 지원 밖이면 영어, 수동 지정 우선
struct AppLanguageTests {
    private func withOverride(_ v: String?, _ body: () -> String) -> String {
        let key = L10n.languageKey
        let prev = UserDefaults.standard.object(forKey: key)
        if let v { UserDefaults.standard.set(v, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
        defer {
            if let prev { UserDefaults.standard.set(prev, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        return body()
    }

    @Test func manualOverrideWins() {
        #expect(withOverride("ko") { L10n.currentLanguage(system: ["en"]) } == "ko")
        #expect(withOverride("en") { L10n.currentLanguage(system: ["ko"]) } == "en")
    }

    @Test func systemLanguageFollowed() {
        #expect(withOverride(nil) { L10n.currentLanguage(system: ["ko-KR"]) } == "ko")
        #expect(withOverride(nil) { L10n.currentLanguage(system: ["en-GB"]) } == "en")
        #expect(withOverride(nil) { L10n.currentLanguage(system: ["ja", "ko"]) } == "ko")
    }

    @Test func unsupportedSystemFallsBackToEnglish() {
        #expect(withOverride(nil) { L10n.currentLanguage(system: ["fr-FR", "de"]) } == "en")
        #expect(withOverride(nil) { L10n.currentLanguage(system: []) } == "en")
    }

    @Test func invalidOverrideFallsThroughToSystem() {
        #expect(withOverride("xx") { L10n.currentLanguage(system: ["ko"]) } == "ko")
    }
}
