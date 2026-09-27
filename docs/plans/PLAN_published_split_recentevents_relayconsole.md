# PLAN — recentEvents 분리 (@Published 세분화 축소판) (2026-09-28)

> 성격: **구조 · 계측 기반 착수** · 직전 작업 `PLAN_refactor_perf_stability_macos` 후속
> 관련: `docs/RESEARCH_alert_tab_slowness.md` §3 제안 3 · `.agent/session-2026-09-27-5-macos.md`
> T-번호: `T-2026-09-28-1`

---

## 0. 왜 축소판인가

`docs/TODO.md` 에 남아 있던 항목은 "`@Published` 20개 세분화" 였고,
조사 문서는 이를 **제안 3 — 하지 않는다** 로 두고 **"제안 1·2 후 체감 재확인 → 통과하면 미착수"**
라는 착수 조건을 명시했다.

**그 측정이 이번에 끝났다.** 계측 결과("추측 아님"):

| 항목 | 실측 |
|---|---|
| 실제 경로 `ingestWatch` | `objectWillChange` **2회** — `recentWatchEvents` 1 + `pushEvent` 1 (문서와 일치 ✅) |
| `pushEvent` 의 추가 비용 | 인사이트 캐시 키 9종에 `recentEvents` 없음 → **캐시 적중, 재계산 0ms** |
| 남은 중복 신호의 계산 비용 | `AlertsView 0.15 + Dashboard 0.12 + serials 0.16 ≈ 0.43ms` = 프레임 예산의 **2.6%** |
| Swift 격리 프로브 | `assignOnce`(복사→1회 대입) **항상 1회** · `mutateInPlace`(in-place) 링 초과 시 **2회** |

→ **제안 1·2 가 문제를 실제로 없앴다.** 14개 View 전면 재매핑은 사라진 문제를 향한 작업이다.

## 1. 그런데도 하는 이유 — 축소판

전면 재매핑 대신 **중복 신호의 원인 필드 하나만** 뺀다. 계측이 지목한 전수 참조:

| 필드 | 읽는 View | 분리 비용 |
|---|---|---|
| `recentWatchEvents` | AlertsView · MenuBarPopoverView · DroidDashboardView · InsightsView (+ 위젯 sync) | **14개** — 손대지 않음 |
| `recentEvents` | **MenuBarPopoverView 하나 (3곳)** | **1개** |

`recentEvents` 만 `RecentEventsStore` 로 빼면 **View 1개 재매핑**으로 중복 신호가 통째로 사라진다.
리스크 등급이 "높음" → "낮음"으로 내려간다.

## 2. 부수 발견 — 디버그 경로가 실제보다 나쁘다

`debugIngestWatchQuietly`(DebugPanel 알림 주입 경로)가 in-place 변이라:

- 링이 가득 차면 `removeLast()` 가 **두 번째** `objectWillChange` 를 낸다 → **실제 경로 2회 vs 디버그 3회**
- `ConsoleStore.swift:912-914` 주석이 경고한 **"상한 501건 중간 상태"도 이 경로에서는 관측된다**

→ **체감 재확인 도구가 실제보다 나쁜 경로를 재고 있었다.** DebugPanel 로 알림을 몰아넣으면
실제와 다른 원인을 측정하게 된다. 실제 경로와 **같은 1회 대입 패턴**으로 통일한다.

## 3. 변경 범위

| 파일 | 변경 |
|---|---|
| `Sources/RelayConsole/App/RecentEventsStore.swift` | **신규** — 분리된 스토어 |
| `Sources/RelayConsole/App/ConsoleStore.swift` | `@Published recentEvents` 제거 · 상한 상속 · `pushEvent` 포워딩 · `debugIngestWatchQuietly` 1회 대입 통일 |
| `Sources/RelayConsole/Views/MenuBarPopoverView.swift` | `@ObservedObject recentEvents` 추가 · 읽는 곳 3곳 |
| `Tests/RelayConsoleTests/PublishedSignalTests.swift` | **신규** — 신호 횟수 회귀 고정 |
| `Tests/RelayConsoleTests/RefactorPart4Tests.swift` | 상한 상수 위치 변경 1줄 |

`pushEvent` 시그니처는 유지한다 → `DeviceMonitor.swift:929` 는 **손대지 않는다**.

## 4. 왜 신호 횟수를 테스트로 고정할 수 있나

`ConsoleStore` 는 `private init` 이라 테스트에서 격리 인스턴스를 만들 수 없다
(`swift test` 에러로 확인). 그래서 `shared` 에 의존하게 되는데,
**병렬 실행 잡음**이 걱정된다(→ `AlertsFilterTests` 가 이미 같은 이유로 델타 검증을 피했다).

**해결**: 신호를 세는 구간을 **동기 + `@MainActor`** 로 만든다. MainActor 는
조정하지 않으므로 `await` 이 없는 동기 구간에는 **다른 MainActor 태스크가 끼어들 수 없다.**
즉 이 테스트는 결정적이다. (`swift-testing` 병렬 실행과 무관)

## 5. 하지 않는 것

- `recentWatchEvents` 는 **분리하지 않는다** — 14개 View 재매핑. 계측 근거로 채택하지 않음
- `pushEvent` 제거 — `DeviceMonitor` 폴링 경로가 아직 씀
- `recentEvents` 를 `EventStore` 에 영속화 — 요청 범위 밖 (현재 메모리 전용이 의도된 설계)
- L10n 키 추가 — 새 사용자 문구 없음 (en/ko 766키 1:1 유지)

## 6. 검증

- `swift test` — 신호 횟수 1회 고정 + 기존 594건 무회귀
- `./scripts/build-macos.sh debug` — 번들 재생성·재서명·재시작
- L10n 766키 en/ko 1:1 · U+FFFD 0건
- **육안**: 알림 유입 시 다른 탭(설정·사이트)이 깜빡이지 않는지
