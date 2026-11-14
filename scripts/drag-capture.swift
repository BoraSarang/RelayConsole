#!/usr/bin/env swift
// 합성 드래그 + 화면 캡처 — "드래그 이미지가 커서에서 떨어져 보인다" 문제를 눈으로 확인한다.
//
// 왜 필요한가 (2026-11-15)
//   파일 탐색기 행을 드래그할 때 **드래그 이미지(고스트)가 커서와 동떨어져** 보인다.
//   긁어모을 수 있는 사진이 없어 원인이 애매했다 → **스크립트로 드래그를 만들고
//   중간 화면을 캡처**하면 무엇이 문제인지(앵커 오프셋인지, 프리뷰 스타일인지)를 바로 본다.
//
// 사용:
//   swift scripts/drag-capture.swift --source="a.txt" --target="폴더명" --out=/tmp/d.png
//   swift scripts/drag-capture.swift --source="a.txt" --target="폴더명" --cancel   # 제자리에서 놓기(이동 X)
//   swift scripts/drag-capture.swift --source="a.txt" --target="폴더명" --keep      # 놓지 않고 화면만 캡처
//
// 전제: 실행 터미널에 **접근성(AX) · 화면 녹화** 권한이 있어야 한다(터미널 권한을 그대로 물려받는다).
import ApplicationServices
import AppKit
import Foundation
import ImageIO

// MARK: - 인자

var sourceNeedle = ""
var targetNeedle = ""
var outPath = "/tmp/relay-drag.png"
var doDrop = true
var keepHeld = false
var moveTo: CGPoint?
var cropSize: CGFloat = 900

for arg in CommandLine.arguments.dropFirst() {
    func value(_ key: String) -> String? {
        guard arg.hasPrefix(key) else { return nil }
        return String(arg.dropFirst(key.count))
    }
    if let v = value("--source=") { sourceNeedle = v }
    else if let v = value("--target=") { targetNeedle = v }
    else if let v = value("--out=") { outPath = v }
    else if let v = value("--crop=") { cropSize = Double(v) ?? 900 }
    else if let v = value("--move=") {
        let parts = v.split(separator: ",").compactMap { Double($0) }
        if parts.count >= 2 { moveTo = CGPoint(x: parts[0], y: parts[1]) }
    }
    else if arg == "--cancel" { doDrop = false }
    else if arg == "--keep" { keepHeld = true }
}

guard !sourceNeedle.isEmpty, !targetNeedle.isEmpty else {
    FileHandle.standardError.write(Data("사용: --source=이름 --target=이름 [--out=경로] [--cancel] [--keep]\n".utf8))
    exit(2)
}

// MARK: - AX 헬퍼

func attr(_ el: AXUIElement, _ key: String) -> AnyObject? {
    var value: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(el, key as CFString, &value)
    return err == .success ? value as AnyObject : nil
}

func str(_ el: AXUIElement, _ key: String) -> String {
    (attr(el, key) as? String) ?? ""
}

