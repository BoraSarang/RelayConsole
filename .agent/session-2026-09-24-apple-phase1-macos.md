# session-2026-09-24-apple-phase1-macos.md

## 1. 목표
- Apple 감시 1차 (방향 A Phase1) — Trust-only libimobiledevice

## 2. 검증
- `swift test` **120/120**
- `./build_and_run.sh debug macos` 0 error · **0.9.0**
- i18n **264/264/264** · 사용 키 missing 0
- 금지 grep: 기존 주석 허용 · print는 DebugLogger 허용

## 3. 산출
- `Apple/IdeviceClient.swift` — 순수 파서 + locate
- `Apple/AppleDeviceMonitor.swift` — 60s 폴링 actor
- `Views/AppleDashboardView.swift` + `AppleCards.swift` (BATTERY/STORAGE/THERMAL/DEVICE)
- `ConsoleStore.appleDevices` / `selectedAppleUdid` (`relay.selectedAppleUdid`)
- ErrorCodes E-MAC-APL-0001..0004 · 설정 Apple 섹션
- `PLAN_apple_phase1` · i18n +30 → 264

## 4. 미해결
- 실기기 육안 (USB Trust · brew 안내 버튼 · 카드 수치)
- THERMAL/건강·사이클: lockdown 미제공 기기에서는 — 표시
