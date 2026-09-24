# PLAN_sites_calendar_relayconsole.md — A6 Sites 90일 캘린더 + 그룹/태그

> 생성일: 2026-09-24 | 상태: **구현 완료** (사용자 일괄 검토 대기) · bd: `RelayConsole-9vi`
> 모체: `RESEARCH_competitive_v1` §8 **P3 (A6)** · Uptime Kuma 벤치마크
> 앱: **Relay Console** | 목표 버전: **1.13.0** | 최소 OS: **macOS 26.0**

---

## 1. 목표

Sites 목록에 **태그 그룹 필터**와 **90일 캘린더 뷰**(주 단위 격자·일 단위 상태 색)를 추가한다.
범위 폭주 주의 — 태그 문자열·필터·캘린더 셀만.

| 기능 | 설명 |
|------|------|
| 태그 | `Site.tags: [String]` (JSON 하위호환 기본 `[]`) |
| 필터 칩 | 전체 + 고유 태그 · 다중 선택 AND |
| 캘린더 | 90일 · 주 7열 · `dayBars` 재사용 · 오늘 강조 |

### OUT
- 태그 색상 편집 · 다중 사이트 일괄 편집 · 캘린더 클릭 상세 · 그룹 폴더 히라키

---

## 2. 범위

| IN | OUT |
|----|-----|
| `Site.tags` + 폼 태그 입력 (쉼표 구분) | 태그 관리 UI 별도 |
| `SitesCalendarLogic` 90일 격자·필터 | 히스토리 DB |
| 리스트 ↔ 캘린더 토글 | Apple Sites |

---

## 3. 설정키

| 키 | 타입 | 기본 | 설명 |
|----|------|------|------|
| — | — | — | 뷰 모드는 세션 `@State` |

---

## 4. 모델·로직

```swift
// Site
var tags: [String]  // decodeIfPresent ?? []

// SitesCalendarLogic
static func parseTags(_ raw: String) -> [String]
static func formatTags(_ tags: [String]) -> String
static func allTags(_ sites: [Site]) -> [String]
static func filter(_ sites: [Site], selectedTags: Set<String>) -> [Site]
static func calendarDays(days: Int = 90, now: Date, calendar: Calendar) -> [Date]
static func weekdayHeaders(calendar: Locale) -> [String]
```

필터: 선택 태그가 **전부** 포함된 사이트만 (AND).

---

## 5. UI

- 헤더: 리스트/캘린더 segmented · 태그 칩 행(스크롤)
- 캘린더: 주차 라벨(월/일) + 7열 셀 · 상태색은 합산(하나라도 down=bad, partial=warn, 전부 ok=ok, 없음=unknown)
- 폼: 태그 TextField 쉼표 구분

---

## 6. 파일 변경

| 파일 | 변경 |
|------|------|
| `Models/SitesJobs.swift` | `tags` + `SitesCalendarLogic` |
| `Views/SitesView.swift` | 칩·캘린더·폼·토글 |
| `Tests/.../SitesCalendarTests.swift` | 파싱·필터·격자 |
| i18n 3처 | `sites.cal.*` · `sites.tag.*` |
| 버전 7처 | **1.13.0** |

---

## 7. DoD

- [x] 태그 파싱·필터 AND·캘린더 90일·요일 헤더 회귀 테스트
- [x] 기존 JSON(`tags` 없음) 디코드 하위호환
- [x] 리스트/캘린더 전환 · 태그 칩 필터
- [x] i18n 3처 parity · 금지 grep 0 · `%s` 0
- [x] `swift test` 통과 · `build-macos.sh debug` **1.13.0**
- [ ] 사용자 일괄 검토

---

## 8. 버전 1.13.0 동기화처

Info.plist · build-macos.sh(3) · AppDelegate · SettingsView · MenuBarPopoverView · AGENTS.local.md · README.md · McpProtocol.serverVersion
