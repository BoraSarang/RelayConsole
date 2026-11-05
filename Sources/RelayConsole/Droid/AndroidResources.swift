import Foundation

// MARK: - Android 바이너리 XML (AndroidManifest.xml)

/// 안드로이드 바이너리 XML 최소 파서 — 매니페스트에서 **패키지명·버전·아이콘 리소스 ID** 만 뽑는다.
///
/// 왜 직접 파싱하는가: 외부 도구(aapt)를 부를 수 없고(외부 프로세스는 adb·scrcpy 로 제한),
/// APK 안의 `AndroidManifest.xml` 은 텍스트가 아니라 청크 포맷이기 때문이다.
/// 필요한 필드만 읽고, 형식이 예상과 다르면 **nil 로 물러난다**(아이콘은 타일로 폴백).
enum AndroidBinaryXML {
    struct Info: Equatable, Sendable {
        var packageName: String?
        var versionName: String?
        var versionCode: Int64?
        var iconResId: UInt32?
        var roundIconResId: UInt32?
        /// `android:label` 의 문자열 리소스 ID (`@string/app_name`)
        var labelResId: UInt32?
        /// `android:label="Foo"` 처럼 리소스가 아닌 **직접 문자열**인 경우
        var labelText: String?
    }

    // android: 속성 리소스 ID
    private static let attrLabel: UInt32 = 0x0101_0001
    private static let attrIcon: UInt32 = 0x0101_0002
    private static let attrRoundIcon: UInt32 = 0x0101_052c
    private static let attrVersionCode: UInt32 = 0x0101_021b
    private static let attrVersionName: UInt32 = 0x0101_021c

    private static let typeString: UInt16 = 0x0001
    private static let typeResourceMap: UInt16 = 0x0180
    private static let typeStartElement: UInt16 = 0x0102

    static func parse(_ data: Data) -> Info? {
        let b = [UInt8](data)
        guard b.count >= 8, u16(b, 0) == 0x0003 else { return nil }
        let declared = Int(u32(b, 4))
        let end = min(b.count, declared >= 8 ? declared : b.count)

        var strings: [String] = []
        var resourceMap: [UInt32] = []
        var info = Info()
        var offset = Int(u16(b, 2))
        if offset < 8 { offset = 8 }

        while offset + 8 <= end {
            let type = u16(b, offset)
            let size = Int(u32(b, offset + 4))
            guard size >= 8, offset + size <= end else { break }
            switch type {
            case typeString:
                if strings.isEmpty { strings = parseStringPool(b, at: offset, limit: offset + size) }
            case typeResourceMap:
                resourceMap = parseResourceMap(b, at: offset, limit: offset + size)
            case typeStartElement:
                parseStartElement(
                    b,
                    at: offset,
                    limit: offset + size,
                    strings: strings,
                    resourceMap: resourceMap,
                    info: &info
                )
            default:
                break
            }
            offset += size
        }
        if info.packageName == nil, info.iconResId == nil, info.versionName == nil {
            return nil
        }
        return info
    }

    // MARK: 범용 트리 (벡터·어댑티브 아이콘 XML)

    /// AXML 한 장을 **요소 트리**로 읽는다. 매니페스트 파서(`parse`)와 달리
    /// 어떤 XML(벡터 드로어블·어댑티브 아이콘·레이어 목록)에도 쓴다.
    struct Node: Equatable, Sendable {
        var name: String = ""
        var attributes: [String: ResourceValue] = [:]
        var children: [Node] = []

        func attribute(_ name: String) -> ResourceValue? { attributes[name] }
    }

