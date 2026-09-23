# PLAN_v0.1_relayconsole.md — Android 안드로이드 v2 (팝오버 + Droid 대시보드)

> 생성일: 2026-09-23 | 갱신: 2026-09-23 (PROMPT-FINAL-V0-2 흡수) | 상태: **확정 — 문서·브랜드 이관 완료, 코드는 신규**
> 앱: **Relay Console** (릴레이 콘솔) | bundleId: **`com.borasarang.relayconsole`** | 최소 OS: **macOS 26.0** | 버전: **0.1.0**
> 빌드: Xcode 16+ / Swift 6 / macOS 26.0 Tahoe Liquid Glass
> 원본 프로젝트: Outpost (macOS SwiftUI MenuBarExtra) — 본 RelayConsole로 이관
> 참고 조사: `docs/research/RESEARCH_droid_devicecare.md`, `SKILLPACK_mimo_v2_6.md`, HTML 목업 2종, `BrandKit/`
> 보강 원본: `docs/plans/PROMPT-FINAL-V0-2-No-IStat-I18n-V2fix.md` (Critical·i18n·Red/Rainbow 핫픽스 우선 — 구 V0-1 교체)
> 언어: 한국어 | 대상 표시: **Android만, 2표면** | **iStats/iStat 문구 금지**

---

## 0. 배경 & 스코프

| 항목 | 내용 |
|------|------|
| 컨셉 | 맥에서 폰을 만지지 않고 관제하는 Mission Control (외부 기기 통합 모니터) |
| 브랜드 | Relay Console — 맥은 콘솔, 신호는 외부에서 릴레이 (BrandKit README) |
| 표시 A | **메뉴바 팝오버** — Compact 모니터 (텍스트 로그 리스트 전면 교체) |
| 표시 B | **콘솔 Droid 탭** — Full 2열 대시보드 |
| 기기 | SM_S901N (Galaxy S22, Android 16/SDK36) 실측 기준 |
| 범위 밖 | Apple/Sites/Jobs/Notify, 카드 On/Off UI, 메뉴바 5지표 라벨, GPU util·gfxinfo, 센서 LIVE, GRDB 타임라인, scrcpy 실행 버튼, 라이트 테마(이 2표면은 다크 고정) |

**출처 문서 (읽기 순서):**
1. `docs/plans/PLAN_v0.1_relayconsole.md` — 본 문서 (FINAL)
2. `docs/research/RESEARCH_droid_devicecare.md` — ADB 실측 샘플
3. `docs/research/SKILLPACK_mimo_v2_6.md` — §5 Popover / §6 Dashboard
4. `BrandKit/` — AppIcons + `MenuBar_Black_Template_22.png` (reference)
5. `docs/research/Istat-Menus-Android-Dashboard.html` — 8카드 → **6카드 축소**
6. `docs/research/Outpost-Menubar-V2-Istat.html` — 360px 팝오버 목업

---

## 1. Critical Fixes (보강 — 목업·BrandKit 예시에 덮어쓰기)

| # | 항목 | 확정 |
|---|------|------|
| C1 | bundleId | **`com.borasarang.relayconsole`** 고정. `com.relay.console` 기각. Package.swift·Info.plist·UserDefaults 전부 이 값 + **`relay.*` 키만**. `outpost.*` 금지 |
| C2 | GPU 카드 | **제외**. Adreno util 미보장. 6카드 = **[CPU, MEMORY, BATTERY, NETWORK, THERMAL, STORAGE]**. `dumpsys gfxinfo` 파싱 시도 금지 |
| C3 | Scrcpy 버튼 | **없음**. 팝오버·Droid 헤더에 `[Scrcpy로 열기]` 금지. 배너 클릭은 `openWindow(id:"console")`만 |
| C4 | Thread model | AdbClient=순수 static 파서 / DeviceMonitor=**actor** 백그라운드 / DeviceInventory=**@MainActor** 유일 read 모델 / DroidMetrics=링 60점(5s×60=5분) |
| C5 | Dark 강제 | 2표면 `.preferredColorScheme(.dark)`. 라이트 없음. card #1c1f2a r16, popBG #0f111a, thermal #ff8c32/#ffb86a, cta #2f6bff, border white 8%, 숫자 SF Mono |
| C6 | 금지 | print 버튼 · `.borderedProminent` 기본 · 웹 느낌 링크 · 밝은 테마 · `dumpsys meminfo` 상시(3.3s) · Outpost 라벨(grep 0건) · `outpost.*` 키 · **iStats/iStat Menus 문구 0건** |
| C7 | Red/Rainbow 핫픽스 | material/glass/`.bar`/backgroundStyle 전면 금지(grep 0). **SOLID** `#0f111a` 루트 ZStack + 카드 `#1c1f2a` fill( opacity X ) + white 8% stroke. `NSApp.appearance = darkAqua`. 콘솔도 ZStack 솔리드 (V0-2 image_795cd0) |
| C8 | i18n | ko+en · `Localizable.xcstrings` · UI Text 키화 · 한글 하드코딩 금지 · 360px 영어 깨짐 방지 lineLimit |

