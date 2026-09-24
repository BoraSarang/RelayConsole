# PLAN_apple_phase1_relayconsole.md — Apple 감시 1차 (Trust-only)

> 생성일: 2026-09-24 | 상태: **구현**
> 근거: `docs/research/RESEARCH_apple_relay.md` 방향 A Phase 1
> 앱: **Relay Console** | 목표: 사이드바 Apple 실뷰 · 버전 유지 **0.9.0** (기능만 추가)

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
- [x] i18n **264/264/264** · 사용 키 missing 0
- [ ] Apple 세그먼트 육안: 도구 없음 안내 / 기기 연결 시 카드 (실기기 대기)
- [x] 금지 grep 0 (기존 주석 허용) · 자동 curl/다운로드 0
