# PLAN — Prometheus /metrics 엔드포인트 (2026-09-28)

> 성격: **TIER A 착수** · TIER A 6개 중 "Prometheus/JSON export" 의 **Prometheus 쪽만**
> 관련: `docs/research/RESEARCH_competitive_v1.md` TIER A · `docs/TODO.md`
> 브랜치: `feat/macos-metrics-endpoint` (main 직접 push 금지 — [HARD])

---

## 0. 착수 전 계측 — "무엇이 없나" 를 먼저 잰다

TIER A 6개를 그대로 고르면 **이미 있는 걸 다시 만든다.** 먼저 훑는다.

| TIER A 항목 | 계측 결과 | 판정 |
|---|---|---|
| **Prometheus/JSON export** | `prometheus` 0 파일 · `/metrics` 0 파일 · **JSON export 는 있음**(`AlertsView.exportJSON()`, `alerts.export.json`) | ★ **Prometheus 쪽만 공백** |
| Things·캘린더 연동 | `EventKit` 0 파일 | 전무 — 단, **캘린더 TCC 권한 승인이 사람 손**에 있음 |
| 스샷 스크랩북 | `IncidentBundle`·갤러리 버튼 존재 | 부분 구현 |
| 멀티 스냅샷 그리드 | (갤러리에 종속) | 스냅샷 갤러리 이후 |
| cron 기기 태그 | `jobs.add.hint` 에 cron curl 안내만 존재 | 정의 자체가 흐림 |
| 충전 방치 리포트 | (grep 대상 불일치 — 미확인) | 미확인 |

**선택 근거 3가지**
1. **JSON export 는 이미 있다** → 남은 건 Prometheus 한쪽뿐. 중복 작업이 없다
2. **배관이 이미 끝나 있다** — `HeartbeatServer`(127.0.0.1 고정 TCP 서버)가 있다.
   `/metrics` 는 **라우팅 3줄**이면 붙고, 서버를 새로 만드는 위험이 없다
3. **완전히 자동 검증 가능하다** — `curl 127.0.0.1:8787/metrics` 로 끝난다.
   육안도, 기기도, 사용자 권한 승달도 필요 없다

배외: 캘린더 연동은 **구현은 되지만 검증이 사람 손**(TCC 승인)에 걸린다.
이번 세션의 원칙([HARD] 육안은 문서로 저장)에 따라 **순서를 미룬다.**

---

## 1. 범위 — "확장" 이 아니라 **"덮어쓰기"**

S3 와 같은 원칙: **있는 경로에 값을 얹는 것만** 한다.

### 1-1. 하는 것
- `GET /metrics` → Prometheus text exposition format (`text/plain; version=0.0.4`)
- 응답 본문을 만드는 **순수 함수** `MetricsTextBuilder.render(_:)` — store 없이 테스트 가능
- store 상태 → 스냅숏을 만드는 `MetricsSnapshotBuilder`(MainActor)
- `HeartbeatServer` 는 `onMetrics: @Sendable () -> String` 주입만 받는다 (**store 를 모른다**)

### 1-2. **안 하는 것** (이유 남김)
| 안 하는 것 | 이유 |
|---|---|
| 인증·TLS | loopback 고정(기존 `requiredLocalEndpoint`). 외부 노출이 아니다 |
| remote 바인드 | 위와 같은 이유로 배관에 이미 차단되어 있다 |
| 히스토그램·카운터 누적 | 저장소가 없다. **지어내면 없는 데이터**가 된다 |
| 설정 UI·L10n 키 | **화면이 없다** → 새 키 0개(키가 늘면 죽은 키 위험도 생긴다) |
| 규칙 추가 UI (S3 류) | S3 §9 와 동일 — **디버그 못 하는 규칙은 없는 규칙** |

---

## 2. 지표 집합 — **있는 것만** 낸다

재사용 가능한 판정 로직이 이미 있다. **새로 정의하지 않는다** (DRY + 값이 어긋나면 안 된다).

