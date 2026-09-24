# PLAN_notify_channels_relayconsole.md — 외부 알림 채널 ntfy·Slack (A1)

> 생성일: 2026-09-24 | 상태: **완료** (육안 ✓ · PR #21 머지 `44e2cd6` · `avf` closed)
> 모체: `RESEARCH_competitive_v1.md` §4 A1 · `RESEARCH_watch_events.md` §3 [E]
> 앱: **Relay Console** | 목표 버전: **1.2.0** | 최소 OS: **macOS 26.0**
> bd: `RelayConsole-avf`

---

## 1. 범위 (IN / OUT)

| IN | OUT |
|----|-----|
| ntfy HTTP 발행 (서버·토픽·선택 Bearer 토큰) | 클라우드/SaaS 상태 페이지 |
| Slack Incoming Webhook (심플 텍스트) | 이메일 SMTP · 에스컬레이션 |
| `relay.notify.*` 설정 + 연동 탭 UI + 테스트 전송 | GRDB / 원격 설정 동기화 |
| 심각도 임계(warning/critical) + 복구 포함 토글 | 반복 mute/알림 규칙 빌더 |
| fingerprint 5분 쿨다운 재사용 (시스템 알림과 동일) | ack 연동 역방향 (Slack→Relay) |
| E-MAC-NOTIFY-0001 + 로그 마스킹 | 내장 미러링·Apple Phase 2 |
| i18n 3처 · 단위 테스트 · debug 빌드 1.2.0 | |

### 출처
- RESEARCH_watch_events §3 [E] ntfy 역푸시 (옵션)
- openstatus / Uptime Kuma 채널 패턴 (채택)
- 구 PLAN_v0.2 아카이브: 서버 사용자 입력·시크릿 하드코딩 금지

---

## 2. 설정키 (`relay.notify.*`)

| 키 | 타입 | 기본 | 설명 |
|----|------|------|------|
| `relay.notify.ntfy` | Bool | false | ntfy 채널 ON |
| `relay.notify.ntfy.server` | String | `""` | base URL (예: `https://ntfy.sh`) — **빈 값이면 미전송** |
| `relay.notify.ntfy.topic` | String | `""` | 토픽 (필수) |
| `relay.notify.ntfy.token` | String | `""` | 선택 Bearer 토큰 |
| `relay.notify.slack` | Bool | false | Slack 웹훅 ON |
| `relay.notify.slack.webhook` | String | `""` | Incoming Webhook URL |
| `relay.notify.minSeverity` | String | `warning` | `warning` \| `critical` |
| `relay.notify.recovery` | Bool | false | clear(복구) 이벤트도 전송 |

시크릿: 하드코딩 금지 · 로그/화면에 토큰·웹훅 원문 노출 금지 (마스킹).

---

## 3. 아키텍처

```
WatchEvent → ConsoleStore.ingestWatch
  ├─ 시스템 알림 (기존)
  ├─ 배너 (기존)
  └─ [신규] NotifyChannel.send(event)   // 쿨다운·필터 통과 시에만
        ├─ ntfy:  POST {server}/{topic}  (Title/Priority/Tags 헤더 + body)
        └─ slack: POST {webhook}         ({"text": "..."})
```

- **순수 빌더** `NotifyChannel` — 테스트 대상 (요약·필터·URL·헤더·우선순위)
- **전송** `URLSession` 백그라운드 · 실패 시 E-MAC-NOTIFY-0001 로그 (UI 크래시 금지)
- 쿨다운: 기존 `lastNotifiedAt` fingerprint(enter/clear 분리)와 **동일 경로** — 시스템 알림 발화 조건을 통과한 뒤에만 외부 발송

### ntfy 우선순위 매핑
| severity | ntfy Priority |
|----------|---------------|
| critical | 4 (high) |
| warning  | 3 (default) |
| info     | 2 (low) — 복구/정보 |

### Slack 텍스트
```
[critical] 제목 — 상세
source=android serial=…5555 kind=…
```
(시리얼은 UI와 동일하게 축약 · 전체 시리얼 로그 금지)

---

## 4. UI (설정 → 연동)

```
연동
├─ 외부 알림 채널
│   ☐ ntfy
│     server [____] topic [____] token [•••]
│   ☐ Slack 웹훅
│     webhook [•••]
│   최소 심각도: [경고 이상 | 치명만]
│   ☐ 복구 이벤트도 전송
│   [테스트 전송]
├─ Apple / scrcpy / Droid (기존)
```

---

## 5. 에러 코드

| 코드 | 의미 |
|------|------|
| `E-MAC-NOTIFY-0001` | ntfy/Slack 발행 실패 (HTTP≠2xx / 네트워크) |

---

## 6. DoD

- [ ] 순수 빌더 단위 테스트 (필터·우선순위·ntfy URL/헤더·Slack payload·마스킹)
- [ ] 설정 저장·재시작 유지
- [ ] 시스템 알림 경로와 동일 이벤트에서 외부 채널 발송 (debug 주인 경유)
- [ ] i18n ko/en/xcstrings 키 동치 · `%s` 없음
- [ ] 금지 grep 0 (신규 소스) · `print(` 는 DebugLogger만
- [ ] `swift test` 통과 · `./scripts/build-macos.sh debug` 1.2.0
- [ ] 사용자 육안 (설정 UI + 테스트 전송)

---

## 7. 버전 1.2.0 동기화처

`Resources/Info.plist` · `scripts/build-macos.sh`(3) · `AppDelegate` · `SettingsView` · `MenuBarPopoverView` · `AGENTS.local.md`
