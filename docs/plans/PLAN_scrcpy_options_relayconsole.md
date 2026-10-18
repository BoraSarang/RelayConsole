# PLAN_scrcpy_options_relayconsole — scrcpy 옵션 노출 확대 (5.0.1 실측 기반)

> 착수: 2026-10-18 · 규모 M · 상태: **구현 완료 (2026-10-18 · 앱 1.18.0) · 육안 대기**
> 선행: `docs/TODO.md` T-2026-10-17-6 (리서치 v2 §4.1 G3·G10 · §5.2 P2-1)
> 결정 유지: **미러링 자체 구현 금지** — 외부 scrcpy 위임(A안). 이 PLAN 은 **플래그 노출만** 다룬다.

---

## 1. 왜 5.0.1 실측이 먼저인가

T-6 원문 지시: "착수 시 scrcpy 5.x 실기기에서 옵션별 동작 실측 후 노출 목록 확정".
2026-10-18 에 scrcpy **4.1_1 → 5.0.1** 업그레이드를 실제 수행하고, 하드웨어 디코딩 도입이
설정 목록에 영향을 주는지 A/B 로 측정했다. 그 결과를 근거로 후보를 확정한다.

## 2. 업그레이드·실측 결과 (2026-10-18)

### 2-1. 환경
| 항목 | 값 |
|---|---|
| scrcpy | **5.0.1** (brew, `/opt/homebrew/bin/scrcpy`) |
| 링크 의존 | SDL 3.4.18 · libavcodec 63.1.102 (compiled/linked 일치 — 4.1 의 3.4.14/3.4.18 불일치 해소) |
| 렌더러 | Metal (`INFO: Renderer: metal`) |
| 기기 | `192.168.86.30:5555` (SM_A908N) **무선(TCP)** |
| 앱이 넘기는 옵션 9종 | `--show-touches --stay-awake --legacy-paste --max-size --video-bit-rate --max-fps --screen-off-timeout --turn-screen-off --no-control` → **5.0.1 에서 전부 존재(코드 변경 불필요)** |

### 2-2. CLI 옵션 diff (v4.1 → v5.0.1, `app/src/cli.c` 파싱 테이블)
- long 옵션 **108 → 109**, short 옵션 20 → 20, **제거 0건**
- 추가된 옵션은 **`--hwdec` 하나** — 5.0 의 유일한 신규 설정 표면

### 2-3. 하드웨어 디코딩 A/B (동일 기기·동일 화면 동작·동일 옵션, 차이는 `--hwdec` 뿐)
측정: 3초 워밍업 후 4~5초 간격 3회 `ps -o %cpu,time`, CPU 시간 ÷ 실측 구간 = 프로세스 평균 CPU.

| 조건 | 소프트웨어(`--hwdec=disabled`) | 하드웨어(기본 `auto`) | 감소 |
|---|---|---|---|
| 앱 기본값 1024/2M/30fps (15초) | 0.69s ≈ **4.6%** | 0.45s ≈ **3.0%** | 1.5× |
| 고부하 1920/8M/60fps (18초) | 2.42s ≈ **13.4%** | 0.75s ≈ **4.2%** | **3.2×** |
| 프레임레이트(모션 구간) | 36~52 fps | 35~50 fps | 동등 |

디코딩 경로 로그(근거):
```
soft : INFO: Interop: software      INFO: Video decoding: software
hw   : INFO: Interop: videotoolbox  INFO: Video decoding: videotoolbox
```
- 릴리스 노트의 "CPU 10×"는 **디코딩 단계 한정** 표현이다. 프로세스 전체(디코딩+렌더+UI)로는 위 표처럼 1.5~3.2×.
- **앱 기본값(1024/2M/30fps)에서는 이득이 작다** — 정지 화면 위주면 더 작다. 이득은 설정을 올려 쓸 때(1080p↑·60fps·8M)와 기기 2대 동시 미러링에서 커진다.
- 측정 한계: 화면 동작을 `input swipe`/`HOME` 으로 인위 생성, 15~18초 짧은 구간, 절대 CPU 값이 작음(오차에 민감).

## 3. 노출 후보 (등급별)

