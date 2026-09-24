# PLAN_login_item_relayconsole.md — A8 로그인 항목 + 헤드리스

> 생성일: 2026-09-24 | 상태: **구현 완료** (사용자 일괄 검토 대기) · bd: `RelayConsole-njd`
> 모체: `RESEARCH_competitive_v1` §8 **P2-3**
> 앱: **Relay Console** | 목표 버전: **1.9.0** | 최소 OS: **macOS 26.0**

---

## 1. 목표

로그인 시 앱을 **자동 기동**하고, **헤드리스**로 시작(콘솔 창 없이 메뉴바만)해 "상주 관제" 경험(K2)을 완성한다.

| 항목 | 내용 |
|------|------|
| 로그인 항목 | `SMAppService.mainApp` register/unregister — 시스템 설정 토글과 동기화 |
| 헤드리스 | 시작 시 콘솔 윈도우를 열지 않고 accessory(메뉴바) 유지 · `relay.launch.headless` |
| 진입 | 설정 → 일반 → **시작** 그룹 |

### OUT
- Dock 배지·LSUIElement 해제 · 시스템 로그인 항목 UI 직접 열기(API 제한) · iOS
- LaunchAgent plist 수동 편집

---

## 2. 범위 (IN / OUT)

| IN | OUT |
|----|-----|
| `LoginItemLogic` 순수 (상태·메시지 키·headless 판정) | 다중 프로필/사용자 |
| `LoginItemController` IO (SMAppService) | 백그라운드 데몬 분리 |
| Settings 일반 토글 + 상태 라인 | 로그인 항목 환경설정 패널 deep-link |
| 헤드리스 시작 (창 미오픈) | 독 아이콘 표시 제어 |

---

## 3. 설정키

| 키 | 타입 | 기본 | 설명 |
|----|------|------|------|
| `relay.login.launchAtLogin` | Bool | false | 로그인 시 자동 시작 (SMAppService 상태 미러) |
| `relay.launch.headless` | Bool | true | 시작 시 콘솔 창 열지 않음 |

---

## 4. 모델·로직

```swift
// LoginItemLogic (순수 · 테스트)
static func statusKey(SMAppService.Status) -> String   // enabled/approval/off/notFound/unknown
static func messageKey(enabled: Bool) -> String        // on/off
static func errorKey(from: Error) -> String            // approval/failed
static func shouldOpenConsole(headless: Bool) -> Bool  // !headless

// LoginItemController (MainActor · ObservableObject)
@Published status / messageKey / busy
func refresh()
func setLaunchAtLogin(Bool)
```

`AppDelegate.applicationDidFinishLaunching`: `headless=false`이면 콘솔 창 오픈 (기본 headless=true → 창 없음).

---

## 5. UI

- 설정 → 일반 → `settings.startup.section`
  - 토글: 로그인 시 시작 (`settings.login.launch`) — SMAppService status Binding
  - 토글: 헤드리스 모드 (`settings.launch.headless`)
  - 상태 라인 (`settings.login.status.*` · 오류 시 `settings.login.error`)

---

## 6. 파일 변경

| 파일 | 변경 |
|------|------|
| `App/LoginItem.swift` | Logic + Controller (신규) |
| `App/AppDelegate.swift` | headless 판정 · refresh |
| `App/RelayConsoleApp.swift` | headless=false 시 콘솔 창 |
| `Views/SettingsView.swift` | 일반 섹션 토글 |
| i18n 3처 | `settings.login.*` · `settings.launch.*` · `settings.startup.*` |
| `Tests/.../LoginItemTests.swift` | Logic 신규 |
| 버전 7처 | **1.9.0** |

---

## 7. DoD

- [x] status/message/error/headless 테스트
- [x] 로그인 토글 ↔ SMAppService 동기화 코드
- [x] headless accessory 시작 · 기본 ON
- [x] i18n 3처 parity **496키** · 금지 grep 0 · `%s` 0
- [x] `swift test` **59 + 197** · `build-macos.sh debug` **1.9.0**
- [ ] 사용자 일괄 검토

---

## 8. 버전 1.9.0 동기화처

Info.plist · build-macos.sh(3) · AppDelegate · SettingsView · MenuBarPopoverView · AGENTS.local.md · README.md
