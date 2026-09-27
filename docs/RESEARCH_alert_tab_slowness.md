# 조사 — 알림 유입 시 전 탭 지연 (2026-09-27)

> 성격: **조사 → 적용 완료** (제안 1·2 구현됨, 2026-09-27 저녁) · 실측 기반 · 추측 금지
> 관련: `session-2026-09-27-2/3/4` · 성능 예산 `rules/budgets.json` (p95 프레임 16.7ms)
> **구현 결과 → §7**

---

## 0. 결론 먼저

**"데이터가 많아서" 는 아니다.** 이벤트 500건 기준 **계산 자체는 합쳐 6.7ms** 다.
진짜 원인은 **세 가지가 겹친 구조**이고, 셋 중 둘은 상수 시간 개선이 가능하다.

| # | 원인 | 실측 | 성격 |
|---|---|---|---|
| **A** | 알림 1건이 `objectWillChange` 를 **2회** 발생시키고, 그것이 **열려있는 모든 탭의 body 를 재평가**한다 | 2회 × 탭 수 | 구조 |
| **B** | `dayKey(for:)` 가 이벤트마다 **1,500회 이상** 호출되고, 매번 `String(format:)` + String 할당 | 500건 기준 **3.5ms** | **상수 시간 개선 가능** |
| **C** | `ConsoleStore` 의 `@Published` **20개** — 하나가 바뀌면 **14개 View** 가 전부 무효화 | 20 / 14 | 구조 |

---

## 1. 측정 방법과 결과

임시 계측 테스트를 만들어 실제로 재고 **제거**했다 (측정 코드 상주 금지).
`ConsoleStore` 는 `@MainActor` + private(set) 이라 `ingestWatch` 직접 계측은 값이 안 나오고,
경로를 구성 요소로 쪼개 측정했다. **알림 1건 = `ingestWatch` 1회** 기준.

### 1-1. 이벤트 500건, 탭별 body 계산 비용

| 대상 | 최소 | 평균 |
|---|---|---|
| `InsightsView.insight` | 0.126 ms | 0.469 ms |
| **`InsightsView.report`** | **4.330 ms** | **4.460 ms** |
| `InsightsView.patterns` | 1.759 ms | 1.773 ms |
| `AlertsView.filter` | 0.147 ms | 0.151 ms |
| `Dashboard.detectToday` | 0.120 ms | 0.122 ms |
| `serials` 집합 (500 map) | 0.159 ms | 0.162 ms |

→ **InsightsView body 1회 = 약 6.2ms. 60fps 프레임 예산(16.7ms)의 37%.**

### 1-2. 알림 1건의 유입 경로 (500건 상태)

| 단계 | 최소 | 평균 |
|---|---|---|
| 배열 insert+trim (500) | 0.038 ms | 0.038 ms |
| `@Published` 대입 1회 | 0.001 ms | 0.001 ms |
| `pushEvent` (20 상한) | 0.001 ms | 0.003 ms |
| `EventStore.save(500)` | 0.000 ms | 0.001 ms |
| `DeviceDailyStore.countEvent` | 0.004 ms | 0.005 ms |
| `IssueLog.append` | 0.077 ms | 0.130 ms |
| **합계** | **≈ 0.12 ms** | **≈ 0.18 ms** |

→ **데이터 유입 자체는 느리지 않다.** `EventStore` 는 `CoalescingWriter` 로 백그라운드 합치기가
이미 되어 있고(4단계에서 개선), 디스크 직렬화도 큐로 빠져 있다. **여기 finger 를 대지 않는다.**

### 1-3. 실제 이벤트 유입률 (500건 파일 분석)

```
최근 15분: 11건 (signalDrop 11)
15분 구간별: 3~14건  → 평균 약 0.5~1건/분
severity: info 369 · warning 67 · critical 64
```

→ **초당 storms 아니다.** 초당 수십 건이 아니라 분당 1건 수준.
"알림이 들어오면 느려진다" 는 체감이 **건수가 아니라 건당 비용(레이아웃 정지)** 때문이라는 뜻이다.