    static func parseTree(_ data: Data) -> Node? {
        let b = [UInt8](data)
        guard b.count >= 8, u16(b, 0) == 0x0003 else { return nil }
        let declared = Int(u32(b, 4))
        let end = min(b.count, declared >= 8 ? declared : b.count)

        var strings: [String] = []
        var resourceMap: [UInt32] = []
        var stack: [Node] = []
        var root: Node?
        var offset = Int(u16(b, 2))
        if offset < 8 { offset = 8 }

        while offset + 8 <= end {
            let type = u16(b, offset)
            let size = Int(u32(b, offset + 4))
            guard size >= 8, offset + size <= end else { break }
            switch type {
            case typeString:
                if strings.isEmpty { strings = parseStringPool(b, at: offset, limit: offset + size) }
            case typeResourceMap:
                resourceMap = parseResourceMap(b, at: offset, limit: offset + size)
            case typeStartElement:
                if let node = parseElement(
                    b,
                    at: offset,
                    limit: offset + size,
                    strings: strings,
                    resourceMap: resourceMap
                ) {
                    stack.append(node)
                }
            case 0x0103:                                     // END_ELEMENT
                if let node = stack.popLast() {
                    if stack.isEmpty { root = node } else { stack[stack.count - 1].children.append(node) }
                }
            default:
                break
            }
            offset += size
        }
        if root == nil, let first = stack.first { root = first }
        return root
    }

    private static func parseElement(
        _ b: [UInt8],
        at offset: Int,
        limit: Int,
        strings: [String],
        resourceMap: [UInt32]
    ) -> Node? {
        guard offset + 36 <= limit else { return nil }
        guard let name = string(strings, u32(b, offset + 20)) else { return nil }
        let attributeStart = Int(u16(b, offset + 24))
        let attributeSize = Int(u16(b, offset + 26))
        let attributeCount = Int(u16(b, offset + 28))
        var node = Node(name: name)
        let base = offset + 16 + attributeStart
        for i in 0..<attributeCount {
            let a = base + i * max(attributeSize, 20)
            guard a + 20 <= limit else { break }
            let nameIdx = u32(b, a + 4)
            let rawIdx = u32(b, a + 8)
            let dataType = b[a + 15]
            let data = u32(b, a + 16)
            guard let attrName = string(strings, nameIdx), !attrName.isEmpty else { continue }
            if let value = ResourceValue.decode(type: dataType, data: data, strings: strings) {
                node.attributes[attrName] = value
            } else if rawIdx != 0xFFFF_FFFF, let raw = string(strings, rawIdx), !raw.isEmpty {
                node.attributes[attrName] = .text(raw)
            }
        }
        return node
    }

    // MARK: 청크 내부

    private static func parseStartElement(
        _ b: [UInt8],
        at offset: Int,
        limit: Int,
        strings: [String],
        resourceMap: [UInt32],
        info: inout Info
    ) {
        guard offset + 36 <= limit else { return }
        let nameIndex = u32(b, offset + 20)
        let attributeStart = Int(u16(b, offset + 24))
        let attributeSize = Int(u16(b, offset + 26))
        let attributeCount = Int(u16(b, offset + 28))
        let element = string(strings, nameIndex)

        var values: [UInt32: UInt32] = [:]       // resId → typed data
        var rawStrings: [UInt32: String] = [:]   // resId → rawValue 문자열
        var plainStrings: [String: String] = [:] // 네임스페이스 없는 속성 이름 → 값

        // `attributeStart` 는 **attrExt 구조 시작 기준** 오프셋이다 (보통 20).
        // attrExt 는 노드 헤더(16바이트: chunk header 8 + lineNumber 4 + comment 4) 뒤에 온다.
        // 따라서 절대 위치 = offset + 16 + attributeStart.
        let base = offset + 16 + attributeStart
        for i in 0..<attributeCount {
            let a = base + i * max(attributeSize, 20)
            guard a + 20 <= limit else { break }
            let nameIdx = u32(b, a + 4)
            let rawIdx = u32(b, a + 8)
            let dataType = b[a + 15]
            let value = u32(b, a + 16)
            let attrName = string(strings, nameIdx) ?? ""
            let resId = nameIdx < resourceMap.count ? resourceMap[Int(nameIdx)] : 0

            let text: String? = {
                if dataType == 0x03 { return string(strings, value) }
                if rawIdx != 0xFFFF_FFFF { return string(strings, rawIdx) }
                return nil
            }()

            if resId != 0 {
                values[resId] = value
                if let text { rawStrings[resId] = text }
            } else if !attrName.isEmpty, let text {
                plainStrings[attrName] = text
            }
        }

        switch element {
        case "manifest":
            if info.packageName == nil { info.packageName = plainStrings["package"] }
            if info.versionName == nil {
                info.versionName = rawStrings[attrVersionName]
                    ?? plainStrings["versionName"]
            }
            if info.versionCode == nil {
                if let code = values[attrVersionCode] ?? UInt32(plainStrings["versionCode"] ?? "") {
                    info.versionCode = Int64(code)
                }
            }
        case "application":
            if info.iconResId == nil, values[attrIcon] != nil {
                info.iconResId = values[attrIcon]
            }
            if info.roundIconResId == nil, values[attrRoundIcon] != nil {
                info.roundIconResId = values[attrRoundIcon]
            }
            if info.labelResId == nil, let id = values[attrLabel] {
                info.labelResId = id
            }
            // 리소스 참조가 아니라 직접 적힌 이름 (`@` 로 시작하지 않는 값만)
            if info.labelText == nil, let text = rawStrings[attrLabel],
               !text.hasPrefix("@") {
                info.labelText = text
            }
        default:
            break
        }
    }

