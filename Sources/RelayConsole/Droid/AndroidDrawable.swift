import Foundation
import CoreGraphics
import ImageIO

// MARK: - SVG path data

/// 벡터 드로어블의 `pathData`(SVG 경로 문법) → `CGPath`.
///
/// 외부 프로세스(aapt·rsvg)를 쓸 수 없어 직접 해석한다. 아이콘에 실제로 쓰이는
/// 명령만 구현하되 **전체 명령 집합**(M/L/H/V/C/S/Q/T/A/Z, 대소문자)을 지원한다.
/// 호(arc)는 90° 이하 큐빅 베지어로 근사한다 — CGPath.addArc 의 방향 규약에
/// 기대지 않기 위해서다.
enum SVGPath {
    static func cgPath(_ d: String) -> CGPath? {
        var scanner = Scanner(d)
        let path = CGMutablePath()
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastCubic: CGPoint?
        var lastQuad: CGPoint?
        var command: Character = "M"
        var sawAny = false

        while true {
            scanner.skipSeparators()
            if scanner.isAtEnd { break }
            if let next = scanner.command() { command = next }

            var guardCount = 0
            repeat {
                guardCount += 1
                if guardCount > 100_000 { return sawAny ? path.copy() : nil }
                let absolute = command.isUppercase
                switch Character(command.lowercased()) {
                case "m":
                    guard let x = scanner.number(), let y = scanner.number() else {
                        return sawAny ? path.copy() : nil
                    }
                    let point = absolute
                        ? CGPoint(x: x, y: y)
                        : CGPoint(x: current.x + x, y: current.y + y)
                    path.move(to: point)
                    current = point
                    subpathStart = point
                    command = absolute ? "L" : "l"
                    lastCubic = nil
                    lastQuad = nil
                    sawAny = true

                case "l":
                    guard let x = scanner.number(), let y = scanner.number() else {
                        return sawAny ? path.copy() : nil
                    }
                    let point = absolute
                        ? CGPoint(x: x, y: y)
                        : CGPoint(x: current.x + x, y: current.y + y)
                    path.addLine(to: point)
                    current = point
                    lastCubic = nil
                    lastQuad = nil
                    sawAny = true

                case "h":
                    guard let x = scanner.number() else { return sawAny ? path.copy() : nil }
                    let point = CGPoint(x: absolute ? x : current.x + x, y: current.y)
                    path.addLine(to: point)
                    current = point
                    lastCubic = nil
                    lastQuad = nil
                    sawAny = true

                case "v":
                    guard let y = scanner.number() else { return sawAny ? path.copy() : nil }
                    let point = CGPoint(x: current.x, y: absolute ? y : current.y + y)
                    path.addLine(to: point)
                    current = point
                    lastCubic = nil
                    lastQuad = nil
                    sawAny = true

                case "c":
                    guard let x1 = scanner.number(), let y1 = scanner.number(),
                          let x2 = scanner.number(), let y2 = scanner.number(),
                          let x = scanner.number(), let y = scanner.number() else {
                        return sawAny ? path.copy() : nil
                    }
                    let c1 = absolute ? CGPoint(x: x1, y: y1) : CGPoint(x: current.x + x1, y: current.y + y1)
                    let c2 = absolute ? CGPoint(x: x2, y: y2) : CGPoint(x: current.x + x2, y: current.y + y2)
                    let end = absolute ? CGPoint(x: x, y: y) : CGPoint(x: current.x + x, y: current.y + y)
                    path.addCurve(to: end, control1: c1, control2: c2)
                    lastCubic = c2
                    lastQuad = nil
                    current = end
                    sawAny = true

                case "s":
                    guard let x2 = scanner.number(), let y2 = scanner.number(),
                          let x = scanner.number(), let y = scanner.number() else {
                        return sawAny ? path.copy() : nil
                    }
                    let c1 = lastCubic.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                    let c2 = absolute ? CGPoint(x: x2, y: y2) : CGPoint(x: current.x + x2, y: current.y + y2)
                    let end = absolute ? CGPoint(x: x, y: y) : CGPoint(x: current.x + x, y: current.y + y)
                    path.addCurve(to: end, control1: c1, control2: c2)
                    lastCubic = c2
                    lastQuad = nil
                    current = end
                    sawAny = true

                case "q":
                    guard let x1 = scanner.number(), let y1 = scanner.number(),
                          let x = scanner.number(), let y = scanner.number() else {
                        return sawAny ? path.copy() : nil
                    }
                    let c = absolute ? CGPoint(x: x1, y: y1) : CGPoint(x: current.x + x1, y: current.y + y1)
                    let end = absolute ? CGPoint(x: x, y: y) : CGPoint(x: current.x + x, y: current.y + y)
                    path.addQuadCurve(to: end, control: c)
                    lastQuad = c
                    lastCubic = nil
                    current = end
                    sawAny = true

                case "t":
                    guard let x = scanner.number(), let y = scanner.number() else {
                        return sawAny ? path.copy() : nil
                    }
                    let c = lastQuad.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                    let end = absolute ? CGPoint(x: x, y: y) : CGPoint(x: current.x + x, y: current.y + y)
                    path.addQuadCurve(to: end, control: c)
                    lastQuad = c
                    lastCubic = nil
                    current = end
                    sawAny = true

                case "a":
                    guard let rx = scanner.number(), let ry = scanner.number(),
                          let rotation = scanner.number(), let large = scanner.flag(),
                          let sweep = scanner.flag(), let x = scanner.number(),
                          let y = scanner.number() else {
                        return sawAny ? path.copy() : nil
                    }
                    let end = absolute ? CGPoint(x: x, y: y) : CGPoint(x: current.x + x, y: current.y + y)
                    addArc(
                        to: path,
                        from: current,
                        to: end,
                        rx: rx,
                        ry: ry,
                        rotationDegrees: rotation,
                        largeArc: large,
                        sweep: sweep
                    )
                    current = end
                    lastCubic = nil
                    lastQuad = nil
                    sawAny = true

                case "z":
                    path.closeSubpath()
                    current = subpathStart
                    lastCubic = nil
                    lastQuad = nil
                    sawAny = true

                default:
                    return sawAny ? path.copy() : nil
                }
            } while scanner.hasNumber()
        }
        return sawAny ? path.copy() : nil
    }

