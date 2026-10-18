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

---

## 9. 1.21.0 보강 (T-2026-10-17-8 · 2026-10-18)

> bd `RelayConsole-r07` · 리서치 v2 §4.2 M3 "번들 export 없음" · §5.2 P2-3
> dropbox **회수** 축은 `docs/plans/PLAN_dropbox_recovery_relayconsole.md` 로 분리했다.

### 9.1 dropbox 원문 첨부 (`dropbox.txt`)

logcat 이 놓친 ANR·크래시의 원문은 dropbox 에 남는다. 번들이 그 원문을 함께 갖도록 첨부를 추가했다.

- 후보 선별: `dumpsys dropbox` 목록 → **같은 종류 + 이벤트 시각 앞뒤 창**(앞 600초 · 뒤 300초) 최대 2건
- 본문: `--print '<정확한 시각>' | head -c 200000` — **앞을 남긴다**
  (`Process`·`Package`·`Subject`·트레이스 머리가 전부 앞이다. logcat 덤프가 `-T` 기준으로 **뒤를
  남기는** 것과 반대 방향인 이유)
- "항목 없음"과 "조회 실패"를 구분한다 — 모든 크래시가 dropbox 에 남지는 않으므로
  항목 없음은 정상이고 `failures` 에 적지 않는다(`DropboxBundleOutcome`).

### 9.2 실패 케이스 로깅 ([표시②])

종전 캡처는 `try?` 로 쓰기 오류를 **조용히 삼켰다.** 번들은 첨부가 없는데도 이유를 말하지 않았다.

| 자리 | 변경 |
|---|---|
| 첨부 쓰기 | 실패마다 `failures` 에 `"<파일>: <사유>"` 누적 |
| 스크린샷 | 캡처 실패·PNG 아님을 명시적으로 기록(조용한 누락 금지) |
| manifest | `schema` **2** + `failures: [String]?` — `files` 는 있는 것만 말하므로 **없는 이유**는 여기에만 있다 |
| manifest 쓰기 실패 | 번들의 **인덱스**가 없으면 목록·MCP 가 읽지 못한다 → 디렉터리를 되돌리고 실패 기록 |
| 로그 | `DebugLogger` warn(실패 n건 + 사유) / info(파일 n건) — Debug 패널에서 보인다 |
| 사용자 알림 | `lastCaptureError` → Alerts 배너(제목 "번들 캡처 실패", 본문에 사유 그대로) |
| MCP | `list_incidents` 가 `failures` 를 그대로 전달(있을 때만 키 생성) |

### 9.3 번들 내보내기

- Alerts 행에서 **캡처된 번들이 있을 때만** `square.and.arrow.up` 버튼이 함께 뜬다
  (디렉터리명이 이벤트에서 결정적으로 나오므로 행 → 번들 매칭이 정확하다).
- `NSSavePanel` 로 위치를 고르면 그 자리에 **번들 폴더를 만들어 파일을 복사**한다
  (원본은 그대로 — 내보내기가 원본을 옮기면 감시 이력이 사라진다).
- 이미 있는 이름이면 **덮어쓰지 않고** 사유를 띄운다.
- **zip 은 의도적으로 OUT** — 단일 아카이브는 `ditto` 같은 새 외부 프로세스를 요구한다.
  이 앱의 외부 프로세스는 adb·scrcpy 둘로 못 박혀 있다(공격면 관리).
  내보내기 목적은 "다른 곳에서 열어보기"이므로 원본 파일 그대로가 가장 정직하다.

### 9.4 검증

- 순수: `DropboxLogTests`(30건) · `IncidentBundleExportTests`(5건) · `IncidentBundleTests` manifest `schema 2`·`failures` · `McpProtocolTests` `list_incidents` failures
- 실기기: 픽스처·커맨드 대조(`PLAN_dropbox_recovery_relayconsole.md` §2·§5)
- 육안: `docs/MANUAL_VERIFY.md` §28 (69~72)

### 9.5 파일 변경 (1.21.0)

| 파일 | 변경 |
|------|------|
| `Incident/DropboxLog.swift` | **신규** — 목록·본문 파싱, 태그/패키지/사유 해석, 회수·창 선별, 커맨드 조립 |
| `Incident/IncidentBundleExport.swift` | **신규** — 폴더 복사 내보내기(덮어쓰기 금지) |
| `Incident/IncidentBundle.swift` | `failures` 누적 · `dropbox.txt` 첨부 · manifest `schema 2` |
| `Droid/DeviceMonitor.swift` | dropbox 회수(구조화 이벤트) — 종전 건수 알림 대체 |
| `Droid/AdbClient.swift` | `shellQuoted` 공용화 · `parseDropboxRecentTags` 제거(대체) |
| `Droid/FindPhone.swift` | `shellQuoted` → `AdbClient.shellQuoted` 위임 |
| `Views/AlertsView.swift` | 내보내기 버튼 · 배너(캡처 실패 포함) · `bundles` 관찰 |
| `RelayMcpCore/McpDataStore.swift` | `list_incidents` `failures` |
| i18n 2처 | `incident.export.*` · `incident.capture.failed*` (819/819) |

