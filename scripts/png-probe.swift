#!/usr/bin/env swift
// PNG 속 **특정 색 픽셀의 경계 상자**를 정확히 잰다.
//
// 왜 필요한가 (2026-11-15)
//   드래그 이미지가 커서에서 얼마나 떨어져 있는지 눈으로 추정하면 ±30pt 오차가 났다.
//   마커(녹색 사각형)를 넣고 **픽셀 좌표로 정확히** 재야 보정값을 믿을 수 있다.
//
// 사용:
//   swift scripts/png-probe.swift <png> [r,g,b]      # 기본값 0,255,0 (녹색 마커)
//
// 출력: 픽셀 경계 상자 + (--crop=x,y,w,h 를 주면 화면 좌표도 같이)
import AppKit
import Foundation
import ImageIO

let args = Array(CommandLine.arguments.dropFirst())
guard let path = args.first, let image = NSImage(contentsOfFile: path),
      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("이미지를 못 읽었습니다: \(args.first ?? "")\n".utf8))
    exit(1)
}

var target = (r: 0, g: 255, b: 0)
if let c = args.dropFirst().first {
    let parts = c.split(separator: ",").compactMap { Int($0) }
    if parts.count >= 3 { target = (parts[0], parts[1], parts[2]) }
}

let width = cg.width
let height = cg.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)
let ctx = CGContext(
    data: &pixels,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: width * 4,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
var count = 0
for y in 0..<height {
    for x in 0..<width {
        let i = (y * width + x) * 4
        let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
        // 여유 있게 판정 (JPEG 압축·스케일링 흔들림 대비)
        if abs(r - target.r) < 70, abs(g - target.g) < 70, abs(b - target.b) < 70 {
            count += 1
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
}

guard count > 0 else {
    print("색 \(target) 픽셀 없음 · 이미지 \(width)x\(height)")
    exit(2)
}

print("색 \(target) 픽셀 \(count)개")
print("경계 상자(px) x:\(minX)...\(maxX)  y:\(minY)...\(maxY)")

// 캡처 영역이 주어지면 화면 좌표(포인트)로 환산
if let cropArg = args.dropFirst(2).first(where: { $0.hasPrefix("--crop=") }) {
    let v = cropArg.replacingOccurrences(of: "--crop=", with: "")
    let parts = v.split(separator: ",").compactMap { Double($0) }
    if parts.count >= 4 {
        let scale = Double(width) / parts[2]
        let x0 = parts[0] + Double(minX) / scale
        let x1 = parts[0] + Double(maxX) / scale
        let y0 = parts[1] + Double(minY) / scale
        let y1 = parts[1] + Double(maxY) / scale
        print("화면 좌표(pt) x:\(String(format: "%.1f", x0))...\(String(format: "%.1f", x1))  "
            + "y:\(String(format: "%.1f", y0))...\(String(format: "%.1f", y1))")
        print("중심 x:\(String(format: "%.1f", (x0 + x1) / 2))  y:\(String(format: "%.1f", (y0 + y1) / 2))")
    }
}
