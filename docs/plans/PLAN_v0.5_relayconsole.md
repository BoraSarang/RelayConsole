# PLAN_v0.5_relayconsole.md — 감시 이벤트: ThresholdGate·hysteresis·severity

> 생성일: 2026-09-24 | 상태: **완료 (DoD 전수 · 육안 ✓ · PR #2 머지 `64d84e4`)**
> 모체: `docs/research/RESEARCH_watch_events.md` (Downloads 보완판 v1.1)
> 앱: **Relay Console** | bundleId: **`com.borasarang.relayconsole`** | 목표 버전: **0.5.0** | 최소 OS: **macOS 26.0**

---

## 0. 리서치 분석 요약 (간단)

| 항목 | 리서치 결론 | 코드베이스现状 | 갭 |
|------|-------------|----------------|-----|
| 아키텍처 | ThresholdGate(hysteresis+cooldown) → MonitorEvent(kind+severity+fingerprint) → 파이프 | `DeviceMonitor.notifyEvent(String)` + `ConsoleStore.recentEvents:[String]` | **구조화 이벤트 없음** |
| 스로틀링 | enter≥3, clear≤1, 60s 쿨다운, ntfy p4 | `parseThermal`✓ · UI 배너 `status≥2`✓ · **이벤트 발행 없음** | Gate+이벤트만 연결 |
| 충전/보호모드 | 전이성 이벤트 | 필드 수집✓ (`isCharging`, `isProtectionMode`) · 발행 없음 | delta 검출 |
| PSI/load/mem | Phase2 임계 | `parseMemInfo`✓ `load1`✓ PSI **수집 없음** | PSI 파서 신규 |
| Bsoh/신호 | Phase2 | `batteryHealthPct`✓ · RSRP **수집 없음** | telephony grep |
| 알림 파이프 | 2중 쿨다운 + fingerprint + GRDB 5000 | GRDB **OUT**(PLAN_v0.4) · pushEvent 문자열만 | 메모리 ringbuffer 20 → fingerprint 5분 |
| 설정 UX | 토글+임계값 편집 | SettingsView 간단 | Phase1는 defaults 고정, UI 토글은 Phase1.5 |

**핵심 판단**: 리서치의 "kind 비대화 방지 → severity+fingerprint"를 채택. GRDB는 계속 OUT — 이력은 `metricsHistory`/`recentEvents`로 충분.

---

## 1. 범위 (IN / OUT)

| IN | OUT (유지) |
|----|------------|
| `ThresholdGate` + 단위 테스트 (hysteresis·cooldown·fingerprint) | GRDB / EventStore 영구 DB |
| **Phase1 이벤트**: 스로틀링, 충전 전이, 보호모드 전이 | ntfy 역푸시 (Notify 모듈 미구현 범위 밖) |
| 구조화 `WatchEvent` (kind, severity, fingerprint) + 기존 문자열 파이프 병행 | Apple thermalState (방향A 분기 — 본 버전 Android만) |
| ConsoleStore: 알림 필터 + fingerprint 5분 쿨다운 + 시스템 알림 | 설정 화면 임계값 슬라이더 (defaults 고정으로 시작) |
| i18n ko/en/xcstrings + 메뉴바 주황 배지(초기) | 메모리 상주 알림 앱 전용 UX |
| **Phase2 (동일 브랜치 or 후속)**: PSI 파서+알림, load 임계, MemAvailable 임계 | Bsoh 구간 하락·RSRP (수집기 미완 → 보류) |

---

## 2. 데이터 모델 (신규)

### 2.1 WatchEvent (기존 문자열과 병행)

```swift
// Sources/RelayConsole/Models/WatchEvent.swift
enum WatchKind: String, Sendable {
  case throttling, chargeChanged, protectionChanged
  case psiPressure, loadSpike, memoryLow   // Phase2
}

enum WatchSeverity: String, Sendable { case info, warning, critical }

struct WatchEvent: Identifiable, Sendable {
  let id = UUID()
  let kind: WatchKind
  let severity: WatchSeverity
  let serial: String          // shortId는 UI에서
  let title: String           // L10n 미리 포맷
  let detail: String
  let at: Date
  var fingerprint: String { "\(serial):\(kind.rawValue)" }
}
```

### 2.2 ThresholdGate (Utils)

```swift
// Sources/RelayConsole/Utils/ThresholdGate.swift
/// enter/clear hysteresis + cooldown — 플래핑 방지
struct ThresholdGate {
  let enter: Double
  let clear: Double          // enter > clear 필수
  let cooldown: TimeInterval
  private var activeUntil: Date?   // nil = normal
  private var lastFired: Date?

  mutating func evaluate(value: Double, now: Date = .now) -> GateAction
  // .none | .enter | .clear
}
```

상태 머신: `normal →(value≥enter, cooldown만료)→ active →(value≤clear)→ cooldown → normal`

| 파라미터 | 스로틀링 | 충전 | 보호모드 | PSI Phase2 |
|----------|----------|------|----------|------------|
| enter | 3 (SEVERE) | 전이 감지(이중 값) | 1 | 5.0 |
| clear | 1 (LIGHT) | — | 0 | 3.0 |
| cooldown | 60s | 5s(중복 전이 방지) | 10s | 120s |

---

## 3. 수집기 연결 (DeviceMonitor)

| 지표 | 기존 수집 | delta/Gate 지점 | 이벤트 |
|------|-----------|-----------------|--------|
| thermalStatus | 5s `parseThermal` ✓ | `state.prevThermal` 비교 → Gate | `.throttling` critical if ≥3, warning if 2 |
| isCharging | 5s battery ✓ | prev != new | `.chargeChanged` info |
| isProtectionMode | 5s battery ✓ | 0→1 enter / 1→0 clear | `.protectionChanged` warning |
| PSI memory | **미수집** → `cat /proc/pressure/memory` 5s | Gate some.avg10 | `.psiPressure` Phase2 |
| load1 | 5s ✓ | ≥ cores×2 | `.loadSpike` Phase2 |
| MemAvailable% | 15s meminfo ✓ | <10% / >20% | `.memoryLow` Phase2 |

알림은 `onEvent(WatchEvent)` → ConsoleStore 단일 경로. 기존 `notifyEvent(String)`은 UI 푸터용으로 **유지**.

---

## 4. 파이프 (ConsoleStore)

```
WatchEvent
  → recentWatchEvents (ring 50) 갱신          // 팝오버 "Latest" 강화용
  → fingerprint 쿨다운: lastFired[fp] ≥5분?   // 2중 안전
  → 시스템 알림 (UNUserNotification)
       severity critical → interruptionLevel .timeSensitive
       warning → .active, info → passive(선택)
  → 메뉴바 배지: critical 미해결 → MenuBar-Online + 주황점(아이콘 교체 or 배지)
```

기존 `recentEvents:[String]`은 하위호환 유지, 새 이벤트는 문자열 요약도 push.

---

## 5. 구현 지점 (파일 단위)

| 파일 | 변경 |
|------|------|
| **신규** `Models/WatchEvent.swift` | kind/severity/fingerprint |
| **신규** `Utils/ThresholdGate.swift` | hysteresis 상태머신 |
| **신규** `Droid/WatchEngine.swift` | serial별 Gate 맵 · evaluate · 이벤트 emit (DeviceMonitor와解耦) |
| `DeviceMonitor.swift` | prev thermal/charging/protection 보존 → WatchEngine.feed |
| `ConsoleStore.swift` | `recentWatchEvents`, fingerprint 쿨다운, UNNotification 발송 |
| `RelayConsoleApp.swift` / `AppDelegate.swift` | 알림 권한 요청(최초 1회) |
| `MenuBarPopoverView.swift` | Latest events → WatchEvent 목록(심각 우선) |
| `DroidDashboardView` / 배너 | 기존 status≥2 배너는 유지, Gate 이벤트와 중복 주의 |
| i18n `ko/en.lproj` + `Localizable.xcstrings` | `event.throttling.enter/clear`, `event.charge.*`, `event.protection.*`, `event.psi.*` … |
| `SettingsView.swift` | Phase1.5: 감시 알림 on/off (`relay.watch.throttling` 등) |
| `Tests/.../ThresholdGateTests.swift` | **신규** 4+케이스 |
| `Tests/.../WatchEventTests.swift` | fingerprint/cooldown |

---

## 6. 테스트 계획

| 케이스 | 기대 |
|--------|------|
| enter 3, value 2→3 | `.enter` 1회 |
| value 3→2 (clear 1) | `.none` (flap 방지) |
| value 3→1 | `.clear` |
| enter 직후 value 3 again within 60s | `.none` (cooldown) |
| fingerprint 동일 5분 재진입 | 알림 발송 안 함 |
| charging true→false→true 빠른 토글 | 전이당 1회 |
| 빈 Gate 초기 normal | 즉시 high value → enter |

기존 `swift test` 60건 유지 + 신규 ≥10 → 목표 **70+**.

---

## 7. 검증 (DoD)

- [x] `swift test` 통과 (신규 Gate 테스트 포함) — **84/84** (ThresholdGate + WatchEvent + 프로세스 파서 + 기존)
- [x] `./build_and_run.sh debug macos` 빌드 0 error · 번들 **0.5.0**
- [x] 금지 grep 0건 (Outpost, iStat, Scrcpy, gfxinfo, material…)
- [x] i18n 3곳 키 수 일치 — **129/129/129** (알림 배너 + 후속 조치 + 저전력/배터리 임계 + 프로세스 목록 포함)
- [x] DEBUG 합성 주입 훅 — `ConsoleStore.debugInjectSynthetic` + 디버그 패널 (스로틀링/충전/보호 on·off/저전력/배터리20%/배지) — release 미포함
- [x] 알림형 상단 배너 — `AlertBannerPresenter` (NSPanel, 메뉴 팝오버 아님) · `relay.watch.banner` 기본 ON · `alert.banner.{notify,cleared}` 메시지
- [x] **권장 후속 조치 가이드** — 미해결 warning+ → 팝오버 `권장 후속 조치` 체크리스트 (스로틀링 대응 5항 등), 탭 → 콘솔
- [x] **저전력 모드·배터리 임계** — `lowPowerChanged` + `batteryThreshold` 20/10/5% · 설정 2토글 · 테스트 80/80
- [x] 실기기 육안 — 주입(스로틀/충전/보호)·알림 배너·팝오버 Latest·메뉴바 배지 ✓
- [x] 충전 전이 육안 — 켜기/끄기 이벤트 ✓
- [x] 팝오버 Latest에 심각 이벤트 상단 노출 (육안 ✓)
- [x] 메뉴바 주황 배지 (critical 미해결 시) 육안 ✓
- [ ] Phase2 A5: PSI 파서 + load/mem 임계 — **보류(후속)**

---

## 8. 실행 순서 (A1–A6)

| 단계 | 작업 | 산출 | 검증 |
|------|------|------|------|
| **A0** | 본 PLAN + research 커밋 | 문서 | — ✓ |
| **A1** | ThresholdGate + 테스트 | Utils + Tests | flap/cooldown 케이스 ✓ |
| **A2** | WatchEvent + WatchEngine + thermal/charge/protection feed | 3종 이벤트 | 단위 emit 테스트 ✓ |
| **A3** | ConsoleStore 쿨다운 + UNNotification + 권한 | 파이프 | 중복 0 ✓ / 시연 알림 대기 |
| **A4** | 팝오버 Latest + 메뉴바 주황 배지 + i18n | UI | 코드 ✓ · 육안 ✓ |
| **A5** | PSI 파서 + load/mem 임계 (Phase2) | 3종 추가 | **보류** |
| **A6** | 설정 토글 (`relay.watch.*`) + 문서화 + 버전 0.5.0 | Settings + CHANGELOG | DoD 자동 항목 ✓ |
| **+** | 프로세스 목록(이름/PID/CPU/RAM/커맨드) · 독립 윈도우 | ProcessList* | 84/84 · 육안 ✓ |

**소요**: A1–A3 반나절 · A4–A6 하루.  
**병렬 가능**: i18n 키 목록은 A2와 동시 작성.

---

## 9. 리스크

| 리스크 | 대응 |
|--------|------|
| 알림 폭주 | Gate cooldown + notify fingerprint 5분 이중 |
| UI 배너와 이벤트 중복 | 배너=현재 상태 표시, 이벤트=전이 기록 — 공존 허용, 문구 구분 |
| GRDB 없는 이력 | recentWatchEvents 50건 + DebugLogger — 요구 생기면 후속 |
| PSI 권한/부재 | optional 파서, nil이면 이벤트 생략 |
| 스로틀링 실측 난이 | 에뮬 `dumpsys thermalservice` 오버라이드 또는 status 필드 테스트 픽스처 |

---

## 10. 대기 의존 (먼저 정리 권장)

1. **v0.4.1 메뉴바 UX push → PR → 머지** (브랜치 `feat/menubar-ux-windowfocus`, 커밋 `c960c3d` ready)  
   → 본 v0.5는 main 머지 후 새 브랜치 `feat/watch-events`에서 A0 착수.
2. WindowFocus 육안 1건 (사용자 확인) — v0.5와 무관, 병렬 가능.

---

## 11. 다음 액션 제안

| # | 선택 |
|---|------|
| 1 | **(권장)** 메뉴바 브랜치 push·PR·머지 → `feat/watch-events` A0–A3 착수 |
| 2 | 문서만 확정하고 구현 일정 재조율 |
| 3 | Phase2(PSI/load/mem)를 Phase1과 같은 범위로 승격 |
