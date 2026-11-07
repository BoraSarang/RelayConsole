# CHANGELOG — Relay Console

> **작성 규칙** (`rules/workflow.md` §2): 항목은 `type(platform): subject` · platform 태그 · error_code(해당 시) ·
> perf/cache 영향 기재. 버전은 **기능 마일스톤**에서 상승(`Resources/Info.plist`).
> 날짜는 해당 버전이 머지된 날. 상세 근거는 git log · `docs/TODO.md` · `docs/plans/` · `docs/MANUAL_VERIFY.md`.
> 버전별 항목은 **주요 변경만** 기재한다(전수는 PR 번호로 git log 조회).

---

## Unreleased (PR #136·#139 머지 · `9da9114` · 버전 미정)

### Fixed
- **fix(macos)**: **Wi-Fi ADB 수동 연결·자동 재연결에서 앱 전체가 얼어붙던 문제** — 도달 불가 호스트(`192.168.190.216:5555`)에 `adb connect` 를 걸면 macOS TCP 타임아웃까지 **75초**를 기다리는데, 이 호출이 `@MainActor` 컨트롤러에서 **타임아웃 없는 동기 `Process`** 로 실행돼 그동안 앱이 무응답(무지개 커서)이었다. 15분 자동 재연결도 같은 경로라 주기적으로 재발했다 — 2026-11-07 실측 `time adb connect` **real 75.03s**
  - `WifiAdbRunner` 의 모든 실행을 **`ProcessRunner`(데드라인·stderr 교착 방어) + detached Task** 로 교체. connect 계열 **8초**, 일반 명령 **15초** — 메인 스레드는 어떤 경우에도 잠기지 않는다
  - 데드라인 초과는 일반 실패와 구분해 `wifi.error.timeout`("기기가 %d초 안에 응답하지 않았습니다")으로 표시한다 (`catch` 원인 삭제 금지 유지)
  - 수동 연결은 `adb connect` 전에 **TCP 도달성 선검사**(`nc -z`, detached 2초)를 한다 — 없는 호스트는 8초 시도 전에 "…에 닿지 않습니다"로 즉시 끝난다
  - 검증: `swift test` **881/881**(신규 2 — runner 데드라인·connect 기한 상한) · `./scripts/build-macos.sh debug` BUILD SUCCEEDED · 앱 1.25.0 재시작 — 육안 확인은 사용자 몫
  - 같은 뿌리의 후속(별건): 자동 재연결 실패 시 **전역 `adb kill-server`** 가 다른 정상 기기 세션까지 끊는다 · 폴링 실패가 JSONL 에 남지 않는다

- **fix(macos)**: **APK 설치가 "1/1대 기기 준비 중…"에 멈춘 것처럼 보이던 문제** — 실기기 설치가 24초 걸리는 동안 배너 문구가 **설치 전 단계에 고정**돼 있었고, 그 구간 로그가 없어 사용자가 두 번 취소했다(2026-11-05 23:04·23:05 `app.install` `cancelled` 2건 → 23:26 `adb install -r` 24초 성공)
  - `runSingleInstall` 이 `adb install` 직전에 **"설치 중…"** 으로 전환하고, `applyInstallResult` 가 끝나기 전 **"설치 확인 중…"**(패키지 변경·버전 확인)을 표시한다. 종전에는 번들 설치만 `install`/`obb` 단계가 있었다
  - 단일 APK 는 진행률이 없어 0 에 머물렀다 → 배너가 **불확정(움직이는) 진행 막대**를 보여 주고, 끝나면 1 로 채운다. 성공 직후 `installProgress` 가 0 인 채 사라지던 것도 함께 정리
  - 단계 로그(`DebugLogger` › `AppHub`): **설치 시작(파일·바이트·대상·옵션) → SHA-256(ms) → 설치 전 패키지 확인(개수·ms) → adb install(exit/timeout·ms) → 설치 확인(변경 수·버전·ms) → 성공/실패(ms)**, 취소 시 경과 시간. 로그 창(`relayconsole://logs`)에서 설치 중에도 흐른다
  - 아이콘 pull(동시 2개)이 같은 ADB 대역폭을 나눠 쓰지 않도록 **설치 중 새 pull 을 멈추고** 끝나면 재개(`AppIconStore.suspend/resume`)
  - 1대일 때 문구를 `1/1대 기기 준비 중…` → **`기기 준비 중…`** 으로 정리(`apphub.install.phase.device.one`, 한/영)
  - 검증: `swift test` **879/879**(신규 1 — 단계 문구 키) · `./scripts/build-macos.sh debug` BUILD SUCCEEDED · **사용자 확인(2026-11-06)** — 설치가 정상 동작하고 로그 창에서 단계 로그가 보인다 · `MANUAL_VERIFY` §38 114~115 ✅
  - **PR #139 → squash merge `9da9114`**