    static func parseStringPool(_ b: [UInt8], at offset: Int, limit: Int) -> [String] {
        guard offset + 28 <= limit else { return [] }
        let count = Int(u32(b, offset + 8))
        let flags = u32(b, offset + 16)
        let stringsStart = Int(u32(b, offset + 20))
        let isUTF8 = flags & 0x100 != 0
        // 삼성 시스템 앱 실측 230,461개 — 100,000 상한에 걸려 풀이 통째로 비었다.
        // 실제 방어선은 아래 `offsetsStart + count * 4 <= limit` (파일 크기) 이다.
        guard count >= 0, count <= 2_000_000 else { return [] }
        let offsetsStart = offset + Int(u16(b, offset + 2))
        guard offsetsStart + count * 4 <= limit else { return [] }
        let base = offset + stringsStart
        guard base >= offset, base <= limit else { return [] }

        var out: [String] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            let rel = Int(u32(b, offsetsStart + i * 4))
            var p = base + rel
            guard p < limit else { out.append(""); continue }
            if isUTF8 {
                // UTF-8 풀은 길이가 **두 개**다: 문자 수(UTF-16 length) → 바이트 수.
                // 하나만 읽으면 바이트 수를 문자열 첫 글자로 먹어 경로가 한 글자씩 밀린다
                // (`res/…png` → `\nres/….pn`). 2026-10-24 실기기 아이콘 실패의 원인.
                let (_, usedChars) = utf8Length(b, at: p, limit: limit)
                p += usedChars
                let (byteLen, usedBytes) = utf8Length(b, at: p, limit: limit)
                p += usedBytes
                guard byteLen >= 0, p + byteLen <= limit else { out.append(""); continue }
                out.append(String(decoding: b[p..<(p + byteLen)], as: UTF8.self))
            } else {
                let (len, used) = utf16Length(b, at: p, limit: limit)
                p += used
                guard len >= 0, p + len * 2 <= limit else { out.append(""); continue }
                var units: [UInt16] = []
                units.reserveCapacity(len)
                for j in 0..<len {
                    units.append(UInt16(b[p + j * 2]) | (UInt16(b[p + j * 2 + 1]) << 8))
                }
                out.append(String(decoding: units, as: UTF16.self))
            }
        }
        return out
    }

    private static func parseResourceMap(_ b: [UInt8], at offset: Int, limit: Int) -> [UInt32] {
        let start = offset + Int(u16(b, offset + 2))
        guard start >= offset, start <= limit else { return [] }
        var out: [UInt32] = []
        var p = start
        while p + 4 <= limit {
            out.append(u32(b, p))
            p += 4
        }
        return out
    }

    private static func utf8Length(_ b: [UInt8], at p: Int, limit: Int) -> (Int, Int) {
        guard p < limit else { return (0, 1) }
        let first = b[p]
        if first & 0x80 != 0 {
            guard p + 1 < limit else { return (0, 2) }
            return ((Int(first & 0x7F) << 8) | Int(b[p + 1]), 2)
        }
        return (Int(first), 1)
    }

    private static func utf16Length(_ b: [UInt8], at p: Int, limit: Int) -> (Int, Int) {
        guard p + 1 < limit else { return (0, 2) }
        let first = u16(b, p)
        if first & 0x8000 != 0 {
            guard p + 3 < limit else { return (0, 4) }
            return ((Int(first & 0x7FFF) << 16) | Int(u16(b, p + 2)), 4)
        }
        return (Int(first), 2)
    }

    private static func string(_ table: [String], _ index: UInt32) -> String? {
        index < table.count ? table[Int(index)] : nil
    }

    static func u16(_ b: [UInt8], _ offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= b.count else { return 0 }
        return UInt16(b[offset]) | (UInt16(b[offset + 1]) << 8)
    }

    static func u32(_ b: [UInt8], _ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= b.count else { return 0 }
        return UInt32(b[offset])
            | (UInt32(b[offset + 1]) << 8)
            | (UInt32(b[offset + 2]) << 16)
            | (UInt32(b[offset + 3]) << 24)
    }
}

