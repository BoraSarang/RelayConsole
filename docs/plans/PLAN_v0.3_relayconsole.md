# PLAN_v0.3_relayconsole.md — 목업 피델리티 + 다중 기기

> 생성일: 2026-09-23 | 상태: **완료 (DoD 전수 통과 · 실기기 육안 확인)**
> 모체: `PLAN_v0.1_relayconsole.md` + `PROMPT-FINAL-V0-2-No-IStat-I18n-V2fix.md`
> 앱: **Relay Console** | bundleId: **`com.borasarang.relayconsole`** | 버전: **0.3.0** | 최소 OS: **macOS 26.0**
> 대상: Android 다중 기기 · 2표면 (팝오버 + Droid 대시보드)
> 언어: 한국어 | **iStats/iStat·Outpost 문구 금지 유지**

---

## 0. 배경 & 변경 이유

v0.1은 목업에서 의도적으로 축소(6카드·단일 기기·단순 헤더)했다. v0.2에서 설정/logcat 실연동을 넣었다.

사용자 확인된 간극:
1. **목업 피델리티 부족** — 코어 미니바·MEMORY 압박/RSS·NET 분리/RSRP·THERMAL 존·메뉴바 5지표 등
2. **다중 기기 미지원** — 저장 계층만 다중, 수집·표시·선택은 1대 고정 (`.first`)
3. **연결 방식 표시 부정확** — `…5555`만 보여 USB/Wi-Fi 구분 불가, 기기 이름(S22) 미표시

### v0.3 확정 방향 (사용자 결정)

| # | 항목 | 결정 |
|---|------|------|
| 1 | GPU·SENSORS | **P2로 이동** (kgsl denied·센서 미실측 리스크) — v0.3 범위 밖 |
| 2 | 메뉴바 5지표 | **설정 ON/OFF** (`relay.menubarMetrics`) + **권장: `Relay n/m`과 병기** |
| 3 | 다중 기기 | 코드는 **N대 가정**, 실기기 1대 — 단위 테스트로 2 serial 검증 + 접힘/펼침 UI 필수 |
| 4 | 기기 클릭 | **클릭 → 콘솔 대시보드** (선택 serial 반영) |
| 5 | 연결 표시 | **USB / IP:5555 구분** + `device_name`(예: S22) 표시 |

---

## 1. 범위

### 1-1. v0.3 IN (P0/P1)

| 영역 | 내용 |
|------|------|
| 다중 기기 | DeviceMonitor 다중 serial 폴링 (`-s`), selectedSerial, 팝오버 기기 목록 접힘/펼침, 행 클릭→콘솔 |
| 연결 표시 | USB vs network(`IP:PORT`) 판별, `device_name` + model, 상세 ADB 행 |
| 팝오버 접힘/펼침 | ① 기기 목록 접힘(다중) ② 단일 기기 상세 접힘(목업) ③ 이벤트 접힘 |
| 카드 Phase1 | CPU 8코어 미니바, MEMORY 압력색+Top RSS, NETWORK up/down 분리+RSRP/Wi-Fi, THERMAL Status 배지+존 미니바 |
| BATTERY | 6타일 그리드 (H·T·V·Cycle·Current·Type) — nil → `—` |
| 메뉴바 | 5지표 토글 설정 + n/m 병기 |
| 이벤트 | 타임라인 도트 UI, 접힘 기본(점3) — 기존 유지하며 UI 강화 |
| i18n | 신규 키 전부 ko/en |

### 1-2. P2 (v0.3 범위 밖 — 다음 또는 수요)

- GPU 카드 (SurfaceFlinger GLES / kgsl / gfxinfo)
- SENSORS LIVE (sensorservice 스트림)
- STORAGE R/W 히스토그램 (diskstats delta)
- GRDB 타임라인, 카드 On/Off UI, Apple/Sites/Jobs/Notify, scrcpy, 라이트 테마

### 1-3. 범위 밖 유지 (C 계열 존치)

- bundleId `com.borasarang.relayconsole`, `relay.*` 키만
- Scrcpy 버튼 없음
- iStat/Outpost 라벨 0, material/glass 0, print 0, `.borderedProminent` 기본 0
- `dumpsys meminfo` 상시 금지 · 대형 dumpsys는 기기内 grep
- 2표면 다크 고정 · SOLID `#0f111a` + 카드 `#1c1f2a` r16

---

## 2. 다중 기기 아키텍처