- **fix(macos)**: **앱을 재시작하면 선택한 기기가 다른 기기로 바뀌던 문제** — 시작 직후 인벤토리가 비어 있는데 저장된 선택(S7)이 있다는 이유로 첫 온라인 기기(S22/A90)로 덮어썼고, 그 값이 UserDefaults 에 다시 저장됐다 (2026-11-05 실측)
  - `DeviceInventory.SelectionStep`(`visible`/`wait`/`adopt`)으로 **"아직 안 옴"과 "없어짐"을 구분**한다. 목록에 있으면 유지, 아직 리포트 전이면 기다리고, **60초** 동안 끝내 안 나타나면 그때 첫 온라인 기기를 따른다
  - `ConsoleStore.select()` 는 대기 타이머를 해제한다 — 사용자가 직접 고른 선택은 기다리지 않는다
  - 실측: S7 선택 후 재시작 → `relay.selectedSerial` 유지 · 팝오버 헤더 SM-G930S · 없는 serial(`9.9.9.9:5555`)은 t=60s까지 유지, t=75s에 S22 로 전환
- **fix(macos)**: **S7 배터리 카드에 `만충 …mAh` 가 안 뜨던 문제** — `bb66f49` 이 파서·merge 에만 sysfs 대체 필드를 추가하고 `DeviceSnapshot.applyBattery` 화이트리스트에는 넣지 않아, 매 틱 파싱값이 그 자리에서 버려졌다 (2026-11-05 실측)
  - `batteryFullCapNomMAh` · `batteryKernelHealth` · `batterySysCycle` 3필드를 복사에 추가
  - 기존 가드는 표본에 `rlysysfs_*` 줄이 없어 누락을 못 잡았다 → 표본에 실제 S7 4줄을 넣어 회귀 시 실패하게 했다
  - 실측(S7 실제 덤프): `만충 1374mAh · 92%` · 사이클 `미보고` (`fg_cycle=0` 은 값이 아니다)
- **fix(macos)**: **배터리 요약 그리드가 첫 실행 후 통째로 비던 문제** — 카드 안 `LazyVGrid` 가 첫 레이아웃에서 높이 0 으로 측정된 뒤 다시 재지 않아 6칸(건강·전압·사이클·온도·전류·유형)이 사라졌고, 같은 경로에서 `EXC_BAD_ACCESS`(LazyVGridLayout 값 복사)로 **앱이 죽기도 했다** (2026-11-05 실측 · 크래시 리포트 3건)
  - 6칸짜리라 게으를 이유가 없다 — 일반 `VStack` + `HStack` 행으로 바꿨다. 재실행 후 그리드가 즉시 보이고 크래시 없음
- **fix(macos)**: **LineageOS(S7)에서 scrcpy 미러가 즉시 죽던 문제** — scrcpy 5.0.1 은 오디오를 기본 opus 로 보내는데, `herolte` LineageOS 21 빌드에는 opus 인코더가 없어 서버가 `Could not create default audio encoder for opus` 로 실패하고 **오디오 demuxer 오류가 영상 스트림까지** 끊었다 (2026-11-05 실측)
  - 실행 인자에 `--audio-codec=aac` 를 고정한다 — AAC 는 AOSP 공통 인코더라 어느 기기에서도 열린다. 사용자 `customOpts` 는 뒤에 붙으므로 `--no-audio` 등으로 덮어쓸 수 있다
  - 실측 대조: 기본(opus) 즉시 종료 · `--audio-codec=aac` 8초 유지 · `--no-audio` 12초 유지(720x1280 렌더)
