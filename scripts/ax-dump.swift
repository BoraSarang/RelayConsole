#!/usr/bin/env swift
// AX 트리 순회 도구 — SwiftUI 창의 보조기술 요소를 실제로 훑는다
//
// 왜 필요한가 (2026-09-28)
// SwiftUI 창에서 AppleScript 의 `entire contents` 는 **0** 을 반환한다.
// `UI elements` 로 한 단계는 들어가지만, `entire contents` 의 재귀가 실패한다.
// → 사용 가능한 경로는 **직접 AXChildren 을 따라가는 것**뿐이다.
//
// 사용:
//   swift scripts/ax-dump.swift                     # 프로세스 이름 앞 4글자로 찾음
//   swift scripts/ax-dump.swift "Relay Console"      # 프로세스 이름 지정
//   swift scripts/ax-dump.swift "Relay Console" --buttons   # 버튼 계열만
//   swift scripts/ax-dump.swift "Relay Console" --click "기기에서"   # 이름에 포함된 요소를 누름
import ApplicationServices
import AppKit
import Foundation

// 인자: [프로세스이름] [--window=이름] <모드> [검색어]
// `--window=` 는 **위치를 밀지 않게** 먼저 떼어 낸다 —
// (실측: 제거하지 않으면 needle 이 "--click" 이 되어 매칭이 조용히 실패했다)
let rawArgs = Array(CommandLine.arguments.dropFirst())
let windowNeedle = rawArgs.first(where: { $0.hasPrefix("--window=") })?
    .replacingOccurrences(of: "--window=", with: "")
let args = rawArgs.filter { !$0.hasPrefix("--window=") }
let procName = args.first ?? "RelayConsole"
let mode = args.count > 1 ? args[1] : "--buttons"
let needle = args.count > 2 ? args[2] : ""

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

func pidOf(_ name: String) -> pid_t? {
    guard AXIsProcessTrusted() else {
        FileHandle.standardError.write(Data("접근 권한(AXIsProcessTrusted) 이 없습니다\n".utf8))
        return nil
    }
    // 실행 중 프로세스를 NSWorkspace 로 찾는다 (AX API 에 이름→pid 함수가 없다)
    let running = NSWorkspace.shared.runningApplications
    guard let found = running.first(where: {
        $0.localizedName?.contains(name) == true || $0.bundleIdentifier?.contains(name) == true
    }) else { return nil }
    return found.processIdentifier
}