```
AdbClient (순수 static 파서)
  └ DeviceMonitor (actor)
       adb devices → serials: [String]          ← 전체 (`.first` 제거)
       for serial in serials:
         run(adb, ["-s", serial, "shell", …])   ← 모든 셸 -s 강제
         per-serial state: prevStat/prevNet/caches/watch
         → handler(DeviceSnapshot(serial:))
  └ DeviceInventory (@MainActor)                ← serial upsert (기존 유지)
       └ ConsoleStore
            ├ @Published selectedSerial: String? // 신규
            ├ metricsHistory[serial]            // 기존
            └ select(serial) / openConsole(serial)
                 ├ MenuBarPopoverView
                 └ DroidDashboardView  ← selectedSerial 기준
```

### 2-1. ConsoleStore 신규

| 멤버 | 용도 |
|------|------|
| `@Published selectedSerial: String?` | 현재 선택 기기 |
| `func select(_ serial: String)` | 선택 변경 + `relay.selectedSerial` 저장 |
| `func device(for serial: String) -> DeviceSnapshot?` | 조회 |
| `var selectedDevice: DeviceSnapshot?` | selectedSerial → snapshot, nil이면 `.first` 폴백 |
| `func openConsole(serial: String)` | select + `openWindow(id:"console")` 콜백 경유 |

UserDefaults: `relay.selectedSerial` (없으면 첫 온라인 기기).

### 2-2. DeviceMonitor 변경

| 항목 | before | after |
|------|--------|-------|
| serial 추적 | 단일 `serial: String?`, `devices`에서 `.first` | `serials: [String]`, 전체 채택 |
| shell | `["shell"] + args` (**-s 없음**) | **항상 `["-s", serial, "shell"] + args`** |
| prevState/prevNet/caches | 인스턴스 1벌 | `[serial: State]` 맵 |
| SettingWatch/LogcatWatch | 단일 baseline | serial별 baseline/cursor |
| 연결/끊김 이벤트 | 1대 기준 | serial별 push, model·연결종류 포함 |

### 2-3. DeviceSnapshot 연결 필드 (신규)

| 필드 | 타입 | 소스 |
|------|------|------|
| `connectionKind` | `enum ConnectionKind { usb, network }` | serial에 `:` 유무 |
| `connectionLabel` | `String` | USB → `USB`, network → `IP:PORT` 전체 |
| `deviceName` | `String?` | `settings get global device_name` (연결 시 1회 + 15s 갱신) |
| `model` | 기존 | `getprop ro.product.model` |

**파서:**
- `AdbClient.parseConnection(serial:) -> (kind, label)` — `:` 포함 → `.network`, 아니면 `.usb`
- `AdbClient.parseDeviceName(_ raw: String) -> String?` — `settings get` 0/null 제외

**표시 규칙:**

```
헤더:  [S22] · SM-S901N · Wi-Fi 10.233.247.205:5555 · ● 연결됨
또는:  [Galaxy] · SM-S901N · USB …ABCD · ● 연결됨

상세 ADB 행: network → IP:PORT 전체 (마스킹 없음)
             usb     → shortId (…ABCD)
```

이벤트: `기기 연결 S22 · 10.233.247.205:5555` / `기기 연결 …ABCD (USB)`

---

## 3. 팝오버 UX — 접힘/펼침 (다중 기기)

```
[헤더 고정]
● RELAY  1/2                    [batt %] 0.3.0
S22 · SM-S901N  Wi-Fi 10.233…:5555  ● 연결됨   ⌄ ← 기기 영역 토글

[기기 ⌄ 접힘 상태 — 분기]
(1대) → 기존 목업: 상세 3줄 (모델 / Android / ADB)
(2대↑) → 기기 목록 행:
   ┌ ✓ S22    SM-S901N   Wi-Fi … 87% 42°C   ← 클릭 → 콘솔
   │   S22B   SM-A536N   USB …   91% 38°C
   └ offline 행 그레이 + 연결 해제 표시

[스크롤 중간]
  발열 배너 (있을 때)
  카드 6 (Phase1 피델리티)
  기기 상세 (접힘 시)
  최신 이벤트 ⌄ 접힘 기본(점3) — 타임라인 도트

[푸터]
  [◧ 콘솔 열기]  [디버그]  [⚙]
```

**상태:**
| 상태 | 의미 | 1대 | 2대↑ |
|------|------|-----|------|
| `showDeviceList` | 헤더 ⌄ | 상세 3줄 토글 (목업 동일) | 기기 목록 토글 |
| `showEvents` | 이벤트 접힘 | 기본 **false**(점3) | 동일 |

**기기 행 클릭** → `store.select(serial)` + `openConsole()` → 콘솔이 해당 기기 대시보드.

