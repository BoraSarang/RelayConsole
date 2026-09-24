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
- 실기기 USB Trust 육안 **보류** — iPad 데이터 불량 (안드로이드 동일 케이블 OK · 복구 모드도 맥 ioreg 미인식)
- THERMAL/건강·사이클: lockdown 미제공 기기에서는 — 표시

## 5. 후속 (USB 없이)
- Apple DEBUG 주입 온/오프/오류 · 오프라인 배너 · E-MAC-APL 문구 · 카드 OFF 육안