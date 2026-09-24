# PLAN_incident_bundle_relayconsole.md — S4 Incident Bundle

> 생성일: 2026-09-24 | 상태: **구현 완료** (사용자 일괄 검토 대기) · bd: `RelayConsole-5cr`
> 모체: `RESEARCH_competitive_v1` §8 **P2-1** · `PLAN_alerts` · `PLAN_v0.8`
> 앱: **Relay Console** | 목표 버전: **1.7.0** | 최소 OS: **macOS 26.0**

---

## 1. 목표

ANR·크래시·사이트 down 발생 시 **로컬 incident 번들**을 자동(또는 수동) 캡처한다.
번들 = `manifest.json` + 해당 시점 logcat 덤프 + 스크린샷(Android) — Alerts에서 열기·Finder 공개.

| 항목 | 내용 |
|------|------|
| 자동 캡처 | `ingestWatch` 진입 시 `relay.incident.auto` ON이면 fingerprint 5분 쿨다운 |
| 수동 캡처 | Alerts 행 → `bundle` 버튼 (대상 kind 한정) |
| 번들 내용 | manifest(이벤트 원본 JSON) · logcat(연결 기기) · screenshot.png(연결 기기) |
| 표시 | Alerts 툴바 링크 · `NSWorkspace`로 폴더 열기 |

### OUT
- zip/공유 업로드 · 클라로 전송
- Apple 기기 logcat(없음 — manifest만)
- 백그라운드 상시 logcat 스트림 보존(기존 커서 기반 감시 유지)
- 번들 자동 정리 UI (수동 삭제 — Finder)

---

## 2. 범위 (IN / OUT)

| IN | OUT |
|----|-----|
| `IncidentBundleLogic` 순수 (대상 판별·디렉터리명·쿨다운·manifest) | zip archive |
| `IncidentBundleStore` IO (쓰기·목록·Finder·수동 캡처) | 클라우드 동기화 |
| `ConsoleStore.ingestWatch` 훅 (자동) | 실시간 logcat 길게 캡처 |
| Alerts 행 bundle 버튼 · 툴바에서 폴더 열기 | 전용 사이드바 탭 |
| Settings `relay.incident.auto` | — |

---

## 3. 설정키

| 키 | 타입 | 기본 | 설명 |
|----|------|------|------|
| `relay.incident.auto` | Bool | true | ANR/crash/siteDown 자동 번들 캡처 |

---

## 4. 모델·로직

```swift
// IncidentBundleLogic (순수 · 테스트)
static func captures(kind: WatchKind) -> Bool  // anr | crash | siteDown
static func directoryName(event:at:) -> String // 20260924-195900-<kind>-<short>
static func shouldAutoCapture(event:now:lastAt:) -> Bool // 5분 쿨다운
static func manifestData(event:related:) -> Data? // pretty JSON + iso8601

// IncidentBundleStore (MainActor · ObservableObject)
static let shared
@Published bundles: [BundleEntry]
var rootURL: URL  // Application Support/RelayConsole/incidents/
func reload()
func capture(event: WatchEvent, adbPath: String?) // async 백그라운드 쓰기
func openRoot()  // NSWorkspace
func reveal(_ entry: BundleEntry)
```

호출:
```
ConsoleStore.ingestWatch(event)
  → guard !event.isClear, IncidentBundleLogic.captures(kind)
  → guard incidentAuto, shouldAutoCapture
  → IncidentBundleStore.capture(event, adbPath: DeviceMonitor.adbPathNow())
```

capture 세부 (ioUtility):
1. 디렉터리 생성 `incidents/<dirName>/`
2. `manifest.json` — WatchEvent(+관련 note) + capturedAt + appVersion
3. Android serial (`:` 없음·apple 아님)이면:
   - `adb -s S logcat -d -t 500 -v time` → `logcat.txt`
   - `adb -s S exec-out screencap -p` → `screenshot.png`
4. 실패 파일은 건너뛰고 manifest는 항상 씀
5. `reload()` 로 목록 갱신

---

## 5. UI

- **Alerts 이벤트 행**: `captures(kind)` && !isClear → `photo.on.rectangle` 버튼 (수동 캡처)
- **Alerts 툴바**: `Incident bundles` — `folder` 아이콘 → `openRoot()`
- **Settings → 감시 알림**: `settings.incident.auto` 토글 (fatal 섹션 아래)

---

## 6. 파일 변경

| 파일 | 변경 |
|------|------|
| `Incident/IncidentBundle.swift` | Logic + Store (신규) |
| `App/ConsoleStore.swift` | `@AppStorage relay.incident.auto` + ingestWatch 훅 |
| `Views/AlertsView.swift` | 행 버튼 · 툴바 열기 |
| `Views/SettingsView.swift` | 토글 |
| i18n 3처 | `incident.*` · `settings.incident.*` |
| `Tests/.../IncidentBundleTests.swift` | Logic 신규 |
| 버전 7처 | **1.7.0** |

---

## 7. DoD

- [x] `captures` · `directoryName` · `shouldAutoCapture` · `manifestData` 테스트
- [x] ingestWatch 자동 캡처 (온/오프·쿨다운)
- [x] Alerts 수동 캡처 + 폴더 열기
- [x] i18n **466** 3처 parity · 금지 grep 0 · `%s` 0
- [x] `swift test` (XCTest **59** + swift-testing **179**) · `build-macos.sh debug` **1.7.0**
- [ ] 사용자 일괄 검토

---

## 8. 버전 1.7.0 동기화처

Info.plist · build-macos.sh(3) · AppDelegate · SettingsView · MenuBarPopoverView · AGENTS.local.md · README.md
