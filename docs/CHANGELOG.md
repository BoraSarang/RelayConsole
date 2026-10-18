# CHANGELOG — Relay Console

> **작성 규칙** (`rules/workflow.md` §2): 항목은 `type(platform): subject` · platform 태그 · error_code(해당 시) ·
> perf/cache 영향 기재. 버전은 **기능 마일스톤**에서 상승(`Resources/Info.plist`).
> 날짜는 해당 버전이 머지된 날. 상세 근거는 git log · `docs/TODO.md` · `docs/plans/` · `docs/MANUAL_VERIFY.md`.
> 버전별 항목은 **주요 변경만** 기재한다(전수는 PR 번호로 git log 조회).

---

## 1.21.0 — 2026-10-18

### Added
- **feat(macos)**: **dropbox 경로 보강 — 놓친 ANR·크래시 회수** (T-2026-10-17-8 · `PLAN_dropbox_recovery_relayconsole`)
  - logcat 은 링 버퍼라 롤아웃된 ANR·크래시가 사라진다(실측: 초당 3만 줄 기기에서 500줄 ≈ 2초분). dropbox 는 영속 큐(1000건)라 원문이 남는다
  - 종전에는 **"크래시/ANR N건 발견" 문자열 알림 1건**이 전부였다 → 이제 **구조화 이벤트**로 Alerts·알림·자동 번들·진단 파이프라인에 편입
    - 목록(`dumpsys dropbox` · 3.8~10.5KB) → 새 시각만 `--print '<정확한 시각>' | head -c 200000` (**정확 일치 필터** · 시각 인용 필수)
    - 첫 스캔은 기준선만 설정(과거 폭주 방지) · 사건 시각 = dropbox 시각(정렬·집계가 정확해진다) · 스캔 결과 로그
    - 중복 2중 차단: 시각 기준선 + `WatchEngine` 5분 쿨다운 (logcat 이 먼저 보면 logcat 이벤트가 남고, 놓쳤을 때만 산다)
- **feat(macos)**: **번들 내보내기** — 캡처된 번들 행의 `square.and.arrow.up` → 위치 선택 → 번들 폴더를 만들어 **원본 그대로 복사**
  - 이미 있는 이름은 **덮어쓰지 않는다** · zip 은 의도적 OUT(새 외부 프로세스 불필요 — 외부 프로세스는 adb·scrcpy 둘로 못 박음)

### Changed
- **fix(macos)**: **번들 생성 실패를 더 이상 삼키지 않는다** ([표시②])
  - `try?` 로 조용히 사라지던 첨부·스크린샷 실패를 모아 manifest **`schema 2` + `failures`** · `DebugLogger` warn · **Alerts 배너**(사유 그대로)로 노출
  - manifest(번들의 인덱스) 쓰기 실패 시 디렉터리를 되돌린다(반쪽 번들 방지) · MCP `list_incidents` 가 `failures` 전달
- **feat(macos)**: 번들에 **`dropbox.txt` 첨부** — 같은 종류 + 이벤트 앞 600초·뒤 300초 창, 최대 2건 (logcat 에 없던 원문 확보)
  - 본문은 **앞을 남긴다**(`Process`·`Package`·`Subject`·트레이스 머리) · "항목 없음"(정상)과 "조회 실패"를 구분
- **chore(macos)**: 버전 **1.21.0** — `Info.plist` · `README.md` · `McpProtocol.serverVersion` · `AGENTS.local.md` 4곳 동시 갱신
- **chore(macos)**: `AdbClient.shellQuoted` 공용화(폰 찾기 중복 제거) · `parseDropboxRecentTags` 제거(새 파서 대체 — 픽스처가 실기기 형식과 달랐다) · L10n `event.dropbox.hits` 제거