### 1-S. Skill Pack 분석 보정

| 섹션 | 채택 | 보정 |
|------|------|------|
| §2 IA 2표면 | ✅ | — |
| §3 Tokens #0f111a/#1c1f2a/r16 | ✅ | 라이트 폴백 토큰은 코드에만, **표시는 다크 강제** |
| §4 데이터 소스 | ✅ | `dumpsys notification` 제외, `/proc/meminfo` 우선 |
| §5 MenuBar v2 | ✅ | 목업 HTML과 대조 확정 |
| §6 Droid v2 6카드 | ✅ | GPU 제외 → Thermal+Storage 분리 6카드 |
| §7 scrcpy 열기 | ❌ | **버튼 없음** (C3) |
| §8 산출 3파일 | ✅ | §8 산출 파일로 확장 |
| §9 체크리스트 | ✅ | §10 DoD에 흡수 |

---

## 2. 선결 (Outpost 버그 교훈 — 새 코드에서 방지)

Outpost의 배터리 `-` 원인: `DeviceMonitor.snapshots`가 `inventory.devices`와 미병합.

| # | 항목 | 규칙 |
|---|------|------|
| P0-a | 단일 read 모델 | UI는 **오직 `DeviceInventory.devices`** 만 읽음. monitor는 inventory에 병합 콜백 |
| P0-b | 충전 nil | `isCharging == nil` → `"—"` (true/false 아님) |
| P0-c | poll 실패 | silent catch 금지 — DebugLogger + lastError |
| P1 | 콘솔 열기 | `openWindow` + `NSApp.activate` (Outpost-4ag 패턴 재검증) |
| P1-b | 설정 키 | UserDefaults/설정 접두어 **`relay.*`** (구 `outpost.*` 미사용 — 코드 신규) |

---

## 3. 아키텍처 & Thread Model

```
AdbClient (순수 파서 — static func, 단위 테스트 대상)
  └ DeviceMonitor (actor, 백그라운드 queue)
       5s tick: battery + thermalservice + loadavg
       10~15s tick: /proc/meminfo, /proc/net/dev, df
       2회 샘델타: cpufreq, /proc/stat use%, net bps (첫 틱은 스냅샷만)
       └ DeviceInventory (@MainActor, @ObservableObject)  ← UI 유일 read 모델
            └ ConsoleStore
                 ├ MenuBarPopoverView (compact)
                 └ DroidView → DroidDashboardView (full)

DroidMetrics — 링버버 60점 = 5분치 (5s × 60)
  cpuHistory[] / tempHistory[] / levelHistory[] / netHistory[]
```

- UI는 오직 `inventory.devices`만 읽음 (P0-a)
- 메인 스레드 차단 금지 · ADB 폴링은 백그라운드
- **금지:** `dumpsys meminfo` 상시 (3.3s), 대형 dumpsys 미가공 수신 — 기기内 grep

### 3-2. 신규 파서 (AdbClient 순수 함수 + Tests)

| 함수 | 소스 | 용도 |
|------|------|------|
| `parseThermal` | dumpsys thermalservice | Status 0~6 + AP/SKIN/BAT |
| `parseLoadAvg` | /proc/loadavg | 1/5/15 |
| `parseMemInfo` | /proc/meminfo | Total/Available/Swap |
| `parseCpuCores` | cpufreq sysfs | 8코어 cur/max |
| `parseProcStat` | /proc/stat delta | 코어 use% |
| `parseDf` | df /data | 스토리지 % |
| `parseNetDev` | /proc/net/dev delta | up/down MB/s |
| `parseBatteryEx` | dumpsys battery 확장 | voltage, Bsoh, 보호모드 |

- 필드 optional + `"—"` 폴백
- silent catch 금지 — DebugLogger + lastError
- 실측 샘플: RESEARCH §2-4
- 테스트: `Tests/RelayConsoleTests/AdbParsingTests.swift`
- **gfxinfo 파싱 금지** (C2)

---

## 4. 디자인 토큰