### 1-4. 병목 pinpoint — `dayKey(for:)`

`DeviceDailyLogic.dayKey(for:)`:
```swift
static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d%02d%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)  // ← 할당
}
```

`ReportLogic.dayOverDay` 안에서 호출되는 횟수:
- `filterDay` × 2 = 이벤트마다 1회씩 → **1,000회**
- `PatternLogic.patterns` 의 `Set(enters.map { dayKey(...) })` → **500회**
- **합계 1,500회 이상**, 매번 `String(format:)` + String 할당

| 1,500회 기준 | 최소 | 평균 |
|---|---|---|
| 현행 (문자열) | **3.471 ms** | 3.595 ms |
| 후보 (정수 비교) | **0.672 ms** | 0.700 ms |

→ **5.2배. `report` 4.3ms 중 대부분이 이것이다.**

---

## 2. 느려지는 메커니즘 (왜 "모든 탭" 인지)

```
알림 1건 유입
  └─ ingestWatch()
       ├─ recentWatchEvents = next   → @Published → objectWillChange ①
       ├─ pushEvent(event.summary)   → @Published → objectWillChange ②
       └─ (알림 표시·IssueLog 등)
                    ↓
       ConsoleStore 의 objectWillChange 가 **관찰 중인 모든 View** 에 전파
                    ↓
       ┌────────────┬────────────┬────────────┐
    InsightsView  AlertsView  DroidDashboard  MenuBarPopover  … 14개
       6.2ms      0.15ms       0.12ms        (팝오버는 상시 마운트)
                    ↓
       SwiftUI 는 **열려있는(마운트된) 탭만** 재평가 — 콘솔 창이 1개라
       현재 탭 + 상시 살아있는 메뉴바 팝오버가 같이 맞는다
```

`InsightsView` 는 이미 4단계에서 body 상단 1회 계산으로 개선됐지만(57ms→3ms),
**계산 대상 데이터가 500건** 이라 여전히 6.2ms 다. 60fps 예산의 37%.

**프레임 예산 대비 (실측 기반 추정)**

| 상황 | 프레임 예산 소요 |
|---|---|
| InsightsView 탭 1개 + 알림 1건 | **약 13 ms (80%)** |
| InsightsView 탭 1개 + 알림 1건 + 로그 창 스트림 | **초과** (로그 창 자체가 CPU 100% — 별건) |

`objectWillChange` 2회가 겹치면 SwiftUI 는 같은 프레임 안에서 두 번 갱신을 시도하므로
실제 정지 시간은 위 표보다 길어진다.

---

## 3. 제안 (측정 근거 있는 것만)

### 제안 1 — `dayKey` 비교를 정수로 (권장 · **상수 시간 · 위험 최소**)

`dayKey` 문자열을 쓰지 않고 `yyyyMMdd` 정수로 비교한다.
할당이 사라지고 `String(format:)` 도 사라진다.

- **예상 절감**: `report` 4.3ms → 약 **1.2ms** (1,500회 × 문자열→정수)
- **위험**: 낮음. `DeviceDailyLogic.dayKey` 는 시그니처가 넓게 쓰이므로
  **비교 전용 헬퍼**(`dayKeyInt(for:)`)를 추가하고, 문자열 키가 필요한
  스토어 키(`serial|dayKey`)는 유지하는 방식이 안전하다
- **검증**: `ReportLogic` / `PatternLogic` / `DetectLogic` 의 기존 테스트가
  결과를 고정하고 있어 **동치성 검사가 그대로 된다**

### 제안 2 — `insight` / `report` / `patterns` 를 **1회 계산 + 캐시** (권장)

`InsightsView` 는 이미 body 상단에서 1회 계산하지만, **그 계산을 매 body 평가마다 다시 한다.**
알림 1건 → body 2회 평가 → `report` 2회 = **8.6ms**.

`ConsoleStore` 에 `insightsCache: (eventsVersion, insight, report, patterns)` 를 두고
`recentWatchEvents` 가 **실제로 바뀔 때만** 재계산한다.