// MARK: - 리소스 값

/// `resources.arsc` · AXML 이 담는 **타입 있는 값**.
///
/// 아이콘(경로·색)과 앱 이름(문자열)을 같은 파서로 읽기 위해 필요한 만큼만 모델링한다.
/// 모르는 타입은 `nil` — 화면은 타일로 폴백한다.
enum ResourceValue: Equatable, Sendable {
    /// 파일 경로(`res/...png`) 또는 문자열 리소스 값
    case text(String)
    /// 다른 리소스 ID (`@drawable/x`)
    case reference(UInt32)
    /// 0xAARRGGBB
    case color(UInt32)
    case integer(Int64)
    case float(Float)
    /// 저작 단위 그대로 (dp ≈ viewport unit). 벡터 `strokeWidth` 등에 쓴다
    case dimension(Float)

    /// `Res_value` → 값. 문자열이 아닌 타입은 전부 여기서 해석한다.
    static func decode(type dataType: UInt8, data: UInt32, strings: [String]) -> ResourceValue? {
        switch dataType {
        case 0x00:                                   // TYPE_NULL
            return nil
        case 0x01:                                   // TYPE_REFERENCE
            return data == 0 ? nil : .reference(data)
        case 0x03:                                   // TYPE_STRING
            guard Int(data) < strings.count else { return nil }
            let text = strings[Int(data)]
            return text.isEmpty ? nil : .text(text)
        case 0x04:                                   // TYPE_FLOAT
            return .float(Float(bitPattern: data))
        case 0x05, 0x06:                             // TYPE_DIMENSION / FRACTION
            return .dimension(complexToFloat(data))
        case 0x10, 0x11:                             // TYPE_INT_DEC / HEX
            return .integer(Int64(Int32(bitPattern: data)))
        case 0x12:                                   // TYPE_INT_BOOLEAN
            return .integer(data != 0 ? 1 : 0)
        case 0x1c:                                   // TYPE_INT_COLOR_ARGB8
            return .color(data)
        case 0x1d:                                   // TYPE_INT_COLOR_RGB8
            return .color(0xFF00_0000 | data)
        case 0x1e:                                   // TYPE_INT_COLOR_ARGB4
            let a = UInt32((data >> 12) & 0xF) * 17
            let r = UInt32((data >> 8) & 0xF) * 17
            let g = UInt32((data >> 4) & 0xF) * 17
            let b = UInt32(data & 0xF) * 17
            return .color((a << 24) | (r << 16) | (g << 8) | b)
        case 0x1f:                                   // TYPE_INT_COLOR_RGB4
            let r = UInt32((data >> 8) & 0xF) * 17
            let g = UInt32((data >> 4) & 0xF) * 17
            let b = UInt32(data & 0xF) * 17
            return .color(0xFF00_0000 | (r << 16) | (g << 8) | b)
        default:
            return nil
        }
    }