- **fix(macos)**: **Exynos(Mali) 기기에서 GPU 사용률이 비어 있던 문제** — GPU 폴링이 Qualcomm `kgsl` 경로만 읽었다. kgsl 이 없으면 `/sys/class/misc/mali0/device/norm_utilization` 으로 폴백한다(같은 셸에서 `||` — adb 호출 수 그대로)
  - 실측 S7(Mali-T88x): idle `0` → 화면 스와이프 중 `17·24·21`. 클럭은 화면이 켜져 있을 때 `260` MHz 로 표시된다(꺼져 있으면 `0` = 보고 없음)
- **test(macos)**: `ScrcpyMirrorArgsTests` 오디오 고정 · `PollBatchTests` GPU 폴백 · `parseGpuBusyPercent` mali 단일 숫자 픽스처 추가
- **fix(macos)**: **Qualcomm(Adreno) 기기에서 GPU 클럭이 비어 있던 문제** — `kgsl/kgsl-3d0/gpuclk` 는 root 전용(0600)이라 셸에서 `Permission denied` 다. 같은 폴더의 `clock_mhz`(0444, 이미 MHz)로 폴백한다 (2026-11-05 실측)
  - 폴백 사슬: `kgsl/gpuclk` → `kgsl/clock_mhz` → `mali0/clock` (모두 한 셸 · adb 호출 수 그대로)
  - 실측: S22 **285 MHz** · A90 **257 MHz** · S7 **260 MHz**
- **fix(macos)**: **앱 네트워크 창이 "아직 트래픽 없음" 이라고 거짓말하던 문제** — NETWORK 카드는 실시간 `↑48.1 ↓72.3 KB/s` 를 그리는데(인터페이스 합계), 앱별 창은 비어 있었다 (2026-11-05 S7 실측)
  - 원인은 앱이 아니라 **ROM**: LineageOS 21 `herolte` 의 netd 가 BPF map 을 pin 하지 못해(`map is not pinned` + 덤프 NPE) `dumpsys netstats detail` 에 UID별 바이트가 없다. `/proc/net/xt_qtaguid/stats` 도 0바이트라 대체 경로도 없다
  - 이제 `AdbClient.netStatsUnsupported` 가 덤프 원문으로 **"기기가 보고하지 않음"** 과 **"아직 수집 중"** 을 구분한다. 미지원 기기에서는 0바이트 행을 이력에 넣지 않고, 창은 `이 기기는 앱별 트래픽을 보고하지 않습니다` + `지금 인터페이스 합계 ↑… ↓…` 를 표시한다
  - 정상 기기(S22 = uid 283건)는 종전 그대로 앱별 목록이 나온다

---

## 1.25.0 — 2026-11-05 (PR #123)

### Fixed
- **fix(macos)**: **LineageOS/AOSP 기기에서 배터리 건강·사이클이 "—" 로만 남던 문제** — 삼성 One UI 전용 `dumpsys` 필드가 없는 기기를 sysfs 로 대체 (2026-11-03 Galaxy S7 `herolte` 실측)
  - 배경: `mSavedBatteryBsoh`/`mSavedBatteryAsoc`/`mSavedBatteryUsage` 는 삼성 프레임워크 값이라, LineageOS 21 에서는 세 필드가 통째로 비어 건강·사이클 셀이 미측정으로 굳었다
  - 배터리 폴링 1회에 `fg_fullcapnom`·`fg_asoc`·`fg_cycle`·`health` 를 덧붙인다 — 기존 마커 프로토콜 그대로라 **adb 호출 수는 늘지 않고** `cat` 4회만 추가된다
  - 건강 셀 우선순위: `mSavedBatteryBsoh`(삼성) → `fg_fullcapnom`(만충 mAh) → 커널 `health` 라벨 → **미지원**(`—` 대신 무엇이 없는지 말한다)
  - 사이클 셀 우선순위: `mSavedBatteryUsage` 추정 → `fg_cycle` → **미보고** (`0`·`-1` 은 값이 아니라 "드라이버가 안 센다"로 판정)
  - AOSP 숫자 enum `health`(2=Good · 3=Overheat · 4=Dead …)는 sysfs 원문 라벨이 있으면 라벨이 우선한다
  - L10n 5키 추가(en·ko 1:1): `droid.battery.health.fullcap` · `.state.good` · `.state.problem` · `.unsupported` · `droid.battery.cycles.unsupported`
  - 검증: `swift test` **866/0**(+8) · `./scripts/build-macos.sh debug` 완료 — 실기기 확인은 `MANUAL_VERIFY` §33

