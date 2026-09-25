# TODO.md
> 작업 추적 — bd 연동 (이슈 prefix: RelayConsole)

## 진행 중 (bd ready)
- (없음 — 리서치 §8 백로그 P1~P3 전수 완료)

## 다음 스프린트 (리서치 §8 잔여 · 미착수)
- [ ] **S3 관제 규칙 Rules as Code (로컬 YAML)** — TIER S 중 유일 미착수
- [ ] **A7** 라이브액티비티 / Dock 배지 / 그룹화
- **TIER A**: Things·캘린더 연동 · 스샷 스크랩북 · 멀티 스냅샷 그리드 · Prometheus/JSON export · cron 기기 태그 · 충전 방치 리포트

## 보류
### 육안/실측 대기 (사용자 지시 — 뒤로 미룸)
- [ ] **Wi-Fi 실측 검증** — 사용자 지시: "검증은 추후 실제 테스트 하는걸로 하고 킵 해둬"
- [ ] **A1 ntfy/Slack 실제 채널 테스트 전송** — RESEARCH §8 `148` · 설정→연동 테스트 (사용자)

### 기기 확보 시
- [ ] **Apple 실기 Trust 육안** — iPad USB 데이터 불량(안드로이드 동일 케이블 OK·복구도 미인식). 기기 확보 후 `brew install libimobiledevice` → 배터리/스토리지 카드
- [ ] **Apple Phase 2** — Developer Mode·sysmon 등 — 위 기기 확보 후 착수 (A9)
- [ ] **Apple 크래시 리포트 수집 (반드시 해야 할 작업)** — `idevicecrashreport`로 iOS `.ips` crash/ANR를 IncidentBundle에 첨부. 기기 확보 시 1순위. Trust USB + `idevicecrashreport -u <udid> copy` 패턴. Android `logcat -b crash`/dropbox 대응 Apple 쪽 원재료 — **기기 확보 전 구현 불가, 반드시 기억할 것**

## 완료 (2026-09-25)
- [x] **콘솔 대시보드 정리 (오늘요약 → 순서 → 크기 + 탐지 표시 C)** — ① **오늘 요약 상단 전폭 이동**(하단 제거) ② **우선순위 재배치** `DashboardLayout`(행 `CPU|THERMAL` · `MEMORY|NETWORK` · `BATTERY|HEALTH` · `GPU|STORAGE` · `SENSORS` 전폭) — `LazyVGrid` → **`Grid`+`GridRow`** + `DroidCards.shell(fillsRow:)`로 **행 바닥 정렬**(잘림 없음) ③ **차트 24pt 통일** `DroidCards.chartHeight` · STORAGE 듀얼 16×2 → `OPDualSparkline` 24 · NETWORK 차트를 더보기 직전(하단 고정)으로 재배치 · 오늘요약/탐지 카드 패딩·라운드를 카드와 동일화 ④ **설정 변경·logcat 구조화**: `WatchKind.{settingsChanged,logcatHits}` 신규 · `WatchEvent.detect`(severity **.info** — 알림·일일 경고 집계 제외) · `logcatHitBreakdown`(첫 매칭 귀속, 합계=count) · **5분 집계 윈도우**로 5s 폴링 폭주 방지 · 하단 텍스트 카운터 → **탐지 타임라인 카드**(오늘 건수 칩·시각·원인·행 탭→**Alerts**(`onOpenAlerts`)·`로그` 버튼→LogViewer) · 팝오버·설정 카드 토글 순서 미러링 · i18n **681→690** en/ko 동일·알파벳 정렬 · 테스트 **+9 → 313+86=399 통과** · `./scripts/build-macos.sh debug` **EXIT=0** · **사용자 육안 확인 ✓** · **PR #42 머지**
- [x] **[표시①]/[표시②] 규칙 신설 + 전수 적용** — `AGENTS.local.md` §4 2건(기기 식별 정확 표시 · 에러·상태 정확 표시) → **38 files**: `identLabel` 3종 통일 진입점 + `WatchEngine.ident` 해석기 주입 15곳 · `shortUdid` 삭제 · 내보내기 실패 제목 분리 · notify 테스트 실제 결과 · IssueLog 응답 후 성공/실패 기록 · Sites/Wi-Fi/scrcpy/Apple/하트비트 원인 노출(`sites.fail.*` 15키 포함) · `adbBadState` 통지 + `adb devices` 실패 조기 return · HealthScore 결측 보간 제거 → 가중치 재정규화 · 오프라인/최근 샘플/마지막 에러 배너 · LoginItem `errorDetail` · ko 오탈자 2건 · 테스트 **+5 → 390 passed** · i18n **681키** en/ko 1:1 · `build-macos` **EXIT=0** · **PR #42 머지**
- [x] **플로팅 헤더 미러링 버튼 위치 변경** — 투명도와 교환해 **X 바로 왼쪽**으로 이동 (`FloatingGraphView.swift` 헤더 순서 `대시보드→메뉴→투명도→미러링→X`)
- [x] **신규 4건 (네트워크/플로팅)** — ① 업/다운 분리 그래프(`netUpHistory`/`netDownHistory` 분리 · `OPDualSparkline`) ② 플로팅 헤더 대시보드 진입 버튼(프로세스/앱네트워크/콘솔) ③ 앱(UID) 네트워크 사용량(`netstats` UID stats 합산 + `pm list -U` 매핑 → `ProcessListSheet` NET 열 · `AppNetworkView` 창/시트) ④ 신호 진단(RSRP/RSRQ/SINR·RAT/BAND/CA → `SignalGrade` 등급칩 + 진단 팝오버 · 서브라인 IP 제외) · 플로팅 `isEnabled` 단일 진실원처 + 위치 `x,y,w,h` 저장/복원 + 다중화면 clamp · scrcpy popover+에러 팝오버 · i18n **641** · 테스트 **302** · **1.14.0** · **PR #40 머지 `73e9bd4`** · **사용자 육안 확인 ✓ (4건 전수)**
- [x] **신규 기능 육안 확인 (2026-09-25)** — 업/다운 분리 그래프 · 앱(UID) 네트워크 창 · 신호 등급칩/진단 팝오버 · 플로팅 진입 버튼 **사용자 확인 완료**
- [x] **인사이트 리모델링 Phase1~4 일괄 머지** — 저장 계층(WatchEvent 패키지/지문·ConnectionSessionStore·DeviceDailyStore) · InsightLogic/PatternLogic · InsightsView UI · Phase4 반복/해소 리포트 export · 설정/테마/플로팅/창 크롬 흡수 · **PR #39 머지 `399842c`**
  - [x] Phase1 저장 계층 + Phase2 InsightLogic/PatternLogic + 테스트 275 통과
  - [x] Phase3 UI — InsightsView(캘린더·패턴·전일대비·export) · Alerts 오늘/어제 칩 · Dashboard 오늘 요약 · Settings retention/pattern · i18n 610키 3처 정합 · `swift build`/`swift test` 통과
  - [x] Phase4 반복/해소 리포트 export 마감 — `InsightReportExport`/`InsightReportLogic` · 패턴 CSV 전체 컬럼 · `IssuePattern` Codable · 테스트 +3 · i18n 612 3처 · `swift test`/`build-macos` 통과
  - [x] 미커밋 작업 흡수 커밋 — 설정/테마/플로팅/창 크롬 + Phase1~4 일괄

