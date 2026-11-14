# PLAN_file_browser_relayconsole.md — ADB 파일 탐색기 (읽기+전송)

> 생성일: 2026-09-25 | 상태: **구현·검증 완료 (육안 대기)** · bd: `RelayConsole-qy8`
> 모체: `RESEARCH_adb_file_browser` §6·§7 (범위·UI 형식 확정)
> 앱: **Relay Console** | 목표 버전: **1.16.0** | 최소 OS: **macOS 26.0**

---

## 1. 목표

메뉴바 팝오버에서 여는 **별도 탐색기 창** — 연결된 Android 기기의 `/sdcard` 계열 폴더를
`ls -la --full-time`로 탐색하고, **가져오기(pull)**·**드래그 전송(push)** 을 수행.

| 기능 | 설명 |
|------|------|
| 탐색 | 사이드바 즐겨찾기 + 상위/경로 직접 입력 · 컬럼 정렬(이름·크기·수정일, 폴더 우선) |
| 가져오기 | 선택 파일/폴더 → Mac 지정 폴더 (`relay.files.destDir`) · 중복 파일명 `name (1).ext` 회피 |
| 전송 | Finder → 창 드래그 → 현재 폴더 push (APK 포함) |
| 열기 | 더블클릭 파일(≤50MB) → pull 후 시스템 앱으로 열기 · 초과 시 [표시②] 안내 |

### OUT
- APK 설치(`adb install`) — `PLAN_app_hub` OUT 유지 (백로그) · 삭제·mv·mkdir · FUSE 마운트 · 영상 썸네일 · 텍스트 전체 검색

---

## 2. 범위 (IN / OUT)

| IN | OUT |
|----|-----|
| `FileBrowserLogic` 순수 (ls 파싱·경로·정렬·필터·고유파일명) | `adb install` |
| `FileBrowserController` IO (list/pull/push, stderr 노출) | 삭제·이동·mkdri |
| `FileBrowserWindowView` 창 (사이드바+컬럼+drop) | 시트/팝오버 내장 |
| 팝오버 푸터 실행 버튼 | 콘솔 헤더 버튼 (후속) |
| L10n ko·en `files.*` 19 + `menubar.button.files` | 영문 검색·썸네일 캐시 |

---

## 3. 설정키

| 키 | 타입 | 기본 | 설명 |
|----|------|------|------|
| `relay.files.destDir` | String | `~/Downloads` | 가져오기 대상 폴더 (창에서 변경) |

---

## 4. 모델 · 로직

```swift
// Sources/RelayConsole/Droid/FileBrowser.swift
enum FileBrowserLogic {
  struct Item: Identifiable, Equatable, Sendable {
    let name: String; let path: String; let isDir: Bool
    let size: Int64; let modified: Date?; let perms: String
    var id: String { path }
  }
  static let favorites: [(label: String, path: String)]  // Download·DCIM·Documents·Movies·Pictures·Android/data·tmp
  static func parseLs(_ text: String, dir: String) -> [Item]  // total·.·.. 제외, 심링크 " -> " 분리
  static func parseDateTime(date:time:tz:) -> Date?
  static func formatSize(_ bytes: Int64) -> String        // B/KB/MB/GB (1자리)
  static func sort(_:by:ascending:) -> [Item]             // 폴더 우선 + 키
  static func filter(_:query:) -> [Item]
  static func parentPath(_:) -> String?                   // "/" → nil
  static func join(dir:name:) -> String
  static func uniqueDest(dir:name:) -> String             // "a.png" → "a (1).png"
  static func shellQuote(_:) -> String                   // POSIX 싱글쿼트 — adb argv 무인용 방어 (RESEARCH §2 함정3)
  static func listArgs(dir:) -> [String]                 // ["shell", "ls -la --full-time '<path>/']" 단일 1argv (심링크 trailing slash)
  static func pullArgs(remote:local:) -> [String]
  static func pushArgs(local:remoteDir:) -> [String]
  static func previewAllows(size:) -> Bool                // ≤ 50MB
}
```

- 컨트롤러: `open(serial:)` → 목록, `navigate/refresh/up`, `pull(items)`, `push(urls)`
- I/O: `Process`로 adb 호출 — **실패 시 stderr 원문 + `E-MAC-ADB-0004/5/6`** ([표시②] · DebugLogger `[ERROR]`)

---

## 5. 화면 · 진입

- 창: `Window(id: "files")` + `WindowAccessor` identifier `files` (WindowFocus 패턴)
- 진입: **팝오버 푸터** — 기기 연결 시 folder 아이콘 버튼 → `openFiles()`
- 구조: 사이드바(즐겨찾기) │ 헤더(기기 identLabel([표시①])·경로·상위·새로고침·가져오기 폴더) │
  컬럼 헤더(정렬) │ 목록(더블클릭=진입/열기 · drop=push) │ 상태줄
- 토큰: `OPColor.popBG/card/ink/inkDim/border/cta/ok/bad` · `OPFont` · `OPSpace` (다크 고정 관제탑)