    /// SVG 호 → 큐빅 베지어. (rx 또는 ry 가 0 이면 직선)
    private static func addArc(
        to path: CGMutablePath,
        from start: CGPoint,
        to end: CGPoint,
        rx inputRx: Double,
        ry inputRy: Double,
        rotationDegrees: Double,
        largeArc: Bool,
        sweep: Bool
    ) {
        var rx = abs(inputRx)
        var ry = abs(inputRy)
        guard rx > 0, ry > 0 else {
            path.addLine(to: end)
            return
        }
        let phi = rotationDegrees * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)
        let dx = (start.x - end.x) / 2
        let dy = (start.y - end.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let scale = sqrt(lambda)
            rx *= scale
            ry *= scale
        }

        let rx2 = rx * rx
        let ry2 = ry * ry
        let denominator = rx2 * y1p * y1p + ry2 * x1p * x1p
        guard denominator > 0 else {
            path.addLine(to: end)
            return
        }
        var numerator = rx2 * ry2 - rx2 * y1p * y1p - ry2 * x1p * x1p
        if numerator < 0 { numerator = 0 }
        var coefficient = sqrt(numerator / denominator)
        if largeArc == sweep { coefficient = -coefficient }
        let cxp = coefficient * (rx * y1p / ry)
        let cyp = coefficient * (-ry * x1p / rx)
        let cx = cosPhi * cxp - sinPhi * cyp + (start.x + end.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (start.y + end.y) / 2

        let theta1 = atan2((y1p - cyp) / ry, (x1p - cxp) / rx)
        var theta2 = atan2((-y1p - cyp) / ry, (-x1p - cxp) / rx)
        var delta = theta2 - theta1
        if sweep && delta < 0 { delta += 2 * .pi }
        if !sweep && delta > 0 { delta -= 2 * .pi }
        theta2 = theta1 + delta

        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / Double(segments)

        func point(_ angle: Double) -> CGPoint {
            let x = rx * cos(angle)
            let y = ry * sin(angle)
            return CGPoint(x: cx + cosPhi * x - sinPhi * y, y: cy + sinPhi * x + cosPhi * y)
        }
        func derivative(_ angle: Double) -> CGPoint {
            let x = -rx * sin(angle)
            let y = ry * cos(angle)
            return CGPoint(x: cosPhi * x - sinPhi * y, y: sinPhi * x + cosPhi * y)
        }

        var angle = theta1
        for _ in 0..<segments {
            let nextAngle = angle + step
            let p0 = point(angle)
            let p1 = point(nextAngle)
            let d0 = derivative(angle)
            let d1 = derivative(nextAngle)
            let alpha = 4.0 / 3.0 * tan(step / 4)
            let c1 = CGPoint(x: p0.x + alpha * d0.x, y: p0.y + alpha * d0.y)
            let c2 = CGPoint(x: p1.x - alpha * d1.x, y: p1.y - alpha * d1.y)
            path.addCurve(to: p1, control1: c1, control2: c2)
            angle = nextAngle
        }
    }