### Changed
- **fix(macos)**: 만충 용량은 `%d` 대신 문자열(`%@`)로 포맷 — Locale 천단위 구분(`1,401`)이 좁은 셀에서 잘리지 않는다

---

## 1.24.0 — 2026-11-05 (PR #123)

### Added
- **feat(macos)**: **다기기 순차 설치** — 설치 확인 시트에서 온라인 기기를 여러 대 체크하면 위에서부터 차례로 설치 (T-2026-10-24-3 · `PLAN_app_manage_relayconsole` C)
  - 기본 선택은 **시트를 연 기기 하나** — 실수로 여러 대에 설치하지 않는다. `전체 선택`/`선택 해제` 제공
  - 진행 배너에 `n/m대` 와 현재 기기 단계(`3/5대 기기 준비 중…`)를 표시. 취소는 다음 기기로 넘어가기 전에 멈춘다
  - 설치가 끝나면 **기기별 결과표**(성공/실패·버전·실패 사유)를 시트 상단에 남긴다. 사용자가 `결과 지우기` 를 누를 때까지 유지
  - 번들은 기기 ABI·밀도·언어 프로필마다 **한 번만** 풀고 재사용한다(같은 프로필 기기 2대 = 추출 1회)
- **feat(macos)**: **시스템 앱 비활성화·복원** — `시스템 앱` 토글 시 `설치됨`/`복원 가능` 탭
  - 비활성화는 `pm uninstall --user 0 <pkg>` — **시스템 파티션의 APK 는 지우지 않는다**. 2단계 확인(체크박스 2개)을 모두 켜야 실행
  - 복원은 `cmd package install-existing --user 0 <pkg>` — `복원 가능` 탭에 `pm list packages -u -s` − 현재 설치됨 차집합만 보여준다
  - **하드 블록**: 런처(제조사 변형 포함)·SystemUI·Settings·PackageInstaller·권한 컨트롤러·Phone/Telecom·GMS/GSF·Play 스토어는 UI 에서 잠금 아이콘으로 표시하고 실행 자체를 막는다. 컨트롤러도 한 번 더 거른다
  - 복원해도 **앱 데이터는 돌아오지 않는다**는 사실을 확인창·탭 안내에 고정 표시
- **feat(macos)**: **앱 이름 표시** — 행에 `앱 이름`(1줄) + `패키지명`(2줄)을 함께 보여주고, 검색이 **이름도** 매칭한다
  - `pm list packages` 에는 라벨이 없다 → `AndroidManifest.xml` 의 `android:label` 을 `resources.arsc` 에서 해석한다
  - 라벨이 `@string/...` **참조**면 체인을 따라간다(실측 F-Droid: `application@label → @string/app_name → @string/fdroid` 2단계)
  - 아이콘과 **같은 APK pull 1회**에서 이름도 뽑는다. 아이콘 토글 OFF 면 종전대로 패키지명·색 타일만
- **feat(macos)**: **아이콘 렌더러** — PNG 만 있던 1.23.0 은 실사용 앱 대부분이 색 타일로 폴백했다(실측 12개 중 7개가 XML-only). 벡터·적응형을 직접 그린다
  - `<adaptive-icon>` 의 `background`/`foreground` 를 108dp 캔버스 기준 **1.5배 그려 가운데 크롭**(보이는 영역 72dp)
  - `<vector>` — SVG 경로 전체 명령(M/L/H/V/C/S/Q/T/A/Z · 절대/상대 · 암시 L) · fill/stroke · `group` 변환 · `clip-path` · 그라디언트 근사
  - `<bitmap>` · `<layer-list>` · `<selector>` · `<color>` · 단색 레이어(`colorValue`) · 확장자 없는 난독화 엔트리(네이버 웨일 `res/4jn` = WebP)
  - 실패하면 종전과 같이 결정적 색 + 이니셜 타일로 폴백