    /// `complex` 차원 값 → 실수. AOSP `complexToFloat` 와 같은 식.
    static func complexToFloat(_ complex: UInt32) -> Float {
        let mantissa = Float(Int32(bitPattern: complex & 0xFFFF_FF00))
        let radix = (complex >> 4) & 0x3
        let mult: [Float] = [1.0 / 256, 1.0 / 32768, 1.0 / 8_388_608, 1.0 / 2_147_483_648]
        return mantissa * mult[Int(radix)]
    }

    var text: String? {
        if case .text(let value) = self { return value }
        return nil
    }

    var reference: UInt32? {
        if case .reference(let value) = self { return value }
        return nil
    }

    var color: UInt32? {
        if case .color(let value) = self { return value }
        return nil
    }

    var number: Double? {
        switch self {
        case .integer(let v): return Double(v)
        case .float(let v): return Double(v)
        case .dimension(let v): return Double(v)
        default: return nil
        }
    }
}

// MARK: - resources.arsc

/// `resources.arsc` 최소 파서 — 리소스 ID → 설정별 파일 경로.
///
/// 아이콘 하나를 찾기 위해 필요한 것만 읽는다: 전역 문자열 풀, 패키지, 타입 청크,
/// 밀도 설정. 복잡한 항목(맵·스타일)은 건너뛴다.
enum AndroidResourceTable {
    struct Candidate: Equatable, Sendable {
        let path: String
        let density: Int
    }

    /// 리소스 ID 하나에 대한 설정별 값 — 파일 경로·문자열·색·치수
    struct Resolved: Equatable, Sendable {
        var value: ResourceValue?
        var density: Int = 0
        /// `ko` · `en` … 기본 로케일이면 빈 문자열
        var language: String = ""
        /// `KR` · `US` … 없으면 빈 문자열
        var country: String = ""
        /// 편의: 문자열이면 그 값, 아니면 nil
        var text: String { value?.text ?? "" }
        /// 편의: 참조면 그 리소스 ID
        var reference: UInt32? { value?.reference }
    }

    private static let typeTable: UInt16 = 0x0002
    private static let typeStringPool: UInt16 = 0x0001
    private static let typePackage: UInt16 = 0x0200
    private static let typeTableType: UInt16 = 0x0201

    static func iconPaths(_ data: Data, forResId resId: UInt32) -> [Candidate] {
        values(data, forResId: resId).compactMap { row in
            guard let path = row.value?.text, !path.isEmpty else { return nil }
            return Candidate(path: path, density: row.density)
        }
    }

    /// 문자열 리소스 해석 — 앱 이름(`android:label`)에 쓴다.
    ///
    /// **기본 로케일(설정 없음)을 우선**하고, 없으면 첫 비어있지 않은 값.
    /// 값이 `@string/...` **참조**면 따라간다 (실측: F-Droid 는
    /// `application@label → @string/app_name → @string/fdroid` 2단계).
    /// 기기 로케일별 이름이 필요해지면 `language`/`country` 로 고르면 된다.
    static func stringValue(_ data: Data, forResId resId: UInt32, depth: Int = 0) -> String? {
        guard depth < 8 else { return nil }
        let rows = values(data, forResId: resId)
        guard !rows.isEmpty else { return nil }
        // 설정 없음 → 문자열 있는 행 → 참조 행 순으로 본다
        let ordered = rows.filter { $0.language.isEmpty && $0.country.isEmpty && !$0.text.isEmpty }
            + rows.filter { !$0.text.isEmpty }
            + rows.filter { $0.reference != nil }
        for row in ordered {
            if !row.text.isEmpty { return row.text }
            if let ref = row.reference {
                if let text = stringValue(data, forResId: ref, depth: depth + 1) { return text }
            }
        }
        return nil
    }

