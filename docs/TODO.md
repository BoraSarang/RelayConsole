# TODO.md
> 작업 추적 — bd 연동 (이슈 prefix: RelayConsole)

## 진행 중 (bd ready)
- [ ] **R5 SwiftUI 렌더** — `ConsoleStore` 단일 평면(23 body) · `InsightsView` body당 ~19,500회 이벤트 순회 · `fitAll()` 무조건 호출 · `DateFormatter` body 신규
- [ ] **R6 종료·누수·디스크** — 종료 flush 미보관(0.5s wait 결과 버림) · `NSPanel isReleasedWhenClosed=false` + `teardown`가 `close()` 안 함 · `IssueLog` 무한 append · 저장/로드 실패 무음(`E-MAC-STORE-0001~0003` 미사용)
- [ ] **R4 메인 스레드 정지** — `EventStore` 이벤트마다 500건 전량 인코딩을 메인에서 · `SitesJobsStore` 14,400 레코드 5초마다 · `WidgetSnapshotStore` 유일한 동기 atomic write
- [ ] **R5 SwiftUI 렌더** — `ConsoleStore` 단일 평면(23 body) · `InsightsView` body당 ~19,500회 이벤트 순회 · `fitAll()` 무조건 호출 · `DateFormatter` body 신규
- [ ] **R6 종료·누수·디스크** — 종료 flush 미보관(0.5s wait 결과 버림) · `NSPanel isReleasedWhenClosed=false` + `teardown`가 `close()` 안 함 · `IssueLog` 무한 append · 저장/로드 실패 무음(`E-MAC-STORE-0001~0003` 미사용) · `IssueLog.url`이 알림마다 mkdir syscall

## 다음 스프린트 (리서치 §8 잔여 · 미착수)
- [ ] **S3 관제 규칙 Rules as Code (로컬 YAML)** — TIER S 중 유일 미착수
- [ ] **A7** Dock 배지 / 그룹화 (라이브액티비티·위젯은 1.15.0으로 완료)
- **TIER A**: Things·캘린더 연동 · 스샷 스크랩북 · 멀티 스냅샷 그리드 · Prometheus/JSON export · cron 기기 태그 · 충전 방치 리포트

## 보류
### 육안/실측 대기 (사용자 지시 — 뒤로 미룸)
- [ ] **Wi-Fi 실측 검증** — 사용자 지시: "검증은 추후 실제 테스트 하는걸로 하고 킵 해둬"
- [ ] **A1 ntfy/Slack 실제 채널 테스트 전송** — RESEARCH §8 `148` · 설정→연동 테스트 (사용자)

### 기기 확보 시
- [ ] **Apple 실기 Trust 육안** — iPad USB 데이터 불량(안드로이드 동일 케이블 OK·복구도 미인식). 기기 확보 후 `brew install libimobiledevice` → 배터리/스토리지 카드
- [ ] **Apple Phase 2** — Developer Mode·sysmon 등 — 위 기기 확보 후 착수 (A9)
- [ ] **Apple 크래시 리포트 수집 (반드시 해야 할 작업)** — `idevicecrashreport`로 iOS `.ips` crash/ANR를 IncidentBundle에 첨부. 기기 확보 시 1순위. Trust USB + `idevicecrashreport -u <udid> copy` 패턴. Android `logcat -b crash`/dropbox 대응 Apple 쪽 원재료 — **기기 확보 전 구현 불가, 반드시 기억할 것**