guard let pid = pidOf(procName) else {
    FileHandle.standardError.write(Data("프로세스를 찾을 수 없음: \(procName)\n".utf8))
    exit(1)
}
// ★ 앱을 **앞에 올려야** 트리가 완성된다 — 앞이 아니면 푸터·창 일부가 비어 보인다.
// (2026-09-28 실측: 요소 수가 실행마다 247~270 으로 흔들렸다)
if let running = NSRunningApplication(processIdentifier: pid) {
    running.activate(options: [.activateAllWindows])
    usleep(700_000)
}
let app = AXUIElementCreateApplication(pid)
var wins = (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
if wins.isEmpty {
    print("창 없음 (앱이 실행 중인지, AX 권한이 있는지 확인)")
    exit(1)
}

// ★ **어떤 창이 key 인지가 트리를 정한다** (2026-09-28 실측)
//   앱 전체를 활성화하면 창 0(대시보드) 이 올라가면서 **로그 창의 서브트리가 잘린다**
//   → 요소 수가 실행마다 247~270 으로 흔들린 것이 이 때문이었다.
//   `--window=<이름 일부>` 로 **그 창을** key 로 만들어야 푸터까지 보인다.
//   ★ 다만 **클릭 모드에서는 초점을 건드리지 않는다** — 로그 창을 key 로 만들면
//   **팝오버가 닫힌다**(초점이 다른 곳으로 가면 팝오버는 사라진다).
//   실측: --window 를 붙인 채 클릭하면 팝오버 요소가 보이지 않아 "대상 없음" 이 된다.
// ★ **읽기 전용 모드는 초점을 건드리지 않는다** (2026-09-28 실측)
//   초점을 옮기면 **팝오버가 닫힌다** → 요소를 못 보고 "대상 없음" 으로 조용히 실패한다.
//   클릭·조회·계수 어느 쪽이든 **보는 동작**은 사용자의 화면을 바꾸지 않아야 한다.
let readOnlyModes: Set<String> = ["--click", "--values", "--count", "--rows"]
if !readOnlyModes.contains(mode) {
    if let needle = windowNeedle, let w = wins.first(where: {
        str($0, kAXTitleAttribute).contains(needle)
    }) {
        AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(w, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        usleep(500_000)
        wins = (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? wins
    } else if let w = wins.first {
        AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
        usleep(300_000)
    }
}

var nodes: [(el: AXUIElement, role: String, name: String, desc: String, depth: Int)] = []
func walk(_ el: AXUIElement, _ depth: Int) {
    if depth > 12 || nodes.count > 4000 { return }
    let role = str(el, kAXRoleAttribute)
    if role.isEmpty { return }
    let name = str(el, kAXTitleAttribute).isEmpty ? str(el, kAXDescriptionAttribute) : str(el, kAXTitleAttribute)
    nodes.append((el, role, name, str(el, kAXDescriptionAttribute), depth))
    for c in children(el) { walk(c, depth + 1) }
}
for w in wins { walk(w, 0) }

let interactive: Set<String> = [
    kAXButtonRole, kAXCheckBoxRole, kAXRadioButtonRole, kAXMenuButtonRole,
    kAXPopUpButtonRole, kAXSliderRole, kAXTextFieldRole, kAXDisclosureTriangleRole,
]

if mode == "--click" {
    guard let hit = nodes.first(where: {
        interactive.contains($0.role) && ($0.name.contains(needle) || $0.desc.contains(needle))
    }) else {
        print("클릭 대상 없음: '\(needle)'\n사용 가능한 이름:")
        for n in nodes where interactive.contains(n.role) && !n.name.isEmpty {
            print("  · \(n.role) — \(n.name)")
        }
        exit(2)
    }
    let err = AXUIElementPerformAction(hit.el, kAXPressAction as CFString)
    print("클릭 \(hit.role) '\(hit.name)' → \(err == .success ? "성공" : "실패 \(err.rawValue)")")
    exit(err == .success ? 0 : 1)
}

// ★ `--rows` — **이름이 있는 요소를 전부** (읽기 전용)
//   태그 선택 표의 행은 이름이 `Watchdog, 5종 이상, 2,215줄` 형태인데
//   `--buttons` 는 상호작용 요소만 보고 `--values` 는 AXValue 만 본다 →
//   **이 둘 다 표 행을 잡지 못했다.** 읽기 전용이라 초점을 건드리지 않는다.
if mode == "--rows" {
    var shown = 0
    for n in nodes where !n.name.isEmpty {
        let pad = String(repeating: "  ", count: min(n.depth, 6))
        print("\(pad)\(n.role) — \(n.name)")
        shown += 1
        if shown > 200 { print("… (200개 초과 잘림)"); break }
    }
    print("— 이름 있는 요소 \(shown)개 / 전체 \(nodes.count)개 —")
    exit(0)
}

// ★ `--values` / `--count` — **텍스트 내용**을 읽는다 (2026-09-28 추가)
//   왜 필요했나: 로그 행처럼 SwiftUI 가 AX **이름이 아니라 값**으로 내는 요소가 있다.
//   이름만 보면 "요소 237개 · 이름 없음" 에서 끝나고, **무엇이 화면에 있는지 알 수 없다.**
//   MANUAL_VERIFY 8·9 는 "몇 줄이 보이느냐" 라는 **숫자**가 판별 기준이라 값이 필수였다.
if mode == "--values" || mode == "--count" {
    var texts: [String] = []
    for n in nodes {
        guard n.role == kAXStaticTextRole || n.role == kAXTextFieldRole
                || n.role == kAXTextAreaRole else { continue }
        guard let v = attr(n.el, kAXValueAttribute) as? String, !v.isEmpty else { continue }
        texts.append(v)
    }
    if mode == "--count" {
        guard let re = try? NSRegularExpression(pattern: needle, options: [.caseInsensitive]) else {
            FileHandle.standardError.write(Data("정규식 오류: \(needle)\n".utf8))
            exit(2)
        }
        let hit = texts.filter { re.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
        print("텍스트 요소 \(texts.count)개 중 '\(needle)' 와 일치 \(hit.count)개")
        for t in hit.prefix(5) { print("  · \(t.prefix(90))") }
        exit(0)
    }
    for t in texts { print(t) }
    print("— 텍스트 요소 \(texts.count)개 —")
    exit(0)
}

print("요소 \(nodes.count) 개 · 창 \(wins.count)개")
let wantButtons = mode.contains("--buttons")
var shown = 0
for n in nodes {
    let isInteractive = interactive.contains(n.role)
    if wantButtons && !isInteractive { continue }
    if wantButtons && n.name.isEmpty { continue }
    let pad = String(repeating: "  ", count: min(n.depth, 6))
    print("\(pad)\(n.role) — \(n.name.isEmpty ? n.desc : n.name)")
    shown += 1
    if shown > 60 { print("… (60개 초과 잘림)"); break }
}
