#!/usr/bin/env swift
// 시스템 전역 AX 에서 Relay Console 상태 항목(메뉴바 아이콘)을 찾는다.
//
// 왜 필요한가 (2026-11-15)
//   파일 탐색기 창은 **메뉴바 팝오버의 폴더 버튼**으로만 열려 있다.
//   드래그 이미지 실험(AX 합성 드래그)을 자동화하려면 그 창을 먼저 열어야 하는데,
//   상태 항목 버튼이 화면 어디 있는지 알아야 한다 → 전역 AX 를 훑는다.
import ApplicationServices
import AppKit
import Foundation

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

guard AXIsProcessTrusted() else {
    FileHandle.standardError.write(Data("접근 권한 없음\n".utf8))
    exit(1)
}

let system = AXUIElementCreateSystemWide()
var nodes: [AXUIElement] = []
func walk(_ el: AXUIElement, _ depth: Int) {
    if depth > 8 || nodes.count > 6000 { return }
    let role = str(el, kAXRoleAttribute)
    if !role.isEmpty { nodes.append(el) }
    for c in children(el) { walk(c, depth + 1) }
}
walk(system, 0)

let needles = ["Relay", "RELAY", "Relay Console"]
var hits: [(String, String, CGPoint?)] = []
for el in nodes {
    let name = str(el, kAXTitleAttribute)
    let desc = str(el, kAXDescriptionAttribute)
    let role = str(el, kAXRoleAttribute)
    if needles.contains(where: { name.contains($0) || desc.contains($0) }) {
        hits.append((role, name.isEmpty ? desc : name, point(el)))
    }
}

if hits.isEmpty {
    print("상태 항목 못 찾음 — 메뉴바 쪽 AX 요소를 모두 출력")
    for el in nodes {
        let role = str(el, kAXRoleAttribute)
        guard role == kAXMenuBarItemRole || role == kAXMenuButtonRole || role == kAXButtonRole else { continue }
        let name = str(el, kAXTitleAttribute)
        let desc = str(el, kAXDescriptionAttribute)
        guard !name.isEmpty || !desc.isEmpty else { continue }
        print("  · \(role) — \(name.isEmpty ? desc : name) \(point(el).map { "(\(Int($0.x)),\(Int($0.y)))" } ?? "")")
    }
    exit(1)
}

for h in hits {
    print("\(h.0) — \(h.1) \(h.2.map { "(\(Int($0.x)),\(Int($0.y)))" } ?? "")")
}