### A급 — 바로 넣을 만함
| 옵션 | 이유 | 제안 기본 |
|---|---|---|
| `--hwdec=auto\|disabled\|videotoolbox` | 5.0 유일 신규 옵션. `videotoolbox` 는 **폴백 없이 실패**하므로 기본은 `auto`(옵션 생략). 화면 깨짐/GPU 이슈 때 탈출구 | 옵션 생략(auto) |
| `--keep-active` | 문서 명시: `--stay-awake` 는 **TCP(무선)에서 효과 없음**. 앱은 `stayAwake` 기본 ON 인데 무선 위주라 실효가 없었다 | OFF(선택) |
| `--disable-screensaver` | 관제 목적 장시간 미러링에서 맥 화면보호기/잠자기 방지 | ON 후보 |

> **사용자 결정 (2026-10-18)** — ① 오디오: **현행 유지(설정 미노출)** ② `--keep-active`: **미노출** ③ 범위: **A+B급**.
> 따라서 A급에서 `--hwdec`·`--disable-screensaver`, B급에서 오디오를 뺀 7종(`--video-buffer`·`--window-title`·`--always-on-top`·`--video-codec`·`--background-color`·`--power-off-on-close`)을 구현한다.

### B급 — 실사용 이득
| 옵션 | 이유 | 제안 기본 |
|---|---|---|
| 오디오 정책 `--no-audio` / `--audio-source=playback --audio-dup` (Android 13+) | **현재 앱엔 오디오 설정이 없다.** 기본 `output`(REMOTE_SUBMIX)은 **기기 스피커를 음소거**하고 소리를 맥으로 보낸다 — 폰에서 영상을 켜면 소리가 맥에서만 난다. `--audio-dup` 은 기기에서 계속 재생 | 3택(그대로/끄기/기기에서도 재생) |
| `--video-buffer=ms` | 무선 지터 완화(지연 ↔ 매끄러움 트레이드오프) | 0 유지 + 값 입력 |
| `--window-title=<identLabel>` | 여러 기기 동시 미러링 시 어느 창인지. 기본 제목은 기기 모델명이라 **같은 기종 2대면 구분 불가** → [표시①] 규칙과 직결 | ON |
| `--always-on-top` | 관제탑 성격 — 창이 다른 창에 가려지지 않게 | OFF(선택) |
| `--video-codec=h264\|h265\|vp8\|vp9\|av1` | Wi-Fi 대역폭 부족 시 h265 로 같은 화질 낮은 비트레이트. 4.1 에서 vp8/vp9 추가됨 | h264(옵션 생략) |
| `--background-color=#1c1f2a` | 창 여백 기본이 `#222` → 앱 토큰(v2 카드 bg)과 통일 | ON(고정값) |
| `--power-off-on-close` | `--turn-screen-off` 와 짝 — 종료 후에도 화면 꺼짐 유지 | OFF(선택) |
| `--fullscreen` · `--window-borderless` · `--render-fit` · `--no-window-aspect-ratio-lock` | 창 모드 취향. `--render-fit=stretched` 는 여백 제거 | 미노출 후보 |

### C급 — 진단/고급
- `--verbosity=debug` → stderr 를 `DebugLogger` 로 저장(현재는 오류만 노출) + `--print-fps` → fps 표시: [표시②] "실패 원인 정확 표시" 보강
- `--mouse`/`--keyboard`(uhid/aoa/sdk): 5.0 에서 UHID 키 드롭·AltGr 전달이 수정됨 → 게임·특수키 입력 필요 시
- `--min-size-alignment` · `--ignore-video-encoder-constraints`: 인코더 제약 오보고 기기 대응(4.0/4.1 신규 계열)

### D급 — 이번 범위 밖 (명시적 제외)
- `--record`/`--time-limit`/`--record-format` — **미러링 녹화는 별도 기능**(설정이 아니라 기능). 필요 시 별건 PLAN
- `--new-display`/`--flex-display`/`--start-app` — T-6 원문 후보였으나 **가상 디스플레이 생성 = Android 상태 변경**에 준함 → 스파이크로 판단(이 PLAN 에서 구현 안 함)
- `--video-source=camera` 계열 — 카메라 캡처. 필요성 판단 전 스파이크
- `--tcpip` — 앱이 adb/tcpip 를 직접 관리(`WifiAdb`)
- **`--kill-adb-on-close` 는 절대 노출하지 않는다** — "Kill adb when scrcpy terminates". 앱은 폴링을 위해 adb 서버가 계속 살아 있어야 한다

## 4. IN / OUT
**IN** — 위 A·B급 중 사용자 확정분의 **플래그 노출** · `mirrorArgs` 순수 함수 확장 · 설정 UI 행 · L10n en/ko 동시 추가 · 테스트 · MANUAL_VERIFY 항목
**OUT** — 미러링 자체 구현 · adb 직접 제어 변경 · 기기 설정 쓰기 · 녹화/가상 디스플레이/카메라 기능