## 완료 (2026-09-26)
- [x] **R4 메인 스레드 정지 — 실측 기반 재정의** — `PLAN_refactor_perf_stability_macos` 4단계 · 커밋 `f1cfad2` · 브랜치 `chore/macos-refactor-p4-mainthread` · **육안 대기**
  - **⚠️ 계획이 과장했음을 실측으로 확인** — `EventStore` 인코딩 **0.35ms** + 동기 write 0.11ms = 0.46ms(254건/57KB) · `SitesJobsStore` 8×300 = 2.42ms(288KB) · `WidgetSnapshot`/`DeviceDailyStore` 0.01ms · `IssueLog.url` mkdir 0.0072ms · 디렉터리 스캔 1000파일 6.7ms → **합산 main 스레드 1% 미만**. 조사 에이전트 추정치와 크게 달라 **"인코딩 백그라운드화"만으로는 이득이 없어 측정된 실제 결함만** 작업
  - **실제 결함 ① 쓰기 증폭(95~99% 낭비)** — 상태 파일은 최종 상태 하나만 의미가 있는데 값이 바뀔 때마다 전량 재기록 → 이벤트 20건 연속이면 20회×57KB=1.12MB 쓰고 최종은 마지막 1회로 덮어짐(활동 60건/분=3.4MB, 600건/분=33.5MB 전부 낭비). **`CoalescingWriter` 신설** — 대기 쓰기를 최신 값으로 대체 + 인코딩도 writer 큐에서 수행(MainActor 비용 제거). `EventStore`·`SitesJobsStore`(sites/jobs)·`DeviceDailyStore` 적용. **실측 감소 20건 95% · 60건 98% · 600건 99%**
  - **종료 유실 방지** — `flushSync()`(진행 중 쓰기 + 대기 값 동기 기록) 신설 후 `shutdown()` 에 3개 스토어 flush 연결(R1 `ConnectionSessionStore` 와 동일 결함 방지). **SIGTERM 종료 후 파일 md5 불변 + 259건 정상 디코딩으로 유실 없음 실증**
  - **저장 실패 보존** — `lastSaveError` + `DebugLogger` 기록 (조용한 실패 0건)
  - **실제 결함 ② 비원자적 `@Published` publish** — `ingestWatch`/`pushEvent` 가 insert·trim 을 나눠 대입해 **상한 초과 중간 상태**(501건/21건)가 관측될 수 있었음(그 상태 렌�� 시 대시보드·인사이트 전부 재계산 — 1단계 단일 평면과 결합해 배수 비용) → 로컬 계산 후 **1회만 대입**, 상한을 `maxWatchEvents`/`maxRecentEvents` 상수로화
  - **변경하지 않기로 근거 있게 결정**: `WidgetSnapshotStore`(60초 주기·총 0.12ms — 측정 근거 없음) · 디렉터리 스캔 백그라운드화(현재 gallery 0개·incidents 3개)
  - **검증 [HARD]**: `swift test` **391 + 104 = 495 / 0 failed** (+9 신규) · `./scripts/build-macos.sh debug` **EXIT=0** (1.16.0 · 팀 6GPJQ7BQC9) · 런타임: 기기 재인식·크래시 0건(신규)·종료 후 md5 불변·재기동 정상