---

## 4. 대시보드 UX

- 헤더: 선택 기기 기준 — `deviceName · model · connectionLabel · batt · temp · …serial`
- 기기 전환: 헤더 옆 피커 또는 기기 이름 롱리스트 (1대면 생략 가능, 2대↑ 노출)
- 카드 그리드 2열 gap16 — **6카드 유지 (GPU/SENSORS 제외)**
- Footer: 설정 변경 / logcat 카운트 (v0.2 유지)

---

## 5. 카드 스펙 Phase1 (PLAN_v0.1 약속 이행)

### 5-1. CPU
- 8코어 미니바: 세로 또는 가로 바 ×8 — `scaling_cur_freq / cpuinfo_max_freq`
- use% 마커 또는 행별 use% (`/proc/stat` 코어 라인 delta)
- 전체 use% + 온도 + load 1/5/15 + spark
- `governor` 텍스트 (실패 시 `—`)

**수집 (2~5s):**
```
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq
cat /sys/devices/system/cpu/cpu*/cpufreq/cpuinfo_max_freq
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor   # 연결 시 캐시
cat /proc/stat   # cpu0..cpuN 라인까지
```

**파서:** `parseCpuCores`, `parseProcStatCores` (PLAN §3-2 이행)

### 5-2. MEMORY
- used/total bar (기존)
- **압력색**: PSI `cat /proc/pressure/memory` (없으면 swap 사용률 규칙 fallback)
- **Top RSS 2~3행**: `ps -A -o RSS,NAME --sort=-rss | head -5`
- swap/ZRAM 캡션 (meminfo Swap 계열)

**수집 (15s):**
```
cat /proc/pressure/memory          # optional
ps -A -o RSS,NAME --sort=-rss | head -5
```

**파서:** `parsePressure`, `parseTopRss`

### 5-3. NETWORK
- **up/down 분리 타일** (↑ sky / ↓ violet) — `netUpMBps` / `netDownMBps` 분리 표시 (합산 문자열 폐기)
- 이중 area spark (또는 2선 spark)
- **LTE**: `dumpsys telephony.registry | grep mSignalStrength` (기기内 grep) → RSRP
- **Wi-Fi**: `cmd wifi status` → SSID/RSSI — off 시 `Wi-Fi off 안내`
- IP pill (network 연결 시)

**수집 (5~10s):** 기기内 grep 필수

**파서:** `parseSignal`, `parseWifiStatus`

### 5-4. THERMAL
- Status 배지 0~6 (색: 0~1 ok, 2 warn, ≥3 bad)
- **전체 Temperature 목록** → 존 행 (이름 + 미니바 + °C) — 기기依存 존명 유연 파싱
- 오렌지 강조 + 기존 배너 유지

**파서:** `parseThermalZones` (기존 parseThermal 확장 또는 신규)

### 5-5. BATTERY — 6타일 그리드

```
HEALTH   TEMP      VOLTAGE
CYCLES   CURRENT   TYPE
```

| 타일 | 소스 | nil |
|------|------|-----|
| HEALTH | mSavedBatteryBsoh | `—` |
| TEMP | temperature÷10 | `—` |
| VOLTAGE | voltage mV | `—` |
| CYCLES | mSavedBatteryUsage 추정 | `—` |
| CURRENT | current_now μA (sysfs denied 가능) | `—` |
| TYPE | technology + capacity | `—` |

큰 % + level spark + 충전 상태는 상단 유지.

### 5-6. STORAGE
- used/total bar + **잔량** (total−used)
- (R/W 히스토그램 = P2)

---

## 6. 메뉴바 5지표

| 항목 | 내용 |
|------|------|
| 설정 키 | `relay.menubarMetrics` (Bool, 기본 **true**) |
| UI | SettingsView 토글: `메뉴바 지표 표시` |
| 포맷 (ON) | `Relay 1/2 · CPU 24% · MEM 60% · BAT 87% · 42° · NET` |
| 포맷 (OFF) | `Relay 1/2` (기존) |
| 데이터 | 선택 기기(또는 첫 온라인) 스냅샷에서 즉시 |
| 제약 | 라벨 lineLimit 1, 과도 길이 시 지표축약 (`CPU 24%`만 등) — 메뉴바 폭 안전 |

지표 소스: cpuUsePercent, memoryUsed/total %, batteryLevel, deviceTemp/batteryTemp, netUp+Down.

---

## 7. 파서·테스트

### 7-1. 신규/확장 파서

