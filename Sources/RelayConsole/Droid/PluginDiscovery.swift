import Foundation

/// 플러그인 계약 파서 — 순수 함수 (IO 없음, 테스트 대상)
/// 계약 원천: SpotShift `docs/PLUGIN_CONTRACT.md` v1.1
/// 실측 형식 (2026-10-08, SM-S901N):
///   `[PLUGIN] version=1 actions=autorotate logTag=SpotShift allowed=true`
///   `[REMOTE] 원격 변경 결과 changed=true 118.235.3.241 → 39.7.46.252 측정 2.16Mbps ≥ 기준 2.0Mbps — 달성`
///   `[REMOTE] 거부됨 (연동 OFF)`
/// 1회 덤프에 여러 플러그인 응답이 섞여 오므로 logTag 로 귀속한다.
enum PluginDiscoveryLogic {
    struct Probe: Equatable, Sendable {
        var version: Int
        var actions: [String]
        var allowed: Bool
        /// `[PLUGIN]` 본문의 `logTag=` — 덤프 귀속용, 없으면 빈 문자열
        var logTag: String = ""
        /// `[PLUGIN]` 본문의 `appVersion=` (v2, L1부터 필수) — 없으면 빈 문자열
        var appVersion: String = ""
    }

    struct Field: Equatable, Sendable {
        var key: String
        var value: String
    }

    struct RemoteResult: Equatable, Sendable {
        /// `[REMOTE] action=` (v2 필수, v1 SpotShift형엔 없음)
        var action: String?
        /// v1 SpotShift형 `changed=` — 있으면 IP 전이형 표시
        var changed: Bool?
        /// v2 `ok=` — changed형에도 있으면 함께 파싱
        var ok: Bool?
        var oldIp: String?
        var newIp: String?
        var errorCode: String?
        /// IP 뒤·`note=` 뒤 꼬리 원문 — 그대로 보여준다
        var note: String
        /// 구조 필드 이외 `k=v` 토큰 — 제네릭 행 표시용
        var fields: [Field]
        var refused: Bool
        var raw: String
    }

    // MARK: - 설치 확인

