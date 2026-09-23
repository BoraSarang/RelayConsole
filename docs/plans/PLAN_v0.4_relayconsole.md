# PLAN_v0.4_relayconsole.md — P2: GPU·SENSORS·디스크 R/W

> 생성일: 2026-09-23 | 상태: **완료 (육안 ✓ · bd closed)**
> 모체: `PLAN_v0.3_relayconsole.md` §1-2 (P2 이동 항목)
> 앱: **Relay Console** | bundleId: **`com.borasarang.relayconsole`** | 버전: **0.4.0** | 최소 OS: **macOS 26.0**
> bd: **RelayConsole-or6**

---

## 0. 범위 & C2 해제

| IN | OUT (유지) |
|----|------------|
| STORAGE R/W (diskstats delta → STORAGE 카드 확장) | `dumpsys gfxinfo` 상시/파싱 **금지 유지** |
| GPU 카드 (SurfaceFlinger GLES + kgsl sysfs) | Scrcpy, GRDB, 카드 On/Off, 라이트 테마 |
| SENSORS 카드 (sensorservice 목록·활성) | ADB 구독/푸시 (폴링만) |

- **C2 부분 해제**: GPU 카드는 **kgsl + SurfaceFlinger GLES만** 사용. gfxinfo 0건 유지.
- **6카드 → 8카드** (2열 짝수): CPU, GPU, MEMORY, BATTERY, NETWORK, STORAGE, THERMAL, SENSORS
- **팝오버↔대시보드 형식 통일**: 공용 `DroidCards` 8카드 (단일 컬럼 = 팝오버, 2열 = 대시보드)

### 실측 (SM_S901N · 2026-09-23)
- kgsl: `gpu_busy_percentage` `gpuclk` `gpubusy` `gpu_model` **읽기 OK** (denied 아님)
- GLES: `Adreno (TM) 730, OpenGL ES 3.2 V@0615.98…`
- sensorservice: `Total 39 h/w sensors` + Samsung 활성행 `이름(handle=0x…)` + `active-count` + `selected = 20.00 ms`
- diskstats: `sda` read/write sectors OK

---

## 1. 데이터 소스

| 항목 | 명령 | 주기 |
|------|------|------|
| GPU 모델/ES | `dumpsys SurfaceFlinger \| grep GLES` (기기内 grep) | 연결 시 1회 캐시 |
| GPU busy% | `cat /sys/class/kgsl/kgsl-3d0/gpu_busy_percentage` | 15s |
| GPU clk | `cat /sys/class/kgsl/kgsl-3d0/gpuclk` | 15s |
| Sensors | `dumpsys sensorservice \| head -c …` 또는 grep `Total`+active | 15s |
| Disk R/W | `cat /proc/diskstats` → **sda 행만** delta | 15s |

`gfxinfo` 사용 금지 · shell 전부 `-s` · nil → `—`.

---

## 2. 구현 지점

| 파일 | 변경 |
|------|------|
| `DeviceInventory.swift` | 필드: diskRead/WriteMBps, gpu*, sensor* + merge nil 보존 |
| `AdbClient.swift` | `parseGpuGles`, `parseGpuBusy`, `parseGpuClk`, `parseSensorsSummary`, `parseDiskStats` + `diskRatesMBps` |
| `DeviceMonitor.swift` | DeviceState prev/cache + 15s 폴링 + GPU prime |
| `DroidMetrics.swift` | diskRead/Write history (60점) |
| `ConsoleStore.swift` | disk history push (10s 가드) |
| `DroidCards.swift` | **신규** 공용 8카드 — 대시보드·팝오버 공유 |
| `DroidDashboardView.swift` | 그리드 → `DroidCards.*` 8카드 |
| `MenuBarPopoverView.swift` | 카드 → `DroidCards.*` 8카드 단일 컬럼 (구 cardFull/Values 제거) |
| i18n ko/en/xcstrings | `droid.card.gpu.*`, `droid.card.sensors.*`, `droid.card.sensors.none`, `droid.storage.read/write`, `droid.battery.temp` |
| `AdbParsingTests.swift` | 신규 파서 + Samsung 활성행 + disk delta 첫 틱 nil |

---

## 3. DoD v0.4

- [x] `swift test` 전수 통과 — **60/60**
- [x] 금지: `gfxinfo` 코드 0 · iStat 단어경계/Outpost 라벨/`com.relay.console`/material/glass 0 · UI 한글 하드코딩 0 · print(Views) 0
- [x] STORAGE R/W: diskstats sda delta — 첫 틱 nil → 이후 MB/s, UI `—` 폴백
- [x] GPU 카드: GLES renderer + ES 버전 + busy% + MHz + 스파크라인 (kgsl 실측 OK)
- [x] SENSORS 카드: Total/active count + Samsung 활성 이름(주기 ms) + 없을 때 `droid.card.sensors.none`
- [x] 대시보드·팝오버 **동일** `DroidCards` 8카드 (공용 컴포넌트)
- [x] merge nil 보존 (P2 10필드) · shell 기기内 grep 단일 문자열
- [x] 버전 0.4.0 반영 (Info.plist/build-macos/AppDelegate/Settings/Popover/AGENTS.local)
- [x] i18n ko/en/xcstrings **69키 3곳 정합**
- [x] 실기기 육안 1회 — 8카드 형식·센서 이름+주기·GPU/STORAGE 사용자 확인 ✓