| 함수 | 입력 | 출력 |
|------|------|------|
| `parseConnection` | serial | kind + label |
| `parseDeviceName` | settings get | String? |
| `parseCpuCores` | cpufreq sysfs 묶음 | [(cur,max)] |
| `parseProcStatCores` | /proc/stat | 코어별 use% delta |
| `parsePressure` | /proc/pressure/memory | some/total → 라벨 |
| `parseTopRss` | ps 출력 | [(name, rssMB)] |
| `parseThermalZones` | dumpsys thermalservice | [(name, temp)] + Status |
| `parseSignal` | telephony grep | rsrp, operator, rat |
| `parseWifiStatus` | cmd wifi status | ssid, rssi, enabled |

### 7-2. 필수 테스트 (AdbParsingTests)

- [x] `parseConnection` — IP:5555 → network, 하드웨어 serial → usb
- [x] `parseDeviceName` — S22 / null
- [x] `parseCpuCores` / `parseProcStatCores` 샘플
- [x] `parsePressure` / `parseTopRss` 샘플
- [x] `parseThermalZones` — 다중 Temperature 라인
- [x] `parseSignal` / `parseWifiStatus` 샘플
- [x] **inventoryMerge 2 serial** — 서로 다른 serial 동시 병합, nil 보존
- [x] selectedSerial persist 로직 (가능한 부분)

---

## 8. 다중 기기 검증 시나리오 (실기기 1대)

| 단계 | 방법 |
|------|------|
| 단위 | 테스트에서 serial A+B 스냅샷 주입 → devices.count==2 |
| UI 목록 | Debug 또는 임시 `relay.debugSecondDevice`로 가짜 DeviceSnapshot 1개 append → 팝오버 목록·n/m 검증 후 제거 |
| 실연 | `adb connect 10.233.247.205:5555` 1대만 — n/m = `1/1`, 목록 1행 |
| 접힘/펼침 | 1대=상세 접힘, (가짜 2대)=목록 접힘 육안 |

> **가짜 2번째 기기**: 개발 중 `ConsoleStore`에 `#if DEBUG` inject 또는 테스트 전용 — 출시 빌드 제외. "1대 연결을 복사"하는 것이 아니라 **스냅샷 1개를 다른 serial로 병합**해 UI 경로를 검증.

---

## 9. i18n 신규 키 (ko/en)

```
settings.menubarMetrics          메뉴바 지표 표시 / Show menubar metrics
menubar.device.list              기기 목록 / Devices
menubar.device.usb               USB / USB
menubar.device.network           Wi-Fi / Wi-Fi
menubar.metrics.cpu              CPU %d%% / …          (또는 포맷 키)
menubar.metrics.mem              MEM %d%% / …
menubar.metrics.bat              BAT %d%% / …
droid.header.picker              기기 선택 / Select device
droid.card.memory.pressure       압박 %@ / Pressure %@
droid.card.network.up            업로드 / Upload
droid.card.network.down          다운로드 / Download
droid.card.network.wifiOff       Wi-Fi 꺼짐 / Wi-Fi Off
droid.battery.health             건강 / Health
droid.battery.voltage            전압 / Voltage
droid.battery.cycles             사이클 / Cycles
droid.battery.current            전류 / Current
droid.battery.type               유형 / Type
event.deviceConnected            기기 연결 %@ / Device connected %@
event.deviceDisconnected         기기 연결 끊김 %@ / Device disconnected %@
```

기존 한글 하드코딩 이벤트 5건 → 키화 (DoD 11 이행 보강).

---

## 10. 구현 Step

| Step | 내용 | 검증 |
|------|------|------|
| 0 | 본 PLAN 확정 | 사용자 승인 ✓ |
| 1 | 연결 필드 + 파서 + device_name | unit + 헤더 육안 ✓ |
| 2 | DeviceMonitor 다중 serial + `-s` shell + per-serial state | unit 2 serial ✓ |
| 3 | selectedSerial + openConsole(serial) + persist | unit + 수동 ✓ |
| 4 | 팝오버 기기 목록 접힘/펼침 + 행 클릭→콘솔 | 육안 ✓ |
| 5 | 파서 Phase1 (cores/pressure/rss/zones/signal/wifi) + 모델 확장 | AdbParsingTests +N ✓ |
| 6 | 카드 UI Phase1 (CPU/MEM/NET/THERMAL/BATTERY 그리드) | 육안 ✓ |
| 7 | 메뉴바 5지표 설정 토글 + 병기 | 육안 ✓ |
| 8 | i18n 키화 + 이벤트 하드코딩 제거 | grep UI 한글 하드코딩 0 ✓ |
| 9 | swift test + `./build_and_run.sh debug macos` + DoD 전수 | 50/50 · 빌드 0.3.0 ✓ |
| 10 | 문서 갱신 (TODO·session·본 PLAN DoD) | 완료 ✓ |