## 5. 구현 설계 초안

- `ScrcpyController` 에 `@Published` 추가(기존 패턴 그대로 `didSet` → `UserDefaults` `relay.scrcpy.*`)
  후보 키: `hwdec`(String) · `keepActive`(Bool) · `disableScreensaver`(Bool) · `audioPolicy`(enum→String) · `videoBuffer`(String) · `windowTitleIdent`(Bool) · `alwaysOnTop`(Bool) · `videoCodec`(String)
- `mirrorArgs(...)` 는 **순수 함수 유지** — 인자 추가, 기본값 = **현재 동작과 100% 동일**(옵션 생략) → 기존 테스트·회귀 안전
- 값 검증: `hwdec`/`videoCodec` 은 허용 목록 외 값은 UI 에서 선택(자유 입력 아님). `videoBuffer` 는 숫자만
- `SettingsView.ScrcpySettingsSection` 에 기존 `Toggle`/`scrcpyValueRow` 패턴으로 행 추가 (새 컴포넌트 도입 금지)
- L10n: `settings.scrcpy.*` 신규 키 en·ko **같은 키명 동시 추가**(키 개수 1:1 유지)
- 하위 호환: 새 키 미설정 시 **옵션 미전달** = 5.0.1 기본(auto) → 업그레이드 직후 동작 변화 0

## 6. 검증 (완료 · 2026-10-18)
- [x] `swift test` — **Swift Testing 711/0** (+6 신규: 하위 호환 계약·`--hwdec` 허용 값·코덱 허용 값·버퍼 숫자 제한·신규 플래그·빈 창 제목) · **XCTest 168/0**
- [x] `./scripts/build-macos.sh debug` **EXIT=0** · `/Users/lee/Applications/RelayConsole.app` **1.18.0** 서명 검증 통과
- [x] L10n **807키 en/ko 1:1**(794 → 807 · 신규 13키) · 한자·U+FFFD 0
- [x] 하위 호환: 새 옵션을 모두 끄면 종전 인자와 **정확히 동일**(`legacyParityWhenNewOptionsOff`) · 기본값은 `--background-color=#1c1f2a` 하나만 추가
- [ ] 실기기 육안 → `docs/MANUAL_VERIFY.md` 56~60 (사용자 확인 항목)

## 7. 결정 (2026-10-18 확정 — 사용자)
1. **오디오**: 현행 유지 → 설정 미노출 (기본 동작 = 기기 소리는 맥으로, 기기 스피커 음소거)
2. **`--keep-active`**: 미노출
3. **범위**: A+B급 → 구현 8종
   `--hwdec` · `--video-codec` · `--video-buffer` · `--disable-screensaver` · `--window-title`(=identLabel) · `--always-on-top` · `--background-color(=#1c1f2a)` · `--power-off-on-close`
   + 토글 `창 제목에 기기 식별 표시`(windowTitleIdent) 포함 시 UI 행 9개

### 구현 메모 (실제 코드와 대조)
- 값 검증은 **UI 선택 + 인자 검증 이중**: `hwdecModes`/`videoCodecs` 허용 목록 밖 값은 옵션 생략(자유 입력으로 scrcpy를 깨뜨리지 않는다), `videoBuffer` 는 숫자만
- 창 제목은 `ConsoleStore.shared.identLabel(for:)` **공통 진입점만** 사용([표시①] — 모델명은 같은 기종을 구분하지 못한다)
- 버전 **1.18.0**: `Resources/Info.plist` · `README.md` · `McpProtocol.serverVersion` · `AGENTS.local.md` 4곳 동시 갱신(테스트가 plist ↔ 서버 버전 일치를 강제)

## 8. 남기는 사실
- **`--stay-awake` 는 무선에서 애초에 동작하지 않는다**(Android 정책) — 지금까지 무선 세션에서 "화면 안 꺼짐"을 보장하던 옵션이 아니었다. `--keep-active` 가 그 자리를 채운다.
- **기기 오디오가 기본으로 맥에서 재생되고 기기 스피커는 음소거된다** — 설정에 없는 현재 동작. 5.0 업그레이드와 무관한 기존 사실이지만 T-6 에서 같이 다룰 값이 있다.
- scrcpy 5.0 릴리스 노트의 "adb 37.0.1 번들"은 brew 판에 해당 없음(brew 는 PATH 의 adb 37.0.1 사용) → adb 는 이미 최신, 이 작업과 무관.
