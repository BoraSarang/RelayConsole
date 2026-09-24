# PLAN_v0.6_relayconsole.md — Phase2 감시: PSI · load · MemAvailable

> 생성일: 2026-09-24 | 상태: **완료 (DoD · 실기기 육안 ✓ 2026-09-24)**
> 모체: `docs/plans/PLAN_v0.5_relayconsole.md` A5 · `docs/research/RESEARCH_watch_events.md` §2 Phase2
> 앱: **Relay Console** | bundleId: **`com.borasarang.relayconsole`** | 목표 버전: **0.6.0** | 최소 OS: **macOS 26.0**

---

## 1. 범위 (IN / OUT)

| IN | OUT (유지) |
|----|------------|
| `feedPsi` — memory some avg10 ≥5.0 / clear ≤3.0 / 120s | Bsoh·RSRP (수집 미완) |
| `feedLoad` — load1 ≥ cores×2 / clear ≤ cores×1 / 60s | 임계값 UI 슬라이더 (defaults 고정) |
| `feedMemory` — usedPct ≥90 (avail<10%) / clear ≤80 (avail>20%) / 60s | GRDB / ntfy |
| DeviceMonitor 수집→Gate 연결 (load는 코어 수 확정 후) | Apple thermalState |
| 설정 `relay.watch.{psi,load,memory}` | |
| i18n ko/en/xcstrings · DEBUG 주입 · remediation 3종 | |
| 버전 **0.6.0** | |

## 2. Gate 파라미터

| 지표 | enter | clear | cooldown | severity |
|------|-------|-------|----------|----------|
| PSI avg10 | ≥5.0 | ≤3.0 | 120s | warning / clear=info |
| load1 (cores×) | ≥2× | ≤1× | 60s | warning, ≥3× critical |
| Mem usedPct | ≥90 | ≤80 | 60s | warning, ≥95 critical |

- ThresholdGate `enter > clear` 유지 — 메모리는 **usedPct**(100−avail%)로 변환
- PSI 없는 커널: `parsePressure` nil → feed 생략
- load cores 미확정(첫 틱 전): feed 생략

## 3. 구현 지점

| 파일 | 변경 |
|------|------|
| `Droid/WatchEngine.swift` | `feedPsi` / `feedLoad` / `feedMemory` |
| `Droid/DeviceMonitor.swift` | `pendingLoad1`+`coreCount` cache · mem usedPct · PSI feed |
| `App/ConsoleStore.swift` | `relay.watch.{psi,load,memory}` + `watchEnabled` |
| `Views/SettingsView.swift` | 토글 3종 · 버전 0.6.0 |
| `Views/MenuBarPopoverView.swift` | remediation header/steps 3종 |
| `Views/DebugPanelView.swift` | 주입 PSI enter/clear · load · mem |
| i18n 3곳 | +22키 (129→**151**) |
| `Tests/WatchEventTests.swift` | Phase2 4케이스 |
| 버전 | Info.plist · build script · AppDelegate · popover · settings |

## 4. 검증 (DoD)

- [x] `swift test` — **88/88**
- [x] `./build_and_run.sh debug macos` — 0 error · 번들 **0.6.0**
- [x] 금지 grep — Outpost/iStat/Scrcpy/gfxinfo 0 · Views/App print 0
- [x] i18n 3곳 키 수 일치 — **151/151/151**
- [x] 실기기 육안 — 주입(PSI/load/mem) → 알림/배너/배지/권장 조치 (사용자 확인 ✓)

## 5. 실행 순서

| 단계 | 작업 | 상태 |
|------|------|------|
| B1 | WatchEngine 3 feed + mem% 방향 | ✓ |
| B2 | DeviceMonitor 연결 (coreCount·PSI·mem) | ✓ |
| B3 | 설정 토글 + remediation + DEBUG 주입 | ✓ |
| B4 | i18n 22키 + 테스트 4 + 버전 0.6.0 | ✓ |
| B5 | 검증 + 문서 + PR | ✓ 완료 |