### 검증
- `swift test` — Swift Testing **759/0** (+30: `DropboxLogTests` · `IncidentBundleExportTests` · manifest `failures` · MCP `failures`) · XCTest **168/0**
- `./scripts/build-macos.sh debug` 완료 · 번들 **1.21.0** · L10n **819/819** · 한자·U+FFFD 0
- **실기기 대조**(실측 원문): A908N 75건 중 대상 5건 · `since 04:50:23` → 발행 3건(최신 우선) · 기준선 `04:53:00` ·
  실제 크래시 블록 → `pkg=com.borasarang.zenfreeproxy` 사유 `IllegalFormatConversionException…` · S901N 33건 중 대상 0건(잡음만)
- error_code 신규 없음 · cache/network 영향 없음(5분 쿨다운 · 목록만 매 스캔, 본문은 새 항목에만) · 육안 `MANUAL_VERIFY` **§28(69~72)** — 72 ✅ 실측 · 69~71 ⬜(폰 네트워크 복귀 후)

---

## 1.20.0 — 2026-10-18

### Added
- **feat(mcp)**: **진단 축 MCP 도구 3종** — 읽기 전용 원칙 유지 (T-2026-10-17-7 · `PLAN_local_mcp_relayconsole` §9)
  - `list_diagnoses`(`diagnoses.json` — crash·throttling · `kind`/`serial`/`limit` · 최신순)
  - `list_incidents`(`incidents/*/manifest.json` — `files`·`sizeBytes` · 최신순 · **디렉터리 이름 정렬로 상한만 읽는다**)
  - `get_device_history`(`device-daily.json` — 기기별 최신 N일 · 오래된→최신 순 · 소수 1자리)
  - 보강: `list_events` **`serial` 필터** · `get_summary` **`diagnosedCrashes`·`incidentBundles`**
  - 지문 파싱(`A:5555:crash:…` → 시리얼은 `<kind>` 앞부분) · 상한 1~100(`days` 1~90) · 없는 기기는 오류가 아니라 `[]`
  - **쓰기·제어 도구는 추가하지 않는다**(mobile-mcp 계열과 다른 축 = 진단)

### Changed
- **chore(macos)**: 버전 **1.20.0** — `Info.plist` · `README.md` · `McpProtocol.serverVersion` · `AGENTS.local.md` 4곳 동시 갱신
- **chore(deps)**: `libimobiledevice` **1.4.0 → 1.4.0_2**(홈브루 리비전 · `libusbmuxd` 2.1.1_1 · `libplist` 2.8.0)
  - 업그레이드 후 `idevice_id`/`ideviceinfo` 동작(1.4.0) · `idevice_id -l` **빈 목록 + exit 0**(Apple 기기 미연결 = 정상) · 심볼릭이 `Cellar/1.4.0_2` 로 갱신됨
  - 앱은 `/opt/homebrew/bin/<tool>` 심볼릭으로만 탐지 → 리비전 업그레이드에 코드 영향 0 · `IdeviceParsingTests` **12/12** 회귀 없음
  - 애플 실기 라이브 확인은 **기기 미연결로 불가**(TODO 「기기 확보 시」 유지) · 검증 버전을 `AGENTS.local.md` §4 에 기록

### 검증
- `swift test` — Swift Testing **729/0** (`McpProtocolTests` +7) · XCTest **168/0**
- `./scripts/build-macos.sh debug` **EXIT=0** · 번들 **1.20.0** · L10n 812/812 · 한자·U+FFFD 0
- **stdio 실측**(실제 앱 데이터): 도구 6종 · 크래시 최신순 · 번들 `files` 3 + `sizeBytes` ·
  `get_device_history {days:1}` 14행(기기별 최신 1일) · 시리얼 필터 동작 · 요약 `diagnosedCrashes 263 · incidentBundles 389`
- error_code 신규 없음 · cache/network 영향 없음 · 육안 `MANUAL_VERIFY` **§27(66~68) ✅ 에이전트 실측** · **PR #114**

---

## 1.19.0 — 2026-10-18