## 완료 (2026-09-24)
- [x] **A6 Sites 90일 캘린더 + 태그** — `Site.tags`·`SitesCalendarLogic` · 태그 폼·필터 칩(AND) · 리스트/캘린더 · 90일 주 격자 · i18n **536** · SitesCalendarTests +13 · **1.13.0** · `PLAN_sites_calendar` · **PR #38 머지 `6e4b40e`** · bd `RelayConsole-9vi` closed
- [x] **A4 파일/스샷 갤러리** — `GalleryLogic`·`GalleryStore`·`GalleryController` · `GallerySheet`(로컬/기기) · 헤더 갤러리 버튼 · i18n **529** · GalleryTests +7 · **1.12.0** · `PLAN_gallery` · **PR #37 머지 `17d0cc0`** · bd `RelayConsole-40v` closed
- [x] **S2 Device Health Score** — `HealthScoreLogic`(배터리40·발열40·스로틀20 가중 0–100) · HEALTH 카드 + 헤더 칩 · `relay.cards.health` · i18n **506** · HealthScoreTests +10 · **1.11.0** · `PLAN_health_score` · **PR #36 머지 `9bf0eb5`** · bd `RelayConsole-czg` closed
- [x] **A10 로컬 MCP 서버** — `RelayMcpCore`·`relay-mcp` stdio · 읽기 전용 5도구(devices/sites/jobs/events/summary) · `AdbDevicesParser` · Settings MCP help · i18n **499** · McpProtocolTests +10 · **1.10.0** · `PLAN_local_mcp` · **PR #35 머지 `7fbe8e9`** · bd `RelayConsole-yzw` closed
- [x] **A8 로그인 항목 + 헤드리스** — `LoginItemLogic`·`LoginItemController`(SMAppService) · `HeadlessLaunch` accessory · 설정 일반 토글 2종 · `relay.login.launchAtLogin`·`relay.launch.headless`(기본 ON) · i18n **496** · LoginItemTests +8 · **1.9.0** · `PLAN_login_item` · **PR #34 머지 `be12b61`** · bd `RelayConsole-njd` closed
- [x] **A3 앱 미니 허브** — `AppHubLogic`·`AppHubController`·`AppHubSheet` · 헤더 Apps · 목록/런치/강제종료/삭제(확인) · i18n **484** · AppHubTests +10 · **1.8.0** · `PLAN_app_hub` · **PR #33 머지 `fb31578`** · bd `RelayConsole-mkk` closed
- [x] **S4 Incident Bundle** — `IncidentBundleLogic`·`IncidentBundleStore` · ANR/crash/siteDown 자동 캡처(manifest·logcat·screenshot · fingerprint 5분 쿨다운) · Alerts 행 수동 캡처·폴더 열기 · `relay.incident.auto` · i18n **466** · IncidentBundleTests +11 · **1.7.0** · `PLAN_incident_bundle` · **PR #32 머지 `2b0f227`** · bd `RelayConsole-5cr` closed
- [x] **A2 Wi-Fi ADB 온보딩** — `WifiAdbLogic`·`WifiAdbController` · USB→Wi-Fi 원클릭(tcpip+IP+connect) · 수동 IP:PORT · disconnect · 헤더/빈 상태 시트 · i18n **461** · WifiAdbTests · **1.6.0** · `PLAN_wifi_onboarding` · bd `RelayConsole-z9i` · **PR #31 머지 `dc26447`**
- [x] **A5 Sites SSL 만료 + HTTP assertion** — `Site.sslExpiresAt`·`assertBody` · `SslAssertLogic` · `TrustExpiryBox` · `WatchKind.sslExpiring` · `relay.sites.sslWarnDays`(14) · SSL D-day 배지 · 폼 assertion · Settings Stepper · i18n **439** · 테스트 **59+158** · **1.5.0** · `PLAN_sites_ssl` · **PR #30 머지** · bd `RelayConsole-2tt` closed
- [x] **네트워크 속도 단위 유동 전환** — `formatNetRate`/`formatNetRatePair` · ≥1 MB/s → MB/s, 미만 KB/s · 카드↑↓·cacheNetworkInfo · 테스트 +2 · **PR #29 머지 `da0d9e1`**
- [x] **F1 기기 그래프 플로팅창 육안 마감** — 투명도·헤더 안정화·통합 테스트 **사용자 확인** · `RelayConsole-d2e` closed · **PR #25·#28** · 1.4.0
- [x] **S1 아침 브리핑 육안 마감** — 팝오버 헤더 한 줄 + 설정 토글 **사용자 확인** · `RelayConsole-psh` closed
- [x] **알림 채널 A1 육안 마감** — 설정→연동 ntfy/Slack 테스트 전송 **사용자 확인** · `RelayConsole-avf` closed
- [x] **S1 아침 브리핑 구현** — `Briefing`·`BriefingLogic` · `relay.briefing.enabled` · 팝오버 헤더 한 줄 · i18n **411** · XCTest Briefing 7 + swift-testing 156 · **1.3.0** · `PLAN_briefing` · **PR #22 머지 `c57d546`**
- [x] **리서치 재검토** — `RelayConsole-p1w` · `RESEARCH_competitive_v1` §8 갱신 · P1 3건 도출
- [x] **외부 알림 채널 A1 구현** — `NotifyChannel` · `relay.notify.*` · 설정 연동 · i18n 409 · 테스트 156 · **1.2.0** · `PLAN_notify_channels` · **PR #21 머지 `44e2cd6`**
- [x] **README 공개용** — `README.md` · 포지셔닝·기능·설치·ntfy/Slack 설정
- [x] **경쟁 리서치·방향 확정** — `RESEARCH_competitive_v1` · 사용자 승인: 알림 채널 1순위 · 로컬 전용 · Apple 보류 · README · 완료 후 재검토
- [x] **종료 버튼+확인 (PR A)** — `menubar.button.quit`+`shutdown()` · `applicationWillTerminate` · **PR #19 머지 `4d72f52`**
- [x] **설정 사이드바형 개편 (PR B)** — `NavigationSplitView` 6탭 · 감시 그룹 4 · about 버전/번들 · **PR #20 머지 `18ebab0`** · 버전 1.1.1
- [x] **Alerts 잔여 육안 마감 (PLAN_alerts · 0.9.1)** — 3탭·필터·그룹·ack/mute/메모 재시작 유지 · Apple 연결/해소 · export JSON/CSV · **사용자 육안 완료**
- [x] **Sites/Jobs 잔여 육안 마감 (PLAN_sites_jobs · 1.0.0)** — HTTP 주입/상태 바 · 잘못된 URL 거부+에딧 · curl 하트비트/overdue · curl 붙여넣기 토큰 · site down→Alerts · **사용자 육안 완료**
- [x] **Sites v1.1 육안 마감 (PLAN_sites_v1_1 · 1.1.0)** — UptimeRobot·Google식 타임라인 · failThreshold·effectiveUp·dayBars·가동률%·범례/패딩 · 메뉴바 Sites 섹션 · i18n 382 · 테스트 35+139 · **PR #17 머지 `c383887`** · 사용자 육안 완료
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