### Fixed
- **fix(macos)**: **목록 패키지명에 ` versionCode:N` 접미사가 남던 회귀** — 1.23.0 에서 목록 조회에 `--show-versioncode` 를 추가했지만 파서가 접미사를 자르지 않았다. 화면에 `com.foo versionCode:28` 이 그대로 보였고, `pm path`·아이콘 요청·실행·삭제가 모두 잘못된 이름으로 나가 **아이콘이 전부 색 타일로 폴백**했다. `parsePackages` 가 첫 토큰만 취하도록 수정하고 회귀 테스트 2개를 추가
- **fix(macos)**: **ZIP 엔트리 상한이 APK 기준이 아니었다** — 1.23.0 의 256 은 번들(수십 개)에는 맞지만 APK(수천~수만 개)는 `limitExceeded` 로 열리지 않았다(F-Droid 1,119개). **150,000** 으로 올리고, 실질 방어선은 중앙 디렉터리 16MB 상한임을 주석으로 고정
- **fix(macos)**: **ARSC UTF-8 문자열 풀의 이중 길이 누락** — UTF-8 풀은 `문자 수` + `바이트 수` 두 길이를 갖는데 하나만 읽어 모든 문자열이 어긋났다. `parseStringPool` 을 고치고 합성 픽스처도 실제 포맷으로 교정
- **fix(macos)**: **문자열 풀 상한 100,000** — 삼성 시스템 앱 실측 **230,461개**(삼성 메시지). 풀이 통째로 비어 앱 이름·아이콘이 전부 폴백했다. **2,000,000** 으로 올리고 실제 방어선은 파일 크기 검사임을 명시
- **fix(macos)**: **희소(sparse) · offset16 오프셋 표 미지원** — 구글 포토·Gboard 가 쓰는 `FLAG_SPARSE`(0x01)/`FLAG_OFFSET16`(0x02) 표를 몰라 아이콘 경로가 비었다. 두 인코딩을 지원하고 `entryOffset` 으로 분리. **sparse 에서 `entryCount` 는 쌍의 개수**라 엔트리 인덱스 상한으로 쓰면 안 된다는 점도 반영(포토 아이콘 인덱스 4·7 > 쌍 2·3)
- **fix(macos)**: **리소스 값 타입이 문자열·참조뿐이었다** — 벡터의 색·치수·불린을 읽을 수 없었다. `ResourceValue`(text/reference/color/integer/float/dimension)로 확장하고 `TYPE_INT_COLOR_ARGB8/RGB8/ARGB4/RGB4` · `TYPE_FLOAT` · `TYPE_DIMENSION`(`complexToFloat`)을 해석

### Changed
- **perf(macos)**: 설치·백업 중에는 5초 폴링을 **fast 명령만**으로 줄인다(`PollBatch.cmds(reduced:)`). adb 를 오래 붙잡는 설치와 큐에서 경합하지 않게 하되, `adb devices` 하트비트와 배터리·열·loadavg 는 유지한다. 빠진 slow 값은 병합 로직이 이전 값을 유지하므로 화면이 0 으로 깜빡이지 않는다
- **chore(macos)**: 감사 로그 종류 추가 — `app.system.disable` · `app.system.restore`

### Verify
- `swift test` **859/0** (신규 17 — `ResourceValueTests` 2 · `ResourceTableOffsetTests` 3 · `IconCandidateTests` 4 · `SVGPathTests` 6 · `AXMLTreeTests` 2 / 1.24.0 누적 `AppSystemTests` 14 + 패키지 파서 회귀 2) · `./scripts/build-macos.sh debug` 완료 · 앱 **1.24.0** · L10n **916/916 en/ko 1:1**
- 차단 패키지(정확·접두사·일반·대소문자·빈 값) · `--user 0` 인자 · 복원 차집합 정렬 · reduced 폴링(fast-only·기본값 불변)을 테스트로 고정
- 아이콘 렌더 실측(수동): F-Droid · YouTube · KakaoTalk · Samsung Messages · Gboard(sparse) · Google Photos(sparse) · Naver Whale(무확장 WebP) · Shizuku(`<bitmap>`) · Samsung Camera · 자사 DroidRelay — 10종 모두 정상 렌더(21~390ms)
- 실기기 번들·백업·아이콘·이름 확인은 `MANUAL_VERIFY` §30~§32

