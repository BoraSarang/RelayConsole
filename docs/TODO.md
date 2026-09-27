# TODO.md
> 작업 추적 — bd 연동 (이슈 prefix: RelayConsole)

## 진행 중 (bd ready)
- (0건)

## 다음 스프린트 (리서치 §8 잔여 · 미착수)
- [ ] **로그 창 VoiceOver 노출** — `System Events` 의 `entire contents` 가 **0개**.
      SwiftUI 내용이 보조기술에 노출되지 않는다(배지 버튼만 `.accessibilityLabel` 로 처리).
      측정 우회로 **팝오버 클릭 자동 검증도 불가능**해져 육안 대기 항목이 되었다 (PLAN_log_tag_picker §8-1)
- [ ] **한자(중국어) 혼입 잔재** — `scripts/scan-cjk.py` 로 전수 스캔. **2026-09-28 재기준: 38건 / 12파일**
    (앞선 "24건 / 20파일" 기록은 다른 도구 기준 — **이제 도구 출력이 기준**이다. 재실행: `python3 scripts/scan-cjk.py`)
    - **우선순위가 다르다 — 소스·규칙 파일이 먼저다** (사용자에게 보이는 글자이므로)
      ① `AGENTS.local.md:60` — "밝은 테마/웹**風** 버튼/print 금지" → "웹풍" (규칙 문서 오타)  # scan-cjk: allow
      ② `Sources/RelayConsole/Droid/DeviceMonitor.swift:605` — 주석 `内`  # scan-cjk: allow
      ③ `Sources/RelayConsole/Views/InsightsView.swift:350` — 주석 `年`·`月`  # scan-cjk: allow
      → **이 3건은 주석·문서 1줄 수정이니 위험이 거의 없다. 파일 단위로 묶어 바로 해도 된다**
    - 그다음 docs 9파일: `PLAN_v0.3`(6) · `PLAN_v0.5`(3) · `PLAN_refactor_perf_stability`(2) ·
      `RESEARCH_adb_file_browser`(4) · `RESEARCH_droid_devicecare`(3) · `RESEARCH_apple_relay`(2) ·
      `PLAN_v0.4`(2) · `PLAN_v0.1`(1) · `PLAN_wifi_*`(2)
    - **왜 묶어 놓았나**: 세션 마무리 시점에 12파일 무분별 수정은 검토 없이 코드를 건드리는 것.
      소스 3건은 별도 커밋으로 먼저 처리하는 게 맞다
    - **진짜 해법은 커밋 훅** — 한자 혼입이 한 세션에 4회 재발했다. 스캔 스크립트는 만들었고
      (`# scan-cjk: allow` 로 **인용이 필요한 문서**는 예외 처리 — 검출기를 못 쓰게 하느니 근거를 남길 자리를 만듦),
      **훅 등록만 남음**
- [ ] **강제 종료 시 고아 `adb logcat`** — 앱이 `pkill`/크래시로 죽으면 로그 창의 adb 자식이
      **PPID 1 로 남고 계속 스트리밍**한다. 2026-09-27 에 28분짜리 잔존으로 확인됐고
      2026-09-28 에도 재확인 — 측정 중 adb 자식 2개로 오판할 수 있으니 **PPID 로 구분해야 한다.**
      정상 종료 경로에서는 `onDisappear` → `stop()` 이 죽이므로 **강제 종료 때만** 남는다
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

## 완료 (2026-09-28)
- [x] **T-2026-09-28-3 로그 창 태그 선택 UI — 제외 판단을 사용자에게** — `PLAN_log_tag_picker` ·
      테스트 20건 신규 · 1.16.0 유지
  - **무엇이 달라졌나** — 기본 제외 목록(3종)을 **코드가 정하던 것**에서 **사용자가 고르는 것**으로.
    계측 근거는 코드 주석과 문서에 남지만, 이제 판단 자체는 사용자에게 넘어간다 [표시②]
  - **얼어붙음(freeze)** — 제외는 **기기에서** 일어나므로 제외한 태그는 더 이상 도착하지 않는다.
    값을 버리면 사용자는 **기억으로 되돌려야 한다** → 마지막 집계값을 유지하고 `제외됨` 으로 표시.
    되돌리기가 정보가 된다
  - **마이그레이션 실측** — legacy Bool `1` → 배열 3종 → **adb 인자 3종** ·
    배열 4종 → 인자 4종 (**내가 제외하지 않기로 했던 `ActivityManager` 를 사용자가 켤 수 있다**) ·
    빈 배열 → 인자에 `:S` 없음
  - **★ 크래시 — 내가 만든 코드에서** (`EXC_BREAKPOINT` / `SIGTRAP` · `…-024513.ips`)
    - `LineParser.parse` 의 `index(after:)` 오버런. **메시지가 빈 줄**에서 `)` 가 마지막 글자인 경우
    - 위험 지점 2곳(빈 메시지 · `/` 시작 줄의 `index(before:)`) — 로그 줄은 **기기에서 오는 데이터**
    - **단위 테스트가 통과시킨 이유: 내가 만든 정상 형식만 넣었기 때문.** 회귀 5건 추가 후
      **되돌려 놓으면 테스트 프로세스가 signal 5 로 죽음을 실측 확인**했다
  - **자기 테스트가 잡은 결함 2건** — ① 표가 가득 차면 매 줄마다 정렬·축출되어 건수 1인 새 태그가
    동률에서 즉시 날아가고 **"조용해졌다 다시 시끄러지는" 태그를 영영 못 잡음**(자르는 시점을 상한 2배로) ·
    ② 태그 유무성 판정(키가 변수라 기존 호출부 스캔이 못 봄) → picker 키 형식 별도 테스트
  - **정직성 규칙을 순수 함수로** — 표본 5개 초과 시 `N종` 이 아니라 **`N종 이상`**.
    문자열이 뷰 안에 있으면 이 규칙이 테스트 밖에 놓인다
  - **검증 [HARD]**: `swift test` **528 + 104 = 632 / 0 failed** (착수 시 612, **+20**) ·
    `./scripts/build-macos.sh debug` **EXIT=0** · 재기동 후 신규 크래시 **0건** ·
    L10n **779키 en/ko 1:1** (+11, 죽은 키 1 제거) · U+FFFD 0건
  - **육안 대기**: 배지 클릭 → 팝오버 · 태그 켜기/끄기 · `기본값 복원` · 제외됨 항목 표시
  - **부수 발견**: AX 계층이 비어 있어 **클릭 자동 검증이 불가능** → VoiceOver 노출도 별도 과목으로 등록

