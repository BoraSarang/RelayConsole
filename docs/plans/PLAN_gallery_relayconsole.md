# PLAN_gallery_relayconsole.md — A4 파일/스샷 갤러리

> 생성일: 2026-09-24 | 상태: **구현 완료** (사용자 일괄 검토 대기) · bd: `RelayConsole-40v`
> 모체: `RESEARCH_competitive_v1` §8 **P3 (A4)** · ADB Studio·ADBOSS 벤치마크
> 앱: **Relay Console** | 목표 버전: **1.12.0** | 최소 OS: **macOS 26.0**

---

## 1. 목표

**로컬 스크랩북** — 현재 화면 스크린샷 저장 + 기기 `DCIM/Screenshots` 표준 폴러에서
이미지 파일 목록을 불러와 미리보기·저장·삭제·Finder 공개. 전체 파일 탐색기 아님.

| 기능 | 설명 |
|------|------|
| 저장 | `screencap` → `gallery/` PNG + 메타(시각·serial·source) |
| 기기 목록 | `ls` `/sdcard/DCIM/Screenshots` (png/jpg/webp) |
| 기기 pull | 선택 파일 `pull` → 갤러리에 저장 |
| 그리드 | 썸네일·필터(serial/all)·삭제·폴더 열기 |

### OUT
- 전체 파일 탐색기·아무 경로 브라우징 (TIER B) · 비디오 재생 · 기기 내 삭제 · iCloud

---

## 2. 범위

| IN | OUT |
|----|-----|
| `GalleryLogic` 순수 (필터·파싱·파일명) | 임의 path 셸 |
| `GalleryStore` (Application Support/gallery) | 기기 파일 삭제 |
| `GalleryController` (save/list/pull) | 비디오 |
| `GallerySheet` 그리드 시트 | Apple 기기 |

---

## 3. 설정키

| 키 | 타입 | 기본 | 설명 |
|----|------|------|------|
| — | — | — | 설정 토글 없음 (헤더 버튼) |

---

## 4. 모델·로직

```swift
// Sources/RelayConsole/Droid/Gallery.swift
enum GalleryLogic {
  static let imageExtensions: Set<String>  // png jpg jpeg webp heic
  static func isImage(_ name: String) -> Bool
  static func filter(_ names: [String], query: String) -> [String]
  static func parseLs(_ text: String) -> [String]
  static func localFileName(source: String, serial: String, at: Date) -> String
  static func listArgs(remoteDir: String) -> [String]  // shell ls -1
  static func pullArgs(remoteDir: String, file: String) -> [String]
}
struct GalleryEntry: Identifiable  // id, url, createdAt, serial?, source
@MainActor GalleryStore   // Application Support/RelayConsole/gallery/
@MainActor GalleryController // saveCurrent · listRemote · pullRemote
```

원격 표준 경로 고정: `/sdcard/DCIM/Screenshots`, `/sdcard/Pictures/Screenshots` (둘 다 시도, 합집합).

---

## 5. UI

- 대시보드 헤더: `갤러리` 버튼 → `GallerySheet`
- 시트: 상단 저장/기기에서 가져오기/폴더 · 검색 · 썸네일 그리드 · 행 삭제 · 필터

---

## 6. 파일 변경

| 파일 | 변경 |
|------|------|
| `Sources/RelayConsole/Droid/Gallery.swift` | Logic + Store + Controller (신규) |
| `Views/GallerySheet.swift` | 시트 (신규) |
| `Views/DroidDashboardView.swift` | 헤더 버튼 + sheet |
| `Tests/.../GalleryTests.swift` | 필터·파싱·파일명 |
| i18n 3처 | `gallery.*` |
| 버전 7처 | **1.12.0** |

---

## 7. DoD

- [x] 이미지 확장자 필터 · ls 파싱 · 파일명 안전 · 검색 필터 회귀 테스트
- [x] 저장(현재 스샷) · 기기 목록 · pull · 삭제 · Finder 공개
- [x] 대시보드 헤더 진입
- [x] i18n 3처 parity **529키** · 금지 grep 0 · `%s` 0
- [x] `swift test` **59 + 226** · `build-macos.sh debug` **1.12.0**
- [ ] 사용자 일괄 검토

---

## 8. 버전 1.12.0 동기화처

Info.plist · build-macos.sh(3) · AppDelegate · SettingsView · MenuBarPopoverView · AGENTS.local.md · README.md · McpProtocol.serverVersion