---

## 1.23.0 — 2026-11-05 (PR #123)

### Added
- **feat(macos)**: **분할·번들 설치** — `.apks` · `.xapk` · `.apkm` 을 앱 허브에서 바로 설치 (T-2026-10-24-2 · `PLAN_app_manage_relayconsole` B)
  - 번들 안에서 **이 기기에 맞는 APK 만** 고른다: base/master + ABI(`getprop ro.product.cpu.abilist`) + 밀도(`wm density`, 같거나 작은 것 중 최대) + 언어(기기 로케일)
  - `universal.apk` 가 있으면 그것 하나 · `standalones/` 는 splits 가 있으면 제외 · 모르는 설정 토큰은 **포함**(빠뜨려 설치 실패하는 것보다 낫다) · 아무것도 못 고르면 전체 폴백
  - `.xapk` 은 `manifest.json` 의 목록·OBB(`expansions[].install_path`)를, `.apkm` 은 `info.json` 목록을 우선하고, 없으면 ZIP 안 APK 를 직접 고른다. 이름 대소문자 차이는 고유 파일명일 때 해석
  - 설치: 로컬 추출 → `/data/local/tmp/relay-install-<id>/` 로 push → `pm install-multiple` → **성공한 뒤에만** OBB 를 `/sdcard/Android/obb/<pkg>/` 로 복사. 원격 임시 폴더는 성공·실패와 무관하게 삭제
  - 진행: `전송 중 2/4` 단계 표시 + 원격 파일 크기(`wc -c`) 폴링으로 선형 진행률 · 취소는 push/install 양쪽에서 동작
  - 실패 구분: 형식 미지원 · APK 없음 · 패키지 정보 없음 · 전송 실패 · OBB 실패를 각각 다른 문구로 알린다(부분 성공을 성공으로 뭉개지 않는다)
- **feat(macos)**: **APK 백업** — 행 메뉴/컨텍스트 메뉴에서 `~/Downloads/RelayConsole/APKs/<pkg>/<version>/` 로 `pm path` 의 모든 APK(split 포함)를 pull
  - `meta.json`(패키지·versionName·versionCode·시리얼·파일별 SHA-256·저장 시각) 동봉, **앱 데이터는 포함되지 않는다**는 사실을 파일에도 적는다
  - 같은 버전 재백업은 덮어쓰지 않고 `-2`, `-3` … · 부분 실패는 `N/M 파일만 백업` · 완료 후 `Finder에서 보기`
- **feat(macos)**: **앱 아이콘** (기본 ON · 토글로 끔)
  - `pm path` → base APK 1회 pull → **직접 구현한 AXML/ARSC 파서**로 아이콘 엔트리 추출 → ImageIO 로 512px PNG(256pt@2x) 캐시
    - `AndroidManifest.xml`(바이너리 XML)에서 패키지·versionName·versionCode·`android:icon`/`roundIcon` 리소스 ID
    - `resources.arsc` 에서 리소스 ID → 밀도별 파일 경로 후보 → 기기 밀도에 가장 가까운 이미지
  - 캐시: `~/Library/Application Support/RelayConsole/icons/<pkg>-<versionCode>-512.png` · **30일 · 50MB** 상한(오래된 것부터 삭제) · 동시 2개 · 보이는 행만
  - 실패·미지원이면 **결정적 색 + 이니셜 타일**로 폴백(빈칸 금지), 사유는 디버그 로그에만