### Added
- **feat(macos)**: **폰 찾기** — 메뉴바 팝오버 헤더 아이콘 1회 = 화면 깨우기 + 최대 밝기 + 알림음 3회 → 밝기 원복 (T-2026-10-17-5 · `PLAN_find_phone_relayconsole`)
  - adb 표면 **스파이크 후 부분 채택**: 지속 벨소리(재생기 없음) · 진동(`cmd vibrator` 부재) · 손전등 · 무음/진동 **모드 전환** ·
    통화 인텐트(오발신) · 타이머 우회(시계 앱 권한·알림 꺼짐)는 **미채택** — 사유는 PLAN §2~3
  - 알림은 같은 tag 재게시 → **알림 1건만 유지 · 본문 회차 표기로 다시 울림** · 반복 사이 2초 · 진행 중 중복 탭 잠금
  - **밝기 원복**: 시작 전 `settings get` 으로 읽어 둔 모드/값을 마지막 알림 2초 뒤 되돌린다(읽기 실패면 그 키는 건드리지 않음)
  - 안전장치: 인자는 `Process.arguments` · **제목·본문 단일 인용**(`adb shell` 재파싱 대응 — 실기기에서 잡은 결함) ·
    tag 살균(영숫자·`-`·`_`) · 본문 제어문자 제거·120자 · 밝기 1~255 클램프
  - **한계 명시**: 무음·방해 금지 모드면 소리는 나지 않는다(adb 로 모드 전환 불가) — 툴팁·MANUAL_VERIFY §26 기재
  - L10n **807 → 812키** (en/ko 1:1)

### Changed
- **chore(macos)**: 버전 **1.19.0** — `Info.plist` · `README.md` · `McpProtocol.serverVersion` · `AGENTS.local.md` 4곳 동시 갱신(테스트가 일치 강제)

### 검증
- `swift test` — Swift Testing **722/0** (+11 신규 `FindPhoneTests`) · XCTest **168/0**
- `./scripts/build-macos.sh debug` **EXIT=0** · 번들 **1.19.0** · 서명 검증 통과 · L10n 812/812 · 한자·U+FFFD 0
- 실기기 라이브(SM_S901N · Android 16): 앱과 동일 인자 순서 실행 → `mode 0 · level 255 · mWakefulness=Awake` →
  알림 **3회 게시 성공 · 1건만 유지**(`폰 찾기 (3/3)`) → **`level 49` 로 원복**(부작용 없음)
- error_code 신규 없음 · cache/network 영향 없음 · 육안 `docs/MANUAL_VERIFY.md` **63~65 ✅ 사용자 확인 (2026-10-18)** · **PR #113**

---

## 1.18.0 — 2026-10-18

### Added
- **feat(macos)**: scrcpy 옵션 노출 8종 (T-2026-10-17-6 · `PLAN_scrcpy_options_relayconsole`)
  - `--hwdec` 자동/소프트웨어 강제/VideoToolbox · `--video-codec` (h264/h265/AV1/VP8/VP9) · `--video-buffer` ·
    `--disable-screensaver` · `--window-title`(=`identLabel` · [표시①]) · `--always-on-top` ·
    `--background-color=#1c1f2a` · `--power-off-on-close`
  - 설정 → 연동 → scrcpy 미러링 섹션에 행 9개 · 값 검증 이중(허용 목록 + 인자 검증) · 하위 호환 테스트 고정
  - L10n **794 → 807키** (en/ko 1:1)
- **feat(macos)**: **두 대 동시 미러링** (T-2026-10-18-1) — 프로세스 슬롯을 기기별(`serial → Process` + `runningSerials: Set<String>`)로 전환
  - 두 번째 기기를 열어도 **첫째 미러가 그대로 남는다**(종전: 첫째가 `SIGTERM`) · `WifiAdb` 옛 IP 정리는 **미러링 중인 모든 기기를 보호**(Demuxer error 방지)
  - UI 변경 0줄 — 버튼 상태는 원래 `isRunning(serial:)` 로 기기별 계산 · 앱 종료는 `stopAll()` 로 고아 프로세스 방지
  - 실측: 두 대 동시 13초 유지 (SM_A908N 4.2% CPU + SM_S901N 5.1%) — 하드웨어 디코딩 덕에 2대가 두 배 부담이 아님
