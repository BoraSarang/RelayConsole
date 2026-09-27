import Foundation

/// Localized string lookup for SwiftPM bundle (ko source, en secondary).
/// 진실원천은 `Sources/RelayConsole/Resources/{en,ko}.lproj/Localizable.strings` 다 (2026-09-28).
/// - `Bundle.module.localizedString` 는 **번들 안의 `<lang>.lproj/Localizable.strings` 만** 읽는다
/// - 구 `Resources/Localizable.xcstrings`(612키로 낙오) 는 읽는 코드가 없었고 2026-09-28 에 삭제했다.
///   여기를 고쳐도 아무 일도 일어나지 않는 함정이었기 때문이다 — 키는 위 `.lproj` 에서 고칠 것.
enum L10n {
    static func string(_ key: String) -> String {
        Bundle.module.localizedString(forKey: key, value: key, table: nil)
    }

    /// 포맷 문자열의 변환자를 **실제 인자 타입에 맞춰 교정**한 뒤 `String(format:)` 을 부른다.
    ///
    /// ## 왜 이 단계가 필요한가 (2026-09-27 실측 크래시)
    ///
    /// `"수신 %@줄"` 에 `Int` 를 넣으면 CFString 포맷터가 그 정수를 **객체 포인터로 읽고**
    /// `_NSDescriptionWithStringProxyFunc` → `objc_opt_respondsToSelector` 로 0x8ad(=2221) 에
    /// 메시지를 보낸다. 결과: `EXC_BAD_ACCESS` / SIGSEGV.
    /// ```
    /// RelayConsole-2026-09-27-170630.ips
    ///   exception : EXC_BAD_ACCESS · KERN_INVALID_ADDRESS at 0x8ad
    ///   frames    : L10n.format(_:_:) ← closure in LogViewerContent.header.getter
    /// ```
    /// 즉 **"`%@` 에는 문자열을 넣어야 한다" 는 사람이 지키는 약속이 아니라 런타임 지뢰**다.
    /// 호출부 검수는 사람이 빠뜨리면 그대로 터지므로, 포맷터가 스스로 맞춘다.
    static func format(_ key: String, _ args: CVarArg...) -> String {
        formatted(key, args)
    }

    /// 배열 형태 — 판단 함수가 `(키, 인자)` 튜플을 그대로 돌려줄 때 쓴다
    static func format(_ key: String, _ args: [CVarArg]) -> String {
        formatted(key, args)
    }

    private static func formatted(_ key: String, _ args: [CVarArg]) -> String {
        let fmt = string(key)
        // 인자가 없으면 포맷터를 아예 돌리지 않는다 — 변환자를 그대로 보여주는 편이 낫다
        // (va_list 를 넘겨 읽으면 알 수 없는 값이 찍힌다)
        guard !args.isEmpty else { return fmt }
        return String(format: aligned(fmt, args: args), locale: Locale.current, arguments: args)
    }

    static var na: String { string("common.na") }

    // MARK: - 변환자 스캔 (테스트에서 직접 검증한다)

    /// 포맷 문자열 조각 — `conv` 가 nil 이면 **변환자가 아니다**(예: "50% 이상" 의 `%`).
    /// `%%` 도 여기에 속한다 — 리터럴로 통과시키고 인자를 소비하지 않는다.
    struct Piece {
        let literal: String   // 변환자 앞 일반 텍스트
        let spec: String      // "%" + 플래그 · 폭 · 정밀도 (변환자가 없으면 "")
        let conv: Character?  // nil = 리터럴
    }

    /// 인자를 읽는 변환자 — 문자열이 이 자리에 오면 **포인터가 그대로** 찍힌다
    static let intConversions: Set<Character> = ["d", "D", "i", "u", "U", "x", "X", "o", "O", "c", "s"]
    /// 실수를 읽는 변환자
    static let floatConversions: Set<Character> = ["f", "F", "e", "E", "g", "G", "a", "A"]
    static let knownConversions: Set<Character> = intConversions.union(floatConversions).union(["@"])