### Changed
- **chore(macos)**: 설치 버튼·시트 제목을 `APK 설치` → **`설치`/`앱 설치`** 로 — 이제 APK 만 받지 않는다. 파일 선택·드롭도 4종 확장자 허용
- **chore(macos)**: 앱 목록 조회가 `--show-versioncode` 를 함께 읽어 versionCode 맵을 유지(구형 `pm` 은 플래그 없이 재시도). 아이콘 캐시 키·백업 메타가 이 값을 쓴다
- **chore(macos)**: 외부 프로세스는 여전히 **adb · scrcpy 뿐** — ZIP 해제·AXML/ARSC 파싱·아이콘 변환을 모두 앱 안에서 처리(`unzip`/`aapt` 호출 없음)

### Fixed
- **fix(macos)**: **AXML 속성 오프셋** — `attributeStart` 는 `attrExt` 구조 기준(노드 헤더 16바이트 뒤)인데 노드 시작 기준으로 계산해 아이콘 리소스 ID 를 놓치고 있었다. 합성 AXML 테스트가 잡았고, 실제 APK 아이콘 추출의 전제가 된다

### Verify
- `swift test` **826/0** (신규 `AppBundleTests`·`AndroidResourceTests`·`AndroidBinaryXMLTests` 38) · `./scripts/build-macos.sh debug` 완료 · 앱 **1.23.0** · L10n **886/886 en/ko 1:1**
- ZIP stored/deflate·경로순회 거부·분할 선택(ABI/밀도/언어/universal/standalones)·XAPK/APKM 추출·OBB 목적지·합성 AXML 파싱을 테스트로 고정
- 실기기 번들·백업·아이콘 확인은 `MANUAL_VERIFY` §30

---

## 1.22.0 — 2026-11-05 (PR #123)

### Added
- **feat(macos)**: **APK 설치** — 앱 허브에서 파일 선택 또는 드롭 → 확인 시트 → `adb install -r` (T-2026-10-24-1 · `PLAN_app_manage_relayconsole` A)
  - 확인 시트: 파일명·경로·크기(`AdbClient.formatBytes`)·**SHA-256 앞 12자**(1MB 스트리밍)·대상 기기 라벨 · 옵션 `-r`(기본 ON)·`-g`·`-d`·`-t`(모두 기본 OFF)
  - 진행: 경과초 타이머 + **취소**(`ProcessRunner.capture` 에 `onStart` 훅 추가 → `terminate()`)
  - 검증: 설치 전/후 `pm list packages -3 --show-versioncode` diff → 1건이면 `dumpsys package` versionName 표시.
    동일 버전 재설치처럼 **확인 불가**면 "버전 확인 불가"로 정직하게 표시한다
  - 실패: `Failure [CODE]` → 코드별 한국어 행동 지침 + 원문 코드 병기(14종 매핑 · 미지 코드는 일반 문구)
  - 감사: `IssueLog` `app.install` (파일명·SHA-256·serial·결과) · `E-MAC-ADB-0007`
- **feat(macos)**: **삭제 2옵션 + 의미 교정** — 종전 `pm uninstall -k` 고정은 "삭제"인데 데이터가 남아 저장공간이 회수되지 않았다
  - 기본: **앱 + 데이터 완전 삭제**(`pm uninstall`) · 보조: **앱만 삭제**(`-k`, 데이터 유지)
  - 확인창에 "되돌릴 수 없음" 고정 문구, 행 `⋯` 메뉴·확인창 양쪽에서 선택 · `E-MAC-ADB-0008`
  - `AppHubController` 의 raw `Process`(stderr 폐기·무한 대기)를 `ProcessRunner`(stderr 보존·60초 데드라인)로 교체

### Fixed
- **fix(macos)**: `AppHubSheet` 새로고침/액션 실패가 **원인 없는 일반 문구**로만 표시되던 문제 — stderr 마지막 줄·실패 코드를 함께 보여준다

### Docs
- `PLAN_app_manage_relayconsole` (A/B/C) · `DECISIONS` D6(읽기 전용 경계 · 삭제 기본값) · `MANUAL_VERIFY` §29 · `PLAN_app_hub` OUT 갱신

### Verify
- `swift test` **788/0** (신규 `AppInstallTests` 20) · `./scripts/build-macos.sh debug` 완료 · 앱 **1.22.0** · L10n **863/863 en/ko 1:1**
- 실기기 4시나리오(정상·재설치·서명 불일치·취소)는 `MANUAL_VERIFY` §29 에서 확인

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
