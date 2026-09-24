# PLAN_app_hub_relayconsole.md — A3 앱 미니 허브

> 생성일: 2026-09-24 | 상태: **구현 완료** (사용자 일괄 검토 대기) · bd: `RelayConsole-mkk`
> 모체: `RESEARCH_competitive_v1` §8 **P2-2** · `PLAN_v0.7`
> 앱: **Relay Console** | 목표 버전: **1.8.0** | 최소 OS: **macOS 26.0**

---

## 1. 목표

연결 Android 기기의 **서드파티 앱을 메뉴바 콘솔에서 조회·런치·강제종료·삭제**한다.
B 카테고리(툴박스) 일부 흡수 — 전체 파일 탐색기·56종 툴박스는 OUT (TIER B 유지).

| 항목 | 내용 |
|------|------|
| 목록 | `pm list packages -3` → 패키지 검색·정렬 |
| 런치 | `monkey -p pkg -c android.intent.category.LAUNCHER 1` |
| 강제종료 | `am force-stop pkg` |
| 삭제 | `pm uninstall -k pkg` — 확인 대화상자 필수 |
| 진입 | 대시보드 헤더 **Apps** 버튼 → 시트 |

### OUT
- APK 추출·설치(adb install) · 권한·저장소 정리 상세
- 시스템 앱 전체 목록 (기본 3rd-party만, 토글로 system 포함 가능)
- 다중 선택 일괄 처리

---

## 2. 범위

| IN | OUT |
|----|-----|
| `AppHubLogic` 순수 (파싱·검증·검색·정렬) | APK 백업 |
| `AppHubController` IO (list/launch/stop/uninstall) | 설치(adb install) |
| `AppHubSheet` 시트 (검색·행 액션) | 사이드바 전용 탭 |
| 대시보드 헤더 Apps 버튼 | Apple |

---

## 3. 설정키

| 키 | 타입 | 기본 | 설명 |
|----|------|------|------|
| — | — | — | UI 노출 없음 (시트 메모리 상태만) |

---

## 4. 모델·로직

```swift
// AppHubLogic (순수 · 테스트)
static func parsePackages(_ text: String) -> [String]  // "package:com.x" → com.x
static func isValidPackage(_ s: String) -> Bool        // [a-zA-Z0-9_.] 최소 점 1개
static func filter(_ pkgs: [String], query: String) -> [String]  // 부분 대소문자 무시
static func sort(_ pkgs: [String]) -> [String]         // 알파벳
static func listArgs(includeSystem: Bool) -> [String]  // pm list packages [-3]
static func launchArgs(package: String) -> [String]    // monkey …
static func forceStopArgs(package: String) -> [String] // am force-stop
static func uninstallArgs(package: String) -> [String] // pm uninstall -k

// AppHubController (MainActor · ObservableObject)
@Published packages / loading / lastError / statusLine
func refresh(serial:includeSystem:)
func launch(serial:package:)
func forceStop(serial:package:)
func uninstall(serial:package:)
```

---

## 5. UI

- **헤더**: `square.grid.2x2` Apps 칩 → 시트
- **시트** `AppHubSheet`: 검색 TextField · 개수 · 새로고침 · 시스템 토글
- **행**: 패키지명 · Launch · Stop · Delete(확인)
- 상태 라인 (성공/오류 · i18n)

---

## 6. 파일 변경

| 파일 | 변경 |
|------|------|
| `Droid/AppHub.swift` | Logic + Controller (신규) |
| `Views/AppHubSheet.swift` | 시트 (신규) |
| `Views/DroidDashboardView.swift` | 헤더 버튼 + 시트 |
| i18n 3처 | `apphub.*` |
| `Tests/.../AppHubTests.swift` | Logic 신규 |
| 버전 7처 | **1.8.0** |

---

## 7. DoD

- [x] `parsePackages` · `isValidPackage` · `filter` · args 테스트
- [x] 목록 조회 · 런치 · 강제종료 · 삭제(확인) 코드·로직
- [x] i18n 3처 parity **484키** · 금지 grep 0 · `%s` 0
- [x] `swift test` **59 + 189** · `build-macos.sh debug` **1.8.0**
- [ ] 사용자 일괄 검토

---

## 8. 버전 1.8.0 동기화처

Info.plist · build-macos.sh(3) · AppDelegate · SettingsView · MenuBarPopoverView · AGENTS.local.md · README.md