    private struct Scanner {
        private let chars: [Character]
        private var index = 0

        init(_ text: String) { chars = Array(text) }

        var isAtEnd: Bool {
            var i = index
            while i < chars.count, isSeparator(chars[i]) { i += 1 }
            return i >= chars.count
        }

        mutating func skipSeparators() {
            while index < chars.count, isSeparator(chars[index]) { index += 1 }
        }

        mutating func command() -> Character? {
            skipSeparators()
            guard index < chars.count, chars[index].isLetter else { return nil }
            defer { index += 1 }
            return chars[index]
        }

        mutating func hasNumber() -> Bool {
            skipSeparators()
            guard index < chars.count else { return false }
            let c = chars[index]
            return c.isNumber || c == "-" || c == "+" || c == "."
        }

        mutating func flag() -> Bool? {
            guard let value = number() else { return nil }
            return value != 0
        }

        mutating func number() -> Double? {
            skipSeparators()
            guard index < chars.count else { return nil }
            var text = ""
            if chars[index] == "-" || chars[index] == "+" {
                text.append(chars[index])
                index += 1
            }
            var seenDot = false
            var seenExponent = false
            while index < chars.count {
                let c = chars[index]
                if c.isNumber {
                    text.append(c)
                    index += 1
                } else if c == ".", !seenDot, !seenExponent {
                    seenDot = true
                    text.append(c)
                    index += 1
                } else if (c == "e" || c == "E"), !seenExponent, !text.isEmpty {
                    seenExponent = true
                    text.append(c)
                    index += 1
                    if index < chars.count, chars[index] == "-" || chars[index] == "+" {
                        text.append(chars[index])
                        index += 1
                    }
                } else {
                    break
                }
            }
            return Double(text)
        }

        private func isSeparator(_ c: Character) -> Bool {
            c == " " || c == "," || c == "\n" || c == "\r" || c == "\t"
        }
    }
}

// MARK: - APK 아이콘 렌더러

/// APK 의 아이콘 리소스를 **직접 그려서** PNG 로 만든다.
///
/// 현대 안드로이드 앱의 아이콘은 PNG 가 아니라 **적응형 아이콘 XML**
/// (`background`/`foreground` 레이어) 이고, 레이어는 다시 벡터 드로어블이거나
/// WebP 다. ZIP·AXML·ARSC 만으로 처리해야 하므로(외부 프로세스 금지) 여기서
/// 벡터 경로·색·그룹 변환을 직접 해석해 CoreGraphics 로 합성한다.
///
/// 우선순위: 비트맵 → 벡터/적응형 → 단색. 어느 단계든 실패하면 nil 을 돌려주고
/// 호출부(`AppIconStore`)가 이니셜 타일로 폴백한다.
enum APKIconRenderer {
    static let maxDepth = 6
    static let maxXMLEntryBytes: UInt64 = 4 * 1024 * 1024
    static let maxImageEntryBytes: UInt64 = 32 * 1024 * 1024

    private struct Context {
        let zip: ZipArchive
        let arsc: Data
        let density: Int
    }

    /// APK 안의 아이콘 리소스 ID → `pixels`×`pixels` 이미지
    static func render(apk: URL, resIds: [UInt32], pixels: Int, density: Int = 480) -> CGImage? {
        guard pixels > 0, !resIds.isEmpty,
              let zip = try? ZipArchive(url: apk),
              let arscEntry = zip.entry(named: "resources.arsc"),
              let arsc = try? zip.data(for: arscEntry) else { return nil }
        let context = Context(zip: zip, arsc: arsc, density: density)
        for resId in resIds {
            if let image = renderResource(resId, pixels: pixels, depth: 0, context) {
                return image
            }
        }
        return nil
    }

