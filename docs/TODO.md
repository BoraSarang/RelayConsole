# TODO.md
> 작업 추적 — bd 연동 (이슈 prefix: RelayConsole)

## 진행 중 (bd ready)
- [ ] **WindowFocus 육안** — 팝오버에서 설정/콘솔/디버그 클릭 시 창이 앞으로 오는지 사용자 확인 (코드 ✓ · 자동 확인: status item 1개 존재, 창 0/LSUIElement)
- [ ] **v0.5 감시 이벤트 계획 확정** — `PLAN_v0.5_relayconsole.md` + `RESEARCH_watch_events.md` 흡수 · ThresholdGate/hysteresis/severity 설계 완료 · 구현 착수 대기 (메뉴바 PR 머지 후 `feat/watch-events`)

## 완료 (2026-09-23)
- [x] **메뉴바 UX v0.4.1** — 상태 아이콘(0대 흰 안테나 / 1대+ 흰 Android+초록점) · 텍스트 제거 · 팝오버 `n/m`+`relay.menubarMetrics` · 빈 상태 emptyState · 기기 상세 힌트 · `WindowFocus` 신규 · DEBUG-GHOST 제거 · i18n **72키** · 테스트 **60/60** · 금지 0
- [x] **v0.4 실기기 육안** — 팝오버↔대시보드 8카드 동일 형식 · SENSORS 활성 이름+주기 · GPU/STORAGE R/W 사용자 확인 ✓ · bd `RelayConsole-or6` closed
- [x] **v0.4 UI 통일 + 센서 파서 Samsung 형식** — `DroidCards` 공용 8카드(팝오버 단일 컬럼·대시보드 2열) · `parseSensorsSummary` Samsung 활성행 이름/selected ms · `droid.card.sensors.none`/`droid.battery.temp` · 팝오버 미사용 Values/cardFull 제거 · 테스트 60/60 · i18n 69키 · debug 0.4.0 OK
- [x] **v0.4 P2 구현** — kgsl GLES/busy/clk + sensorservice + diskstats sda delta · Dashboard GPU/SENSORS 카드 + STORAGE R/W · i18n · 버전 0.4.0 · `swift test` 59/59 · debug 빌드 OK · PLAN_v0.4/C2 부분 해제(gfxinfo 금지 유지)
- [x] **v0.3 DoD 전수 + 육안** — 접힘/펼침·행 클릭→콘솔·S22/IP·CPU 8코어·MEM 압박·NET↑↓+RSRP·THERMAL 존·BATTERY 6타일·메뉴바 5지표 ON/OFF 사용자 확인 ✓
- [x] **v0.3 구현 Step 1–9** — 파서·다중 serial·selectedSerial·UI Phase1·i18n·버전 0.3.0 · `swift test` 50/50 · debug 빌드 OK · 금지어/iStat 단어경계/GPU/SENSORS 0
- [x] **v0.3 방향 확정** — 목업 피델리티 상향 + 다중 기기 포함, 기기 클릭→콘솔, GPU/SENSORS→P2, 메뉴바 5지표 설정 토글, USB/IP 연결 표시 · PLAN_v0.3 초안 작성
- [x] **목업·PLAN·구현 갭 분석** — 접힘/펼침=단일 기기 상세(목업), 저장만 다중·수집/표시 1대, 카드 Phase1 미구현 확인
- [x] **v0.2 SettingWatch·LogcatWatch 실연동** — settings get 2키 5s baseline+delta, logcat -T last-cursor + afterTimestamp 필터(중복 재카운트 방지), DeviceSnapshot counters → footer 실데이터 · 테스트 37/37 · 육안 footer (0) 표시 확인
- [x] **DoD 전수 통과 (v0.1)** — PLAN §10 체크 · 테스트 27/27 · 금지 grep 0 · 실기기 육안
- [x] T-106~T-109 — 팝오버·대시보드·인터랙션·빌드/DoD
- [x] sparkline — OPSparkline + ConsoleStore.metricsHistory(60점), CPU/BATTERY/NETWORK/THERMAL 카드 + 발열 배너, netUp/Down 필드
- [x] 팝오버 레이아웃 — 고정 헤더/푸터 + 중간 스크롤(360×560), 배터리 H/V/Cycle·보호모드, 네트워크 Wi-Fi/LTE, 기기 상세 expand, 이벤트 접힘
- [x] 사이드바 선택 — ConsoleView selection 바인딩 + 섹션 전환 placeholder
- [x] ADB 파서 9종 — parseBatteryEx·Thermal·LoadAvg·MemInfo·ProcStat·Df·NetDev·NetworkType + cpu/net delta
- [x] DeviceMonitor 폴링 — 5s battery/thermal/load/stat, 15s mem/net/df/connectivity, Android/SDK, 기기 연결·오프라인 이벤트, P0-a merge
- [x] 샘플 흡수 — 발열 배너·CPU 바·THERMAL 6카드·status/shortId, DeviceSnapshot 확장
- [x] T-101 SwiftPM 스캐폴드 — Package.swift(macOS 26), Info.plist `com.borasarang.relayconsole`
- [x] T-102 BrandKit 반영 — AppIcon.icns + MenuBarTemplate.png, 앱명 Relay Console, 메뉴바 RELAY
- [x] 보강 흡수 — PROMPT-FINAL-V0-2 → PLAN §1·DoD
- [x] 레인보우/Red 핫픽스 — material/glass 0, 솔리드 #0f111a, darkAqua
- [x] 다국어 KO/EN — Localizable.xcstrings + ko/en.lproj, UI 키화
- [x] 버전 0.4.0 · bundleId `com.borasarang.relayconsole`
- [x] git/bd init · 브랜드·문서 이관 · PLAN 확정

## 참고 (Outpost 유산 — 코드 미이관)
- 구 이슈 Outpost-4ag (콘솔 열기) 등은 원 프로젝트에 남음 — 새 코드에서 P1 재검증
- P0 배터리 미연결 버그는 선결 패턴으로 재발 방지 (PLAN §2)
- UserDefaults 접두어 `outpost.*` → `relay.*` (신규 코드)