    /// 색 리소스 해석 — 참조를 따라가 `.color` 만 돌려준다.
    static func colorValue(_ data: Data, forResId resId: UInt32, depth: Int = 0) -> UInt32? {
        guard depth < 4 else { return nil }
        for row in values(data, forResId: resId) {
            if let color = row.value?.color { return color }
            if let ref = row.value?.reference,
               let color = colorValue(data, forResId: ref, depth: depth + 1) { return color }
        }
        return nil
    }

    /// 아이콘 후보 하나 고르기 — **비트맵 우선**, 없으면 벡터/어댑티브 XML.
    ///
    /// `best` 는 기존 의미(이미지 확장자만)를 유지하고, 여기서는 확장자가 없는
    /// 엔트리(난독화된 `res/4jn` = WebP)와 anydpi XML 까지 후보로 본다.
    static func pick(_ candidates: [Candidate], targetDensity: Int) -> String? {
        if let image = best(candidates, targetDensity: targetDensity) { return image }
        let want = targetDensity > 0 ? targetDensity : 320
        let known = candidates.filter { $0.density > 0 && $0.density < 0xFFFE }
        if let below = known.filter({ $0.density <= want }).max(by: { $0.density < $1.density }) {
            return below.path
        }
        if let above = known.min(by: { $0.density < $1.density }) { return above.path }
        return candidates.first(where: { $0.density >= 0xFFFE })?.path
            ?? candidates.first?.path
    }

    /// 리소스 ID → 설정별 값 전부
    static func values(_ data: Data, forResId resId: UInt32) -> [Resolved] {
        let b = [UInt8](data)
        guard b.count >= 12, AndroidBinaryXML.u16(b, 0) == typeTable else { return [] }
        let total = min(b.count, Int(AndroidBinaryXML.u32(b, 4)))
        guard total >= 12 else { return [] }

        let wantPackage = UInt8((resId >> 24) & 0xFF)
        let wantType = UInt8((resId >> 16) & 0xFF)
        let wantEntry = Int(resId & 0xFFFF)

        var globalStrings: [String] = []
        var out: [Resolved] = []
        var offset = Int(AndroidBinaryXML.u16(b, 2))
        if offset < 12 { offset = 12 }

        while offset + 8 <= total {
            let type = AndroidBinaryXML.u16(b, offset)
            let size = Int(AndroidBinaryXML.u32(b, offset + 4))
            guard size >= 8, offset + size <= total else { break }
            switch type {
            case typeStringPool:
                if globalStrings.isEmpty {
                    globalStrings = AndroidBinaryXML.parseStringPool(b, at: offset, limit: offset + size)
                }
            case typePackage:
                out.append(contentsOf: collectFromPackage(
                    b,
                    at: offset,
                    limit: offset + size,
                    globalStrings: globalStrings,
                    wantPackage: wantPackage,
                    wantType: wantType,
                    wantEntry: wantEntry
                ))
            default:
                break
            }
            offset += size
        }
        return out
    }

    private static func collectFromPackage(
        _ b: [UInt8],
        at offset: Int,
        limit: Int,
        globalStrings: [String],
        wantPackage: UInt8,
        wantType: UInt8,
        wantEntry: Int
    ) -> [Resolved] {
        guard offset + 12 <= limit else { return [] }
        let packageId = UInt8(AndroidBinaryXML.u32(b, offset + 8) & 0xFF)
        guard packageId == wantPackage else { return [] }
        let headerSize = Int(AndroidBinaryXML.u16(b, offset + 2))
        guard headerSize >= 12, offset + headerSize <= limit else { return [] }

        var out: [Resolved] = []
        var p = offset + headerSize
        while p + 8 <= limit {
            let type = AndroidBinaryXML.u16(b, p)
            let size = Int(AndroidBinaryXML.u32(b, p + 4))
            guard size >= 8, p + size <= limit else { break }
            if type == typeTableType {
                if let hit = entry(
                    b,
                    at: p,
                    limit: p + size,
                    globalStrings: globalStrings,
                    wantType: wantType,
                    wantEntry: wantEntry
                ) {
                    out.append(hit)
                }
            }
            p += size
        }
        return out
    }