---

## 6. L10n (동일 키명 en·ko 동시 추가)

`files.column.modified|name|size` · `files.dest.change|title` · `files.empty` ·
`files.error.list|pull|push` · `files.hint.drop` · `files.nav.refresh|up` ·
`files.open.tooLarge` · `files.preview.pulling` · `files.pull.done|noSelection` ·
`files.push.done` · `files.status.listing` · `files.title` · `menubar.button.files`

에러코드: `error_message_ko.json`에 `E-MAC-ADB-0004`(목록)·`0005`(가져오기)·`0006`(전송) 추가

---

## 7. 테스트

`Tests/RelayConsoleTests/FileBrowserTests.swift` (swift-testing)
- ls 파싱: 파일·폴더·심링크·공백 이름·total/./.. 제외·오류 줄 무시
- 시각 파싱(nanosecond+tz) · formatSize · sort(폴더 우선) · filter
- parentPath/join · shellQuote(`'`·공백·한글) · listArgs trailing slash+인용 · uniqueDest 충돌 회피 · previewAllows

---

## 8. 검증 (HARD)

```bash
swift test
./scripts/build-macos.sh debug
```
- 버전 상향 1.16.0 (Info.plist · build-macos.sh · AGENTS.local · README · 팝오버 라벨)
- TODO.md 완료 등록 · push 실측(1바이트 `/data/local/tmp`) 포함

---

## 9. 후속 — 다중 선택·일괄 삭제 (2026-11-14)

> T-2026-11-14-1 · 브랜치 `feat/macos-file-multi-select`. 삭제는 1.25.0 에서 추가됐지만
> 선택 UI는 ⌘-클릭뿐이어서 "여러 파일을 한 번에" 라는 요구를 화면이 드러내지 못했다.
> 새 화면이 아니라 기존 목록의 선택 방식 확장이므로 별도 목업 없이 DESIGN 토큰(cta/border)만 사용한다.

| 항목 | 변경 |
|------|------|
| 선택 | 행 체크박스(15px) · 헤더 3상태 전체 선택(없음/일부/전체) · Shift 범위(위/아래) · ⌘+Shift 범위 추가 · ⌘ 토글 유지 |
| 표시 | 툴바 `N개 선택` 칩 + 선택 해제 · 다중 선택 우클릭은 `N개 삭제`/`N개 가져오기` |
| 안전 | 검색·새로고침으로 목록에서 사라진 항목은 선택에서 제거 — 숨은 파일 삭제 방지 |
| 삭제 | 항목별 실패를 계속 진행하고 `N개 삭제, M개 실패 — 첫 원인` 표시. 전부 실패면 원인 그대로 |
| 순수 로직 | `SelectAllState` · `selectAllState` · `toggling` · `rangeSelection` — `FileBrowserTests` 5건 |
| L10n | `files.select.all|row` · `files.selection.clear|count` · `files.action.deleteCount|pullCount` · `files.delete.partial|partialCount` |

검증: `swift test` **914/914** · `./scripts/build-macos.sh debug` 1.25.0(build `20261114.235045`) · 육안 `MANUAL_VERIFY` §41 127~132.

---

## 10. 후속 — 드래그 이동 (2026-11-15)

> T-2026-11-15-1 · 브랜치 `feat/macos-file-drag-move` (PR #146 위 스택).
> 사용자 결정: ① 기기 내부 이동 + Finder→폴더 전송 ② 충돌 시 **이동하지 않고 알림** ③ **같은 저장 영역만** 허용.

| 항목 | 변경 |
|------|------|
| 드래그 소스 | 행 전체(체크박스 포함) · `FileBrowserDragPayload`(커스텀 UTI `com.borasarang.relayconsole.filepaths`)에 **기기 내 경로만** 담음 |
| 드롭 대상 | **폴더 행만** — 대상 테두리 하이라이트(`isTargeted`) · 내부 경로 = 이동, Finder URL = 그 폴더로 push |
| 다중 이동 | 선택된 행을 끌면 `dragPaths` 가 목록 순서대로 **선택 전체**를 실어 감 |
| 덮어쓰기 금지 | `test -e` 사전 확인 → 있으면 건너뛰고 `files.move.exists` 표시. `mv -n` 은 race 용 안전장치(충돌 시에도 exit 0) |
| 이동 제한 | 같은 저장 영역만(`moveRoots`) · 자기 자신/하위 폴더 금지 · 사유별 문구(`crossRoot`/`intoSelf`/`forbidden`) |
| 부분 실패 | `N개 이동, M개 실패 — 첫 원인` · 성공분만 목록/트리 갱신 |
| L10n | `files.move.*` 7 · `files.drag.multiple` · `files.error.move` · `files.push.doneTo` |

검증: `swift test` **920/920** · `./scripts/build-macos.sh debug` 1.25.0(build `20261115.003826`) ·
실기기 확인(`mv -n` 충돌 시 덮어쓰지 않음·exit 0 / `test -e` 0·1) · 육안 `MANUAL_VERIFY` §42 133~138.