| 토큰 | 값 | 비고 |
|------|-----|------|
| card | **#1c1f2a** | `OPColor.card(scheme)` — 라이트 폴백은 panelLight (표시 안 함) |
| popBG | #0f111a | 팝오버 전용 |
| radiusCard | **16** | Droid/팝오버 카드 전용 (기타 12 유지 가능) |
| thermal | #ff8c32 / #ffb86a | 오렌지 발열 |
| cta | #2f6bff | 콘솔 열기 |
| border | white 8% | 1px stroke |
| 숫자 | SF Mono | `OPFont.number` |
| 강제 | `.preferredColorScheme(.dark)` | 2표면 전용 |

버튼: `OPPrimaryButton` (cta) / `OPSecondaryButton` (card bg) — `.borderedProminent`·텍스트링크 금지.

---

## 5. 표면 A — MenuBarPopover (360 × ≤560)

```
● RELAY  ver                     [mini batt %]
SM_S901N …5555  ● 연결됨           ⌄ expand → 모델/Android/ADB
────────────────────────────────
⚠ 발열 주의 42.3°C [스로틀링]  ╌ temp sparkline   ← ≥40°C 또는 Status≥2
────────────────────────────────
┌ CPU 8코어 mini bar · 34% · 42°C ┐
│ MEMORY 7.2/12 │ STORAGE 81/128  │
│ BATTERY 큰숫자·H/V/Cycle·spark  │
│ NETWORK up/down · LTE/Wi-Fi     │
├ 최신 이벤트 (5) ⌄ 접힘 · 점3    │
────────────────────────────────
[ ◧ 콘솔 열기 ]  [ 디버그(DEBUG) ]  [⚙]
```

- 헤더 라벨: **RELAY** (Outpost 아님 · BrandKit 약칭)
- 이벤트: `recentEvents.prefix(5)` 접힘 기본 (점3 표시)
- 배너/콘솔 → `openWindow(id:"console")` — **Scrcpy 버튼 없음** (C3)
- `…5555` = shortId 마스킹 유지 (시리얼 전체 금지)

---

## 6. 표면 B — DroidDashboard

```
헤더: ● SM_S901N · 87% · 42.3°C · device · …5555
윈도우 제목: Relay Console · 외부 관제 콘솔

그리드 2열 gap16 · card #1c1f2a r16:
 1 CPU      8코어 미니바 + use% + 온도 + load spark
 2 MEMORY   used/total bar + 압력색 (+ Top RSS 2~3)
 3 BATTERY  큰% + 온도 + level spark + V·H·충전 (nil → "—")
 4 NETWORK  up/down spark + LTE RSRP / Wi-Fi (off 안내)
 5 THERMAL  Status 배지(0~6) + 존 미니바 + 오렌지 강조
 6 STORAGE  used/total bar + 잔량
  (GPU·SENSORS 카드 없음 — gfxinfo 금지)

헤더 버튼: [Scrcpy로 열기] 없음 (C3)

푸터 (기존 감시 유지, compact):
 · 설정 변경 탐지 (n) — 행/소형 패널
 · logcat 적중 (n)   — 단일 모노 패널 (건별 카드 폐지)
```

- 게이트/온보딩·알림 연동은 기존 정책 유지
- **6카드 고정:** CPU, MEMORY, BATTERY, NETWORK, THERMAL, STORAGE (C2)

---

## 7. 구현 Step

| Step | 내용 | 검증 |
|------|------|------|
| 0 | 문서·브랜드 이관 + 본 PLAN 확정 | 파일 존재 · bundleId 기록 |
| 0b | git/bd init + SwiftPM 스캐폴드 (`com.borasarang.relayconsole`, 0.1.0) + BrandKit 아이콘 | 빌드 골격 |
| 1 | P0 병합·nil·로깅 패턴 (DeviceInventory @MainActor 유일 read) | unit |
| 2 | 토큰 + 버튼 + dark 강제 | 테마 깨짐 없음 |
| 3 | 파서 8종 + DroidMetrics 링60 | AdbParsingTests 신규 |
| 4 | MenuBarPopoverView | DoD 팝오버 분기 |
| 5 | DroidDashboardView + 로그 패널 | DoD 대시보드 분기 |
| 6 | 인터랙션 (배너→콘솔, 콘솔 열기; Scrcpy 없음) | 수동 플로우 |
| 7 | swift test + 빌드 + TODO 갱신 | DoD 전수 |

---

## 8. 산출 파일 (신규 프로이 기준)