    // MARK: 리소스 해석

    private static func renderResource(
        _ resId: UInt32,
        pixels: Int,
        depth: Int,
        _ context: Context
    ) -> CGImage? {
        guard depth <= maxDepth else { return nil }
        let candidates = AndroidResourceTable.iconPaths(context.arsc, forResId: resId)
        if let path = AndroidResourceTable.pick(candidates, targetDensity: context.density),
           let image = renderEntry(path, pixels: pixels, depth: depth + 1, context) {
            return image
        }
        // 파일이 아니라 색/참조 리소스
        let rows = AndroidResourceTable.values(context.arsc, forResId: resId)
        for row in rows {
            if let reference = row.value?.reference,
               let image = renderResource(reference, pixels: pixels, depth: depth + 1, context) {
                return image
            }
        }
        if let argb = AndroidResourceTable.colorValue(context.arsc, forResId: resId) {
            return solid(argb, pixels: pixels)
        }
        return nil
    }

    private static func renderEntry(
        _ path: String,
        pixels: Int,
        depth: Int,
        _ context: Context
    ) -> CGImage? {
        guard depth <= maxDepth, let entry = context.zip.entry(named: path) else { return nil }
        if path.lowercased().hasSuffix(".xml") {
            guard entry.uncompressedSize <= maxXMLEntryBytes,
                  let data = try? context.zip.data(for: entry),
                  let root = AndroidBinaryXML.parseTree(data) else { return nil }
            return renderNode(root, pixels: pixels, depth: depth + 1, context)
        }
        guard entry.uncompressedSize <= maxImageEntryBytes,
              let data = try? context.zip.data(for: entry) else { return nil }
        if isBinaryXML(data) {
            guard let root = AndroidBinaryXML.parseTree(data) else { return nil }
            return renderNode(root, pixels: pixels, depth: depth + 1, context)
        }
        return decodeImage(data, pixels: pixels)
    }

    private static func isBinaryXML(_ data: Data) -> Bool {
        guard data.count >= 8 else { return false }
        return data[0] == 0x03 && data[1] == 0x00 && data[2] == 0x08 && data[3] == 0x00
    }

    private static func renderValue(
        _ value: ResourceValue?,
        pixels: Int,
        depth: Int,
        _ context: Context
    ) -> CGImage? {
        guard let value, depth <= maxDepth else { return nil }
        switch value {
        case .color(let argb):
            return solid(argb, pixels: pixels)
        case .reference(let resId):
            return renderResource(resId, pixels: pixels, depth: depth + 1, context)
        case .text(let path):
            return renderEntry(path, pixels: pixels, depth: depth + 1, context)
        default:
            return nil
        }
    }

    // MARK: XML 노드

    private static func renderNode(
        _ node: AndroidBinaryXML.Node,
        pixels: Int,
        depth: Int,
        _ context: Context
    ) -> CGImage? {
        guard depth <= maxDepth else { return nil }
        switch node.name {
        case "vector":
            return renderVector(node, pixels: pixels, context)
        case "adaptive-icon":
            return renderAdaptive(node, pixels: pixels, depth: depth, context)
        case "bitmap":
            return renderValue(node.attribute("src"), pixels: pixels, depth: depth, context)
        case "layer-list", "selector", "inset", "clip":
            return renderLayers(node.children, pixels: pixels, depth: depth, context)
        case "color":
            return renderValue(node.attribute("color"), pixels: pixels, depth: depth, context)
        case "shape":
            if let color = color(node.attribute("solidColor") ?? node.attribute("color"), context) {
                return solid(color, pixels: pixels)
            }
            return nil
        case "item":
            if let value = node.attribute("drawable") ?? node.attribute("src") {
                return renderValue(value, pixels: pixels, depth: depth, context)
            }
            return nil
        default:
            for child in node.children {
                if let image = renderNode(child, pixels: pixels, depth: depth + 1, context) {
                    return image
                }
            }
            return nil
        }
    }

