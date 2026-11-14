#!/usr/bin/env swift
// 화면 좌표를 실제 마우스 클릭으로 누른다.
//
// 왜 필요한가 (2026-11-15)
//   메뉴바 상태 항목(NSStatusItem)은 **커스텀 뷰**라 AXPress 가 없다
//   (`perform action "AXPress"` → missing value). System Events 의 `click at` 은
//   앞에 있는 앱 창을 누르는 경우가 있어 팝오버가 열리지 않았다.
//   → CGEvent 로 좌표를 직접 눌러야 상태 항목이 열린다.
//
// 사용: swift scripts/click-at.swift 1287,12 [--double]
import CoreGraphics
import Foundation

let args = Array(CommandLine.arguments.dropFirst())
guard let xy = args.first?.split(separator: ",").compactMap({ Double($0) }), xy.count >= 2 else {
    FileHandle.standardError.write(Data("사용: click-at.swift x,y [--double]\n".utf8))
    exit(2)
}
let point = CGPoint(x: xy[0], y: xy[1])
let double = args.contains("--double")

func post(_ type: CGEventType, _ p: CGPoint) {
    guard let e = CGEvent(mouseEventSource: nil, mouseType: type,
                          mouseCursorPosition: p, mouseButton: .left) else { return }
    e.post(tap: .cghidEventTap)
}

post(.mouseMoved, point)
usleep(80_000)
for _ in 0..<(double ? 2 : 1) {
    post(.leftMouseDown, point)
    usleep(60_000)
    post(.leftMouseUp, point)
    usleep(80_000)
}
print("클릭 \(Int(point.x)),\(Int(point.y))")
