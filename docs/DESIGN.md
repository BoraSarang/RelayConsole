# DESIGN.md — 디자인 시스템
> 언어: 한국어 (문서), 앱 표시 언어: ko+en (PLAN_v0.4, 설정에서 수동 선택)

## 1. design_profile
- custom (관제탑 Mission Control)

## 2. 플랫폼별 가이드
- macOS 메뉴바 상주 (LSUIElement), 팝오버 + 콘솔 윈도우. 설정·디버그 패널은 native.

## 3. 토큰 (custom일 때)
- 모드: 시스템/다크/화이트 3종, 기본 시스템 추종 (`ThemeManager`, `AppStorage themeMode`)
- 색상 (다크 / 라이트):
  - 베이스: abyss #0D1220 / #F4F6FB, panel #171E31 / #FFFFFF, panelHi #212945 / #E8EDF6, ink #EBF0FA / #131A2B, inkDim #9EADC7 / #5A6A86
  - 도메인: droid 그린 #33D973 (공통), apple 실버 #D9E0F2 / #3E4A68 (라이트 대비 확보), sites 블루 #4D99FF, jobs 앰버 #FFB333, notify 퍼플 #B373FF
  - 상태: ok=그린, warn=앰버, bad=#FF4D52 / #D81E26 (라이트)
- 시맨틱 별칭: `background/surface/surfaceHi/text/textDim` = 모드별 해석, 기존 `abyss/panel/...` 호출 호환 유지
- 텍스트 안전색 (v0.6, 흰배경 AA 4.5:1 실측): droidLight #147A3D·sitesLight #0D52CC·jobsLight #996105·notifyLight #662EC7 — 본문 텍스트에는 `*For(scheme)`만 사용, 원색은 채움·글로우 전용
  - 실측: droidLight 5.4:1, sitesLight 6.8:1, jobsLight 5.2:1, notifyLight 7.6:1
- 게이트 단계(OPSteps): done=그린✓, active=블루 테두리, locked=회색🔒+60% 투명, 잠금은 탭 불가·내용 표시
- 폰트: UI=SF Rounded Bold(제목), 숫자=SF Mono Semibold
- 간격: xs4 / sm8 / md12 / lg16 / xl24, 모서리 12 continuous
- 상태 표현: 글로우 닷(정상 은은·장애 강조), 90일 상태 바(v0.2), 링/바 게이지, 스파크라인(v0.2)
  - 상태 바: 최근 N건 결과를 초록/빨강 막대로 나열, 호버 시 시각·사유 툴팁
  - 스파크라인: 응답속도(ms) 미니 라인, 최신값 숫자 병기 (SF Mono)

## 4. 시스템 UI (프로필 무관 native)
- 설정창, 디버그 패널, 권한 요청 화면, 알림

## 5. 검색 · 필터 UI 규칙 (v1.16 로그 뷰어)
- **형태**: 헤더 아래 2행 — ① 검색 입력 + `Aa` + 지우기 ② 프리셋 칩 4종
- **칩 문법**: `OPColor.card` 채움 + `Capsule` + `OPColor.border` 1px. 활성 시 테두리 `OPColor.cta` + 본문 `ink`
  (AlertsView `filterChip` 과 **같은 문법** — 한 화면에서 두 가지 필터 문법이 섞이지 않게)
- **입력창**: `card` 채움 + `RoundedRectangle(6)` + `border` 1px · `magnifyingglass` 아이콘 선형(weight .light, 11pt)
- **다크 전용**: 이 화면은 다크 고정(AGENTS.local §4). 라이트 대응은 하지 않는다
- **색은 상태에만**: 검색 결과 행은 기존 E/W 색칠 규칙 유지. 일치 하이라이트는 **의도적으로 넣지 않음**
  (링 2000행 × 초당 1.4만 줄 → 행마다 `AttributedString` 재생성은 CPU 예산 초과) — 장식보다 예산이 우선
- **정직 표시**: 필터가 걸리면 푸터에 `기기 필터 <검색어>` 배지(cta 색)를 띄운다.
  "어디서 걸렀는가"를 숨기지 않는다 — 기기 필터는 **이전 구간이 되돌아오지 않는다**
- 프리셋은 **실패 신호만**: ANR / FATAL EXCEPTION / has died / dropbox
  (`thermal`·`accelerometer_rotation` 같은 상태 변화는 넣지 않는다 — 2026-09-27 "감지 142건" 장식 사건)

## 6. 접근성 최소선
- 대비: ink/abyss 대비 10:1 이상, dim 텍스트 4.5:1 이상 유지
- 상태는 색+텍스트 병기 (색맹 대비)
- Dynamic Type 대응 (SwiftUI 기본)

## 7. 지표(`/metrics`) 규칙 — 2026-09-28
> `docs/plans/PLAN_metrics_endpoint.md` · 기계가 읽는 값이므로 **거짓말이 없어야 한다**

- **모르면 0 이 아니라 행을 내지 않는다.** 미확인 배터리를 `0%` 로, 판정 유보 사이트를
  `0`(down) 으로 쓰면 "확인했다가 그 값" 이라는 거짓말이 된다
- **사라지지 않는다.** 오프라인 기기는 행이 있고 값이 `0` — 행이 사라지면
  "기기가 사라졌다" 와 구분되지 않는다
- **끈 것은 죽은 것이 아니다.** 비활성 사이트·잡은 행을 내지 않는다
- 판정은 **기존 로직을 재사용**한다 (`effectiveUp`·`isOverdue`·`activeCriticalCount`).
  지표용 판정을 따로 만들면 어느 쪽이 맞는지 알 수 없다
- 값이 있으면 **HELP·TYPE 을 항상** 낸다. 빈 응답은 scrape 실패와 구분되지 않는다

### 7-1. 시간 축 지표 — "지금" 이 아니라 **"얼마나"**
- 충전 방치(`relay_device_battery_neglect_seconds`)는 **누적 시간**이다. 이벤트(`WatchEvent`)로
  만들지 않고 상태 기계가 잰다 — 이벤트는 순간이므로 시간을 말하지 못한다
- **충전은 방치를 끊는다.** 다시 하강하면 **새로 시작** — 중간에 충전이 있었냐로 갈린다
- **배터리 미확인은 끊지 않는다.** 모르는 구간이 방치를 끝낸다는 근거가 없다
- 임계가 바뀌면 누적도 **0 부로** — 다른 기준에서 잰 시간은 이 기준의 시간이 아니다
- **판정 시점은 앱이 아니라 모니터링 쪽이다.** 앱은 초만 낸다. "몇 시간부터 위험한가" 는
  Prometheus 규칙이 정한다 — 앱에 넣으면 쓰이지 않는 설정이 된다
