# PLAN_sites_jobs_relayconsole.md — Sites·Jobs 사이드바 v1.0.0

> 생성일: 2026-09-24 | 상태: **완료** (육안 ✓ 2026-09-24 · Sites UI는 v1.1로 계승)
> 벤치마크: Uptime Kuma · Cronitor · Dead Man's Switch
> 앱: **Relay Console** | 버전: **1.0.0** | macOS 26.0
> 근거: `PLAN_v0.2_macos`(아카이브) · `docs/DESIGN.md` 상태바/스파크라인 토큰 · BrandKit "Sites & Jobs"
> 승인: 사용자 — 업타임+하트비트 · 1.0.0 · PR A/B 분할
> PR **#14** (A) + PR-B (화면)

---

## 1. 범위 (IN / OUT)

| IN | OUT |
|----|-----|
| Sites: HTTP·TCP·ping 업타임 체크 | 인증서 pinning · 자동 다운로드 |
| 90일 상태 바 + ms 스파크라인 (DESIGN) | 사용자 대시보드 공유 · 클라우드 동기화 |
| Jobs: 로컬 하트비트 수신(127.0.0.1) | 외부 노출 · ntfy/Slack 발행(다음) |
| overdue 판정(예정 주기 기준) | 반복 cron 파서 · 요일/시간 스케줄러 |
| Alerts 연동 (site down → WatchEvent) | Late/NoData 전용 심각도 |
| JSON 스토리지 · DEBUG 주입 · i18n | GRDB / SQLite |
| 설정: 체크 주기 · 하트비트 포트 | 사용자 규칙 빌더 |

### 출처 (채택 근거)

| 기능 | 출처 |
|------|------|
| 90일 상태 바 + 스파크라인 | Uptime Kuma · DESIGN.md v0.2 |
| HTTP/TCP/ping 3종 | Uptime Kuma · PLAN_v0.2 |
| 하트비트 overdue | Cronitor · Dead Man's Switch |
| Alerts 편입 | 현황 갭 (Alerts가 알림 중앙) |

---

## 2. 모델

```swift
enum SiteProbe: String, Codable, Sendable { case http, tcp, ping }

struct SiteCheck: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var at: Date
    var ok: Bool
    var latencyMs: Int?     // nil = 측정 불가(ping fail 등)
    var detail: String?     // 오류 한 줄 (마스킹 주의)
}

struct Site: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var target: String          // URL | host:port | host
    var probe: SiteProbe
    var intervalSec: Int        // 기본 60
    var enabled: Bool
    var history: [SiteCheck]    // 최근 90일 · 최대 300건
    var createdAt: Date
}

struct Job: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var token: String           // 하트비트 경로 토큰 (UUID 앞 8)
    var expectEverySec: Int     // 기본 3600
    var lastBeatAt: Date?
    var lastBeatOk: Bool?
    var enabled: Bool
    var createdAt: Date
}

// 판정
Site.isUp(now:)  → history.last 적합 (성공/최근 실패)
Job.isOverdue(now:) → lastBeatAt == nil || now - lastBeatAt > expectEverySec * 1.5
```

- 스토리지: `SitesStore` / `JobsStore` → Application Support JSON (EventStore 패턴)
- 하트비트 서버: `NWListener` 127.0.0.1 고정 · `POST/GET /hb/{token}` → Job 갱신
- Alerts: site down 전이 → `WatchEvent(source:.android 아님 → 신규 source 없음, kind 신규)`  
  → **`WatchKind.siteDown` / `jobOverdue` 추가**, source는 nil(android)로 두지 않고 **`WatchSource` 확장 불필요** — kind로 구분.  
  (결론: source는 기기용 유지. site/job은 serial="site:{id}" / "job:{id}"로 그룹핑)

---

## 3. 문서 위치

| 문서 | 위치 |
|------|------|
| PLAN | 본 문서 |
| TODO | `docs/TODO.md` 진행중 2줄 (Sites / Jobs) |
| DESIGN | 90일 상태바·스파크라인 이미 정의 — Sites 블루 `#4D99FF` · Jobs 앰버 `#FFB333` 사용 |
| API | `docs/api/HEARTBEAT.md` (하트비트 경로·응답) |
| error_message_ko.json | E-MAC-NET / E-MAC-JOB 추가 |