---

## 11. DoD v0.3

- [x] `adb devices` 결과 전체 serial 폴링 · shell 인자 `-s` 포함 (grep — `shell()` 배열 `["-s", serial, "shell"]`)
- [x] `DeviceInventory` 서로 다른 serial 2대 병합 테스트 통과
- [x] `selectedSerial` 선택·persist `relay.selectedSerial` (코드 검증)
- [x] 팝오버: 기기 ⌄ 접힘/펼침 — 1대=상세, 2대+=목록 *(육안 ✓ — Galaxy A53 USB + S22)*
- [x] 기기 행 클릭 → 콘솔 오픈 + 해당 기기 대시보드 *(육안 ✓)*
- [x] 연결 표시: USB vs `IP:PORT` 구분 · `device_name` 표시 *(육안 ✓ — S22 / 10.233.247.205:5555)*
- [x] CPU 8코어 미니바 실데이터 (전부 `—` 금지 — nil만 `—`) *(육안 ✓ — C0–C7 + walt)*
- [x] MEMORY 압력색 + Top RSS ≥1 (또는 nil `—`) *(육안 ✓ — 압박 none)*
- [x] NETWORK up/down 분리 + RSRP 또는 Wi-Fi(off 안내) *(육안 ✓ — KT · RSRP −100)*
- [x] THERMAL Status 배지 + 존 행 ≥1 *(육안 ✓ — Status 3 + 존 미니바)*
- [x] BATTERY 6타일 그리드 *(육안 ✓)*
- [x] 메뉴바 5지표 설정 ON/OFF 동작 · OFF 시 `Relay n/m`만 *(육안 ✓)*
- [x] GPU·SENSORS 코드 0건 (P2 미포함) · 기존 금지어 전부 0 *(iStat 단어경계 grep 0)*
- [x] i18n 신규 키 ko/en · UI 한글 하드코딩 0 (이벤트 포함) — ko/en/xcstrings 59키 정합
- [x] P0-a: UI는 `DeviceInventory.devices` + selectedSerial만 (Views `devices.first` 0 — Store 폴백만)
- [x] swift test 전수 통과 · 실기기 육안 1회 *(50/50 · 사용자 육안 확인 완료)*
- [x] `NSApp.appearance = darkAqua` · material/glass 0 (v0.1 C7 유지)

---

## 12. 리스크

| 리스크 | 대응 |
|--------|------|
| `-s` 없는 shell 잔존 | 전수 grep 리뷰 + 테스트 |
| PSI 없는 커널 | swap 규칙 fallback + `—` |
| power_supply denied | CURRENT nil → `—` |
| telephony/wifi 출력 기기依存 | 기기内 grep + optional |
| 메뉴바 라벨過長 | lineLimit + 축약 폴백 |
| 가짜 2번째 기기 디버그 코드 출시 유입 | `#if DEBUG` 전용 |
| 다중 폴링 부하 | 기기당 5s/15s 유지, serial 수 ×는 기대 (≤3) |

---

## 13. 산출 파일 (예정)

```
docs/plans/PLAN_v0.3_relayconsole.md          ← 본 문서
Sources/RelayConsole/Droid/AdbClient.swift     ← 파서 확장
Sources/RelayConsole/Droid/DeviceMonitor.swift ← 다중 serial
Sources/RelayConsole/Droid/DeviceInventory.swift ← connection/deviceName
Sources/RelayConsole/App/ConsoleStore.swift    ← selectedSerial
Sources/RelayConsole/App/RelayConsoleApp.swift ← 메뉴바 5지표
Sources/RelayConsole/Views/MenuBarPopoverView.swift ← 목록/클릭/접힘
Sources/RelayConsole/Views/DroidDashboardView.swift ← 카드 Phase1
Sources/RelayConsole/Views/SettingsView.swift   ← 메뉴바 지표 토글
Sources/RelayConsole/DesignSystem/Components.swift ← 코어바/타일/배지 등
Resources/Localizable.xcstrings + *.lproj       ← 신규 키
Tests/RelayConsoleTests/AdbParsingTests.swift   ← 신규 테스트
```

---

## 14. 승인

- [x] 본 PLAN_v0.3 초안 승인 (Step 0 — 사용자 "진행하자")
- [x] 구현 진입 (Build 모드)