- [x] **R3 신선도·정직성** — `PLAN_refactor_perf_stability_macos` 3단계 · 커밋 `6efd4d4` · 브랜치 `chore/macos-refactor-p3-freshness` · **육안 대기**
  - **신선도 위장 제거(핵심)** — `pollDevice`가 `isOnline=true` 무조건 세팅 → `merge`가 그걸 보고 `lastSampleAt` 갱신 → **adb 전부 실패에도 "방금 측정" 으로 위장**. `DeviceSnapshot.measuredAt`/`failureStreak` 신설로 **실제 응답이 있을 때만** 신선도 상승, 무응답 시 마지막 정상 시각 유지 + 연속 실패 증가 + `lastError` 에 실제 원인 기록(`DeviceState.lastPollError`, 성공 시 초기화)
  - **측정 실패를 오프라인과 구분 표시** — `DroidDashboardView.staleBanner`(경고 배너 + 연속 실패 횟수 + **실제 마지막 정상 수집 시각**). 종전엔 구분 수단 없었음 · L10n **729 → 733**(`adb.error.noResponse`·`adb.error.pollFailed`·`droid.stale.banner`·`droid.stale.count`, en/ko 1:1)
  - **오프라인 기기 정리(1단계 근본 해결)** — `offlineSince` + `pruneOffline(olderThan:)` 신설(보관 30분). `markOffline`이 플래그만 바꾸던 구조가 "한 번 연결된 기기 영구 잔류"를 만들었고 무선 ADB 는 serial 이 `IP:PORT` 라 DHCP 변경마다 새 항목이 쌓였다 → `markDeviceOffline`에서 `metricsHistory`(60×8 Double 링)·`lastNetPushAt`·`lastDailyIngestAt` 정리 + `DeviceMonitor.dropboxScannedAt` 정리. **1단계에서 비율 분모를 뺏던 것을 정상 복원**
  - **logcat 폭주 + 중복 스캔 제거** — 절전 중 폴링 정지 후 깨어나면 cursor가 수 시간 전이라 `logcat -d -T`가 **전체 버퍼**를 한 String 으로 읽음 → `| tail -c 200000` 상한(실기기 실측 **429,643줄 → 1,779줄**, 최신 라인 보존 확인) · `AdbClient.logcatKeywordScan` 신설로 anr/crash/logcat 집합을 **1회 순회**로 집계(종전 집합별 2회 전수 스캔), 기존 `countLogcatHits` 와 동일함을 테스트로 고정
  - **검증 [HARD]**: `swift test` **382 + 104 = 486 / 0 failed** (+15 신규) · `./scripts/build-macos.sh debug` **EXIT=0** (1.16.0 · 팀 6GPJQ7BQC9) · 런타임: 기기 재인식·크래시 0건(신규)·logcat 상한을 앱과 동일한 명령으로 실기기 검증(정확히 200,000바이트에서 절단 + 최신 라인 보존)
- [x] **R2 ADB 배치화 + 기기별 병렬 폴링** — `PLAN_refactor_perf_stability_macos` 2단계 · 커밋 `91d7732` · 브랜치 `chore/macos-refactor-p2-batching` (R1 위에 stacked) · **육안 대기**
  - **`PollBatch` 마커 프로토콜** — 기기측 sh 가 `@@RLY<n>@@` 마커를 내면 호스트가 마커로 출력을 잘라 **종전과 동일한 문자열**을 각 순수 파서에 넘김 → **파서 무변경**(리스크 최소). 마커 없으면 전부 nil(조용한 오염 금지) · 빈 청크=종전 `try?` 실패와 동일 · **실기기 대조 21개 명령: 18개 줄 단위 완전 일치**, 3개는 실행 시점마다 변하는 누적 카운터라 개별 실행끼리도 다름 · 빈 청크 3건(GPU sysfs 미지원)도 개별 실행과 동일 확인
  - **기기별 병렬 폴링(Head-of-Line 해소)** — 종전 기기마다 순차라 느린 기기가 전체 지연 → `tick()`이 `withTaskGroup`으로 기기별 adb 실행을 겹쳐 돌림(actor 격리 밖 `detached`), 상태 갱신은 순차 보존
  - **측정(동일 방법 전/후 비교 · 고유 PID 30초 샘플)**: fast 틱 **361~401ms → 171~174ms(2.1배)** · slow 틱 **1378~1518ms → 546~551ms(2.6배)** · **adb 프로세스 분당 313 → 47(85% 절감)**
  - **그 외**: `logcatHitBreakdown` 키워드 소문자화 진입 시 1회화 · `DroidMetrics`에 `firstAt/lastAt`+`windowSeconds/actualInterval` 추가(**"5s×60=5분" 주석이 실제와 불일치하나 아무도 몰랐음** → 9초 주기면 9초로 보고하도록 정직화, 테스트 고정) · `ProcessRunner` 동시 var 캡처 경고 제거(DataBox)·`captureAsync`·`describe` 추가
  - **검증 [HARD]**: `swift test` **367 + 104 = 471 / 0 failed** (+22 신규) · `./scripts/build-macos.sh debug` **EXIT=0** (1.16.0 · 팀 6GPJQ7BQC9) · 런타임: 기기 재인식·크래시 0건(신규)·`device-daily.json` 실값 파싱(`memUsedPctAvg 56.9`·`tempMax 53.3`·`netUp 6544MB`·`rsrpMin -103`·`psiMax 17.86` — 배치 파싱이 끝까지 정상) · `pollDevice` 내 `tickCount` 잔존 0 · 남은 직접 shell 3건은 전부 1회성/조건부로 의도적
  - **육안 확인 필요**: 대시보드 8카드 값 정상 · 그래프 스파크라인 정상 · 센서/thermal zone/네트워크/스토리지 값 정상
