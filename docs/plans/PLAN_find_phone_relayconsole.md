# PLAN — 폰 찾기 (즉시 조치) · RelayConsole

> 작성 2026-10-18 · 앱 **1.19.0** · bd `RelayConsole-4gl` · TODO T-2026-10-17-5
> 리서치 v2 §4.1 G2 · §5.1 P1-2 — "감시 → 알림 → **조치**의 마지막 한 걸음"

## 1. 왜

경쟁 제품(KDE Connect · Phone Link · Sefirah · CoveLink)이 **전부** 폰 찾기를 제공하는데 우리에게만 없었다.
리서치 v2 는 폰 찾기를 **"광고되는 adb 경로가 여러 개라 구현 경로를 먼저 실측(스파이크)해야 한다"** 로 표시했다(§6 L3).
그래서 구현 전에 adb 표면을 실기기 2대로 전수 확인했다.

## 2. 스파이크 — adb 표면 실측 (2026-10-18)

기기: **SM_S901N** (`192.168.86.49:39775` · Android 16) · **SM_A908N** (`192.168.86.30:5555` · Android 12)

| 후보 | 명령 | 결과 |
|---|---|---|
| 진동 | `cmd vibrator vibrate 1500` | ❌ `Can't find service: vibrator` — `cmd vibrator_manager` 는 `help`/`list` 뿐 |
| 손전등 | `cmd flashlight` | ❌ `Can't find service: flashlight` |
| 통화 걸기(벨 대용) | `am start -a android.intent.action.CALL -d tel:…` | ⚠️ **실제 발신 시도**(다이얼러 열림 + 실패 다이얼로그) → 오발신 위험, **미채택** |
| 오디오 파일 재생 | `cmd package query-activities -a android.intent.action.VIEW -t audio/mpeg -d content://…` | ❌ 핸들러가 Termux·Chrome·검색뿐 — 재생기 없음 (`file://` 는 앱 정책상 차단) |
| 지속 벨소리 | — | ❌ 표준 adb 경로 없음 |
| 타이머 우회(알람 스트림) | `am start -a android.intent.action.SET_TIMER --ez android.intent.extra.ALARM_SKIP_UI true` | ❌ 시계 앱 **권한 다이얼로그** 유발 + 시계 알림이 사용자 설정으로 꺼져 있음(`importance=NONE`) |
| 무음/진동 **모드 전환** | `cmd audio` | ❌ 서브커맨드에 ringer mode 없음(서라운드·사운드도즈만) |
| 볼륨 | `cmd media_session volume --stream N --set i` | ✅ 12·16 동작 — 단 **모드는 안 바뀐다**: 벨소리 볼륨 7↔0 왕복에도 `Ringer mode = SILENT` 유지 |
| **알림 게시(소리)** | `cmd notification post -t T tag text` | ✅ 12·16 동작. 채널 `shell_cmd` = 중요도 **DEFAULT(3)** · `mSound=content://settings/system/notification_sound` · `mVibrationEnabled=false` → **소리 남/진동 없음** |
| **화면 깨우기** | `input keyevent 224` (KEYCODE_WAKEUP) | ✅ |
| **최대 밝기** | `settings put system screen_brightness 255` (+ `screen_brightness_mode 0`) | ✅ (자동 밝기가 덮어쓰므로 **수동 고정 필수**) |
| 스크린샷 | `exec-out screencap -p` | ✅ **이미 구현**(`ScreenshotService`) |
| 앱 강제 종료 | `am force-stop` | ✅ **이미 구현**(`AppHub`) |

## 3. 결정 — 부분 채택

**채택** (실측으로 검증된 표면만):

1. 화면 깨우기 — `input keyevent 224`
2. 최대 밝기 — `settings put system screen_brightness_mode 0` → `screen_brightness 255`
3. 알림음 **3회** — `cmd notification post` 를 같은 tag(`relay-find`)로 재게시
   - 알림은 **한 건만** 남고(같은 tag), 본문이 회차마다 달라(`(1/3)`…) **다시 울린다**
   - 반복 사이 2초 간격 — 소리가 겹치지 않게

