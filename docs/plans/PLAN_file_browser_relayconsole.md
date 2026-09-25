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
