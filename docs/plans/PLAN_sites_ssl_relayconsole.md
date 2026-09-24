# PLAN_sites_ssl_relayconsole.md — A5 Sites SSL 만료 + HTTP assertion

> 생성일: 2026-09-24 | 상태: **구현 완료** (사용자 일괄 검토 대기)
> 모체: `RESEARCH_competitive_v1` §8 **P1-2** · `PLAN_sites_jobs` · `PLAN_sites_v1_1`
> 앱: **Relay Console** | 목표 버전: **1.5.0** | 최소 OS: **macOS 26.0**
> bd: `RelayConsole-2tt`

---

## 1. 목표

HTTPS 사이트의 **인증서 만료**와 **응답 본문 assertion**을 감시하고 Alerts·배너로 알린다.

| 항목 | 내용 |
|------|------|
| SSL 만료 | https 체크 시 인증서 notAfter 수집 → D-day 배지 · 만료 임박 시 `sslExpiring` |
| Assertion | HTTP 응답 body에 기대 문자열 포함 검사 — 실패 시 체크 fail |
| 알림 | `WatchKind.sslExpiring` (warning) · assert fail은 체크 fail로 기존 siteDown 경로 |
| 설정 | `relay.sites.sslWarnDays` (기본 14) |

### OUT
- 인증서 pinning · CA 검증 실패를 down으로 처리 (reachability 유지)
- whois 도메인 만료 (별 이슈 — rate limit·외부 의존)
- TCP/ping probe의 SSL

---

## 2. 범위 (IN / OUT)

| IN | OUT |
|----|-----|
| `Site.sslExpiresAt` · `Site.assertBody` | whois 도메인 만료 |
| `SiteCheck.sslExpiresAt` | pinning / OCSP |
| https 체크 시 Security로 notAfter 추출 | Apple·iOS |
| body 포함 assertion (HTTP only) | JSONPath·XPath assertion |
| Sites 행 SSL D-day 배지 · 폼에 assertion 필드 | 전용 Settings 탭 |
| `relay.sites.sslWarnDays` · Alerts 이벤트 | — |

---

## 3. 설정키

| 키 | 타입 | 기본 | 설명 |
|----|------|------|------|
| `relay.sites.sslWarnDays` | Int | 14 | 이 이하로 남으면 `sslExpiring` |

---

## 4. 모델 확장 (하위호환 decode)

```swift
// Site
var sslExpiresAt: Date?     // decodeIfPresent
var assertBody: String?     // decodeIfPresent — HTTP body must contain

// SiteCheck
var sslExpiresAt: Date?     // decodeIfPresent

// WatchKind
case sslExpiring
```

순수 로직 `SslAssertLogic`:
- `daysRemaining(expiresAt:now:)` → Int?
- `sslShouldWarn(expiresAt:now:warnDays:)` → Bool
- `assertBody(_ body: String, expected: String?)` → Bool

---

## 5. 체크 흐름

```
checkHTTP(https)
  → URLSession + trust challenge
  → notAfter → SiteCheck.sslExpiresAt
  → body contains assertBody? (nil이면 pass)
  → ok = HTTP status ∧ assertion

ConsoleStore.runSiteCheck
  → site.sslExpiresAt = check.sslExpiresAt (갱신)
  → emitSiteTransition (기존 down/up)
  → emitSslTransition (신규 — warn 임박 전이)
```

---

## 6. UI

- Sites 행: probe 배지 옆 `SSL D-12` (warn/bad 색) · 만료일 있으면 표시
- 사이트 폼: "본문 포함 문자열" TextField (HTTP 전용 힌트)
- Settings → 알림·작업: SSL 경고 D-day Stepper

---

## 7. 파일 변경

| 파일 | 변경 |
|------|------|
| `Models/SitesJobs.swift` | Site·SiteCheck 필드 · SslAssertLogic |
| `Models/WatchEvent.swift` | `sslExpiring` |
| `Sites/SiteChecker.swift` | https trust expiry · assertion |
| `App/ConsoleStore.swift` | sslExpiresAt 반영 · emitSsl · watchEnabled |
| `Views/SitesView.swift` | 배지 · 폼 assertion |
| `Views/SettingsView.swift` | sslWarnDays · about 1.5.0 |
| `Views/DebugPanelView.swift` | SSL 주입 (선택) |
| i18n 3처 | `sites.ssl.*` `event.site.sslExpiring` `settings.sites.*` |
| 버전 7처 | **1.5.0** |
| `Tests/.../SitesJobsTests.swift` | 하위호환 · SslAssertLogic |

---

## 8. DoD

- [x] https 체크가 sslExpiresAt 수집 (실패해도 HTTP up 유지)
- [x] assertion 미포함 시 체크 fail → failThreshold 경유 siteDown
- [x] warnDays 이내 → `sslExpiring` 1회 + 회복 시 clear
- [x] 기존 JSON 하위호환 (ssl 키 없음 decode OK)
- [x] i18n **439** 3처 · 금지 grep 0 · `swift test` **59+158** · `build-macos.sh debug` **1.5.0**
- [ ] 사용자 일괄 검토

---

## 9. 버전 1.5.0 동기화처

Info.plist · build-macos.sh(3) · AppDelegate · SettingsView · MenuBarPopoverView · AGENTS.local.md · README.md
