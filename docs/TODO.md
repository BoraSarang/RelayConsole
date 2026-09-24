# TODO.md
> 작업 추적 — bd 연동 (이슈 prefix: RelayConsole)

## 진행 중 (bd ready)
- [ ] **Alerts 육안 (PLAN_alerts · 0.9.1)** — 3탭·필터·그룹·ack/mute/메모·export · 탭 전영역 클릭 ✓ · **잔여 육안 대기**
- [ ] **Sites/Jobs 육안 (PLAN_sites_jobs · 1.0.0)** — 구현 PR-A+B ✓ · 육안 피드백 수정 완료 · **사용자 육안 대기**
- [ ] **Sites v1.1 (PLAN_sites_v1_1 · UptimeRobot+Google식)** — C1 임계값·가동률·dayBars · C2 Sites 행 UI · C3 메뉴바 폭오버 구현 ✓ · i18n 382 · 테스트 ✓ · build 1.1.0 ✓ · **육안 대기**

## 보류 (기기 확보 시)
- [ ] **Apple 실기 Trust 육안** — iPad USB 데이터 불량(안드로이드 동일 케이블 OK·복구도 미인식). 기기 확보 후 `brew install libimobiledevice` → 배터리/스토리지 카드
- [ ] **Apple Phase 2** — Developer Mode·sysmon 등 — 위 기기 확보 후 착수