- [x] **R1 어댑버 안전화 + 즉시 결함 9건** — `PLAN_refactor_perf_stability_macos` 1단계 · 커밋 `7c4f8bb` · 브랜치 `chore/macos-refactor-p1-adapter-safety` · **육안 대기**
  ① **앱 정지(Hang) 근본 제거** `Utils/ProcessRunner.swift` 신설 — `DeviceMonitor.run`이 `standardError = Pipe()`만 만들고 읽지 않아 adb가 64KB 넘기면 자식이 write에서 블로킹 → stdout EOF 미도달 → `readDataToEndOfFile()` **영구 대기**·타임아웃 없어 half-open TCP에서 **actor 전체 정지**(복구 수단 없음). 동시 소진 + 데드라인 20s + `terminate`→`interrupt` escalation + 대기도 유한 + **stderr 원문 보존**. 같은 저장소의 안전한 `SiteChecker.run`을 모델로 삼음 ② 폴링 루프 취소 후 tick 1회 추가 실행(`try?`가 `CancellationError` 삼킴) ③ `ConnectionSessionStore.flush()` **영구 no-op**(`dirty=true` 대입 0건) + `save()` 비동기 큐 미배출 → **동기 flush**로 교체·함정 플래그 제거·테스트용 `init(url:)` 주입 ④ `runSiteCheck` await 전 인덱스 캡처 → **A 사이트 결과가 B에 기록**(업타임·SSL·위젯 오염) → await 후 id+target 재확인 ⑤ `ScrcpyController` terminationHandler 세대 race(`|| serial ==` 제거 → identity만) ⑥ **[HARD] 하트비트 토큰 평문 로그**(`ConsoleStore:566`) → `NotifyChannel.maskSecret` ⑦ 기기 0대인데 메뉴바 "Online"(`isEmpty` → `contains(\.isOnline)`) ⑧ `WifiAdb.disconnect` 성공인데 오류 스타일 → `statusIsError` 리셋 ⑨ 버전 하드코딩 3곳 낡음(설정 1.14.0·MCP 1.14.0·로그 1.15.0) → **`Utils/AppVersion.swift`** 신설(Info.plist 단일 소스)·MCP는 테스트로 대조 고정 · 부수: `MenuBarPopoverView:822` 주석 U+FFFD 문자 손상 복구(기존 결함)
  - **검증 [HARD]**: `swift test` **345(swift-testing) + 104(XCTest) = 449 / 0 failed** (+13 신규 — 교착·데드라인·stderr 보존 회귀 포함, 타임아웃 테스트 1.031s에 종료 확인) · `./scripts/build-macos.sh debug` **EXIT=0** (1.16.0 · 팀 6GPJQ7BQC9 일치) · 신규 파일 경고 0 · U+FFFD 0건
  - **런타임**: 기기 재인식(`device.connected 02:33:09Z` — 새 ProcessRunner로 fast-tick 6회 adb 실제 성공) · 위젯 스냅샷 기록 · **CPU 1.7%**(12초 샘플, 정지 0% 아님) · RSS 96.7MB