**미채택 + 사유**:

| 후보 | 사유 |
|---|---|
| 지속 벨소리(진짜 "벨") | 표준 adb 경로 없음 — 재생기·핸들러 부재 |
| 진동 | `cmd vibrator` 부재 (서비스는 있어도 셸 커맨드 없음) |
| 손전등 | `cmd flashlight` 부재 |
| 무음/진동 모드 전환 | `cmd audio` 에 없음 · 벨소리 볼륨만으로는 모드가 안 바뀜(실측) |
| 통화 인텐트 대용 | 실제 발신 위험 |
| 타이머/알람 우회 | 시계 앱 권한·알림 설정 의존 = 신뢰 불가 |

**한계 명시(제품 정직성)**: 무음 모드·방해 금지 모드면 **소리는 나지 않는다**(adb 로 모드 전환이 불가하므로).
그때도 화면은 켜지고 최대 밝기가 된다 — `.help()` 툴팁과 `MANUAL_VERIFY` §26 에 그대로 적는다.

## 4. 구현

| 위치 | 내용 |
|---|---|
| `Sources/RelayConsole/Droid/FindPhone.swift` | `FindPhoneLogic`(순수 — 인자 조립·클램프·살균) + `FindPhoneController`(adb IO · 기기별 진행 상태) |
| `Views/MenuBarPopoverView.swift` | 헤더 아이콘 `bell.badge` (미러링·파일 탐색기 옆) — 진행 중 `bell.slash` + 잠금 |
| L10n | `findphone.*` 4키 · `menubar.button.findPhone` (en/ko 1:1 · 807 → **812키**) |

안전장치:

- adb 인자는 **셸 없이 `Process.arguments`** 로 전달(맥 셸 인용 문제 없음)
- **`adb shell` 은 인자를 기기 셸에 문자열로 넘겨 다시 파싱한다** — 구현 중 실기기에서 잡은 결함:
  본문 `폰 찾기 (1/3)` 의 괄호가 `sh: syntax error: unexpected '('` 를 냈다(재현·확인).
  → 제목·본문을 **단일 인용으로 감싼다**(`shellQuoted` · 내부 `'` 는 `'\''` 로 이어 붙임). 인용 후 3회 모두 정상 게시됨
- 알림 tag 는 영숫자·`-`·`_` 만(공백·특수문자 제거) · 본문은 제어문자 제거·120자 제한
- 밝기 값 1~255 클램프 · 반복 1~5회 클램프
- **밝기 원복**: 시작 전 `settings get` 으로 원래 모드/값을 읽어 두고, 마지막 알림 2초 뒤 되돌린다
  (읽기 실패·`null` 이면 그 키는 건드리지 않는다) — 폰이 최대 밝기·수동 모드로 남지 않는다
- 같은 기기 **중복 탭 무시**(`busySerials`)

## 5. 검증

- `swift test` — Swift Testing **722/0**(+11 신규 `FindPhoneTests`) · XCTest **168/0**
  (깨우기 코드 · 적용 순서 · 밝기 클램프 · `settings get` 파싱 · **복원 규칙** · 알림 인자 · **셸 인용** · tag/본문 살균 · 반복 클램프 · 단계 판정)
- 실기기 라이브(SM_S901N · Android 16): 앱이 만드는 인자 순서 그대로 실행 →
  `mode 0 · level 255 · mWakefulness=Awake` → 알림 **3회 게시 성공 · 알림 1건만 유지**(본문 `폰 찾기 (3/3)`) → **`mode 0 · level 49` 로 원복**
- 결함 1건을 이 실측에서 잡았다 — 괄호 미인용(§4) · 수정 후 재실행 통과
- 한계 재확인: 무음 모드에서는 화면만 켜진다(소리 없음) — 의도된 동작
