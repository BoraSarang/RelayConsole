# session-2026-09-24-apple-phase1-macos.md

## 1. 목표
- Apple 감시 1차 (방향 A Phase1) — Trust-only libimobiledevice + 오프라인 UI

## 2. 검증
- `swift test` **120/120**
- `./build_and_run.sh debug macos` 0 error · **0.9.0**
- i18n **271/271/271** · 사용 키 missing 0
- 금지 grep: 기존 주석 허용 · print는 DebugLogger 허용
- **오프라인 UI 육안 사용자 확인 완료** (주입 5종·배너·cards.empty)

## 3. 산출
- PR **#7** `feat/apple-phase1` — IdeviceClient·AppleDeviceMonitor·Dashboard·4카드
- PR **#8** `feat/apple-offline-ui` — DEBUG 주입·오프라인/오류 배너
- ErrorCodes E-MAC-APL-0001..0004 · `PLAN_apple_phase1`

## 4. 보류 (사용자 확정)
- 실기 USB Trust — iPad 데이터 불량 (안드로이드 동일 케이블 OK)
- Apple Phase 2 — 기기 확보 후

## 5. 다음
- 사이드바 Sites / Jobs / Alerts 실뷰 (placeholder → 실제 화면)