- **예상 절감**: 알림 1건당 InsightsView 비용 6.2ms → **0ms** (캐시 적중 시)
- **위험**: 중간. 캐시 무효화 조건을 정확히 잡아야 한다 (dayKey 변경·설정 변경·날짜 경계).
  **자정 경계**가 빠지기 쉬우므로 `selectedKey` 를 키에 넣어야 한다

### 제안 3 — `@Published` 세분화 (구조적 · **나중**)

`ConsoleStore` 의 `@Published` 20개 중 `recentWatchEvents` 하나가 바뀔 때
`selectedSerial` 만 읽는 View 까지 함께 무효화된다.

- **방법**: `ConsoleStore` 를 `DeviceStore` / `EventStore` / `SettingsStore` 로 분리하거나,
  최소한 `recentWatchEvents` 를 **별도 ObservableObject** 로 뺀다
- **위험**: 높음. 14개 View 의 의존성을 전부 다시 매핑해야 한다
- **판단**: **하지 않는다.** 제안 1+2 로 체감 문제를 먼저 없앤 뒤, 측정 후 다시 판단한다.
  (09-26 세션에서도 `ConsoleStore` 57속성 분리한 적이 있어 **보류** 로 남긴 전례가 있다)

### 하지 않는 것
- **이벤트 상한을 500 → 100 으로 줄이기** — 되돌릴 수 없다. 데이터가 사라진다. **금지**
- **`ingestWatch` 를 백그라운드로 옮기기** — 이미 0.12ms 다. 의미 없음
- **알림 쿨다운을 늘리기** — 체감(속도)을 데이터(빈도)로 해결하지 않는다

---

## 4. 예상 효과

| 단계 | InsightsView 알림 1건당 | 프레임 예산 대비 |
|---|---|---|
| 현행 | 6.2 ms | 37% |
| 제안 1 | 약 2.1 ms | 13% |
| 제안 1 + 2 | **0 ms** (캐시 적중) | **0%** |

`AlertsView` / `DroidDashboard` 는 이미 0.15ms / 0.12ms 라 **지적 대상이 아니다.**
느린 곳 하나가 반복을 증폭시키고 있었다.

---

## 5. 남는 사실 (이번 조사에서 드러난 것)

- **느린 탭은 하나뿐이다** (Insights). "거의 모든 탭" 이라는 체감은
  `objectWillChange` 전파 + 프레임 예산 초과가 만드는 **연쇄 지연**이다
- **데이터는 늘려야 한다.** 500건 상한은 되돌릴 수 없는 삭제이며,
  사용자에게는 "이력이 없다" 로 나타난다. **성능은 계산으로 이겨야 한다**
- **로그 창은 별개 병목** (CPU 89~104%, 초당 1.4만 줄 — 검색 기능 세션에서 실측).
  이건 알림과 무관하므로 이번 조사 범위 밖
- `EventStore` 는 500건을 **매번** JSON 인코딩(93KB) 한다. `CoalescingWriter` 가
  합쳐서 디스크 쓰기를 줄이지만 **인코딩은 값이 바뀔 때마다** 일어난다.
  알림 유입이 잦아지면 백그라운드 큐 작업도 늘어난다 — 이번엔 지표가 작아 우선순위 낮음

## 6. 미해결 / 육안 필요
- 실제 앱에서 알림을 수십 건 밀어넣고 **프레임 정지 시간**을 프로파일로 재는 것은
  Instruments 없이 코드만으로 확정할 수 없다. 제안 1 적용 후 **체감 재확인**이 최종 증거
- `MenuBarPopoverView` 의 15초 타이머(`now = t`)가 매 15초 body 를 깨우는데,
  이 탭이 얼마나 무거운지는 **별도 측정**이 필요하다 (팝오버는 상시 마운트)

---

## 7. 적용 결과 (제안 1·2 · 2026-09-27 저녁)

### 제안 1 — `dayKey` 정수화 ✅

`DeviceDailyLogic.dayKeyInt(for:)` / `dayKeyInt(_:)` 추가.
`ReportLogic.dayOverDay` 의 `filterDay` 2회와 `PatternLogic.patterns` 의 `Set(map:)` 를 정수 비교로 전환.