## 완료 (2026-09-25)
- [x] **파일 탐색기 핫픽스 (1.16.0)** — ① **공백/한글/일본어 폴더 실패 수정**: `adb shell`이 argv를 인용 없이 공백 연결 → 원격 sh 재분리 (`ls: …/Windows: No such file` 재현) → `FileBrowserLogic.shellQuote`(POSIX 싱글쿼트 `'`→`'\''`) + `listArgs`를 **단일 명령 1argv**로 변경 · push/push는 sync 프로토콜이라 무관(공백·한글 roundtrip 실측 OK) · `Windows 11`·`테스트 폴더`·`サブ フォルダ`·`O'Brien's Files` 4종 실기기 검증 OK · RESEARCH §2 **함정 3건으로 갱신** ② **팝오버 푸터 아이콘화**: 한/영 라벨 길이 차이로 줄바꿈 깨짐 → `footerIcon`(콘솔=macwindow cta · 로그=doc.text · 디버그=ladybug · 탐색기=folder · 설정·종료) 32×32 통일 · tooltip=L10n 유지 · 테스트 **+1 → 332 통과** · `build-macos` **EXIT=0**
- [x] **파일 탐색기 ADB 읽기·전송 (1.16.0 · bd `RelayConsole-qy8`)** — `FileBrowserLogic`(`ls -la --full-time` 파싱 · **`/sdcard` 심링크 trailing-slash 함정 방어** · 시각(nanosecond+tz)/크기 포맷 · 폴더 우선 정렬 · 이름 필터 · 고유파일명 `name (1).ext` · 50MB 미리보기 가드) + `FileBrowserController`(list/pull/push · **실패 시 stderr 원문 노출 [표시②]** · `E-MAC-ADB-0004~0006`) · `FileBrowserView`(사이드바 즐겨찾기 7 · 컬럼 정렬 · Finder 드래그 push · 더블클릭 열기 · contextMenu · 가져오기 폴더 `relay.files.destDir`) · `Window(id:"files")` + **팝오버 푸터 실행 버튼**(기기 연결 시) · i18n **707→729** (`files.*` 21 + `menubar.button.files` en/ko 1:1) · FileBrowserTests **+18 → 331 통과** · **push 실측** (15B→`/data/local/tmp` exit=0·cat 일치·정리 OK) · `build-macos` **EXIT=0** · `RESEARCH_adb_file_browser` · `PLAN_file_browser_relayconsole`
- [x] **macOS 위젯 WidgetKit (A7 방향 · 1.15.0)** — `PLAN_widget` ① **RelayWidgetCore**(스냅샷 schema v1 + App Group `6GPJQ7BQC9.com.borasarang.relayconsole` 파일 저장소 · public) ② **WidgetSnapshotSync** objectWillChange+UserDefaults → **60s 스로틀** 기록 → `WidgetCenter.reloadTimelines("RelayStatusWidget")` · 종료 flush · 순수 `WidgetSnapshotBuilder`(선택기기 1순 캡4 · 사이트 캡6+up/down/집계 · jobs overdue · 이벤트 캡3 · critical은 `BriefingLogic` 동일 산식) ③ **위젯 3종**(small=톤배지+선택기기 배터리/발열 · medium=브리핑+사이트4+기기2+지연 · large=브리핑+기기3+사이트6+이벤트3) 다크 토큰 #1c1f2a · SF Mono · 전 family "마지막 업데이트" ([표시②]) ④ **딥링크** `relayconsole://<target>` (CFBundleURLTypes + `WidgetDeepLink` pending 플러시 + `ConsoleSection` 공용 분리 + `pendingConsoleSection` 탭 이동) ⑤ **빌드**: `WidgetXcode/project.yml`(xcodegen) + xcodebuild appex → PlugIns 복사 · **서명 ad-hoc → Apple Development 통일**(앱·appex TEAM 6GPJQ7BQC9 · 앱은 비샌드박스+App Group / 위젯 sandbox+App Group) ⑥ i18n **690→707** (`widget.*` 17키 en/ko 1:1 · 위젯은 앱 lproj 공유) ⑦ 테스트 **+18 → 313+104=417 통과** · `build-macos` **EXIT=0** · 진단: appex/NSExtension·pluginkit 등록·크래시 0건·App Group 파일 기록 실측 OK · **위젯 갤러리 육안 ✓ (2026-09-25 · 3종 표시·동작 확인 · appex 프로세스 PID 27708 · 크래시 0건)** · `PLAN_widget_relayconsole`
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
