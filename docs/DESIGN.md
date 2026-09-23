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

## 5. 접근성 최소선
- 대비: ink/abyss 대비 10:1 이상, dim 텍스트 4.5:1 이상 유지
- 상태는 색+텍스트 병기 (색맹 대비)
- Dynamic Type 대응 (SwiftUI 기본)