| 대상 | 적용 전 | 적용 후 | 개선 |
|---|---|---|---|
| `report` | 4.330 ms | **1.935 ms** | 2.2배 |
| `patterns` | 1.759 ms | **1.164 ms** | 1.5배 |
| `insight` | 0.126 ms | 0.131 ms | — |
| **body 합계** | **6.2 ms** | **3.2 ms** | **1.9배** |

**설계 규칙**: 이 함수는 **비교 전용**이다. 스토어 키(`serial|dayKey`)처럼 문자열이 필요한
곳은 `dayKey(for:)` 를 그대로 쓴다 — 키 포맷을 바꾸면 저장 데이터와 어긋난다.

### 제안 2 — 인사이트 캐시 ✅

`InsightsView` 에 `InsightCacheBox`(클래스) + `InsightCacheKey`(9종)를 도입.

- **캐시 키 9종**: `events.first` · `events.last` · `events.count` · `selectedKey` ·
  **`todayKey`(자정 경계)** · `serialFilter` · `thresholds` · `dailyRevision` · `sessionRevision`
- **전제 확보**: `DeviceDailyStore` / `ConnectionSessionStore` 에 **`revision` 카운터** 신설.
  둘 다 `@Published` 가 아니라 "바뀌었나" 신호가 없었다 — **이게 캐시가 성립하는 근거**
- **예상**: 알림 1건당 InsightsView 비용 **6.4ms → 0ms(적중 시)**

### 검증

- **캐시 규칙 실측**: 상태 변화 6종(알림·날짜·기기필터·Daily·세션)이 **정확히 1회씩** 무효화,
  동일 입력은 hit 반복 — 확인 후 **영구 테스트로 고정** (`everyStateChangeInvalidatesExactlyOnce`)
- **동치성**: `dayKeyInt` ↔ `dayKey` 문자열이 1,600일에 걸쳐 일치(윤년·월경계 포함),
  `dayOverDay` 결과가 정수화 전과 **동일**함을 테스트로 고정
- `[HARD]`: `swift test` **473 + 104 = 577 / 0 failed** · `build-macos.sh debug` **EXIT=0**

### 부수 — 환경 의존 테스트 제거

`WifiAutoTests.reachabilityUsesAdbPortNotPing` 가 실기 IP(`10.233.247.205`)를 하드코딩해
**핫스팟을 끄는 순간 실제로 깨졌다.** 판정과 무관한 입력 검증(잘못된 IP·루프백·닫힌 포트)으로 교체.

> **원칙**: 환경이 바뀌면 깨지는 테스트는 **버그 신호가 아니라 잡음**이다.
> 실기 계측은 그 시점에 문서에 남기고, 테스트는 결정적(deterministic)으로만 유지한다.

### 남은 것
- **알림 1건이 여전히 `objectWillChange` 2회** — 캐시로 계산 비용을 없앴지만
  SwiftUI 자체 재평가 비용은 남는다. 완전 제거는 `@Published` 세분화(제안 3)이며 **보류**
- **체감 재확인** — Instruments 없이 코드만으로 프레임 정지 시간은 확정 불가.
  실제 앱에서 알림을 몰아넣고 체감 확인이 최종 증거다

---

## 8. 제안 3 재개 — 계측 후 축소판으로 착수 (2026-09-28)

> §3 제안 3 은 **"제안 1·2 후 체감 재확인 → 통과하면 미착수"** 를 착수 조건으로 걸었다.
> 그 측정이 끝났고 결과는 **"14개 재매핑은 불필요"** 였다. → `PLAN_published_split_recentevents_relayconsole`

### 8-1. 계측 (추측 아님 — 임시 계측 테스트 실행 후 삭제, 트리 clean)

격리 프로브로 Swift `@Published` 시맨틱을 분리 검증 + 실제 `ConsoleStore.shared` 를 관찰:

| 항목 | 실측 |
|---|---|
| 실제 경로 `ingestWatch` | **2회** — `recentWatchEvents` 1 + `pushEvent` 1 · **§2 서술과 일치 ✅** |
| `assignOnce` (복사 → 1회 대입) | 링 미만 **1** · 링 초과 **1** → **항상 1** |
| `mutateInPlace` (in-place 변이) | 링 미만 **1** · 링 초과 **2** ⚠️ |
| `recentEvents` 1회 대입 | 1 |
| 무변화 시 자발 신호 | **0** (잡음 없음) |

### 8-2. 결론 ① — 14개 View 재매핑은 필요 없었다

중복 신호의 원인은 `recentEvents` 다. 필드별 읽는 곳을 전수 계측하면:

| 필드 | 읽는 View | 분리 비용 |
|---|---|---|
| `recentWatchEvents` | AlertsView · MenuBarPopoverView · DroidDashboardView · InsightsView (+ 위젯 sync) | **14개** |
| `recentEvents` | **MenuBarPopoverView 하나 (3곳)** | **1개** |

→ **원인 필드만 자르면 된다.** `recentEvents` 를 `RecentEventsStore` 로 분리해
View 1개만 재매핑. `pushEvent` 시그니처를 유지해 `DeviceMonitor` 는 무변경.
`recentWatchEvents` 는 **여전히 분리하지 않는다** — 14개 재매핑의 근거가 없다.

### 8-3. 결론 ② — 제안 1·2 가 이미 문제를 없앴다

중복 2번째 신호의 계산 비용:
- `InsightsView` — 캐시 키 9종에 `recentEvents` 가 **없다** → 신호가 와도 **캐시 적중, 재계산 0ms**
- 나머지 View body — §1-1 실측 기준 `AlertsView 0.151 + Dashboard 0.122 + serials 0.162 ≈ 0.43ms`
  = 프레임 예산(16.7ms)의 **2.6%**

→ 착수 전 시점(§7)의 "6.4ms" 는 이미 사라졌다. **14개 재매핑은 없어진 문제를 향한 작업**이었다.

### 8-4. 결론 ③ — 부수 발견: 디버그 경로가 실제보다 나빴다

`debugIngestWatchQuietly`(DebugPanel 알림 주입 경로)가 in-place 변이라:

- 링이 가득 차면 **3회** (실제 2회 대비 +1)
- §2 가 경고한 **"상한 501건 중간 상태"가 이 경로에서는 관측된다** — 실제 경로는 1회 대입으로 회피 중

→ **체감 재확인 도구가 실제보다 나쁜 경로를 재고 있었다.** DebugPanel 로 알림을 몰아넣으면
실대와 다른 원인을 측정하게 된다. 실제 경로와 **같은 1회 대입 패턴**으로 통일했다.

### 8-5. 왜 신호 횟수를 테스트로 고정했나

중복 신호는 **되돌아오기 쉽다.** 필드 하나를 다시 `ConsoleStore` 에 붙이는 것만으로
모든 View 가 다시 무효화되고, **눈에 보이지 않는다**(느려지는 게 아니라 원인이 사라진 것처럼 보인다).
계측 없이는 못 잡는다 → `PublishedSignalTests` 5건으로 고정.

**결정성 근거**: `ConsoleStore.init` 이 `private` 라 격리 인스턴스가 없다(컴파일 에러로 확인).
`shared` 의 병렬 실행 잡음을 걱정할 수 있지만, **신호를 세는 구간이 동기 + `@MainActor` 이면**
MainActor 는 조정하지 않으므로 `await` 이 없는 그 구간에 다른 태스크가 끼어들 수 없다.
→ `swift-testing` 병렬 실행과 무관하게 결정적.

### 8-6. 남은 것
- **육안** — 알림 유입 시 다른 탭(설정·사이트)이 깜빡이지 않는지
- **`recentWatchEvents` 분리는 계속 하지 않는다** — 계측 근거 없음. 되돌아오면 위 표를 먼저 볼 것
- **`MenuBarPopoverView` 15초 타이머 비용** — §6 이 남긴 미측정 항목. 이번 범위 밖