    /// `pm list packages` 1회 출력에서 명찰 패키지가 있는가
    static func isInstalled(pmListText text: String, packageName: String) -> Bool {
        for line in text.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t == "package:\(packageName)" { return true }
        }
        return false
    }

    // MARK: - adb 인자 (실행은 Store, 계약 고정)

    /// 패키지 목록 1회 — 전 플러그인 설치 판정이 이 한 번으로 끝난다
    static func pmListArgs(serial: String) -> [String] {
        ["-s", serial, "shell", "pm", "list", "packages"]
    }

    /// L2 메타데이터 1행 조회 (`content query` 1발)
    static func infoQueryArgs(serial: String, packageName: String) -> [String] {
        ["-s", serial, "shell", "content", "query",
         "--uri", "content://\(packageName).plugin/info"]
    }

    /// 아이콘 캐시 경로 — 패키지 + 앱 버전 키 (버전 바뀌면 다시 받음)
    static func iconCacheURL(packageName: String, appVersion: String) -> URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let safeV = appVersion.replacingOccurrences(
            of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression
        )
        return base
            .appendingPathComponent("com.borasarang.relayconsole/plugin-icons", isDirectory: true)
            .appendingPathComponent("\(packageName)_\(safeV).png")
    }

    static func probeBroadcastArgs(serial: String, action: String, receiver: String) -> [String] {
        ["-s", serial, "shell", "am", "broadcast",
         "-a", action, "-n", receiver]
    }

    /// 로그 덤프 1회 — 등록된 태그를 `-s` 에 전부 실어 한 번에 긁는다.
    /// 빈 태그면 필터 없이 전체를 덤프한다 (파서가 마커 줄만 골라낸다).
    static func logcatDumpArgs(serial: String, logTags: [String]) -> [String] {
        var args = ["-s", serial, "shell", "logcat", "-d", "-s"]
        let tags = logTags.filter { !$0.isEmpty }
        if tags.isEmpty {
            args.append("*:V")
        } else {
            args += tags.map { "\($0):*" }
        }
        return args
    }

    static func actionStartArgs(
        serial: String, activity: String, key: String, value: String, asBool: Bool
    ) -> [String] {
        if asBool {
            return ["-s", serial, "shell", "am", "start",
                    "-n", activity, "--ez", key, value]
        }
        return ["-s", serial, "shell", "am", "start",
                "-n", activity, "--es", key, value]
    }

    /// 액션 호출 인자 조립 (순수 — 테스트 대상).
    /// broadcast는 `[(cmdKey, id)] + [(argKey, 값)]`, activity는 `[(key, 값)]`.
    /// 입력값 필요인데 비어 있으면 nil (호출자가 needInput 처리).
    static func invokeArgs(
        serial: String, action: PluginDescriptor.Action, input: String
    ) -> [String]? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        switch action.invoke {
        case .broadcast(let receiver, let broadcastAction, let cmdKey, let argKey):
            var extras = [(key: cmdKey, value: action.id, asBool: false)]
            if let argKey {
                let v: String
                switch action.value {
                case .fixed(let f): v = f
                case .input:
                    guard !trimmed.isEmpty else { return nil }
                    v = trimmed
                }
                extras.append((key: argKey, value: v, asBool: false))
            }
            return explicitBroadcastArgs(
                serial: serial, receiver: receiver, action: broadcastAction, extras: extras
            )
        case .activity(let component, let key):
            let v: String
            switch action.value {
            case .fixed(let f): v = f
            case .input:
                guard !trimmed.isEmpty else { return nil }
                v = trimmed
            }
            return actionStartArgs(serial: serial, activity: component, key: key, value: v, asBool: false)
        }
    }
    static func explicitBroadcastArgs(
        serial: String, receiver: String, action: String,
        extras: [(key: String, value: String, asBool: Bool)]
    ) -> [String] {
        var args = ["-s", serial, "shell", "am", "broadcast",
                    "-a", action, "-n", receiver]
        for e in extras {
            args += [e.asBool ? "--ez" : "--es", e.key, e.value]
        }
        return args
    }

    /// L2 메타데이터 1행 파서 — `Row: 0 label=… description=… contractVersion=… appVersion=… allowed=… iconBase64=… actionsJson=…`
    /// 값에 공백·콤마가 있어 키 순서 고정 분할로 자른다 (제공자 컬럼 순서 고정 전제).
    struct PluginMetadata: Equatable, Sendable {
        var label: String
        var description: String
        var appVersion: String
        var allowed: Bool
        var iconBase64: String
    }

    static func parseInfoRow(_ line: String) -> PluginMetadata? {
        func slice(from key: String, to next: String) -> String? {
            guard let r1 = line.range(of: key) else { return nil }
            let after = line[r1.upperBound...]
            if next.isEmpty { return String(after).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard let r2 = after.range(of: next) else { return nil }
            return String(after[after.startIndex..<r2.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // `, actionsJson=` 앞까지가 icon — 행 끝이 actionsJson이 아닐 수도 있어 뒤에서 자른다
        guard let label = slice(from: "label=", to: ", description="),
              let desc = slice(from: "description=", to: ", contractVersion="),
              let appVersion = slice(from: "appVersion=", to: ", allowed="),
              let allowedStr = slice(from: "allowed=", to: ", iconBase64="),
              let allowed = boolValue(allowedStr) else { return nil }
        var icon = ""
        if let r1 = line.range(of: "iconBase64=") {
            let after = String(line[r1.upperBound...])
            if let r2 = after.range(of: ", actionsJson=") {
                icon = String(after[after.startIndex..<r2.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                icon = after.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        guard !label.isEmpty else { return nil }
        return PluginMetadata(
            label: label, description: desc, appVersion: appVersion,
            allowed: allowed, iconBase64: icon
        )
    }

    /// base64 PNG → 바이트 (서명 검증만 — 표시는 AppKit이 파일에서 읽는다)
    static func pngBytes(base64: String) -> Data? {
        let clean = base64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let data = Data(base64Encoded: clean) else { return nil }
        let sig = Data([137, 80, 78, 71, 13, 10, 26, 10])
        guard data.prefix(8) == sig else { return nil }
        return data
    }

    // MARK: - 덤프 귀속

    /// logcat 줄의 TAG — `… I SpotShift: [REMOTE]…` → `SpotShift`
    static func lineTag(_ line: String, marker: String) -> String? {
        guard let r = line.range(of: ": \(marker)") else { return nil }
        let prefix = line[..<r.lowerBound]
        return prefix.split(whereSeparator: \.isWhitespace).last.map(String.init)
    }

    // MARK: - 프로브 파싱

    /// logcat 한 줄에서 `[PLUGIN] ...` 구간 파싱 — 접두(시각·pid·태그)가 붙어도 됨
    static func parseProbeLine(_ line: String) -> Probe? {
        guard let r = line.range(of: "[PLUGIN]") else { return nil }
        let body = String(line[r.upperBound...])
        guard let version = intField(body, key: "version="),
              let allowedStr = stringField(body, key: "allowed=") else { return nil }
        let allowed: Bool
        switch allowedStr.lowercased() {
        case "true": allowed = true
        case "false": allowed = false
        default: return nil
        }
        let actionsRaw = stringField(body, key: "actions=") ?? ""
        let actions = actionsRaw.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        let tag = stringField(body, key: "logTag=") ?? lineTag(line, marker: "[PLUGIN]") ?? ""
        let appVersion = stringField(body, key: "appVersion=") ?? ""
        return Probe(version: version, actions: actions, allowed: allowed, logTag: tag, appVersion: appVersion)
    }

    /// 덤프 전체에서 플러그인별 **마지막** 프로브 응답 — 같은 태그 최신 한 건이 진실
    static func parseProbeOutput(_ text: String) -> [String: Probe] {
        var out: [String: Probe] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let p = parseProbeLine(String(line)), !p.logTag.isEmpty else { continue }
            out[p.logTag] = p
        }
        return out
    }

    /// 이 프로브와 연동해도 되는가 — 버전·액션이 명단과 맞을 때만
    static func supports(_ probe: Probe, descriptor: PluginDescriptor) -> Bool {
        guard probe.version == descriptor.contractVersion else { return false }
        return !Set(probe.actions).intersection(descriptor.knownActionIds).isEmpty
    }

    // MARK: - 결과 파싱

    /// logcat 한 줄에서 `[REMOTE] ...` 구간 파싱 — v1 changed형·v2 ok형 모두
    static func parseRemoteLine(_ line: String) -> RemoteResult? {
        guard let r = line.range(of: "[REMOTE]") else { return nil }
        let body = String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        let raw = String(line)
        // 거부 — changed 없음
        if body.contains("거부됨") {
            return RemoteResult(
                action: nil, changed: nil, ok: nil, oldIp: nil, newIp: nil,
                errorCode: nil, note: body, fields: [], refused: true, raw: raw
            )
        }
        let action = stringField(body, key: "action=")
        let ok = boolField(body, key: "ok=")
        let errorCode = stringField(body, key: "errorCode=")
        // v1 changed형: `changed=true OLD → NEW note...` (IP 자리는 `-` 가능)
        if body.contains("changed=") {
            guard let changedStr = stringField(body, key: "changed="),
                  let changed = boolValue(changedStr) else { return nil }
            guard let cRange = body.range(of: "changed=") else { return nil }
            let after = body[cRange.upperBound...]
                .replacingOccurrences(of: changedStr, with: "", options: [], range: nil)
                .trimmingCharacters(in: .whitespaces)
            // 첫 토큰=구IP, `→`, 다음 토큰=신IP, 나머지=note
            let tokens = after.split(whereSeparator: \.isWhitespace).map(String.init)
            guard tokens.count >= 3, tokens[1] == "→" else { return nil }
            let oldIp = tokens[0] == "-" ? nil : tokens[0]
            let newIp = tokens[2] == "-" ? nil : tokens[2]
            let note = tokens.count > 3 ? tokens[3...].joined(separator: " ") : ""
            return RemoteResult(
                action: action, changed: changed, ok: ok, oldIp: oldIp, newIp: newIp,
                errorCode: errorCode, note: note,
                fields: extraFields(body, skip: ["action", "ok", "changed", "errorcode", "note"]),
                refused: false, raw: raw
            )
        }
        // v2 ok형: `action=… ok=… [errorCode=…] [note=…꼬리] [자유 k=v…]`
        guard let okStr = stringField(body, key: "ok="),
              let okValue = boolValue(okStr),
              action != nil else { return nil }
        let note: String
        if let nRange = body.range(of: "note=") {
            note = String(body[nRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        } else {
            note = ""
        }
        return RemoteResult(
            action: action, changed: nil, ok: okValue, oldIp: nil, newIp: nil,
            errorCode: errorCode, note: note,
            fields: extraFields(body, skip: ["action", "ok", "changed", "errorcode", "note"]),
            refused: false, raw: raw
        )
    }

    /// 구조 키를 제외한 `k=v` 토큰 — 제네릭 행 표시용 (값에 공백 없는 것만)
    private static func extraFields(_ body: String, skip: Set<String>) -> [Field] {
        var out: [Field] = []
        for token in body.split(whereSeparator: \.isWhitespace).map(String.init) {
            guard let eq = token.firstIndex(of: "=") else { continue }
            let k = String(token[token.startIndex..<eq])
            let v = String(token[token.index(after: eq)...])
            guard !k.isEmpty, !v.isEmpty, !skip.contains(k.lowercased()) else { continue }
            // `→` 같은 비 k=v 토큰·note 꼬리 오탐 방지 — 영문 키 + 값 형태만
            guard k.allSatisfy({ $0.isLetter || $0 == "_" }) else { continue }
            out.append(Field(key: k, value: v))
        }
        return out
    }

    private static func boolField(_ text: String, key: String) -> Bool? {
        stringField(text, key: key).flatMap(boolValue)
    }

    private static func boolValue(_ s: String) -> Bool? {
        switch s.lowercased() {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }

    /// 덤프 전체에서 플러그인별 **마지막** 결과 — 줄 TAG 로 귀속
    static func parseRemoteOutput(_ text: String) -> [String: RemoteResult] {
        var out: [String: RemoteResult] = [:]
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            guard let r = parseRemoteLine(line) else { continue }
            guard let tag = lineTag(line, marker: "[REMOTE]"), !tag.isEmpty else { continue }
            out[tag] = r
        }
        return out
    }

    // MARK: - 필드 추출

    private static func intField(_ text: String, key: String) -> Int? {
        guard let s = stringField(text, key: key) else { return nil }
        return Int(s)
    }

    /// `key=value` — 값은 공백·콤마·대괄호 전까지
    private static func stringField(_ text: String, key: String) -> String? {
        guard let r = text.range(of: key) else { return nil }
        let after = text[r.upperBound...]
        var end = after.endIndex
        for idx in after.indices {
            let c = after[idx]
            if c.isWhitespace || c == "," || c == "]" || c == "[" {
                // `actions=autorotate logTag=...` — actions 값은 공백 전까지
                // `allowed=true` 끝부분 — `]`·개행 전까지
                if key == "actions=", c.isWhitespace || c == "]" {
                    end = idx
                    break
                } else if key != "actions=" {
                    end = idx
                    break
                }
            }
        }
        let v = String(after[after.startIndex..<end]).trimmingCharacters(in: .whitespaces)
        return v.isEmpty ? nil : v
    }
}