---

## 4. 성능 예산

- `rules/budgets.json` 참조 (Cold ≤1.5s, 메모리 ≤300MB)
- 체크: 기본 60초/사이트 · 백그라운드 Task · 동시 상한 8
- 하트비트 판정 30초 주기 루프 (또는 beat 수신 시 즉시)
- History cap: 사이트당 300건 / 90일 초과 순차 삭제
- 백그라운드에서도 URLSession invalidate

---

## 5. 에러 코드

| 코드 | 의미 |
|------|------|
| `E-MAC-NET-0001` | DNS/연결 실패 |
| `E-MAC-NET-0002` | 타임아웃 |
| `E-MAC-NET-0003` | HTTP 오류 상태 (4xx/5xx) |
| `E-MAC-NET-0004` | TCP 연결 실패 |
| `E-MAC-NET-0005` | ping 실패 / 툴 없음 |
| `E-MAC-JOB-0001` | 하트비트 서버 바인드 실패 |
| `E-MAC-JOB-0002` | 알 수 없는 토큰 |

매핑: `error_message_ko.json` + `ErrorCode` enum

---

## 6. 구현 순서 (PR)

| PR | 내용 |
|----|------|
| **A #14** | 모델·스토리지 · SiteChecker · HeartbeatServer · Alerts kind · 테스트 · HEARTBEAT.md · error_code |
| **B** | SitesView·JobsView · ConsoleView 연결 · 90일 상태바·스파크라인 · DEBUG 주입 · 설정 · i18n · **1.0.0** · 육안 |

---

## 7. 검증 (DoD)

- [x] `swift test` 통과 (SitesJobsTests 20종 포함)
- [x] 기존 EventStore JSON 하위호환 (Sites/Jobs 별도 파일)
- [x] debug 0 error · i18n **353/353/353** missing 0
- [x] 금지 grep 0 · 버전 **1.0.0**
- [x] `error_message_ko.json` 갱신 (E-MAC-NET/JOB)
- [x] 하트비트 바인드 127.0.0.1 고정
- [x] 육안 피드백 수정 — Sites 에딧·대상 검증 · Jobs curl 붙여넣기 토큰 import · `jobs.token`/`jobs.lastBeat` `%s`→`%@` 크래시 수정 · SitesJobsTests **25종** · i18n **365**
- [x] Sites: HTTP localhost 성공/실패 주입 · 상태 바 갱신 — **육안** (2026-09-24)
- [x] Sites: 잘못된 URL 거부 + 수정(에딧) 저장 — **육안** (2026-09-24)
- [x] Jobs: curl 하트비트 → lastBeat · overdue 표시 — **육안** (2026-09-24)
- [x] Jobs: 추가 시트 curl 붙여넣기 → 토큰 import — **육안** (2026-09-24)
- [x] site down → Alerts 반영 — **육안** (2026-09-24)

### 육안 순서

1. 디버그 → **Site down 주입** → Sites: 빨강 상태바 · Alerts에 siteDown
2. **Site up 주입** → 초록 복구 · Alerts 해소
3. 사이트 추가 (https://example.com, HTTP) → 즉시 체크 · ms 표시 · 잘못된 URL → 오류 메시지
4. 사이트 **연필(수정)** → 대상/주기 변경 저장 → 재체크
5. 작업 추가 → **curl 붙여넣기 영역** 확인 · 카드 curl 선택/복사 → 터미널 실행 → lastBeat 갱신 (과거 추가 직후 크래시 수정 확인)
6. **Job beat 주입** → OK 배지
7. 설정 → 하트비트 포트 변경 → 재시작 · Jobs 배너 갱신
8. 앱 재시작 → Sites/Jobs 유지

---

## 8. 백로그 (v2+)

- ntfy/Slack 알림 파이프
- 사용자 인증서 pinning
- 요일/시간 기반 cron 스케줄러
- Sites 그룹·태그 · 다중 하트비트 경로
