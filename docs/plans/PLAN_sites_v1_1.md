# PLAN_sites_v1_1.md — Sites 업타임 재정의 (로컬 UptimeRobot + Google식 타임라인)

> 생성일: 2026-09-24 | 상태: **완료** (육안 ✓ · PR #17 머지 `c383887`)
> 벤치마크: **UptimeRobot** (모니터·임계값·상태 유지시간) · **Google Apps Status Dashboard** (행×기간 바·범례·incident)
> 앱: **Relay Console** | 버전 목표: **1.1.0** | 선행: `PLAN_sites_jobs` 1.0.0 (체크 엔진·Alerts 연동)
> 승인: 사용자 — 타임라인 메뉴바 7d/콘솔 7·30d 토글 · Jobs 유지(폭오버 합침 표시) · down=연속 2회

---

## 1. 목표 재정의

| 항목 | 1.0.0 | **1.1.0** |
|------|-------|-----------|
| 정체 | 카드형 업타임 | **로컬 UptimeRobot** — 관리 서버/사이트 생사 감시 |
| 표시 | 최근 90**회** 상태 바 | **Google식 서비스 행 × 날짜 세그먼트** + 가동률% |
| down 판정 | 1회 실패 = down | **연속 N회 실패**(기본 2) — flapping 방지 |
| 즉시성 | 콘솔 탭 | **메뉴바 폭오버에 Sites 섹션** + 기존 알림·배지 |
| 개인정보 | — | 전부 로컬 (외부 전송 없음) |

Jobs(하트비트)는 **모델·탭 유지**. 폭오버에만 사이트와 함께 한 줄로 표시.

---

## 2. 범위 (IN / OUT)

| IN | OUT |
|----|-----|
| `failThreshold` 연속 실패 판정 (1~5, 기본 2) | 클라우드 SaaS · 외부 상태 페이지 |
| 현재 상태 유지시간 (`stateSince`) | 이메일/웹훅 알림 (백로그) |
| 가동률% (7d·30d 창) | SSL/도메인 만료 감시 |
| 일 단위 DayBar (7/30일) Google식 | 4색 전이 (정보/장애 구분 — 3단계부터) |
| 콘솔 Sites 행 UI 재설계 + 7d/30d 토글 | 그룹·태그 |
| 메뉴바 폭오버 Sites 섹션 (7일 바) | 상태 페이지 공유 |
| Sites 추가/수정 폼에 임계값 스테퍼 | 반복 알림 주기 |

---

## 3. 모델 (SitesJobs.swift)

```swift
// Site 추가 필드
var failThreshold: Int          // 1...5, 기본 2 — decode 시 키 없으면 2

/// 연속 실패 ≥ failThreshold 전까지 up 유지
func effectiveUp() -> Bool?     // history 없으면 nil

/// 현재 effective 상태가 시작된 시각 (상태 유지시간용)
func stateSince() -> Date?

/// 창 가동률 % (0...100) — 체크 0건이면 nil
func uptimePercent(since: Date) -> Double?

/// 일 단위 집계 (과거→최신) — Google 행 바
enum DayBarStatus { case unknown, up, down, partial }
func dayBars(days: Int, now: Date) -> [(date: Date, status: DayBarStatus)]
```

- `isUp()` → **raw 최신 체크** 유지 (기존 테스트 호환)
- 알림·상태 dot → `effectiveUp()`
- 상태 바(회색 없음) → `recentBars()` raw 유지 **or** 콘솔은 `dayBars` 사용

### down 전이 (ConsoleStore)

`emitSiteTransition`이 `check.ok` 대신 **append 후 `site.effectiveUp()`** 로 before/after 비교.  
DEBUG down 주입: `failThreshold`만큼 연속 실패 append → 전이 발생.

---

## 4. UI

### 4.1 콘솔 · Sites (Google식 축소판)

```
사이트 4개          [7일|30일]  [+ 추가]
● 정상  ● 장애  ○ 데이터 없음
────────────────────────────
● 결제API   HTTP  99.8%  42ms   ████████████
● PG primary TCP  down 3m  —    ████░░██████
○ 스테이징   PING  —      —      ○○○○○○○○○○○○
────────────────────────────
진행 중: PG primary · 14:20~
[기존 카드 액션: 토글·연필·↻·삭제는 행 유지]
```

- 행: 상태점 · 이름 · probe · 가동률%(또는 ms) · **날짜 세그먼트 바** · 액션
- 세그먼트: `dayBars` — up=ok · partial=warn · down=bad · unknown=inkDim 20%
- 상단: 진행 중 siteDown (미해결 WatchEvent serial `site:`)
- 폼: 기존 + **연속 실패 임계값** Stepper 1...5

### 4.2 메뉴바 폭오버 (360px)

- `store.sites` 비어 있으면 섹션 숨김
- 헤더: `Sites  3 up · 1 down` (down>0이면 빨강)
- 행 최대 5: 점 · 이름 · (up 2h / down 3m / ms) · 7일 미니 바
- overdue Jobs는 기존과 별개 — 사이트 아래에만 `Jobs` 한 줄 요약 (있는 경우)
- down 존재 시 기존 critical 배지·시스템 알림 재사용 (변경 없음)

---

## 5. PR 분할

| PR | 내용 |
|----|------|
| **C1** | 모델 `failThreshold`·`effectiveUp`·`stateSince`·`uptimePercent`·`dayBars` · 전이 수정 · DEBUG 주입 · 테스트 |
| **C2** | SitesView 행 UI · 7d/30d 토글 · 임계값 폼 · incident 카드 · i18n |
| **C3** | MenuBarPopover Sites 섹션 · i18n · 육안 · **1.1.0** |

---

## 6. 성능·안전

- dayBars: history ≤300 · O(n·days) 무시 가능
- 체크 루프·동시 상한 8 기존 유지
- sanitizeTarget 기존 유지 (query/userinfo 제거)
- 금지 grep · `print(` DebugLogger only

---

## 7. DoD

- [x] `swift test` 통과 (SitesJobsTests 신규 threshold·effectiveUp·dayBars·uptimePercent 포함 · swift-testing 139)
- [x] i18n 3곳 **382** 키 일치 · missing 0
- [x] 금지 grep Sources 기존 허용만 · 버전 **1.1.0**
- [x] `./scripts/build-macos.sh debug` 완료 (1.1.0 재설치)
- [x] 육안 (사용자 확인 2026-09-24):
  - [x] 연속 1회 실패는 up 유지, 2회째에만 down 알림
  - [x] Sites 콘솔: 행×날짜 바 · 7d/30d 토글 · 가동률% · 범례/패딩 정렬
  - [x] 메뉴바 폭오버에 Sites 요약 · down 시 빨강
  - [x] Jobs 탭·하트비트 기존 유지

---

## 8. 백로그

- ntfy/Slack/Webhook · 반복 알림 주기
- 4색 범례(정보/장애) · 90일 캘린더 뷰
- 그룹/태그 · 다중 하트비트 경로 통합 표시