## 완료 (2026-09-24)
- [x] **Sites/Jobs 육안 피드백 수정** — `jobs.token`/`jobs.lastBeat` `%s`→`%@` (작업 추가 직후 카드 렌더 크래시 · IPS `L10n.format`) · Sites 연필 수정 + `updateSite` · 대상 검증 `validateTarget`(http/tcp/ping) · Jobs 추가 curl 붙여넣기→토큰 import · 카드 curl 선택/복사 · i18n **365** · SitesJobsTests **25**
- [x] **Sites/Jobs 구현 (PR-A+B · 1.0.0)** — Site HTTP/TCP/ping · 90일 상태바·스파크라인 · Job 하트비트 127.0.0.1·overdue grace · Alerts siteDown/siteUp/jobOverdue/jobRecovered · SitesView·JobsView · 설정 포트 · i18n **353** · 테스트 신규 20 · **1.0.0** · `PLAN_sites_jobs` · PR **#14** + PR-B
- [x] **Alerts 탭 전영역 클릭** — `contentShape(Rectangle())` · PR **#13** 머지
- [x] **Alerts 구현 (PR-A+B)** — `WatchEvent` source/ack/note/mutedUntil · `WatchEventAlerts` 필터·그룹·export · Apple WatchEvent 편입 · `AlertsView` 3탭·심각도/기간/플랫폼 필터·serial 그룹·ack/mute 1h·24h/메모·JSON/CSV export · ConsoleView 연결 · 설정 기간 · i18n **315** · 테스트 **139/139** · **0.9.1** · `PLAN_alerts` · PR **#10**·**#11** 머지
- [x] **Apple 오프라인 UI 육안 (USB 불필요)** — DEBUG 주입 온/오프/오류/도구오류·해제 · 오프라인 배너 · E-MAC-APL 배너 · 카드 OFF `cards.empty` **사용자 확인 완료** · PR **#8** 머지
- [x] **Apple 감시 1차 (방향 A Phase 1)** — Trust-only `IdeviceClient` 파서·`AppleDeviceMonitor` 60s 폴링 · `AppleDashboardView`+4카드(`OPColor.apple`) · brew 확인 1회 안내 · `relay.selectedAppleUdid` · E-MAC-APL-0001..4 · i18n **264** · 테스트 **120/120** · debug **0.9.0** · `PLAN_apple_phase1` · PR **#7** 머지
- [x] **실기기 육안 (v0.7~v0.9·사이드바)** — scrcpy·스샷·로그·ANR/크래시 주입·카드 On/Off·이력 복원·사이드바 B안 **전부 확인 완료**
- [x] **사이드바 B안 라벨** — Droid/Apple/Sites/Jobs/Notify → **기기(Devices)**·사이트·작업·알림(Alerts) · Devices 하위 Android/Apple 세그먼트 · placeholder `sidebar.soon` · i18n **234** · PR **#6** 머지
- [x] **v0.9 카드 On/Off + EventStore 1차** — `relay.cards.*` 8카드 `@AppStorage` · 대시보드·팝오버 공통 필터 · 전체 OFF `cards.empty` · 설정 섹션 · `WatchEvent: Codable` · `EventStore` JSON(Application Support, 500건, ISO8601) · 시작 로드/ingest 저장 · i18n **227** · 버전 **0.9.0**
- [x] **v0.8 ANR/크래시 logcat** — `WatchKind.{anr,crash}` · `DeviceMonitor.{anr,crash}Keywords` · `feedAnr`/`feedCrash` 5분 쿨다운·kind 독립 · clear 자동 없음(TTL) · `relay.watch.{anr,crash}` · remediation steps · DEBUG 주입 · i18n · 테스트 +7
- [x] **v0.7 PR #4 머지** — `feat/v07-scrcpy-watch` → main `39c4115` · scrcpy A안 + 감시 마감 + 스샷·로그뷰어
- [x] **헤더 썸네일 UX A안** — 36×64 미니 썸네일 제거 · `[미러링][스샷][IP]` · 📷 → `ScreenshotPreviewSheet`(400pt·시각·새로고침·미러링 열기) · i18n **201** · 테스트 101/101 · debug 0.7.0
- [x] **후속조치 영구잔류 수정 (A+B)** — 스로틀링 clear ≤2(SEVERE 이탈) · TransitionGate 해제는 쿨다운 무시 · forget/disconnect synthetic clear · 배터리 충전 시 warning clear · Bsoh pre-drop 회복 clear · 저전력 ON severity warning · 가이드 fingerprint 최신 우선 + **30분 TTL** · i18n **198** · 테스트 **101/101** · debug 0.7.0
- [x] **scrcpy 창 포커스** — 런치 후 0.35/0.9/1.8/3s activate 리트라이 + System Events frontmost · 실행 중 헤더 클릭=창 앞으로(정지 아님, 종료=창 닫기) · `runningHint` 키 · i18n **196** · 테스트 91/91 · debug 0.7.0
- [x] **v0.7 scrcpy A안 + 감시 마감 + 썸네일·로그뷰어** — `ScrcpyController`(PATH/brew/원클릭/옵션 8종) · 헤더 버튼 2면 · `feedBsoh`(Δ≥5)·`feedRsrp`(Δ≤−6)·복구 토글 · screencap 썸네일 · logcat 창 `id:"logs"` · C3 Scrcpy 해제 · i18n **195→196키 3곳** · `PLAN_v0.7` · 버전 **0.7.0**
- [x] **v0.6 Phase2 감시 A5** — `feedPsi`(5.0/3.0/120s)·`feedLoad`(cores×2/×1/60s, ≥3× critical)·`feedMemory`(usedPct 90/80, ≥95 critical) · DeviceMonitor 연결(coreCount·mem usedPct·PSI) · 설정 `relay.watch.{psi,load,memory}` · remediation 3종 · DEBUG 주입 4 · i18n **151키 3곳** · 테스트 **88/88** · debug **0.6.0** OK · `PLAN_v0.6`
- [x] **브랜치 정리** — `feat/watch-events` 로컬·원격 삭제 · `feat/menubar-ux-windowfocus` 원격 prune · main 동기화
- [x] **v0.5 PR #2 머지** — `feat/watch-events` → main `64d84e4` · 육안 확인 완료 · 다음 스프린트: Phase2
- [x] **v0.5 육안·WindowFocus 육안** — 팝오버 설정/콘솔/디버그 창 포커스 ✓ · 디버그 주입(스로틀/충전/보호)·알림 배너/메뉴바 배지 ✓ · 실기 충전 전이 ✓
- [x] **프로세스 목록 수정** — 메뉴바 시트 닫힘 → 독립 윈도우 `id:"processes"` · 컬럼 이름/PID/CPU/RAM/커맨드(ps ARGS: 앱=패키지ID, 네이티브=경로) · 아이콘 adb 제한 명시 · i18n **129키 3곳** · 테스트 **84/84** · debug 0.5.0 OK
- [x] **프로세스 목록 (CPU+RAM)** — 메모리 카드 상위5+CPU%+더보기 · `ProcessListSheet` 시트(이름/CPU/RAM 정렬) · `dumpsys cpuinfo`+`ps` RSS 병합 · 대시보드·팝오버 양쪽 · i18n **126키 3곳** · 테스트 **82/82** · debug 0.5.0 OK
- [x] **디버그 주입 버튼 히트영역** — `.plain` 글자만 클릭 → `contentShape`+배경 내부 이동으로 버튼 전체 클릭
- [x] **권장 후속 조치 가이드 + 신규 감시 3종** — 팝오버 미해결 warning+ 시 `권장 후속 조치` 체크리스트(스로틀링/보호모드/배터리/저전력) · `lowPowerChanged`(`settings global low_power`) · `batteryThreshold` 20/10/5% discharge 1회+충전 재무장 · 보호모드 해제 주입 · 설정 `relay.watch.{lowPower,battery}` · i18n **118키 3곳** · 테스트 **80/80** · WindowFocus 빌드 수정 · debug 0.5.0 OK
- [x] **알림형 상단 배너 + 설정 토글** — `AlertBannerPresenter`(NSPanel, 메뉴 팝오버 아님) · "알림: 기기 — 이벤트" 4초 자동 사라짐 · `relay.watch.banner` 기본 ON · `settings.watch.banner` · i18n **93키 3곳** · `swift test` **77/77** · debug 빌드 0.5.0 OK
- [x] **팝오버 상단 이벤트 배너** — `recentWatchEvents` 최신 1건, `thermalBanner`와 동일 스타일, severity 색(critical=bad/warning=warn/clear=ok), 접힘 무관 노출
- [x] **v0.5 감시 이벤트 Phase1 구현** — `ThresholdGate`+`TransitionGate`(hysteresis/cooldown) · `WatchEvent` kind/severity/fingerprint · `WatchEngine` thermal/charge/protection feed · `ConsoleStore` fingerprint 5분 쿨다운+UNNotification · 팝오버 severity 목록 · 메뉴바 critical 주황 배지 · 설정 `relay.watch.*` 4토글 · i18n **83키 3곳 일치** · 버전 **0.5.0** · `swift test` **77/77** · 금지 grep 0(Views/App print) · `PLAN_v0.5` A1–A4·A6

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
