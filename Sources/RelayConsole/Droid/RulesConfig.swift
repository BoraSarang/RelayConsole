import Foundation

/// S3 — 관제 규칙을 **바깥에서** 정하게 한다 (로컬 YAML)
///
/// ## 왜 이 파일이 있나 (2026-09-28)
///
/// 규칙 **엔진은 이미 있다** — `WatchEngine` 이 규칙 7종을 먹고,
/// `ThresholdGate` 가 hysteresis·쿨다운을 처리한다. 없던 것은 **임계값의 입구**였다.
/// 그러므로 여기서는 **새 규칙을 만드는 것이 아니라**, 이미 있는 7종의 값을
/// 사용자가 덮어쓸 수 있게 한다. (디버그 못 하는 규칙은 없는 규칙이다)
///
/// ## ★ 이 파일이 막아야 하는 것 — 크래시
///
/// ```swift
/// // ThresholdGate.swift
/// precondition(enter > clear, "…hysteresis")   // 실패하면 즉시 죽는다
/// ```
/// 사용자가 `enter: 3 / clear: 5` 를 쓰면 **앱이 죽는다.**
/// 사용자가 쓴 파일 때문에 앱이 죽는 것은 허용할 수 없다 → **여기서 먼저 막는다.**
/// 파서가 아니라 **이 검증이 1순위**다.
///
/// ## 계약
///
/// 1. **파일이 없으면 지금과 완전히 동일**하게 동작한다 (선택 사항 · 없는 것은 정상)
/// 2. **모르는 키는 오류**다 (조용한 무시는 [표시②] 위반 — 사용자가 고쳐도 안 바뀌면 모른다)
/// 3. **값이 잘못되면 적용하지 않고 사유를 돌려준다** (조용히 기본값으로 대체하지 않는다)
/// 4. 파싱·검증은 **전부 여기서** 끝난다 — 그 뒤는 이미 안전한 값만 다룬다
struct RulesConfig: Equatable, Sendable {
    /// 규칙 7종 — 키 이름 = `WatchKind` 의 raw 값이라 오타가 곧 오류가 된다
    enum Kind: String, CaseIterable, Sendable {
        case throttling
        case chargeChanged
        case protectionChanged
        case lowPowerChanged
        case psiPressure
        case loadSpike
        case memoryLow

        /// 이 규칙이 임계값(hysteresis) 을 쓰나 — 아니면 전이만 보는가
        var usesThresholds: Bool {
            switch self {
            case .throttling, .psiPressure, .loadSpike, .memoryLow: return true
            case .chargeChanged, .protectionChanged, .lowPowerChanged: return false
            }
        }
    }

    /// 한 규칙의 임계값 — `enter > clear` 가 **불변식**이다
    struct Rule: Equatable, Sendable {
        var enter: Double
        var clear: Double
        var cooldown: TimeInterval

        /// 값이 유효한가 (유한수 + hysteresis + 쿨다운)
        var isValid: Bool {
            enter.isFinite && clear.isFinite && cooldown.isFinite
                && enter > clear && cooldown >= 0
        }
    }

    /// 배터리 **방치** 기준 — 잔량 임계 1개
    ///
    /// ## 왜 `Rule` 이 아닌가
    /// `Rule` 은 `enter > clear` hysteresis 불변식이 있는 구조다. 방치는
    /// **임계 1개**라 clear 가 없다. 억지로 넣으면 "가짜 clear" 를 만들어
    /// `precondition` 검증과 싸운다(S3 §15-1). **불변식이 겹치지 않게** 별도로 둔다.
    ///
    /// ## 왜 "얼마나 지속되면 위험한가" 는 앱이 정하지 않는가
    /// 그건 **모니터링 시스템의 일**이다. `/metrics` (PR #61) 로 초를 노출하면
    /// Prometheus 규칙에서 임계를 정할 수 있다. 앱에 `minutes` 를 넣으면
    /// **쓰이지 않는 설정**이 되어 dead config 가 된다 — 넣지 않는다.
    struct Battery: Equatable, Sendable {
        /// 방치로 볼 배터리 잔량(%) — 이 값 **이하** + 충전 중이 아닐 때
        var neglectPercent: Int