    /// 포맷 문자열을 왼쪽부터 훑어 조각으로 분해한다.
    static func pieces(of fmt: String) -> [Piece] {
        var out: [Piece] = []
        var literal = ""
        var i = fmt.startIndex
        while i < fmt.endIndex {
            guard fmt[i] == "%" else {
                literal.append(fmt[i])
                i = fmt.index(after: i)
                continue
            }
            // "%" + 플래그 · 폭 · 정밀도
            var spec = "%"
            var j = fmt.index(after: i)
            while j < fmt.endIndex, "-+ #0".contains(fmt[j]) {
                spec.append(fmt[j])
                j = fmt.index(after: j)
            }
            while j < fmt.endIndex, fmt[j].isNumber {
                spec.append(fmt[j])
                j = fmt.index(after: j)
            }
            if j < fmt.endIndex, fmt[j] == "." {
                spec.append(".")
                j = fmt.index(after: j)
                while j < fmt.endIndex, fmt[j].isNumber {
                    spec.append(fmt[j])
                    j = fmt.index(after: j)
                }
            }
            // 뒤가 없거나 변환자가 아니면 리터럴로 통과시킨다
            guard j < fmt.endIndex, knownConversions.contains(fmt[j]) else {
                literal += spec
                if j < fmt.endIndex {
                    literal.append(fmt[j])
                    j = fmt.index(after: j)
                }
                i = j
                continue
            }
            out.append(Piece(literal: literal, spec: spec, conv: fmt[j]))
            literal = ""
            i = fmt.index(after: j)
        }
        if !literal.isEmpty { out.append(Piece(literal: literal, spec: "", conv: nil)) }
        return out
    }

    /// 포맷 문자열이 **소비하는 인자 수** — 호출부 검수용 (테스트가 이 값을 대조한다)
    static func conversions(of fmt: String) -> [Character] {
        pieces(of: fmt).compactMap(\.conv)
    }

    // MARK: - 인자 정합

    private enum ArgKind { case object, integer, floating }

    private static func kind(of arg: CVarArg) -> ArgKind {
        if arg is any BinaryInteger { return .integer }
        if arg is any BinaryFloatingPoint { return .floating }
        return .object
    }

    /// 변환자 하나를 인자 타입에 맞는 것으로 바꾼다.
    private static func conversion(_ conv: Character, for kind: ArgKind) -> Character {
        switch kind {
        case .object:
            // 문자열을 %d 에 넣으면 포인터가 정수로 읽혀 화면에 주소값이 찍힌다
            return intConversions.contains(conv) || floatConversions.contains(conv) ? "@" : conv
        case .integer:
            // 숫자를 %@ 에 넣으면 객체를 로드하다 죽는다 (위 크래시) — %s 도 같은 결과
            if conv == "@" || conv == "s" { return "d" }
            // 정수를 %f 로 읽으면 64bit 를 double 로 재해석해 쓰레기가 나온다
            return floatConversions.contains(conv) ? "d" : conv
        case .floating:
            if conv == "@" || conv == "s" { return "f" }
            return intConversions.contains(conv) ? "f" : conv
        }
    }

    /// 포맷 문자열의 변환자를 인자 타입에 맞춰 바꾼다.
    ///
    /// - `%@` + 숫자 → `%d` / `%f`  → SIGSEGV 방지
    /// - `%d` + 문자열 → `%@`       → 주소값 출력 방지
    /// - `%s` + 숫자 → `%d`         → 동일 (포인터 역참조)
    /// - 인자가 남지 않은 변환자는 **통째로 버린다** — va_list 를 넘겨 읽지 않는다
    ///   (개수 불일치는 `L10nFormatTests` 의 전수 스캔이 잡는다)
    static func aligned(_ fmt: String, args: [CVarArg]) -> String {
        var out = ""
        var argIndex = 0
        for piece in pieces(of: fmt) {
            out += piece.literal
            guard let conv = piece.conv, argIndex < args.count else { continue }  // 리터럴·인자 없음
            out += piece.spec + String(conversion(conv, for: kind(of: args[argIndex])))
            argIndex += 1
        }
        return out
    }
}