- **perf(macos)**: scrcpy **4.1_1 → 5.0.1** — 하드웨어 디코딩(VideoToolbox) 실측
  - 1920/8M/60fps: 프로세스 CPU **13.4% → 4.2%** (3.2배 감소) · 1024/2M/30fps(앱 기본): 4.6% → 3.0% (1.5배)
  - 앱이 넘기는 기존 9종 옵션 5.0.1에서 전부 유효 → **코드 변경 없이 드롭인**
- **docs**: `CHANGELOG`(본 문서) · `PLAN_scrcpy_options_relayconsole` 신규 · `MANUAL_VERIFY` §24 (56~60) 신규 · `bd RelayConsole-atv`

### Changed
- **chore(macos)**: 버전 **1.18.0** — `Info.plist` · `README.md` · `McpProtocol.serverVersion` · `AGENTS.local.md` 4곳 동시 갱신(테스트가 일치 강제)

### 검증
- `swift test` Swift Testing **711/0** (+6 신규) · XCTest **168/0**
- `./scripts/build-macos.sh debug` **EXIT=0** · 번들 1.18.0 · 서명 검증 통과 · L10n 807/807 · 한자·U+FFFD 0
- 실기기 라이브: 새 옵션 조합 실행 → `Interop: videotoolbox` 확인 (SM-A908N · Android 12 · 무선)
- error_code 신규 없음 · cache/network 영향 없음 · **PR #111** · 육안 61·62 ✅ 사용자 확인 · 56~60 **사용자 지시 마감**(개별 실측 대신 — 사유는 `docs/MANUAL_VERIFY.md` §24 머리말)

---

## 1.17.0 — 2026-10-17 ~ 2026-10-18