        /// 0 이면 "방치 없음" 이 아니라 **"배터리가 0 인 건 방치로 치지 않는다"** 라는 모호함이 생긴다
        static let percentRange = 1...100

        static let builtIn = Battery(neglectPercent: 20)

        var isValid: Bool { Self.percentRange.contains(neglectPercent) }
    }

    /// 코드에 박혀 있던 값이 곧 **기본값**이다 — YAML 이 없어도 이 값으로 동작한다
    static let builtIn: [Kind: Rule] = [
        .throttling: Rule(enter: 3, clear: 2, cooldown: 60),
        .psiPressure: Rule(enter: 5.0, clear: 3.0, cooldown: 120),
        .loadSpike: Rule(enter: 0, clear: 0, cooldown: 60),   // 0 = 코어수 파생값 (아래)
        .memoryLow: Rule(enter: 90, clear: 80, cooldown: 60),
        .chargeChanged: Rule(enter: 1, clear: 0, cooldown: 5),
        .protectionChanged: Rule(enter: 1, clear: 0, cooldown: 10),
        .lowPowerChanged: Rule(enter: 1, clear: 0, cooldown: 10),
    ]

    /// 사용자가 덮어쓴 값 (없으면 `builtIn`) — 몇 개가 적용됐는지 표시할 때 쓴다
    private(set) var overrides: [Kind: Rule]
    /// 배터리 방치 기준 — 사용자가 안 쓰면 `Battery.builtIn` (20% · 120분)
    public private(set) var battery: Battery = .builtIn
    /// 파싱은 성공했지만 **검증에서 걸린 항목** — 적용하지 않는다
    public private(set) var rejected: [String] = []
    /// 파일이 없었는가 — 없는 것은 **오류가 아니다**
    public private(set) var fileMissing: Bool = true

    init(overrides: [Kind: Rule] = [:], battery: Battery = .builtIn,
         rejected: [String] = [], fileMissing: Bool = true) {
        self.overrides = overrides
        self.battery = battery
        self.rejected = rejected
        self.fileMissing = fileMissing
    }

    /// 파일 없이 시작하는 구성 — **지금과 정확히 동일하게 동작한다**
    static var builtInConfig: RulesConfig { RulesConfig() }

    /// 배터리 방치 기준의 최종값 — **반환값은 언제나 유효하다** (검증이 앞에서 끝난다)
    func safeBattery() -> Battery {
        battery.isValid ? battery : Battery.builtIn
    }

    /// 규칙 하나의 최종 임계값
    ///
    /// - Parameter cores: `loadSpike` 만 사용 (기본값은 코어수 파생)
    /// - **반환값은 언제나 유효하다** — `precondition` 이 죽지 않도록 검증이 이 앞에서 끝난다
    func rule(_ kind: Kind, cores: Int = 0) -> Rule {
        var r = overrides[kind] ?? Self.builtIn[kind]!
        // loadSpike 는 파생값(코어수×2 / ×1)이 기본이다 — **값이 없을 때만** 파생한다
        if kind == .loadSpike, r.enter == 0, r.clear == 0 {
            let c = Double(max(cores, 1))
            r.enter = c * 2
            r.clear = c
        }
        return r
    }

    /// 안전성 **재확인** — 게이트를 만들기 직전에 한 번 더 본다.
    ///
    /// 파싱 검증이 통과했어도 이 불변식이 깨진 상태가 되면 `precondition` 이 죽으므로,
    /// **생성 전에 한 번만 더 막는다.** 반환값이 유효하지 않으면 기본값으로 되돌린다.
    func safeRule(_ kind: Kind, cores: Int = 0) -> Rule {
        let r = rule(kind, cores: cores)
        guard r.isValid else { return Self.builtIn[kind]! }
        return r
    }

    // MARK: - 파일

