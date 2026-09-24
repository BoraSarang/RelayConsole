# PLAN_briefing_relayconsole.md — 아침 브리핑 한 줄 (S1)

> 생성일: 2026-09-24 | 상태: **완료** (육안 ✓ · PR #22 머지 `c57d546` · `psh` closed)
> 모체: `RESEARCH_competitive_v1.md` §5 TIER S · §8 P1-1
> 앱: **Relay Console** | 목표 버전: **1.3.0** | 최소 OS: **macOS 26.0**
> bd: `RelayConsole-psh`

---

## 1. 범위 (IN / OUT)

| IN | OUT |
|----|-----|
| 팝오버 헤더 하단 **한 줄 통합 요약** (sites·jobs·폰·critical) | 콘솔 대시보드 전용 위젯 |
| 합성 로직 순수 `BriefingLogic` + 단위 테스트 | 아침 스케줄 알림·푸시 |
| `relay.briefing.enabled` 토글 (설정 → 일반) | 실시간 WebSocket·원격 |
| i18n ko/en/xcstrings 3처 | 메뉴바 아이콘 텍스트 변경 |
| 금지 grep · `swift test` · `build-macos.sh debug` 1.3.0 | Apple Trust·Phase 2 |

### 출처
- RESEARCH §5 S1: “아침 브리핑 한 줄 (sites·jobs·폰·critical)”
- 기존 패턴: `sitesSection` 요약 (`MenuBarPopoverView:641`) · `hasActiveCritical` (`ConsoleStore:808`)

---

## 2. 설정키

| 키 | 타입 | 기본 | 설명 |
|----|------|------|------|
| `relay.briefing.enabled` | Bool | **true** | 팝오버 상단 한 줄 표시 |

Settings → 일반, `menubarMetrics` 토글 바로 아래 동일 패턴.

---

## 3. 아키텍처

```
ConsoleStore (sites/jobs/inventory/appleDevices/recentWatchEvents)
  └─ makeBriefing(now:) → BriefingSnapshot  (순수 · 테스트)
        │
        ▼
MenuBarPopoverView.headerBlock 하단 1행
  Text(L10n.format("briefing.line", …))  lineLimit(1)
  color: critical|down|overdue > 0 ? bad : ok
```

### BriefingSnapshot 필드

| 필드 | 계산 |
|------|------|
| `upSites` / `downSites` | `sites.filter(\.enabled)` → `effectiveUp()` true/false |
| `overdueJobs` | `jobs.filter { enabled && isOverdue()==true }.count` |
| `offlinePhones` | Android `!isOnline` + Apple `!isOnline` 합 |
| `totalPhones` | inventory + apple devices |
| `activeCriticals` | `hasActiveCritical` 알고리즘 count 확장 (fingerprint clear 판별) |

### 한 줄 포맷 (ko 예)

```
사이트 4/5 · 작업 1 지연 · 폰 2/3 · critical 1
```

- 전부 정상(0 문제)이면 `ok` 컬러: `사이트 5/5 · 작업 0 지연 · 폰 3/3 · critical 0`
- critical>0 이면 우선 `bad` · 아니면 down/overdue>0 → `warn` · 나머지 `ok`

i18n 키 후보:
- `briefing.line` — `"%d/%d sites · %d job late · %d/%d phones · %d critical"` (ko/en 각각 자연어 배치)
- `settings.briefing` — 토글 라벨

---

## 4. UI

```
┌ headerBlock ─────────────────────────┐
│ ● Relay Console    2/3  87%  1.2.0   │
│ Pixel 7  USB  ● 연결됨          [⌄] │
│ ─────────────────────────────────── │
│ 사이트 4/5 · 작업 1 지연 · … critical 1  ← 신규 1행
└─────────────────────────────────────┘
```

- 위치: `headerBlock` 2행 HStack **아래** (`:129` 후)
- `lineLimit(1)` · `OPFont.number(10)` · `OPColor`로 심각도 색
- `relay.briefing.enabled == false` 이면 숨김
- 기기 0·sites 0·jobs 0이어도 **critical 집계는 표시** (폰 없어도 관제 가능)

---

## 5. 파일 변경 목록

| 파일 | 변경 |
|------|------|
| `Sources/RelayConsole/Models/Briefing.swift` | **신규** — `BriefingSnapshot` + `BriefingLogic` 순수 |
| `Sources/RelayConsole/App/ConsoleStore.swift` | `makeBriefing(now:)` 위임 · `@AppStorage("relay.briefing.enabled")` |
| `Sources/RelayConsole/Views/MenuBarPopoverView.swift` | headerBlock 하단 briefingLine |
| `Sources/RelayConsole/Views/SettingsView.swift` | generalSection 토글 |
| `Resources/Localizable.xcstrings` + ko/en `.strings` | `briefing.line`, `settings.briefing` |
| `Tests/RelayConsoleTests/BriefingTests.swift` | **신규** — 카운트·색 우선순위·비활성 |
| `Resources/Info.plist` 등 버전 6처 | **1.3.0** |

---

## 6. DoD

- [x] `BriefingLogic` 단위 테스트 (사이트 up/down·overdue·critical count·포맷 인자) — BriefingTests 7
- [x] 토글 off 시 헤더 한 줄 숨김 · on 시 표시 (재시작 유지) — `relay.briefing.enabled`
- [x] i18n 3처 동치 · `%s` 없음 — **411**
- [x] 금지 grep 0 · `print(` 는 DebugLogger만
- [x] `swift test` 통과 (XCTest 42 + swift-testing 156) · `./scripts/build-macos.sh debug` **1.3.0**
- [x] 사용자 육안 (팝오버 헤더 한 줄 + 설정 토글) — **2026-09-24 확인 · `psh` closed**

---

## 7. 버전 1.3.0 동기화처

`Resources/Info.plist` · `scripts/build-macos.sh`(3) · `AppDelegate` · `SettingsView` · `MenuBarPopoverView` · `AGENTS.local.md` · `README.md` (해당 시)
