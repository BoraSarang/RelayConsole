# AGENTS.local.md — 프로젝트별 확장 규칙
> 위치: /Users/lee/Documents/Apps/RelayConsole/AGENTS.local.md
> 이 파일은 프로젝트 특화 규칙만 기록. 공통 가이드 재작성 금지.
> 이관: 2026-09-23 Outpost → RelayConsole (문서만, 코드 신규)

## 1. 프로젝트 정보
- **프로젝트명**: RelayConsole / 앱 이름 **Relay Console** (구 Outpost → 브랜드 이관, 코드 신규)
- **플랫폼**: macos (확정 예정 — 이관 시점 가정: SwiftUI MenuBarExtra)
- **기술 스택**: SwiftPM + SwiftUI MenuBarExtra + AppKit + 시스템 ADB 외부 호출 (GRDB는 범위 밖 · **외부 scrcpy 호출은 허용**, 내장 미러링은 범위 밖)
- **최소 OS**: macOS 26.0 Tahoe (BrandKit/AppStore_Metadata)
- **선정 이유**: 맥 메뉴바 상주 — 외부 안드로이드 기기 관제
- **design_profile**: custom — "관제탑" (docs/DESIGN.md + 팝오버/대시보드 v2 토큰)
- **작업 모드 기본값**: 정식

## 2. 번들ID / 앱 ID
- macOS bundleIdentifier: `com.borasarang.relayconsole` **확정** (AGENTS 플랫폼 규칙 `com.borasarang.{AppName}`)
- 앱 표시명: Relay Console / 메뉴바: RELAY
- **버전**: `1.6.0` (기기 그래프 플로팅창 — 이전 1.3.0 브리핑 S1)
- UserDefaults·설정 키 접두어: `relay.*` (구 `outpost.*` 계승 금지 — 코드 신규)

## 3. 성능 예산 Override
- ADB 폴링: 백그라운드 스레드, 메인 스레드 차단 금지
- 무거운 dumpsys(meminfo·batterystats 등) 상시 폴링 금지 — RESEARCH §2-3

## 4. 프로젝트 특화 예외 규칙
- 외부 바이너리(adb, scrcpy)는 시스템 PATH 우선, 없으면 안내·사용자 확인 brew 설치만 (자동 다운로드 금지)
- scrcpy **외부 프로세스 실행은 허용** (A안) · 내장 미러링·Android 설정 쓰기는 금지 — 감시(읽기) 전용
- C3 "Scrcpy 버튼 없음" **해제** (PLAN_v0.7 사용자 승인) · 금지 grep `Scrcpy` 제거
- 로그 마스킹: 시리얼 전체 출력 금지 (뒤 4자리만 …5555)
- **팝오버·Droid 대시보드 표시: 다크 전용** (밝은 테마/웹風 버튼/print 금지)
- **[HARD] 소스·리소스 수정 후에는 항상 `./scripts/build-macos.sh debug` 실행** — 번들 재생성·재서명·`open` 재실행까지 한 번에. 생략하면 구버전 앱이 떠서 육안/크래시 재검증이 깨짐 (2026-09-24 구버전 `%s` 크래시 재발 사례). 테스트만으로 끝내지 말 것.

## 5. 디자인 토큰
- 색/폰트: docs/DESIGN.md
- v2 카드: bg #1c1f2a, radius 16, 숫자 SF Mono, 발열 오렌지 배너
- 아이콘: BrandKit/AppIcons + MenuBarIcons (Black Template = Xcode template)
- 상세: docs/plans/PLAN_v0.1_relayconsole.md §4