    private static func renderLayers(
        _ children: [AndroidBinaryXML.Node],
        pixels: Int,
        depth: Int,
        _ context: Context
    ) -> CGImage? {
        guard let canvas = makeCanvas(pixels: pixels) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: CGFloat(pixels), height: CGFloat(pixels))
        var drew = false
        for child in children {
            if let value = child.attribute("drawable") ?? child.attribute("src"),
               let image = renderValue(value, pixels: pixels, depth: depth + 1, context) {
                canvas.draw(image, in: rect)
                drew = true
            } else if let image = renderNode(child, pixels: pixels, depth: depth + 1, context) {
                canvas.draw(image, in: rect)
                drew = true
            }
        }
        return drew ? canvas.makeImage() : nil
    }

    private static func renderAdaptive(
        _ node: AndroidBinaryXML.Node,
        pixels: Int,
        depth: Int,
        _ context: Context
    ) -> CGImage? {
        // 적응형 아이콘: 108dp 캔버스 중 가운데 72dp 가 보이는 영역 → 1.5배 그려 자른다
        let layerPixels = Int((CGFloat(pixels) * 1.5).rounded())
        guard layerPixels > 0, let canvas = makeCanvas(pixels: pixels) else { return nil }
        let rect = CGRect(
            x: -CGFloat(pixels) / 4,
            y: -CGFloat(pixels) / 4,
            width: CGFloat(pixels) * 1.5,
            height: CGFloat(pixels) * 1.5
        )
        var drew = false
        for name in ["background", "foreground"] {
            guard let layer = node.children.first(where: { $0.name == name }) else { continue }
            let value = layer.attribute("drawable") ?? layer.attribute("src")
            if let image = renderValue(value, pixels: layerPixels, depth: depth + 1, context) {
                canvas.draw(image, in: rect)
                drew = true
            }
        }
        return drew ? canvas.makeImage() : nil
    }

    // MARK: 벡터

    private static func renderVector(
        _ node: AndroidBinaryXML.Node,
        pixels: Int,
        _ context: Context
    ) -> CGImage? {
        let viewportWidth = node.attribute("viewportWidth")?.number ?? 24
        let viewportHeight = node.attribute("viewportHeight")?.number ?? viewportWidth
        guard viewportWidth > 0, viewportHeight > 0, let canvas = makeCanvas(pixels: pixels) else {
            return nil
        }
        canvas.saveGState()
        // SVG 좌표는 y 아래 방향 — 비트맵 컨텍스트(y 위)를 한 번 뒤집는다
        canvas.translateBy(x: 0, y: CGFloat(pixels))
        canvas.scaleBy(x: 1, y: -1)
        canvas.scaleBy(x: CGFloat(pixels) / viewportWidth, y: CGFloat(pixels) / viewportHeight)
        if let alpha = node.attribute("alpha")?.number {
            canvas.setAlpha(CGFloat(alpha))
        }
        drawChildren(node.children, canvas: canvas, context)
        canvas.restoreGState()
        return canvas.makeImage()
    }

    private static func drawChildren(
        _ children: [AndroidBinaryXML.Node],
        canvas: CGContext,
        _ context: Context
    ) {
        for child in children {
            switch child.name {
            case "path":
                drawPath(child, canvas: canvas, context)
            case "group":
                canvas.saveGState()
                let translateX = child.attribute("translateX")?.number ?? 0
                let translateY = child.attribute("translateY")?.number ?? 0
                let pivotX = child.attribute("pivotX")?.number ?? 0
                let pivotY = child.attribute("pivotY")?.number ?? 0
                let rotation = child.attribute("rotation")?.number ?? 0
                let scaleX = child.attribute("scaleX")?.number ?? 1
                let scaleY = child.attribute("scaleY")?.number ?? 1
                canvas.translateBy(x: CGFloat(translateX + pivotX), y: CGFloat(translateY + pivotY))
                if rotation != 0 { canvas.rotate(by: CGFloat(rotation * .pi / 180)) }
                canvas.scaleBy(x: CGFloat(scaleX), y: CGFloat(scaleY))
                canvas.translateBy(x: CGFloat(-pivotX), y: CGFloat(-pivotY))
                drawChildren(child.children, canvas: canvas, context)
                canvas.restoreGState()
            case "clip-path":
                if let d = child.attribute("pathData")?.text, let path = SVGPath.cgPath(d) {
                    canvas.addPath(path)
                    canvas.clip()
                }
            default:
                break
            }
        }
    }

    private static func drawPath(
        _ node: AndroidBinaryXML.Node,
        canvas: CGContext,
        _ context: Context
    ) {
        guard let d = node.attribute("pathData")?.text, let path = SVGPath.cgPath(d) else { return }
        if let argb = color(node.attribute("fillColor"), context) ?? gradientColor(node, context) {
            let alpha = node.attribute("fillAlpha")?.number ?? 1
            canvas.saveGState()
            canvas.setFillColor(cgColor(argb, alphaMultiplier: alpha))
            canvas.addPath(path)
            let evenOdd = (node.attribute("fillType")?.number ?? 0) == 1
            canvas.fillPath(using: evenOdd ? .evenOdd : .winding)
            canvas.restoreGState()
        }
        if let argb = color(node.attribute("strokeColor"), context),
           let width = node.attribute("strokeWidth")?.number, width > 0 {
            let alpha = node.attribute("strokeAlpha")?.number ?? 1
            canvas.saveGState()
            canvas.setStrokeColor(cgColor(argb, alphaMultiplier: alpha))
            canvas.setLineWidth(CGFloat(width))
            switch Int(node.attribute("strokeLineCap")?.number ?? 0) {
            case 1: canvas.setLineCap(.round)
            case 2: canvas.setLineCap(.square)
            default: canvas.setLineCap(.butt)
            }
            switch Int(node.attribute("strokeLineJoin")?.number ?? 0) {
            case 1: canvas.setLineJoin(.round)
            case 2: canvas.setLineJoin(.bevel)
            default: canvas.setLineJoin(.miter)
            }
            canvas.addPath(path)
            canvas.strokePath()
            canvas.restoreGState()
        }
    }

    private static func gradientColor(
        _ node: AndroidBinaryXML.Node,
        _ context: Context
    ) -> UInt32? {
        for child in node.children {
            if child.name == "gradient" {
                for key in ["startColor", "centerColor", "endColor"] {
                    if let argb = color(child.attribute(key), context) { return argb }
                }
            }
            if let nested = gradientColor(child, context) { return nested }
        }
        return nil
    }

    // MARK: 색

    private static func color(_ value: ResourceValue?, _ context: Context) -> UInt32? {
        guard let value else { return nil }
        switch value {
        case .color(let argb):
            return argb
        case .reference(let resId):
            return AndroidResourceTable.colorValue(context.arsc, forResId: resId)
        case .text(let text):
            return parseColor(text)
        default:
            return nil
        }
    }

    /// `#rgb` · `#argb` · `#rrggbb` · `#aarrggbb`
    static func parseColor(_ text: String) -> UInt32? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#") else { return nil }
        let hex = String(trimmed.dropFirst())
        guard let value = UInt32(hex, radix: 16) else { return nil }
        switch hex.count {
        case 3:
            let r = (value >> 8) & 0xF
            let g = (value >> 4) & 0xF
            let b = value & 0xF
            return 0xFF00_0000 | (r * 17 << 16) | (g * 17 << 8) | (b * 17)
        case 4:
            let a = (value >> 12) & 0xF
            let r = (value >> 8) & 0xF
            let g = (value >> 4) & 0xF
            let b = value & 0xF
            return (a * 17 << 24) | (r * 17 << 16) | (g * 17 << 8) | (b * 17)
        case 6:
            return 0xFF00_0000 | value
        case 8:
            return value
        default:
            return nil
        }
    }

    private static func cgColor(_ argb: UInt32, alphaMultiplier: Double) -> CGColor {
        let alpha = CGFloat((argb >> 24) & 0xFF) / 255
        return CGColor(
            srgbRed: CGFloat((argb >> 16) & 0xFF) / 255,
            green: CGFloat((argb >> 8) & 0xFF) / 255,
            blue: CGFloat(argb & 0xFF) / 255,
            alpha: alpha * CGFloat(max(0, min(1, alphaMultiplier)))
        )
    }

    // MARK: 비트맵

    private static func makeCanvas(pixels: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ).map { context in
            context.interpolationQuality = .high
            return context
        }
    }

    private static func solid(_ argb: UInt32, pixels: Int) -> CGImage? {
        guard let canvas = makeCanvas(pixels: pixels) else { return nil }
        canvas.setFillColor(cgColor(argb, alphaMultiplier: 1))
        canvas.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        return canvas.makeImage()
    }

    /// PNG · WebP · JPEG · 확장자 없는 난독화 엔트리 모두 ImageIO 로 읽는다
    static func decodeImage(_ data: Data, pixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
