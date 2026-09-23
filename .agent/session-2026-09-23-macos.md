# session-2026-09-23-macos — v0.4 P2 + UI 통일

1. **범위**: P2 GPU·SENSORS·STORAGE R/W 카드 + 팝오버↔대시보드 형식 통일 + Samsung 센서 파서
2. **구현**: kgsl GLES/busy/clk, sensorservice, diskstats sda delta → `DeviceInventory` P2 필드·`DeviceMonitor` 15s 폴링·`DroidMetrics` history
3. **UI**: 신규 `Views/DroidCards.swift` 공용 8카드 — `DroidDashboardView` 2열 그리드, `MenuBarPopoverView` 단일 컬럼 (구 cardFull/Values 제거)
4. **파서**: `parseSensorsSummary` Samsung 형식 — `이름(handle=0x…)` + `active-count` + `selected = ms` 이름·주기 추출; `droid.card.sensors.none` 폴백
5. **검증**: `swift test` **60/60**, debug 빌드 **0.4.0** OK, 금지 grep 0, i18n ko/en/xcstrings **69키 3곳 정합**
6. **문서**: `PLAN_v0.4` DoD 갱신 (육안 1항목), `TODO` 갱신, `PLAN_v0.1` C2 부분 해제 유지
7. **bd**: `RelayConsole-or6` **closed** — 육안 확인 ✓
8. **다음**: v0.4 완료. 커밋은 요청 시에만.