### Removed
- **chore(macos)**: 위젯(WidgetKit 3종) 제거 + 미사용 자산 정리 — **1,132 LOC** · `xcodegen` 불필요(SwiftPM 단독) · L10n 782 → 756키 (DECISIONS D2 · PR #107)

### Added
- **feat(macos)**: Android 11+ 무선 디버깅 페어링 + 재부팅 내구성 (PR #108 · MANUAL_VERIFY 48~49)
- **feat(macos)**: 같은 폰이 여러 전송으로 잡혀도 목록은 **한 줄**로 — 전송 합침 (PR #109 · DECISIONS D3)
- **feat(macos)**: 팝오버 헤더 파일 탐색기 아이콘 (PR #100) · 기기 상세 기본 펼침 (PR #103)

### Fixed
- **fix(macos)**: 무선 재연결 내구성 7건 — 포트 하드코딩(555 하드코딩 2곳) · 새 mDNS 광고면 백오프 건너뛰기 ·
  `[끊기]` 되살아남 · 끊김 상태 줄 · 안내 문구 잘림 · 시트 USB→Wi-Fi 대상 (PR #110 · DECISIONS D4)
- **fix(macos)**: 네트워크 합계 **0.0 회귀** — adb 과차감(창 불일치) 클램프 제거, 링 최소값 차감 (PR #99 · perf · PLAN_net_adb_clamp)

### Docs
- MANUAL_VERIFY 45·46 반영 (PR #101 #102) · 경쟁 리서치 v2 (PR #105 #106) · 이관 문서 정리 (PR #104)
- L10n 756 → **794키** 로 회복·확대 (한자 0건 유지)

---

## 1.16.0 — 2026-09-25 ~ 2026-10-14

### Added
- **feat(macos)**: 파일 탐색기 ADB 읽기·가져오기·전송 (PR #44) → 삭제·진행률·취소·Finder형 내비게이션 (PR #72)
- **feat(macos)**: scrcpy 옵션 설정화 1차 — 기본 8종 + 추가 옵션 (PR #77) · 앱 언어 선택 (PR #73)
- **feat(macos)**: 충전 방치 카드/리포트 (PR #68 #62) · Prometheus `/metrics` 엔드포인트 (PR #61) ·
  알림을 캘린더 일정에 추가 — 쓰기 전용 권한, 사용자가 누를 때만 (PR #66)
- **feat(macos)**: S3 관제 규칙 **Rules as Code** — 임계값 로컬 YAML (PR #59) · 로그 창 태그 선택 UI (PR #54)
- **feat(macos)**: 크래시 자동 진단 Phase 1~3 (PR #80 #81) · 플러그인 탭 + SDK v2 (PR #82 #89)
- **feat(macos)**: 메뉴바 **AppKit NSStatusItem** 전환 + 기기별 열 (PR #90) · 외부 트래픽 분리·ipa 중복 제외 (PR #91)

### Changed
- **chore(macos)**: **Sites·Jobs 제거** — 기기 관제로 집중 (DECISIONS D1 · PR #78)

### Fixed / perf
- **perf(macos)**: 성능·안정성 6단계 — 쓰기 증폭 95~99% 제거 (PR #48) · `InsightsView` body **57ms → 약 3ms** (PR #49) ·
  NSPanel 누수·IssueLog 무한 append (PR #50) · 폴링 다이어트 (PR #75) · 감사 배치 5종 (PR #93~#98)
- **fix(macos)**: 미해소 critical 부풀림 — enter 스택을 지문당 1개로 (PR #64) · Wi-Fi ADB가 라우터로 붙던 결함 (PR #65) ·
  강제 종료 시 고아 adb 정리 (PR #55) · 태그 선택 팝오버 닫힘 + AX 자동 검증 도구 (PR #60)

---

## 1.15.0 — 2026-09-25

- **feat(macos)**: WidgetKit 위젯 3종 + App Group 스냅샷 · 딥링크 (PR #43)
  - → **1.17.0 에서 전면 제거**됨 (DECISIONS D2 — 코드 변경 0건·마케팅 가치 0 판정)

---

## 1.14.0 — 2026-09-24 ~ 2026-09-25

- **feat(macos)**: 알림 채널 ntfy·Slack (PR #21) · 아침 브리핑 (PR #22) · 플로팅 그래프 (PR #25 #28) ·
  Wi-Fi ADB 온보딩 (PR #31) · 인시던트 번들 (PR #32) · 앱 미니 허브 (PR #33) · 로그인 항목 (PR #34) ·
  로컬 MCP 서버 (PR #35) · Device Health Score (PR #36) · 파일/스샷 갤러리 (PR #37) · Sites 캘린더 (PR #38) ·
  인사이트 Phase 1~4 (PR #39) · 네트워크 신호·앱별 트래픽 (PR #40) · 대시보드 감지 규칙 (PR #42)
- **feat(macos)**: 설정 사이드바형 (PR #20) · 나가기 확인 (PR #19) · 통신량 단위 (PR #29) · Sites SSL (PR #30)
- 검증: 신규 4건 육안 완료 후 상승

---

## 1.11.0 ~ 1.13.0 — 2026-09-24

- **1.13.0** A6 Sites 90일 캘린더 + 태그 필터
- **1.12.0** A4 파일/스샷 갤러리
- **1.11.0** S2 Device Health Score

---

## 1.0.0 ~ 1.10.0 — 2026-09-24 (초기 스캐폴드)

| 버전 | 내용 |
|---|---|
| 1.10.0 | A10 로컬 MCP 서버 |
| 1.9.0 | A8 로그인 항목 + 헤드리스 |
| 1.8.0 | A3 앱 미니 허브 |
| 1.7.0 | S4 Incident Bundle |
| 1.6.0 | A2 Wi-Fi ADB 온보딩 |
| 1.5.0 | A5 Sites SSL 만료·HTTP assertion |
| 1.4.0 | F1 기기 그래프 플로팅창 |
| 1.3.0 | S1 아침 브리핑 한 줄 |
| 1.2.0 | 외부 알림 채널 ntfy·Slack |
| 1.1.0 / 1.1.1 | Sites v1.1(UptimeRobot·타임라인) / 설정 사이드바형 개편 |
| 1.0.0 | Sites/Jobs B — SitesView·JobsView |

그 이전(v0.1~v0.9): 스캐폴드 · 감시 3종 · **scrcpy A안**(v0.7) · Alerts 3탭 — git log 참고.