func children(_ el: AXUIElement) -> [AXUIElement] {
    (attr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}

func point(_ el: AXUIElement) -> CGPoint? {
    guard let v = attr(el, kAXPositionAttribute) else { return nil }
    var p = CGPoint.zero
    guard AXValueGetValue(v as! AXValue, .cgPoint, &p) else { return nil }
    return p
}

func size(_ el: AXUIElement) -> CGSize {
    guard let v = attr(el, kAXSizeAttribute) else { return .zero }
    var s = CGSize.zero
    guard AXValueGetValue(v as! AXValue, .cgSize, &s) else { return .zero }
    return s
}

/// 요소의 **이름 또는 값**이 needle 을 포함하는지
func matches(_ el: AXUIElement, _ needle: String) -> Bool {
    let name = str(el, kAXTitleAttribute)
    let desc = str(el, kAXDescriptionAttribute)
    let value = str(el, kAXValueAttribute)
    return name.contains(needle) || desc.contains(needle) || value.contains(needle)
}

// MARK: - 앱 · 창 찾기

guard AXIsProcessTrusted() else {
    FileHandle.standardError.write(Data("접근 권한(AXIsProcessTrusted) 이 없습니다\n".utf8))
    exit(1)
}

guard let running = NSWorkspace.shared.runningApplications.first(where: {
    $0.bundleIdentifier?.contains("RelayConsole") == true
        || $0.localizedName?.contains("Relay Console") == true
}) else {
    FileHandle.standardError.write(Data("Relay Console 이 실행 중이 아닙니다\n".utf8))
    exit(1)
}

let app = AXUIElementCreateApplication(running.processIdentifier)
var wins = (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []

// ★ 창을 빈 곳으로 옮기고 전면에 올린다 — 다른 앱이 앞에 있으면 합성 드래그가
//   **그 앱에** 전달돼 아무도 못 본다(2026-11-15 실측).
if let moveTo {
    if let w = wins.first(where: { str($0, kAXTitleAttribute).contains("파일 탐색기") }) {
        var p = moveTo
        AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &p)!)
    }
    running.activate(options: [.activateAllWindows])
    usleep(900_000)
    wins = (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    if let w = wins.first(where: { str($0, kAXTitleAttribute).contains("파일 탐색기") }) {
        AXUIElementPerformAction(w, kAXRaiseAction as CFString)
    }
    usleep(500_000)
} else if let w = wins.first(where: { str($0, kAXTitleAttribute).contains("파일 탐색기") }) {
    AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
    usleep(300_000)
}

var nodes: [AXUIElement] = []
func walk(_ el: AXUIElement, _ depth: Int) {
    if depth > 12 || nodes.count > 4000 { return }
    if !str(el, kAXRoleAttribute).isEmpty { nodes.append(el) }
    for c in children(el) { walk(c, depth + 1) }
}
for w in wins { walk(w, 0) }

/// 이름·값이 needle 인 요소 중 화면에 보이는 것 — 텍스트 요소를 우선(줄의 이름 부분)
func findVisible(_ needle: String) -> AXUIElement? {
    let hits = nodes.filter { matches($0, needle) }
    let withPos = hits.filter { point($0) != nil }
    // 텍스트(StaticText)를 먼저 — 파일명 텍스트가 드래그 시작점으로 쓰기 좋다
    let texts = withPos.filter { str($0, kAXRoleAttribute) == kAXStaticTextRole }
    if let first = texts.first { return first }
    return withPos.first
}

guard let srcEl = findVisible(sourceNeedle) else {
    FileHandle.standardError.write(Data("원본 요소를 찾지 못했습니다: \(sourceNeedle)\n".utf8))
    exit(3)
}
guard let dstEl = findVisible(targetNeedle) else {
    FileHandle.standardError.write(Data("대상 요소를 찾지 못했습니다: \(targetNeedle)\n".utf8))
    exit(3)
}

guard let srcTop = point(srcEl), let dstTop = point(dstEl) else {
    FileHandle.standardError.write(Data("좌표를 얻지 못했습니다\n".utf8))
    exit(3)
}

let srcSize = size(srcEl)
let dstSize = size(dstEl)
// 시작점은 이름 텍스트 중앙(파일 아이콘 쪽), 도착점은 대상 텍스트 중앙
let start = CGPoint(x: srcTop.x + min(srcSize.width / 2, 40), y: srcTop.y + srcSize.height / 2)
let end = CGPoint(x: dstTop.x + min(dstSize.width / 2, 40), y: dstTop.y + dstSize.height / 2)

print("원본 \(sourceNeedle) → \(start)")
print("대상 \(targetNeedle) → \(end)")

// MARK: - 마우스 이벤트

func post(_ type: CGEventType, _ p: CGPoint) {
    guard let e = CGEvent(
        mouseEventSource: nil,
        mouseType: type,
        mouseCursorPosition: p,
        mouseButton: .left
    ) else { return }
    e.post(tap: .cghidEventTap)
}

func capture(_ path: String, around cursor: CGPoint, size: CGFloat = 900) -> Bool {
    // CGWindowListCreateImage 는 macOS 15 에서 폐기 → screencapture CLI 를 쓴다
    // (-R 은 화면 좌표(포인트) 기준 사각형)
    let rect = CGRect(
        x: max(0, cursor.x - size / 2),
        y: max(0, cursor.y - size / 2),
        width: size,
        height: size
    ).integral
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "-R", "\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))", path]
    do {
        try p.run()
        p.waitUntilExit()
    } catch {
        FileHandle.standardError.write(Data("캡처 실패: \(error.localizedDescription)\n".utf8))
        return false
    }
    return p.terminationStatus == 0 && FileManager.default.fileExists(atPath: path)
}

// MARK: - 드래그 수행

post(.mouseMoved, start)
usleep(150_000)
post(.leftMouseDown, start)
usleep(120_000)

// 드래그 시작점 인식용 미세 이동
post(.leftMouseDragged, CGPoint(x: start.x + 6, y: start.y + 4))
usleep(150_000)

// 중간 지점까지 이동 — 여기서 캡처하면 드래그 이미지와 커서를 함께 본다
let steps = 18
for i in 1...steps {
    let t = CGFloat(i) / CGFloat(steps)
    let p = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
    post(.leftMouseDragged, p)
    usleep(28_000)
    if i == 12 {
        let mid = CGPoint(x: start.x + (end.x - start.x) * 0.66, y: start.y + (end.y - start.y) * 0.66)
        // 실제 포인터 위치 — 마지막에 보낸 이벤트 좌표를 그대로 쓴다
        print("포인터 \(mid) (캡처 중심과 동일)")
        if capture(outPath, around: mid, size: cropSize) {
            print("캡처: \(outPath)")
        }
    }
}

if keepHeld {
    print("드래그를 붙든 채 종료 (마우스를 놓지 않음)")
    exit(0)
}

let releasePoint = doDrop ? end : start
post(.leftMouseDragged, releasePoint)
usleep(120_000)
post(.leftMouseUp, releasePoint)
print(doDrop ? "드롭 완료 (이동 실행)" : "제자리에서 놓음 (이동 없음)")