```
docs/plans/PLAN_v0.1_relayconsole.md   ← 본 문서 (FINAL · 보강 흡수)
docs/research/* , BrandKit/*           ← 이관 완료
Package.swift                          ← com.borasarang.relayconsole, macOS 26.0, 버전 0.1.0
Sources/RelayConsole/.../MenuBarPopoverView.swift
Sources/RelayConsole/.../DroidDashboardView.swift
Sources/RelayConsole/.../DroidMetrics.swift          ← ring buffer 60
Sources/RelayConsole/.../AdbClient.swift (+parsers)
Sources/RelayConsole/.../DeviceMonitor.swift         ← actor
Sources/RelayConsole/.../DeviceInventory.swift       ← @MainActor
Sources/RelayConsole/.../Theme/OPColor|OPFont|OPPrimaryButton|OPSecondaryButton.swift
Resources/Assets.xcassets/AppIcon.appiconset         ← BrandKit/AppIcons/AppIcon_1024
Resources/Assets.xcassets/MenuBar.templateicon       ← BrandKit MenuBar_Black_Template_22
Tests/RelayConsoleTests/AdbParsingTests.swift
```

---

## 9. 열린 질문 (기본값 — 확정)

| # | 질문 | 확정값 |
|---|------|--------|
| 0 | bundleId | **`com.borasarang.relayconsole`** (AGENTS 플랫폼 규칙; BrandKit `com.relay.console` 기각) |
| 1 | scrcpy 열기 버튼 | **없음** |
| 2 | 메뉴바 라벨 지표 | `Outpost n/m` → **`Relay n/m`** (기존 n/m 유지, 이름만 교체) |
| 3 | radius | 카드 **16** / 기타 12 |
| 4 | 로그 리스트 | **표시만** 단일 패널, 데이터 유지 |
| 5 | 설정 키 접두어 | **`relay.*`** |
| 6 | 최소 OS | **macOS 26.0 Tahoe** (BrandKit) |

---

## 10. DoD (반드시 통과 — 보강 프롬프트 §7)

- [x] bundleId `com.borasarang.relayconsole` · 앱명 Relay Console · 메뉴바 라벨 **RELAY**
- [x] BrandKit AppIcon + MenuBar Black Template 적용
- [x] 팝오버 360×≤560px **다크 강제** · 카드 #1c1f2a r16 · SF Mono 숫자
- [x] 발열 ≥40°C 또는 Status≥2 → 오렌지 배너 + temp sparkline
- [x] CPU 8코어 미니바 (compact + full)
- [x] Battery 실제값 + history spark (`"-"` 없음, nil → `"—"`)
- [x] `…5555` 마스킹 · [콘솔 열기]/[디버그] 있음 · **[Scrcpy로 열기] 없음**
- [x] 6카드만: CPU/MEMORY/BATTERY/NETWORK/THERMAL/STORAGE (GPU·gfxinfo 0건)
- [x] print 0 · `.borderedProminent` 기본 0 · 웹 링크 0 · 라이트 표시 0 · Outpost 라벨 0 · `outpost.*` 키 0 · **iStats/iStat 문구 0**
- [x] **레드/레인보우 0건** — material/glass/`.bar`/backgroundStyle 0, 솔리드 `#0f111a` + 카드 `#1c1f2a` r16 opacity X, `darkAqua`
- [x] **i18n ko/en 100%** — `Localizable.xcstrings` + `*.lproj`, UI Text 키화, 한글 하드코딩 0, 영어 360px lineLimit
- [x] 파서 8종 + spark/미니바 실데이터 (전부 `—` 금지)
- [x] 설정키 `relay.*`만 · 설정변경·logcat 연동 유지 (카운트 연동은 v0.2 후속)
- [x] **UI는 `DeviceInventory.devices`만 읽음** (P0-a)
- [x] swift test 통과 · 실기기 SM_S901N 수동 1회 (27/27 + 육안 확인)

---

## 11. 이관 기록

| 항목 | 위치 |
|------|------|
| 복사 완료 | 2026-09-23 |
| **보강 흡수** | `docs/plans/PROMPT-FINAL-V0-2-No-IStat-I18n-V2fix.md` → Critical · i18n · Red 핫픽스 · DoD v0.2 (구 V0-1 교체) |
| **BrandKit** | `BrandKit/` (AppIcons·MenuBarIcons·README·AppStore_Metadata) |
| **bundleId 확정** | `com.borasarang.relayconsole` — BrandKit `com.relay.console` 기각, AGENTS.local 갱신 |
| RESEARCH | `docs/research/RESEARCH_droid_devicecare.md` |
| Skill Pack | `docs/research/SKILLPACK_mimo_v2_6.md` (과거명 Outpost — 참고 원본 유지) |
| 목업 | `docs/research/*.html` |
| DESIGN | `docs/DESIGN.md` |
| AGENTS.local | 루트 — 프로젝트명·bundleId·버전 0.1.0·relay.* 갱신 완료 |
| PLAN 아카이브 | `docs/plans/archive/PLAN_v0.*_macos.md` |
| 코드/git/beads | git+bd init 완료 · 코드 **신규** (T-101~T-109 open) |