    private static func entry(
        _ b: [UInt8],
        at offset: Int,
        limit: Int,
        globalStrings: [String],
        wantType: UInt8,
        wantEntry: Int
    ) -> Resolved? {
        guard offset + 20 <= limit else { return nil }
        let typeId = b[offset + 8]
        guard typeId == wantType else { return nil }
        let typeFlags = b[offset + 9]
        let entryCount = Int(AndroidBinaryXML.u32(b, offset + 12))
        let entriesStart = Int(AndroidBinaryXML.u32(b, offset + 16))
        let headerSize = Int(AndroidBinaryXML.u16(b, offset + 2))
        guard let entryOffset = entryOffset(
            b,
            at: offset,
            headerSize: headerSize,
            typeFlags: typeFlags,
            entryCount: entryCount,
            index: wantEntry,
            limit: limit
        ) else { return nil }

        // ResTable_config: size(4) mcc(2) mnc(2) language(2) country(2) orientation(1) touchscreen(1) density(2)
        let configStart = offset + 20
        var density = 0
        var language = ""
        var country = ""
        if configStart + 16 <= limit {
            language = localeTag(AndroidBinaryXML.u16(b, configStart + 8))
            country = localeTag(AndroidBinaryXML.u16(b, configStart + 10))
            density = Int(AndroidBinaryXML.u16(b, configStart + 14))
        }

        let entryStart = offset + entriesStart + entryOffset
        guard entryStart + 8 <= limit else { return nil }
        let entrySize = Int(AndroidBinaryXML.u16(b, entryStart))
        let entryFlags = AndroidBinaryXML.u16(b, entryStart + 2)
        guard entryFlags & 0x0001 == 0 else { return nil }   // 복잡한 항목(맵·스타일) 제외
        let valueStart = entryStart + max(entrySize, 8)
        guard valueStart + 8 <= limit else { return nil }
        let dataType = b[valueStart + 3]
        let data = AndroidBinaryXML.u32(b, valueStart + 4)
        guard let value = ResourceValue.decode(type: dataType, data: data, strings: globalStrings) else {
            return nil
        }
        return Resolved(value: value, density: density, language: language, country: country)
    }

    /// 타입 청크의 엔트리 오프셋 표를 읽는다 — 세 가지 인코딩을 모두 지원한다.
    ///
    /// - 일반: `uint32[entryCount]`, 0xFFFFFFFF = 없음
    /// - `FLAG_OFFSET16`(0x02): `uint16[entryCount] * 4`
    /// - `FLAG_SPARSE`(0x01): `(uint16 index, uint16 offset/4)[]` — **정렬돼 있지 않을 수 있다**
    ///
    /// 실측: 구글 포토·Gboard 는 희소(sparse) 표를 쓴다. 이걸 모르면 아이콘·이름이
    /// 통째로 비어 보인다(2026-10-24).
    static func entryOffset(
        _ b: [UInt8],
        at offset: Int,
        headerSize: Int,
        typeFlags: UInt8,
        entryCount: Int,
        index: Int,
        limit: Int
    ) -> Int? {
        guard index >= 0, entryCount >= 0, entryCount <= 1_000_000 else { return nil }
        let offsetsStart = offset + headerSize
        if typeFlags & 0x01 != 0 {                         // FLAG_SPARSE
            // 희소 표에서 `entryCount` 는 **쌍의 개수**다 — 엔트리 인덱스 상한이 아니다.
            guard offsetsStart + entryCount * 4 <= limit else { return nil }
            for i in 0..<entryCount {
                let at = offsetsStart + i * 4
                guard Int(AndroidBinaryXML.u16(b, at)) == index else { continue }
                return Int(AndroidBinaryXML.u16(b, at + 2)) * 4
            }
            return nil
        }
        guard index < entryCount else { return nil }
        if typeFlags & 0x02 != 0 {                         // FLAG_OFFSET16
            guard offsetsStart + entryCount * 2 <= limit else { return nil }
            let raw = AndroidBinaryXML.u16(b, offsetsStart + index * 2)
            guard raw != 0xFFFF else { return nil }
            return Int(raw) * 4
        }
        guard offsetsStart + entryCount * 4 <= limit else { return nil }
        let raw = AndroidBinaryXML.u32(b, offsetsStart + index * 4)
        guard raw != 0xFFFF_FFFF else { return nil }
        return Int(raw)
    }

