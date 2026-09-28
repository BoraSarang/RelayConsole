# PLAN — 충전 방치 리포트 (TIER A) (2026-09-28)

> 성격: **TIER A 착수 2건째** · `docs/TODO.md` "충전 방치 리포트" (0파일 = 진짜 공백)
> 관련: `PLAN_metrics_endpoint` (PR #61) · `PLAN_rules_yaml` (S3 · PR #59)
> 브랜치: `feat/macos-battery-neglect` (main 직접 push 금지 — [HARD])

---

## 0. 착수 전 계측 — TIER A 목록이 **현실과 달랐다**

TIER A 6개를 그대로 고르면 **이미 있는 걸 다시 만든다.** 이번에도 훑는다.

| TIER A 항목 | 계측 | 판정 |
|---|---|---|
| 스샷 스크랩북 | `GallerySheet.swift` **299줄** · 로컬 스크랩북 그리드·저장·기기 pull · L10n `"스샷 스크랩북"` | ★ **이미 구현됨** |
| 멀티 스냅샷 그리드 | `LazyVGrid` + `GridItem(.adaptive(minimum: 110))` | ★ **이미 구현됨** |
| 충전 방치 리포트 | `neglect`·`lowSince` **0 파일** | ★ **진짜 공백** |
| cron 기기 태그 | `deviceTag`·`tagRule` **0 파일** | 공백이지만 **정의가 흐림** → 사용자 확인 필요 |
| Things·캘린더 | `EventKit` 0 파일 | 공백 — 검증이 사람 손(TCC) |
| Prometheus/JSON | PR #61 에서 완료 | — |

→ **충전 방치**가 "비어 있고, 정의가 분명한" 유일한 항목이다.

---

## 1. 왜 기존 배터리 규칙으로는 부족한가

`WatchEngine.feedBatteryLevel` 는 **20/10/5% 순간 임계**다. 문제는:

- 20% 를 **한 번** 가로지르면 알림이 울리고, **충전 재상승 시 재무장**된다
- 그러므로 **"이 기기는 6시간째 15% 에 머물러 있다"** 를 말하지 못한다
- 그게 바로 **방치**다 — 기기가 위험한 게 아니라 **아무도 충전하지 않았다**는 사실

즉 순간 임계로는 **시간 축 정보가 없어** 표현할 수 없다. 방치는 **지속 시간**의 문제다.

### 데이터는 이미 있다
`DeviceSnapshot` 에 `batteryLevel: Int?` · `isCharging: Bool?` · `measuredAt: Date?` 가 있다
(`DeviceMonitor` 가 5초 주기로 채운다). **새로 수집할 것은 하나도 없다.**

---

## 2. 범위 — "확장" 이 아니라 **"덮어쓰기"**

### 2-1. 하는 것
- `BatteryNeglectTracker` — **순수 상태 기계**. `(serial, level, charging, now)` 을 먹고
  "방치 시작 시각" 을 기기별로 유지한다. 시간원은 **주입**된다(테스트가 시계를 못 쓰게)
- `RulesConfig` 에 `battery:` 블록 — `neglectPercent` / `neglectMinutes` 를 **사용자가 정한다**
  (S3 와 같은 입구. 새 하드코딩 임계값을 만들지 않는다)
- 지표 `relay_device_battery_neglect_seconds{serial}` — **방치 중인 기기만** 행을 낸다

### 2-2. **안 하는 것** (이유 남김)
| 안 하는 것 | 이유 |
|---|---|
| **기기 카드 UI** | ★ 실기가 **충전 중**(`AC powered: true`)이라 "방치 진입" 화면을 **볼 수 없다.** 검증 못 하는 화면은 이 프로젝트에서 "없는 것" 과 같다 (§9 참고) |
| **새 알림 종류**(`batteryNeglect`) | `WatchEvent` 종류를 늘리면 지문·전이·Alerts·Insights 가 같이 흔들린다. 이번 PR 범위를 넘는다 |
| 방치 **해소** 알림 | 진입만 지표로 알린다. 알림 파이프라인 확장은 별건 |
| `precondition` 을 이용한 강제 | `Rule.enter > clear` 불변식에 **손대지 않는다** (S3 §15-1 의 교훈) |

---

## 3. 왜 `Rule` 이 아니라 별도 구조인가

`Rule` 은 `enter > clear` hysteresis 불변식 + 쿨다운 용도다. 방치는
**임계 1개 + 지속 시간**이라 clear 가 없다. `Rule` 에 억지로 넣으면
"가짜 clear" 를 만들어 `precondition` 검증과 싸우게 된다.

→ `RulesConfig.Battery(percent:minutes:)` 를 **별도** 둔다. 불변식이 겹치지 않는다.

---

## 4. 정직성 규칙 (DESIGN §7 을 그대로 적용)

| 경우 | 한 것 | 이유 |
|---|---|---|
| 배터리 미확신 (`nil`) | 방치 아님으로 처리 — `since` **유지**(단정하지 않음) | 모르는 것을 "방치" 라고 하지 않는다 |
| 충전 중 | `since` **초기화** | 충전이 방치를 끊는다는 뜻이다 |
| 임계 초과 → 충전 → 다시 하강 | **새로 시작** | 방치는 "중간에 충전이 있었냐" 로 갈린다 |
| 방치 중이지만 | **행 없음** | "방치 중" 인 기기만 |
| 만료(`minutes`) | ★ **이번 PR 에서 알림 안 함**(§2-2) — 지표만 | 알림은 별건 |

**중요**: 배터리 `nil`(미확인)일 때 `since` 를 **유지**하는 것과 **지우는** 것 중 무엇이
옳은가 — 미확인 구간이 방치를 끊는다고 볼 근거가 없다. **유지**가 정직하다.

---

## 5. 구현 지점

| 파일 | 변경 |
|---|---|
| `Droid/BatteryNeglectTracker.swift` | **신규** — 순수 상태 기계 |
| `Droid/RulesConfig.swift` | `Battery` 구조 + `battery:` 파싱/검증 |
| `Jobs/MetricsText.swift` | `relay_device_battery_neglect_seconds` |
| `Jobs/MetricsSnapshotBuilder` | 트래커 결과 → 스냅숷 |
| `Tests/…/BatteryNeglectTests.swift` | **신규** — 파서 + 상태 기계 + 지표 |
| `docs/DESIGN.md` §7 · `docs/TODO.md` · 세션 로그 | 갱신 |

---

## 6. 검증 (DoD)

- [ ] `swift test` — 689 유지 + 신규 통과
- [ ] `./scripts/build-macos.sh debug` **EXIT=0**
- [ ] **미방치 종단간**: 실제 기기가 충전 중 → `relay_device_battery_neglect_seconds` **행이 없음**을 `curl` 로 확인
- [ ] **참조 종단간**: 순수 상태 기계 테스트 + 지표 렌더 통합 테스트로 고정.
      **실기로는 못 본다** — 이유를 PR 본문에 적는다
- [ ] `rules.yaml` **없을 때** 기본값(20% / 120분)으로 동작 + 배너에 "기본값" 표시
- [ ] `scripts/scan-cjk.py` 0건 · 신규 크래시 0건

## 7. 미해결로 남길 것
- **방치 진입 UI** — 실기가 충전 중이라 검증 불가. 사용자가 실제 방치 상황(또는
  충전기 분리)에서 보면 확인된다. **재현 절차를 TODO 에 적는다.**