    /// 파일 위치 — 다른 스토어와 같은 폴더
    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("RelayConsole", isDirectory: true)
            .appendingPathComponent("rules.yaml")
    }

    /// 파일 크기 상한 — 무한정 파싱은 DoS 다. 사용자가 쓸 파일이 64KB 를 넘으면 이상하다
    static let maxBytes = 64 * 1024

    // MARK: - 파싱 (제한된 YAML)

    /// 파싱 결과 — 실패 사유를 **문자열로** 돌려준다 (화면과 로그가 같은 말을 쓴다)
    enum LoadResult: Equatable {
        case ok(RulesConfig)
        /// 파일이 없다 — **오류가 아니다**
        case missing
        case failed(String)
    }

    /// 규칙 본문 파싱 결과 (사유는 문자열 — 화면과 로그가 같은 말을 쓴다)
    enum BodyResult: Equatable {
        case ok(Rule)
        case rejected(String)
    }

    /// 배터리 본문 파싱 결과
    enum BatteryResult: Equatable {
        case ok(Battery)
        case rejected(String)
    }

    /// `battery: { neglectPercent: 20 }` 형태만 읽는다
    private static func parseBatteryBody(_ line: String, lineno: Int) -> BatteryResult {
        guard let open = line.firstIndex(of: "{"),
              let close = line.lastIndex(of: "}"), close > open
        else { return .rejected("중괄호 형태가 아님 (\(lineno)행)") }

        var b = Battery.builtIn
        for piece in line[line.index(after: open)..<close].split(separator: ",") {
            let p = piece.trimmingCharacters(in: .whitespaces)
            guard let colon = p.firstIndex(of: ":") else { continue }
            let key = p[p.startIndex..<colon].trimmingCharacters(in: .whitespaces)
            let val = p[p.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard key == "neglectPercent" else {
                return .rejected("모르는 키 `\(key)` (neglectPercent 만 가능)")
            }
            // 정수만 받는다 — 20.5% 같은 값은 "몇 퍼센트인지" 를 말하지 못한다
            guard let i = Int(val) else { return .rejected("`\(key)` 값이 정수가 아님: \(val)") }
            b.neglectPercent = i
        }
        guard b.isValid else {
            return .rejected("neglectPercent 가 \(Battery.percentRange) 범위가 아님: \(b.neglectPercent)")
        }
        return .ok(b)
    }

    static func load(from url: URL = defaultURL) -> LoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        guard let data = try? Data(contentsOf: url) else { return .failed("읽기 실패") }
        guard data.count <= maxBytes else {
            return .failed("파일이 너무 큼 (\(data.count)바이트 · 상한 \(maxBytes))")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            return .failed("UTF-8 아님")
        }
        return parse(text)
    }

    /// **제한된 YAML 파서** — 외부 라이브러리 없이, 이 앱이 필요한 형태만 읽는다.
    ///
    /// 지원: `version: 1` · `rules:` 아래 `이름: { enter: 3, clear: 2, cooldown: 60 }`
    /// 미지원(오류): 중첩 목록 · 앵커(&) · 태그 · 들여쓰기 없는 규칙 블록
    static func parse(_ text: String) -> LoadResult {
        var version: String?
        var inRules = false
        var inBattery = false
        var overrides: [Kind: Rule] = [:]
        var battery = Battery.builtIn
        var rejected: [String] = []

        for (lineno, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = stripComment(raw)
            if line.isEmpty { continue }

            // ── 최상위 섹션 전환 ──
            // ★ 한 줄짜리 본문(`battery: { ... }`)을 **스위치하면서 건너뛰지 않는다**
            //   — 건너뛰면 파싱은 "성공"인데 값이 적용되지 않는다(조용한 실패)
            var justEnteredBattery = false
            if line.hasPrefix("battery:") {
                inRules = false
                inBattery = true
                justEnteredBattery = true
            } else if line.hasPrefix("rules:") {
                inBattery = false
                inRules = true
                // 규칙은 줄마다 하나씩 이름을 갖는다 — 본문이 같은 줄에 없다
                continue
            } else if !inRules, !inBattery {
                if line.hasPrefix("version:") {
                    version = String(line.dropFirst("version:".count))
                        .trimmingCharacters(in: .whitespaces)
                } else if let key = topLevelKey(line) {
                    // 그 외 최상위 키는 모르는 것 — 조용히 넘기지 않는다
                    return .failed("모르는 최상위 키 `\(key)` (\(lineno + 1)행)")
                }
                continue
            }

            // ── battery 본문 ──
            if inBattery {
                let body = String(line.dropFirst("battery:".count))
                    .trimmingCharacters(in: .whitespaces)
                // `battery:` 만 있고 다음 줄에 중괄호가 오는 형태도 받는다
                let source = body.isEmpty ? line : "battery:" + body
                guard !justEnteredBattery || !body.isEmpty || line.contains("{") else { continue }
                switch parseBatteryBody(source, lineno: lineno + 1) {
                case .rejected(let why):
                    rejected.append("battery: \(why)")
                case .ok(let b):
                    battery = b
                }
                continue
            }

            let name = topLevelKey(line) ?? line
            guard let kind = Kind(rawValue: name) else {
                return .failed("모르는 규칙 `\(name)` (\(lineno + 1)행)")
            }
            switch parseRuleBody(line, kind: kind, lineno: lineno + 1) {
            case .rejected(let why):
                rejected.append("\(kind.rawValue): \(why)")
            case .ok(let rule):
                if rule.isValid {
                    overrides[kind] = rule
                } else {
                    // ★ 이것이 크래시가 날 지점이다 — 검증 없이 게이트를 만들지 않는다
                    rejected.append(
                        "\(kind.rawValue): enter(\(rule.enter)) > clear(\(rule.clear)) 여야하고 cooldown ≥ 0 이어야 한다")
                }
            }
        }

        if !inRules, !inBattery { return .failed("`rules:` 또는 `battery:` 블록이 없다") }
        if let version, version != "1" {
            return .failed("스키마 버전 \(version) 는 지원하지 않음 (1만 지원)")
        }
        return .ok(RulesConfig(overrides: overrides, battery: battery, rejected: rejected, fileMissing: false))
    }

    // MARK: - 파서 도우미

    private static func stripComment(_ s: Substring) -> String {
        guard let hash = s.firstIndex(of: "#") else { return s.trimmingCharacters(in: .whitespaces) }
        return s[s.startIndex..<hash].trimmingCharacters(in: .whitespaces)
    }

    private static func topLevelKey(_ line: String) -> String? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let k = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces)
        return k.isEmpty ? nil : k
    }

    /// `{ enter: 3, clear: 2, cooldown: 60 }` 형태만 읽는다
    private static func parseRuleBody(_ line: String, kind: Kind, lineno: Int) -> BodyResult {
        guard let open = line.firstIndex(of: "{"),
              let close = line.lastIndex(of: "}"), close > open
        else { return .rejected("중괄호 형태가 아님 (\(lineno)행)") }

        var values: [String: Double] = [:]
        for piece in line[line.index(after: open)..<close].split(separator: ",") {
            let p = piece.trimmingCharacters(in: .whitespaces)
            guard let colon = p.firstIndex(of: ":") else { continue }
            let key = p[p.startIndex..<colon].trimmingCharacters(in: .whitespaces)
            let val = p[p.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard ["enter", "clear", "cooldown"].contains(key) else {
                return .rejected("모르는 키 `\(key)` (enter/clear/cooldown 만 가능)")
            }
            guard let d = Double(val) else { return .rejected("`\(key)` 값이 숫자가 아님: \(val)") }
            values[key] = d
        }
        guard let cooldown = values["cooldown"] else {
            return .rejected("cooldown 이 없다 (전이 전용 규칙이라도 필요)")
        }
        // 전이 전용 규칙은 enter/clear 를 쓰지 않는다 → 규칙 종류에 맞는 기본값을 채운다
        let enter = values["enter"] ?? (kind.usesThresholds ? Double.nan : 1)
        let clear = values["clear"] ?? (kind.usesThresholds ? Double.nan : 0)
        return .ok(Rule(enter: enter, clear: clear, cooldown: cooldown))
    }
}