    /// ResTable_config 의 언어/국가 2바이트 — 0 이면 기본(로케일 없음).
    /// 팩형 3글자 인코딩(0x8000 비트)은 원값 문자열로 둔다(기본 로케일 판정에만 쓴다).
    private static func localeTag(_ raw: UInt16) -> String {
        guard raw != 0 else { return "" }
        if raw & 0x8000 != 0 { return String(format: "packed-%04x", raw) }
        let a = UInt8(raw & 0xFF)
        let c = UInt8((raw >> 8) & 0xFF)
        guard a >= 0x20, a < 0x7F, c >= 0x20, c < 0x7F else {
            return String(format: "%04x", raw)
        }
        return String(UnicodeScalar(a)) + String(UnicodeScalar(c))
    }

    /// 후보 중 화면에 쓸 하나 — 이미지 확장자만, 기기 밀도에 가장 가까운 것
    static func best(_ candidates: [Candidate], targetDensity: Int) -> String? {
        let images = candidates.filter { isImage($0.path) }
        guard !images.isEmpty else { return nil }
        let want = targetDensity > 0 ? targetDensity : 320
        let usable = images.filter { $0.density > 0 && $0.density <= 640 }
        if let below = usable.filter({ $0.density <= want }).max(by: { $0.density < $1.density }) {
            return below.path
        }
        if let above = usable.min(by: { $0.density < $1.density }) {
            return above.path
        }
        return images.max(by: { $0.density < $1.density })?.path
    }

    private static func isImage(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ext == "png" || ext == "webp" || ext == "jpg" || ext == "jpeg"
    }
}

// MARK: - APK 메타데이터 · 아이콘 추출

enum APKInspector {
    struct Metadata: Equatable, Sendable {
        var packageName: String?
        var versionName: String?
        var versionCode: Int64?
        /// 아이콘 리소스 후보 — `icon` → `roundIcon` 순. 그리는 일은 `APKIconRenderer`.
        var iconResIds: [UInt32] = []
        /// 사람이 읽는 앱 이름 (`android:label` → resources.arsc)
        var label: String?
    }

    /// APK 파일에서 패키지 정보·**앱 이름**·**아이콘 ZIP 경로**를 얻는다
    /// (아이콘 바이트는 꺼내지 않는다).
    static func inspect(apk: URL) throws -> Metadata {
        let zip = try ZipArchive(url: apk)
        var meta = Metadata()

        if let manifest = zip.entry(named: "AndroidManifest.xml"),
           let data = try? zip.data(for: manifest),
           let info = AndroidBinaryXML.parse(data) {
            meta.packageName = info.packageName
            meta.versionName = info.versionName
            meta.versionCode = info.versionCode

            let table: Data? = {
                guard let arsc = zip.entry(named: "resources.arsc") else { return nil }
                return try? zip.data(for: arsc)
            }()

            // 앱 이름 — 리소스 참조면 ARSC 에서, 직접 문자열이면 매니페스트에서
            if let labelId = info.labelResId, let table {
                meta.label = AndroidResourceTable.stringValue(table, forResId: labelId)
            }
            if meta.label == nil { meta.label = info.labelText }

            var seen = Set<UInt32>()
            meta.iconResIds = [info.iconResId, info.roundIconResId]
                .compactMap { $0 }
                .filter { seen.insert($0).inserted }
        }
        return meta
    }
}