- [x] **T-2026-09-28-2 로그 창 CPU — 소음 태그를 기기에서 제외** — `PLAN_log_cpu_noise_filter` ·
      테스트 12건 신규 · 1.16.0 유지
  - **TODO 의 질문을 계측이 답했다** — "adb host 옵션만으로 라벨 exclusion 이 되는지 **확인 없이
    구현하지 말 것**". 3-way 실측: `--regex` 부정 순방위 ❌(제외 안 됨) · 기기 측 `grep -v` ✅(위험 있음) ·
    **필터식 `'<tag>:S'` ✅ (adb 인자 한 칸, 위험 0)**
  - **무엇이 소음인가 (20초 전수 스캔 282,655줄)** — `SemApTrafficData` **92.5%**,
    **서로 다른 메시지 1종류**(20초 261,521회 = 초당 1.3만) · `HeatmapThread` 0.4% (3종류, 공장 EFS)
    → 소음의 정의는 **비율이 아니라 반복도**. `ActivityManager`(2.1%, 44종류)처럼
    사람이 읽을 정보가 있는 것은 **남겼다**
  - **비용의 진짜 출처는 "개방 순간"이었다** — 개방하면 CPU **99%**. 원인은 `logcat` 이
    **링 버퍼 전체를 덤프**하는데 그 버퍼에 이전 스팸의 역사가 남아 있기 때문:
    **버퍼 덤프 231,982줄 → 16,763줄(7.2%)**
  - **CPU 짝지 A/B (2라운드 · 순서 반대 · 부하 동시 계측)**

    | 라운드 | 제외 OFF | 제외 ON | 동시 유입률(줄/3초) |
    |---|---|---|---|
    | 1 | 98.5% → 42.4% | 4.8% → 12.8% | 19→398 / 20→299 |
    | 2 | 99.3% → 27.4% | 14.5% → 12.6% | 138→167 / 143→175 |

    → **개방 직후 99% → 5~15%**, 안정 구간 27~55% → 3.6~14.5%
  - **[표시②] 정직성** — `E` 레벨 줄을 감추므로 **푸터 배지 `기기에서 2개 태그 제외` 를 항상 표시**,
    tooltip 에 태그명, 기본 ON + 1클릭 해제(`relay.logs.excludeNoisyTags`).
    **범위는 로그 창의 실시간 스트림뿐** — `IncidentBundle` 캡처와 `logcatKeywords` 스캔은 전량 그대로
    (테스트로 고정: `incidentCaptureIsNotFiltered`)
  - **부수 발견 — `(?i)` 가 이 기기에서 죽는다** (사용자 지시로 즉시 수정): 종전 주석이
    "logcat `--regex` 는 Java `Pattern` 이므로 지원된다" 라 적었으나 **거짓**이었다.
    실측 `--regex=(?i)anr` → 0줄 + `regex_error was thrown in -fno-exceptions mode` →
    **대소문자 무시 검색이 항상 0건**이었다. 같은 근원(엔진이 libutils `RegExp`).
    → **글자별 문자클래스**(`anr` → `[aA][nN][rR]`)로 교체. 실기 검증: `Scheduler` 정확히 585줄 +
    소문자 36줄 → 문자클래스 **607줄**(합집합) · `SCHEDULER` 0줄
  - **한자 스캔 도구** — `scripts/scan-cjk.py` (한자 혼입 + U+FFFD 전수 스캔).
    **PLAN 작성 중 또 한자 4건이 들어갔다**(지난 세션이 지적한 재발 그대로) → 즉시 잡아 정리.
    자기 검증도 했다(탐지 대상 파일에 넣으면 1이 나오는지 확인). 훅 등록은 남은 과제
  - **검증 [HARD]**: `swift test` **507 + 104 = 611 / 0 failed** (착수 시 599, **+12**) ·
    `./scripts/build-macos.sh debug` **EXIT=0** (1.16.0 · 팀 6GPJQ7BQC9 서명 검증 통과) ·
    L10n **769키 en/ko 1:1**(+3) · U+FFFD 0건 · 신규 크래시 0건
  - **UI 스크린샷 검증(육안 대체)** — 푸터에 `☑ 노이즈 태그 제외` + `기기에서 2개 태그 제외` 배지,
    헤더 `LIVE 수신 20,773줄`(버퍼 23만 줄 중 도착분) · SemAp 줄 없음 · CPU 10~11%
  - **3번째 태그 추가 — `ThermalManagerService$ThermalHalWrapper`** (PR #53 2번째 커밋)
    - **선행 검증부터** — TODO 가 "실기 검증 후 다룬다" 였으므로 순서를 지켰다.
      버퍼 2,874줄 → **0줄** ✅ · 과잉 제외 없음(194,910 → 185,309 = 딱 2,874줄만 감소).
      → **`$` 와 39자 길이는 문제가 아니다**
    - **내가 만든 안전 필터가 이 태그를 버리고 있었다** — `safeTags` 허용 집합이 `A-Za-z0-9_` 였고
      `$` 가 있어 **조용히 탈락**했다(효과가 아니라 실패처럼 보임). `noisyTagsAreFilterSafe` 가 잡아냄.
      → **검증된 예외는 예외로 들여다봐야 한다.** `$` 허용 + 회귀 테스트 추가
    - **지형을 재고 목록을 멈췄다** — 잔여 13,811줄 중 `ActivityManager` 가 40.4%.
      94% 가 동일 줄이지만 **범인 앱 이름을 담고 있다**(앱 7종) → **남겼다**(남은 이유를 코드 주석에 기재).
      `PermissionService`(590·1종류)·`DeviceStorageMonitorService`(332·2종류) 는 순수 반복이지만
      잔여량의 6.7% 뿐이라 **뺄 이유가 부족해 보류**
    - **검증 [HARD]**: `swift test` **508 + 104 = 612 / 0 failed** · `build-macos.sh debug` **EXIT=0** ·
      UI 스크린샷에서 배지 **`기기에서 3개 태그 제외`** · 헤더 `수신 13,783줄`(계측 13,811줄과 일치)
  - **계측 부수 발견 (기록)**: 스팸은 **간헐적**이다(6초당 22줄 ~ 114,195줄 — 100배 변함).
    5초 창 비교는 근거가 되지 않고, `logcat` 은 `-t/-T` 없이 **버퍼 덤프 후 추종**하므로
    짧은 창의 앞부분은 과거 로그다. → 짝지측정 + 부하 동시 계측이 유일하게 정직한 방법
- [x] **T-2026-09-28-1 `recentEvents` 분리 — 알림 유입 시 `objectWillChange` 2회 → 1회** —
  `PLAN_published_split_recentevents_relayconsole` · 테스트 5건 신규 · **594 → 599**
  - **착수 전에 계측했다** — TODO 는 "14개 View 재매핑"을 적었지만 **그건 필요 없었다.**
    계측 두 가지가 계획을 바꿨다:
    ① 중복 신호의 원인은 `recentEvents` 인데, 이 필드를 읽는 View 는 **MenuBarPopoverView 하나(3곳)**.
    `recentWatchEvents` 를 빼야 하는 14개 재매핑은 **원인 필드가 아니었다**
    ② 제안 1·2(dayKey 정수화 + 캐시)가 **2번째 신호의 비용을 이미 0으로 만들어 뒀다.**
    인사이트 캐시 키 9종에 `recentEvents` 가 없어 `pushEvent` 는 캐시 적중(0ms)이다
  - **실측** (격리 프로브 + 실제 `ConsoleStore.shared`): 실제 경로 2회 ✅ 문서 일치 ·
    `assignOnce` 항상 1회 · **`mutateInPlace` 는 링이 가득 차면 2회**
  - **부수 발견 — 디버그 경로가 실제보다 나빴다** — `debugIngestWatchQuietly`(DebugPanel 알림 주입)가
    in-place 변이라 **실제 2회 vs 디버그 3회**였고, `ConsoleStore:912-914` 가 경고한
    **"상한 501건 중간 상태"도 이 경로에서 관측**됐다. → 체감 검증 도구가 나쁜 경로를 재고 있었다.
    실제 `ingestWatch` 와 **같은 1회 대입 패턴**으로 통일
  - **변경 범위** — `RecentEventsStore` 신규 · `ConsoleStore` 4곳 · `MenuBarPopoverView` 3곳.
    `pushEvent` 시그니처 유지 → `DeviceMonitor` **무변경**. `recentWatchEvents` 는 **분리하지 않음**
  - **신호 횟수를 테스트로 고정** (`PublishedSignalTests` 5건) — 중복 신호는 필드 하나를 다시
    붙이는 것만으로 **조용히 되돌아오고 눈에 보이지 않는다.** 계측 없이 못 잡는다
  - **검증 [HARD]**: `swift test` **495 + 104 = 599 / 0 failed** (착수 시 594, +5) ·
    `./scripts/build-macos.sh debug` **EXIT=0** (번들 재생성·재서명·앱 재시작) ·
    L10n **766키 en/ko 1:1** · U+FFFD 0건
  - **육안 대기**: 알림 유입 시 다른 탭(설정·사이트)이 깜빡이지 않는지
  - **PR #52 머지 완료** — 리뷰 후 **squash 머지** `699c0af` (main 의 최근 관례 #45~#51 과 동일).
    self-review 결과 **[HARD] 위반 0건** · 차단 사유 없음. [SOFT] 3건 사유는
    PR #52 코멘트에 기재 — ① `catch` 에서 spawn 실패 원인이 버려지는 관측 공백
    ② 신규 실패 사유의 `error_message_ko.json` 미등록(L10n 이 진실원천이라 동작 영향 없음)
    ③ DebugPanel 로그 미첨부(육안 대기) + CHANGELOG 파일 부재
  - **한자 혼입 전수 스캔** — 27건 검출. `main` 대조로 **PR #52 가 넣은 3건**임을 확인해 정리
    (`LogViewerView` 주석 2 · `DESIGN.md` 1 · 커밋 `2b2306e`). **잔재 24건은 별도 과목으로 등록** —
    세션 마무리 시점의 20개 파일 무분별 수정은 하지 않는다
  - **브랜치 정리 + PR #52** — 13커밋이 브랜치명 불일치 상태로 로컬에 방치돼 있었음
    (`fix/logcat-honesty-incident-cap` → `feat/macos-2026-09-27` rename, main 직접 push 는 [HARD] 금지).
    https://github.com/BoraSarang/RelayConsole/pull/52

## 완료 (2026-09-27)
- [x] **TCP 유실 시 자동 재연결** — `PLAN_wifi_reconnect_relayconsole` · 테스트 8건 신규
  - **작업을 여는 계기 — 자기 검토에서 발견한 결함**: `disconnectStaleEndpoints` 는
    "새 엔드포인트를 연 직후"에만 불린다. 그런데 **새 엔드포인트를 여는 경로가 없었다.**
    `autoEnableIfEnabled` 는 "USB 신규 감지"(`DeviceMonitor:1034`)에서만 호출되므로,
    핫스팟 이동으로 IP 가 바뀌면 앱이 **아무것도 하지 않았다** — 정리조차 실행되지 않음.
    **정리보다 재연결 자체가 없는 것**이 더 큰 문제였다
  - **흐름** — TCP 엔드포인트가 `adb devices` 에서 사라지면:
    ① 자동 모드 ON 확인 ② 쿨다운 확인 ③ **IP 재판별**(게이트웨이 1순위) ④ `nc` 도달 확인
    ⑤ `connect` ⑥ 성공 시 **stale 정리** 따라옴
  - **★ `tcpip` 은 건드리지 않는다** — adbd 가 이미 TCP 모드다(TCP 로 붙어 있었으니).
    `tcpip` 은 adbd 를 **재시작**해서 그 순간 연결을 **또** 끊는다
  - **무한 재시도 방지 (이 작업의 최대 위험)** — 폴링 5초 주기이므로 쿨다운 없으면
    **분당 12회** connect 시도 = adb 폭주 + 배터리
    - 기본 **60초** · 연속 실패 시 **2배씩 증가** · 상한 **15분**
    - 15분 지나면 실패 횟수와 무관하게 재시도 (**영구 포기 안 함**)
    - 판정만 `shouldReconnect` 로 분리해 **테스트 8건으로 고정**
  - **안전장치** — 자동 모드 OFF 면 전혀 동작하지 않음 · USB 유실은 이 경로로 안 온다(tcpip 경로가 처리) ·
    `busy`/in-flight 중복 방지 · 실패 시 **조용히 지나가지 않고 사유를 상태로 남김** ([표시②])
  - **검증 [HARD]**: `swift test` **490 + 104 = 594 / 0 failed** (착수 시 586, +8) ·
    `./scripts/build-macos.sh debug` **EXIT=0** · L10n **766키 en/ko 1:1** · U+FFFD 0건
  - **육안**: 핫스팟 이동 후 **USB 재삽입 없이** 기기 재등장 (직접 재현 어려움 — Wi-Fi 토글 필요)
- [x] **stale TCP 엔드포인트 정리 — `ro.boot.serialno` 로 "같은 폰" 판별** — 테스트 9건 신규
  - **문제**: Wi-Fi IP 가 바뀌면 옛 항목이 `adb devices` 에 남아 **같은 폰이 2개 기기**로 잡히고
    **폴링이 2배**(adb 자식 3개 실측). `autoEnableIfEnabled` 는 "이미 열려 있으면 skip" 만 하고 정리 안 함
  - **"같은 기기" 를 어떻게 아는가 — 계측이 답을 줬다**
    `adb devices` 의 TCP 키는 **IP 그 자체**라 IP 가 바뀌면 같은 폰인지 알 수 없다.
    `ro.boot.serialno` 로 판별한다. 실측 — 같은 폰이 하루에 세 번 IP 를 바꿨는데 이 값은 고정:
    ```
    10.233.247.205:5555 (오전)  ─┐
    172.30.102.182:5555 (저녁)  ─┼─ 전부 ro.boot.serialno = R5CT215F4QK
    10.38.120.211:5555 (지금)   ─┘
    ```
    **TCP 로도 읽힌다** — 인증 불필요, `shell getprop` 1회
  - **알고리즘** — TCP 항목이 1개면 아무것도 안 함(대부분) · `keep` 의 물리 ID 와 각 후보의 물리 ID 를
    비교해 **같은 폰의 옛 IP 만** `adb disconnect`
  - **안전장치 3중** (잘못 끊으면 사용자의 다른 기기가 죽으므로)
    ① `keep` 는 절대 끊지 않음 ② **다른 물리 ID 는 절대 끊지 않음** ③ **식별 실패 항목은 끊지 않음**
    (애매하면 남겨두는 편이 옳다) — 셋 다 테스트로 고정
  - **검증 [HARD]**: `swift test` **482 + 104 = 586 / 0 failed** (착수 시 577, +9) ·
    `./scripts/build-macos.sh debug` **EXIT=0** · 신규 경고 0
  - **육안**: IP 가 바뀐 뒤(핫스팟 이동) 목록에 옛 항목이 안 남는지 — 1회 관측 필요

- [x] **T-2026-09-27-5 알림 유입 시 전 탭 지연 — 제안 1·2 적용** — `RESEARCH_alert_tab_slowness` · 테스트 10건 신규
  - **조사 결론**: "데이터가 많아서" 가 **아니다**. 실측 — 알림 1건 유입 = **0.12ms**,
    실제 유입률 **15분에 11건**. 느린 곳은 **InsightsView 하나**(body 1회 6.2ms)였고
    그것이 `objectWillChange` 전파 + 프레임 예산 초과로 **연쇄 지연**을 만든 것
  - **제안 1 — `dayKey` 정수화** (상수 시간 · 위험 최소)
    `dayKey(for:)` 가 `dayOverDay(500건)` 안에서 **1,500회 이상** 호출되며 매번 `String(format:)` + 할당.
    1,500회 기준 **문자열 3.471ms → 정수 0.672ms (5.2배)**
    | 대상 | 적용 전 | 적용 후 |
    |---|---|---|
    | `report` | 4.330 ms | **1.935 ms** |
    | `patterns` | 1.759 ms | **1.164 ms** |
    | body 합계 | **6.2 ms** | **3.2 ms** |
    - 스토어 키(`serial|dayKey`)는 문자열 유지 — 키 포맷을 바꾸면 저장 데이터와 어긋난다
  - **제안 2 — 인사이트 캐시** — 알림 1건이 `objectWillChange` 2회로 body 를 2번 평가해
    **6.4ms**(프레임 예산 38%)였다. 입력이 같으면 재계산하지 않음 → **적중 시 0ms**
    - 무효화 키 9종: `events(first,last,count)` · `selectedKey` · **`todayKey`(자정 경계)** ·
      `serialFilter` · `thresholds` · `dailyRevision` · `sessionRevision`
    - `DeviceDailyStore` / `ConnectionSessionStore` 에 **`revision` 카운터 신설** — 둘 다
      `@Published` 가 아니라 "바뀌었나" 신호가 없었다. **이게 캐시의 전제**
  - **캐시 검증** — 상태 변화 6종(알림·날짜·기기필터·Daily·세션)이 **정확히 1회씩** 무효화되고
    동일 입력은 hit 을 반복하는 것을 **영구 테스트로 고정**(`everyStateChangeInvalidatesExactlyOnce`).
    캐시 버그의 위험은 "안 바뀌어야 할 때 바꾸는" 쪽이 아니라 **"바뀌었는데 그대로 쓰는"** 쪽이다
  - **[HARD]**: `swift test` **473 + 104 = 577 / 0 failed** (착수 시 567, +10) ·
    `./scripts/build-macos.sh debug` **EXIT=0** · 신규 경고 0
  - **하지 않은 것**: `@Published` 20개 세분화(구조적 · 14개 View 의존성 전부 재매핑 필요 —
    **09-26 보류 전례 있음**, 1·2 로 체감 문제 먼저 없앤 뒤 측정 후 재판단)
  - **부수 발견 — 환경 의존 테스트 제거**: `reachabilityUsesAdbPortNotPing` 가 실기 IP 를 하드코딩해
    **핫스pot을 끄는 순간 깨졌다**(실제로 그럼). 판정과 무관한 입력 검증으로 교체 —
    "환경이 바뀌면 깨지는 테스트"는 **버그 신호가 아니라 잡음**이다
- [x] **T-2026-09-27-4 USB 연결 시 자동 Wi-Fi ADB + IP 판별 버그 수정** — `PLAN_wifi_auto_tcpip_relayconsole` · 테스트 16건 신규 · **육안 3단계 대기**
  - **작업을 열자마자 나온 결함**: 자동화를 붙이려던 중 **기존 "Wi-Fi 전환" 버튼이 이 기기에서 고장**임을 계측으로 확인
  - **버그 실측 (SM-S901N · 핫스팟 + 셀룰러 동시)**
    | 방법 | 반환 | 판정 |
    |---|---|---|
    | 앱 1순위 `ip route get 1.1.1.1` | `10.148.183.154` (rmnet_data1) | ❌ **셀룰러 IP** |
    | 앱 2순위 `ip addr show wlan0` | 빈 출력 | ❌ 이 기기에 `wlan0` 없음 |
    | 앱 3순위 `ifconfig wlan0` | 빈 출력 | ❌ 동일 |
    | 맥 게이트웨이 | `10.233.247.205` | ✅ 정답 |
  - **근본 2가지** — ① Samsung Wi-Fi 인터페이스는 `wlan0` 이 아니라 **`swlan0`** ② `ip route get` 의 `src` 는
    **인터넷으로 나가는 쪽의 주소**라 셀룰러를 준다. **빈 값이 아니라 값을 반환해서** 올바른 후보에
    **도달조차 못 했다 → 버튼이 `adb connect 10.148.183.154:5555` 를 시도하며 실패**
  - **순서 개편** — ① 맥 게이트웨이(핫스팟이면 = 폰) ② 기기 `ip addr` 의 Wi-Fi 인터페이스
    ③ `ifconfig` ④ `ip route get`(**마지막으로 강등**) · `isWifiInterface` 로 `wlan*/swlan*/wlp*` 일반화
  - **스크립트의 `ping` 도 이 기기에서 오판한다** — 맥→폰 ping **100% loss** · 폰→자기 ping **0.142ms** ·
    `nc -z :5555` **succeeded** · `get-state` `device`. 즉 **경로가 아니라 폰이 ICMP 를 막는다.**
    ⇒ 도달 확인을 **`nc -z` (실제 서비스 포트)** 로 교체. 유일한 기준이 ping 이면
    **연결 가능한 기기를 "닿지 않음" 으로 처리**해 tcpip 을 건너뛴다
  - **알고리즘** — IP 판별 → `nc` 도달 확인 → **멱등 검사** → `tcpip 5555` → **재시도 3회·2초 간격**
    (고정 대기 800ms 대체) → `disconnect` → `connect` → `No route to host` 면 adb 서버 재시작 후 1회
  - **자동 모드 안전장치** — ① 이미 TCP 열려 있으면 **tcpip 생략**(adbd 재시작 = USB 잠깐 사라짐)
    ② in-flight 세트 (같은 기기 중복 실행 방지) ③ **자동 실패는 팝업 없이 배지 + IssueLog**
    (사용자가 아무것도 안 했는데 튀면 방해) ④ 설정 토글 기본 ON
  - **"USB 뽑아도 유지" 의 원리를 UI 에 명시** — `adb tcpip` 은 adbd 를 네트워크 리스닝으로 바꾸므로
    **케이블을 뽑는 것은 adbd 를 죽이지 않는다.** 단 **재부팅마다 1회** 다시 필요 → 그래서
    "USB 꽂으면 자동" 이 정확한 트리거. 설정 도움말에 이 한계를 적었다
  - **중복 표시** — 배지(`USB` / `IP:5555`)는 **이미 있던 것**이라 신규 UI 없음. USB 항목에
    "자동 연결 실패" 배지만 추가 (안 열렸는데 실패했을 때만)
  - **회귀 실증** — `routeText` 를 1순위로 되돌리면 테스트가 **실패**하며 셀룰러 IP를 고르는 것을 확인 후 복구
  - **검증 [HARD]**: `swift test` **463 + 104 = 567 / 0 failed** (착수 시 551, +16) ·
    `./scripts/build-macos.sh debug` **EXIT=0** · L10n **762키 en/ko 1:1** · U+FFFD 0건
  - **육안 대기 (코드 대체 불가)**: ① USB 꽂기 → 자동 IP 개방 ② **USB 뽑기 → 유지** ③ 재부팅 후 재삽입 → 자동 재연결
- [x] **T-2026-09-27-3 로그 뷰어 검색 (adb 측 필터 + 프리셋 칩)** — `PLAN_log_search_relayconsole` · 테스트 12건 신규 · **육안 대기**
  - **왜 필요했나**: 로그 창에 **텍스트 검색이 없었다.** 레벨 필터(D/I/W/E)만 존재
  - **결정적 계측** — 검색을 어디서 거르느냐가 갈렸다: `*:W` **초당 1.4만 줄**(3초 42,573줄) →
    링 2000행은 **0.14초분**. 클라이언트에서만 거르면 읽을 수 있는 시간이 아니라
    **나타난다 사라지는 것**만 보게 된다. → **adb(기기) 측 1차 필터 + 링 2차 필터** 로 확정(사용자 승인)
  - **단순 문자열 계약의 핵심** — `NSRegularExpression.escapedPattern` 으로 메타문자 이스케이프.
    `a.b` 가 임의 문자로 해석되면 사용자가 검색을 **못 하는 것보다 나쁘다**. 대소문자 무시는 `(?i)` 접두
    (logcat `--regex` 는 Java Pattern)
  - **디바운스 300ms** — 입력 중 adb 를 새로 띄우지 않는다. 기다리는 동안 이전 스트림이 살아 있으므로
    **"일치 없음" 문구가 깜빡이지 않고** 로컬 필터가 즉시 결과를 보여준다
  - **상태 구분 [표시②]** — 검색 중 0줄 = **"일치 없음"**(`droid.logs.search.none`)으로
    "데이터 없음"(오류로 오해)을 쓰지 않는다. adb stderr 가 있으면 **원인을 덮지 않고** 그대로 노출
    (`search.none.err` — 잘못된 패턴이 여기에 뜬다)
  - **정직 배지** — 푸터에 `기기 필터 <검색어>`. adb 필터는 **기기에서** 걸린 결과이며
    **필터 중에는 이전 구간이 되돌아오지 않는다**를 숨기지 않는다
  - **프리셋 4종** — ANR · FATAL EXCEPTION · has died · dropbox. **상태 변화 태그는 넣지 않는다**
    (`thermal` 등 = 2026-09-27 "감지 142건" 장식 사건의 교훈)
  - **의도적 제외(사유 기록)** — 정규식 문법(사용자가 오타로 adb 를 죽인다) · 일치 하이라이트
    (행마다 `AttributedString` 재생성 = 이미 CPU 100% 인 앱에 CPU 예산 초과) · `logcat -b` 버퍼 선택
  - **성능 실측 (같은 기기, 같은 창)** — 검색 전 CPU **89~104%** → 검색 중 **1.4~14%**.
    검색이 **볼륨을 실제로 줄였다는 계측 증거**(장식이 아니다). 자식 adb `*:W --regex=<검색어>` 로 확인
  - **검증 [HARD]**: `swift test` **447 + 104 = 551 / 0 failed** (착수 시 539, +12) ·
    `./scripts/build-macos.sh debug` **EXIT=0** · L10n **755키 en/ko 1:1** · U+FFFD 0건 · 신규 경고 0 ·
    **타이핑 중에도 자식 adb 1개 유지**(디바운스 + `LogcatProcessSlot` 경쟁 수정의 실기 효과)
  - **육안 대기**: 프리셋 칩 4종 동작 · `Aa` 토글 · 지우기 · 0건 문구 · 키보드로 타이핑 시 필드 포커스
- [x] **로그 창 필터 전환마다 adb logcat 이 하나씩 새던 버그** — `LogcatProcessSlot` 신설 · 회귀 테스트 3건
  - **증상**: 레벨 필터(D/I/W/E)를 바꿀 때마다 `adb logcat` 자식이 **누적**. 실측 필터 4회 전환 → **동시 4개 생존**(규칙은 최대 1개)
  - **원인 — 종료 알림이 늦게 도착해 자리를 비운다**: `terminationHandler` 는 `Task { @MainActor }` 로 큐잉된다.
    `stop()` → `terminate()` → 자리 비움 → **새 프로세스 `adopt`** → *이후에* 이전 프로세스 알림이 도착해
    `self.process = nil` 을 실행 → **살아 있는 새 프로세스의 참조가 사라짐** → 다음 전환에서 `stop()` 이 죽일 대상을 못 찾음
  - **adb 는 무죄였고 참조 소실이 원인** — 셸에서 `kill -TERM` 은 즉시 종료함을 실측 확인
  - **조치**: `LogcatProcessSlot`(현재 프로세스 1개의 자리) 신설 — `release(_:)` 는 **내가 아직 들고 있는 그 프로세스일 때만** 비우고 `true`. 알림이 이전 프로세스 것이면 `false` 로 아무것도 안 함
  - **잔여 (기록만)**: `proc.terminationHandler` 가 `proc` 를 강하게 캡처해 **Process 객체 자체가 죽어도 안 돌아옴**(파이프·핸들러 잔류). 기동 1회당 수십 KB 수준이라 측정 전 손대지 않음 — 필요 시 `[weak proc]` 로 사이클 끊기
  - **검증**: `swift test` **435 + 104 = 539 / 0 failed** (+3 신규) · `./scripts/build-macos.sh debug` **EXIT=0** ·
    재실행 후 로그 창 개방 → **adb 자식 정확히 1개**(종전엔 계속 쌓임) · 신규 크래시 0건
  - **육안 대기**: 필터를 여러 번 바꿔도 adb 자식이 1개를 유지하는지(누적 회귀의 유일한 실기 증거)
- [x] **로그 버튼 크래시 근본 제거 — `%@` 에 숫자를 넣으면 죽는다** — 브랜치 `fix/logcat-honesty-incident-cap` · `L10nFormatTests` 12건 신규
  - **증상**: 로그 버튼을 누르면 **즉시 크래시**. 복귀 못 하고 앱이 죽었다가 다시 뜬다
  - **원인 (추측 아님 — 크래시 리포트가 답이었다)**: `~/Library/Logs/DiagnosticReports/RelayConsole-2026-09-27-170630.ips`
    - `exception: EXC_BAD_ACCESS · KERN_INVALID_ADDRESS at 0x8ad` · `far = 2221` · **main thread**
    - 스택: `objc_opt_respondsToSelector` ← `_NSDescriptionWithStringProxyFunc` ← `__CFStringAppendFormatCore` ← `L10n.format` ← **`LogViewerContent.header.getter`**
    - 즉 `"수신 %@줄"` 에 `streamer.totalLines`(Int)를 넣었다. `%@` 는 **객체를 요구**하는데 CFString 포맷터는 정수를 **포인터로** 읽어 2221(0x8ad) 에 `objc_msgSend` 를 날렸다. **줄 수가 곧 주소가 된다**
  - **동일 함정 3곳** — ① `droid.logs.count`(창을 열면 **반드시** 발화) ② `droid.logs.term.exit` ③ `droid.logs.term.signal`(②③ 은 **기기를 뽑으면** adb 가 0 으로 끝나므로 정상 경로). 3곳 모두 `%@` ← 숫자
  - **조치 ① 데이터 정정** — 3개 키 en/ko 동시 `%@` → `%d` (숫자 자리에 숫자 변환자)
  - **조치 ② 클래스 폐쇄** — `L10n.format` 이 **인자 타입에 맞춰 변환자를 교정**하고 넘긴다. `%@`+숫자→`%d`/`%f` · `%d`+문자열→`%@` · `%s`+숫자→`%d` · 변환자 아닌 문자(`50% 이상`)는 리터럴 통과(인자 소비 안 함) · 인자 부족 변환자는 통째로 제거(va_list 초과 읽기 방지). **호출부가 또 실수해도 죽지 않는다**
  - **조치 ③ 검수 자동화** (`L10nFormatTests` 12건) — ① 그 자리의 크래시 회귀(2221줄) ② en/ko **변환자 나열까지** 1:1 (한 로케일만 고치면 그쪽에서 크래시 부활) ③ `L10n.format` 호출부 **전수 스캔** — 인자 수 ≠ 변환자 수 / `%@` 에 숫자처럼 보이는 인자. 되돌려 놓으면 잡히는지 **실측 확인**함
  - **부수 발견 ①**: `files.push.done` 는 변환자 1개에 인자 2개(`dir` 미사용) → 정리
  - **부수 발견 ② (미수정 · 기록만)**: 앱이 죽으면(배포 스크립트 `pkill`) `adb logcat` 자식이 **고아(PPID 1)로 남아 계속 스트리밍** — 28분짜리 잔존 프로세스를 실측으로 확인 후 정리. 종료 시 `LogcatStreamer.stop()` 연결 필요 (앱 정상 종료 경로에서는 `onDisappear` 가 `stop()` 을 부르므로 **강제 종료(pkill·크래시) 때만** 남음)
  - **부수 발견 ③ (미수정 · 기록만)**: 이 기기 `*:W` 유입 **초당 1.6만 줄**(5초 82,167행 실측) → 로그 창 개방 시 앱 **CPU 89%** · RSS 184MB. 링 2000행 × `textSelection(.enabled)` 렌더 비용. 사람이 못 읽는 속도라는 점은 `[표시②]` 관점에서 별건
  - **검증 [HARD]**: `swift test` **432 + 104 = 536 / 0 failed** (착수 시 524, +12) · `./scripts/build-macos.sh debug` **EXIT=0** (1.16.0 · 앱+appex 팀 `6GPJQ7BQC9` 일치) · L10n **744키 en/ko 1:1** 유지 · U+FFFD 0건
  - **런타임 검증 (육안 대신 계측)**: 재설치 후 `relayconsole://logs` 딥링크로 로그 창 개방 → 앱 PID 불변(69697) · 신규 크래시 리포트 0건 · 앱 CPU 67~89% · `adb logcat` 자식 살아 있음 = **줄이 흐르는 상태로 헤더가 수천 번 렌더**됨. 종전엔 이 순간에 죽었다
- [x] **logcat 정직성 + 프로세스 사망 파싱 + incident 덤프 상한** — 커밋 `706daa0` · 브랜치 `fix/logcat-honesty-incident-cap` · **육안 대기**
  - **LogcatStreamer 교착 근본 제거** — `stderr 미배출` 이 원인. 64KB 파이프가 차면 adb 가 `write()` 에서 블로킹돼 **stdout 생산이 멎고** 프로세스도 안 죽어 `terminationHandler` 도 안 불림 = 초록 점 + 빈 화면 영구 지속. stderr 배수 + 알림 펌프 → `readabilityHandler`(전용 스레드, 경합 없음)
  - **LIVE 거짓말 제거** [표시②] — `isLive`(흐르는 중) / `isSilent`(기동됐으나 0바이트) / `isStalled`(3초간 무수신) 구분. 멈춤 시 **adb stderr 원인을 그대로 노출**
  - **볼륨** — 실측 무필터 **초당 약 3만 줄**(6초에 20MB). `MinLevel`(D/I/W/E) 필터를 adb 쪽에 적용 + 링 200 → **2000행** + 안정 id(`offset` id 는 플러시마다 전 줄 재렌더) + 수신 총 줄 수 표시
  - **"크래시 적중 1건"만 남던 문제** — 감지 키워드는 4개인데 파서는 2개만 봄 → `has died` / `force finishing` / `anr in` 대응 추가(`extractProcessDeathContext`). **실기 형식 2종** 처리: `has died. Reason: SIGSEGV` · `has died: cch+5 CEM (926,1457)`(lmkd 킬러 사유 — 종전 `Reason:` 만 찾으므로 통째로 누락)
  - **`logcatKeywords` 의도적으로 비움** — `accelerometer_rotation`·`wm_user_rotation_changed`·`thermal` 은 에러가 아니라 **센서·회전·발열 상태 변화**. 가만히 있어도 5분에 +140건 → `탐지` 카드가 "문제 142건" 처럼 읽힘 + `>` 클릭 → Alerts(같은 카운트 반복) → 로그 창(교착으로 빈 화면) **세 화면 연속으로 장식**. 실패 신호만 남김
  - **IncidentBundle — 스택이 하나도 안 들어가던 문제** — ① crash 버퍼 덤프 신설(`-b crash`, `hasCrashLogcat` 필드) ② main 덤프를 `-T` 시각 앵커로 전환(종전 `-t 500` 은 이 기기에서 **약 2초분**이라 캡처 시점엔 이미 롤아웃) ③ **앵커 60초 리드** — `event.at` 은 크래시 그 자체가 **아니다**(폴링 5초 + 캡처 지연). 실측 이벤트 10:00:12 vs 실제 `has died` **10:00:06** → 앵커를 `event.at` 에 두면 크래시 라인이 창 밖으로 밀려남(실측 18건 → 19건)
  - **39MB 회귀 차단** — 실측 `-T 5분분` = **39.0MB / 33만 줄**(종전 52KB, 750배). adb 쪽에서 못 자름: **`-T` 에 `-t` 를 같이 주면 `-T` 가 이김**(실측 336,024줄) → 읽는 쪽에서 뒤를 자르는 `TailBuffer`(2MB, 이벤트에 가까운 끝 보존). **잘린 양은 파일 첫 줄에 명시**(숨기지 않음). `runCaptureTail` 로 전환하며 stderr 배수 — 종전 `runCaptureData` 에 **같은 함정이 남아 있었음**
  - **검증 [HARD]**: `swift test` **420 + 104 = 524 / 0 failed** (+13 신규) · `./scripts/build-macos.sh debug` **EXIT=0** (1.16.0 · 팀 6GPJQ7BQC9) · L10n **744키 en/ko 1:1** · U+FFFD 0건
  - **실기 계측 (10.233.247.205:5555 · SM-S901N)**: `*:W` 필터 후에도 **55,166줄/6초(초당 9천)** — 상위 태그는 `E/HeatmapThread`(22,851)·`E/SemApTrafficData`(19,061)로 삼성 기기 특유 오류 스팸. **crash 버퍼는 이 기기에서 0줄**(덤프는 유지 — 버퍼를 쓰는 기기를 위해) · 번들 34개 23MB(스크린샷이 대부분)

## 완료 (2026-09-26)
- [x] **성능·안정성 리팩토링 6단계 전체 완료** — `PLAN_refactor_perf_stability_macos` · PR #45~#50 · 태그 `pre-refactor-perf` 롤백 지점
  | 단계 | PR | 핵심 성과 |
  |---|---|---|
  | 1 어댑버 안전화 | #45 | **앱 정지(Hang) 근본 제거**(`ProcessRunner`) · [HARD] 토큰 평문 로그 |
  | 2 ADB 배치화 | #46 | **adb 프로세스 85% 절감** (313→47/분) |
  | 3 신선도·정직성 | #47 | 측정 실패 위장 제거 · logcat 248배 |
  | 4 메인 스레드 정지 | #48 | **쓰기 증폭 95~99% 제거** |
  | 5 SwiftUI 렌더 | #49 | **InsightsView body 57ms→3ms** |
  | 6 종료·누수·디스크 | #50 | NSPanel 누수 · IssueLog 무한 append · 저장 실패 무음 |
  - 테스트 **332 → 511** 전부 통과 · L10n **729 → 736** 키 (en/ko 1:1) · 버전 1.16.0
  - **5·6단계는 착수 전 실측해 계획이 과장된 항목을 범위에서 제외** (추측 금지 원칙 일관 적용)
- [x] **R6 종료·누수·디스크** — `PLAN_refactor_perf_stability_macos` 6단계 · 커밋 `6776605` · 브랜치 `chore/macos-refactor-p6-lifecycle` · **육안 대기**
  - ① **NSPanel 리소스 누수** — `isReleasedWhenClosed = false` 인데 teardown 이 `orderOut` + 딕셔너리 제거만 해 `NSHostingController`·SwiftUI 트리가 잔류(창 반복 열면 단조 증가) → `contentViewController` → `contentView` → `close()` 순으로 명시적 해제
  - ② **종료 시 `group.wait` 결과 버림** — 0.5초 timeout 인데 `_ =` 로 버림 → timeout 시 `shutdown.monitorTimeout` 로그
  - ③ **`ScrcpyController` 5초 타이머 미해제** — `stop()` 이 프로세스만 정리 → `invalidate()` + nil
  - ④ **`IssueLog` 무한 append** — 로테이션·상한 0 + `tail()` 이 전체 파일 로드 → **일자 분리**(`{name}-yyyyMMdd.jsonl`) + 파일당 2MB 상한(초과 시 최근 절반 유지, 잘린 앞부분 반쪽 줄 버려 **JSONL 무결성 보존**) + 14일 자동 삭제 + `tail()` 은 오늘 파일만. **런타임 검증**: `device-20260926.jsonl`·`notify-20260926.jsonl` 생성, 기존 파일 보존
  - ⑤ **저장/로드 실패 무음 (복구 불가 위험)** — 로드 실패가 빈 배열로 대체돼 다음 저장에서 **기존 파일이 통째로 덮어써짐**. 미사용이던 `E-MAC-STORE-0001~0003` 활성화 → (a) 파일 존재 + 디코딩 실패 구분(파일 없음=최초 실행=정상, 오탐 방지) (b) 저장 전 손상 원본을 `.corrupt-<ts>` 로 1회 보존 (c) 2분 주기 저장 건강 검사 → `storeProblem` @Published → 대시보드 배너 (d) 복구 시 자동 해제
  - **검증 [HARD]**: `swift test` **407 + 104 = 511 / 0 failed** (+8 신규) · `./scripts/build-macos.sh debug` **EXIT=0** (1.16.0 · 팀 6GPJQ7BQC9) · 런타임 기기 재인식·크래시 0건(신규)·종료→재기동 후 이벤트 277건 보존 · L10n 3키(총 736, en/ko 1:1) · U+FFFD 0건
  - **TODO 문서 정리**: R4·R5·R6 이 "진행 중" 에 중복 3줄 잔재 → 통합
- [x] **R5 SwiftUI 렌더 — 실측 기반 범위 확정** — `PLAN_refactor_perf_stability_macos` 5단계 · 커밋 `88f8e83` · 브랜치 `chore/macos-refactor-p5-swiftui` · **육안 대기**
  - **실측(실제 데이터 264건)**: `monthGrid`(셀 31 × 전체 필터) **19~38ms** · `insight` 중복 ×13 **14.2ms** · `report` 중복 ×9 **4.6ms** · `DateFormatter` body 내 생성 0.178ms/행 → **body 1회 평가 약 57ms**
  - **monthGrid(최대 단일 항목)** — 셀마다 `dayStatus` 에 전체 이벤트 전달 → **날짜별 1회 그룹핑** 후 각 셀은 자기 날짜 배열만 봄 → **1.4ms(13배)**, 결과 동일 확인
  - **중복 계산 제거** — `daySummaryCard`·`reportCard`·`patternsCard` 가 computed property 를 매번 재계산 → **body 상단 1회 계산 후 주입**. `patterns.last?.id` 행마다 계산 → 루프 밖 1회
  - **`fitAll()` 무조건 호출 차단** — `leftMouseUp` 이 dragPressScreen 유무와 무관하게 항상 호출(클릭 1회당 최대 6창 × 4회 강제 레이아웃) → **실제 드래그 시로 게이트**. `store.objectWillChange`(57개 전부) → 카드가 읽는 `inventory`·`metricsHistory` 만으로 좁힘
  - **`AlertsView.counts` 3회 순회 → 1회** — **8가지 필터 조합 전부에서 신구 결과 동일** 테스트로 확인(합계 정합 포함)
  - **의도적으로 안 함**: `ConsoleStore` 57속성 스토어 분리(대규모 구조 변경) — 위 직접 비용(~57ms)을 먼저 제거하니 체감 개선이 대부분 해결됨. 남은 이득은 추가 측정 후 판단
  - **검증 [HARD]**: `swift test` **399 + 104 = 503 / 0 failed** (+8 신규) · `./scripts/build-macos.sh debug` **EXIT=0** (1.16.0 · 팀 6GPJQ7BQC9) · 런타임 기기 재인식·크래시 0건(신규)·U+FFFD 0건
- [x] **R4 메인 스레드 정지 — 실측 기반 재정의** — `PLAN_refactor_perf_stability_macos` 4단계 · 커밋 `f1cfad2` · 브랜치 `chore/macos-refactor-p4-mainthread` · **육안 대기**
  - **⚠️ 계획이 과장했음을 실측으로 확인** — `EventStore` 인코딩 **0.35ms** + 동기 write 0.11ms = 0.46ms(254건/57KB) · `SitesJobsStore` 8×300 = 2.42ms(288KB) · `WidgetSnapshot`/`DeviceDailyStore` 0.01ms · `IssueLog.url` mkdir 0.0072ms · 디렉터리 스캔 1000파일 6.7ms → **합산 main 스레드 1% 미만**. 조사 에이전트 추정치와 크게 달라 **"인코딩 백그라운드화"만으로는 이득이 없어 측정된 실제 결함만** 작업
  - **실제 결함 ① 쓰기 증폭(95~99% 낭비)** — 상태 파일은 최종 상태 하나만 의미가 있는데 값이 바뀔 때마다 전량 재기록 → 이벤트 20건 연속이면 20회×57KB=1.12MB 쓰고 최종은 마지막 1회로 덮어짐(활동 60건/분=3.4MB, 600건/분=33.5MB 전부 낭비). **`CoalescingWriter` 신설** — 대기 쓰기를 최신 값으로 대체 + 인코딩도 writer 큐에서 수행(MainActor 비용 제거). `EventStore`·`SitesJobsStore`(sites/jobs)·`DeviceDailyStore` 적용. **실측 감소 20건 95% · 60건 98% · 600건 99%**
  - **종료 유실 방지** — `flushSync()`(진행 중 쓰기 + 대기 값 동기 기록) 신설 후 `shutdown()` 에 3개 스토어 flush 연결(R1 `ConnectionSessionStore` 와 동일 결함 방지). **SIGTERM 종료 후 파일 md5 불변 + 259건 정상 디코딩으로 유실 없음 실증**
  - **저장 실패 보존** — `lastSaveError` + `DebugLogger` 기록 (조용한 실패 0건)
  - **실제 결함 ② 비원자적 `@Published` publish** — `ingestWatch`/`pushEvent` 가 insert·trim 을 나눠 대입해 **상한 초과 중간 상태**(501건/21건)가 관측될 수 있었음(그 상태가 렌더되면 대시보드·인사이트 전부 재계산 — 1단계 단일 평면과 결합해 배수 비용) → 로컬 계산 후 **1회만 대입**, 상한을 `maxWatchEvents`/`maxRecentEvents` 상수로화
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
