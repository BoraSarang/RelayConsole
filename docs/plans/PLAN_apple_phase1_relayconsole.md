# PLAN_apple_phase1_relayconsole.md — Apple 감시 1차 (Trust-only)

> 생성일: 2026-09-24 | 상태: **1차 마감** (오프라인 UI 육안 ✓ · 실기 Trust·Phase2 보류)
> 근거: `docs/research/RESEARCH_apple_relay.md` 방향 A Phase 1
> 앱: **Relay Console** | 버전: **0.9.0** | PR **#7**·**#8** 머지

---

## 1. 범위 (IN / OUT)

| IN | OUT |
|----|-----|
| Trust-only `libimobiledevice` (`idevice_id`/`ideviceinfo`) | usbmuxd/공개 API 하드코딩 |
| 배터리·스토리지·디바이스·써멀 enum 카드 | 써멀 raw 온도·CPU/GPU/센서 (Tier1 불가) |
| `AppleDashboardView` + `ConsoleView` 연결 | Wi-Fi 전용 배터리 쿼리 |
| 도구 미설치 brew 안내 (확인 1회) | 자동 설치 · 다운로드 |
| i18n · 파서 테스트 · E-MAC-APL | Apple Watch · 활성 앱/프로세스 |

## 2. 구성

- `Apple/IdeviceClient.swift` — 순수 파서·경로 탐지 (IO 없음)
  - `parseDeviceIds` / `parseInfo` / `parseBool` / `snapshot` / `shortUdid` / `bytesToGB`
- `Apple/AppleDeviceMonitor.swift` — actor · 60s 폴링 · Process IO
  - tools 없음 → 오프라인 정리 · 연결/해제 이벤트 → EventStore 푸시
- `Views/AppleDashboardView.swift` — 헤더·다기기 선택·brew 안내
- `Views/AppleCards.swift` — BATTERY / STORAGE / THERMAL / DEVICE (`OPColor.apple` #D9E0F2)
- `ConsoleStore.appleDevices` / `selectedAppleUdid` (`relay.selectedAppleUdid`)
- `ErrorCodes` E-MAC-APL-0001..0004 · `error_message_ko.json`
- 설정: `settings.section.apple` + tools 상태

## 3. 가용 데이터 (Phase 1)

| 카드 | 키 | 비고 |
|------|-----|------|
| DEVICE | DeviceName/ProductType/ProductVersion | |
| BATTERY | BatteryCurrentCapacity / BatteryIsCharging | USB Trust 권장 |
| STORAGE | com.apple.disk_usage Total* | 실패 시 — |
| THERMAL | ThermalState enum | lockdown 미제공 시 — |

## 4. 검증

- [x] `swift test` **120/120** (IdeviceParsingTests 12 포함)
- [x] debug 빌드 **0 error** · 0.9.0
- [x] i18n 일치 · 사용 키 missing 0
- [x] 금지 grep 0 (기존 주석 허용) · 자동 curl/다운로드 0
- [x] **오프라인 UI 육안** — DEBUG 주입 5종 · 오프라인/오류 배너 · 카드 OFF **사용자 확인**
- [ ] USB 실기기 Trust 카드 — **보류** (iPad 데이터 불량 · 기기 확보 시)

## 5. 오프라인 육안 (Phase1-b) — 완료 ✓

| 상태 | 진입 | 확인 |
|------|------|------|
| 온라인 카드 | 디버그 → Apple 온 | 헤더 초록·4카드·충전 칩 ✓ |
| 오프라인 | Apple 끄기 | 빨강 배너·마지막 스냅샷 ✓ |
| 연결 오류 | Apple 오류 | `[E-MAC-APL-0002]` 배너·해제 ✓ |
| 도구 오류 | Apple 도구오류 | `[E-MAC-APL-0001]` 문구 ✓ |
| 카드 OFF | 설정 카드 표시 | 배터리·스토리지·써멀 OFF → `cards.empty` ✓ |
| 주입 해제 | Apple 주입해제 | 기기 없음 empty ✓ |

## 6. 보류

- 실기 Trust · Apple Phase 2 — 기기(정상 USB 데이터) 확보 후