| 지표 | 값 | 재사용 |
|---|---|---|
| `relay_build_info{version,build}` | 1 | `Bundle` |
| `relay_heartbeat_up` | 1 | — |
| `relay_device_online{serial,model,kind}` | 0/1 (오프라인 기기도 **0 으로 낸다**) | `DeviceSnapshot.isOnline` |
| `relay_device_battery_percent{serial}` | `batteryLevel` (없으면 **행을 내지 않는다**) | `DeviceSnapshot.batteryLevel` |
| `relay_site_up{name,target}` | 0/1 (**판정 유보면 행 없음**) | `Site.effectiveUp()` |
| `relay_site_ssl_expires_in_seconds{name}` | 남은 초 (없으면 행 없음) | `Site.sslExpiresAt` |
| `relay_job_overdue_seconds{name}` | 기한 초과 초 (`isOverdue` 가 true 일 때만) | `Job.isOverdue(now:)` |
| `relay_job_beat_ok{name}` | 0/1/미수신 행 없음 | `Job.lastBeatOk` |
| `relay_alert_active_critical` | 활성 critical 수 | `BriefingLogic.activeCriticalCount` |

**라벨에 원시 토큰을 넣지 않는다** — 이름·모델은 사용자가 정한 값이므로 그대로 쓴다(AGENTS.local §4 [표시②] 와 충돌하지 않음: 이건 사람이 읽는 UI 가 아니라 기계가 읽는 지표다).

### 2-1. 값이 틀리는 경우를 정한다
- **배터리 미수신** → `0` 이 아니라 **행 없음**. `0%` 는 "확인했다가 0" 이라는 뜻이 된다
- **사이트 비활성** → `0` 이 아니라 **행 없음**. 끈 것을 죽은 것으로 세지 않는다
- **사이트 판정 유보** (`effectiveUp()` 이 nil) → **행 없음**. 한 번도 확인 안 한 것을
  "죽었다" 고 말하지 않는다
- **잡 미수신** → `relay_job_beat_ok` 행 없음 + `relay_job_overdue_seconds` 도 없음
- **오프라인 기기** → **행은 있고 값이 0**. 사라지면 "기기가 사라졌다" 와 구분되지 않는다
- **지표에 없는 것** → 지어내지 않는다. 없으면 없는 그대로

---

## 3. 구현 지점

| 파일 | 변경 |
|---|---|
| `Sources/RelayConsole/Jobs/MetricsText.swift` | **신규** — `MetricsSnapshot`(순수 입력) + `MetricsTextBuilder`(순수 출력) |
| `Sources/RelayConsole/Jobs/HeartbeatServer.swift` | `/metrics` 라우팅 + `onMetrics` 주입 |
| `Sources/RelayConsole/App/ConsoleStore.swift` | 2곳 `start()` 호출에 `onMetrics` 추가 |
| `Tests/RelayConsoleTests/MetricsTextTests.swift` | **신규** — 순수 함수 테스트 |
| `docs/DESIGN.md` | 지표 규칙 1절 |
| `docs/TODO.md` | T-2026-09-28-7 |

`MetricsSnapshot` 을 store 와 분리한 이유: builder 테스트가 **store·(MainActor) 없이** 돈다.
`Rule`/`RelayWidgetCore`/`ThresholdGate` 과 같은 전제다.

---

## 4. 검증 (DoD)

- [ ] `swift test` — 기존 660 유지 + 신규 전부 통과
- [ ] `./scripts/build-macos.sh debug` **EXIT=0**
- [ ] **종단간**: 앱 실행 → `curl 127.0.0.1:8787/metrics` → 실제 기기·사이트·잡 값이 나옴
- [ ] **404 가 유지됨** — `/hb/{token}` 이 깨지지 않았는지 (기존 경로 회귀)
- [ ] `scripts/scan-cjk.py` 0건
- [ ] 신규 크래시 0건
