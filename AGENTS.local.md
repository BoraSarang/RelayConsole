# AGENTS.local.md — 프로젝트별 확장 규칙
> 위치: /Users/lee/Documents/Apps/RelayConsole/AGENTS.local.md
> 이 파일은 프로젝트 특화 규칙만 기록. 공통 가이드 재작성 금지.
> 이관: 2026-09-23 Outpost → RelayConsole (문서만, 코드 신규)

---

## ⛔ [HARD] 빌드 스크립트 강제 + 수정 직후 검증 (최상단 — 매 수정 직후)

**소스(`Sources/`)·리소스(`Resources/`)·테스트·L10n·시그니처가 바뀌는 순간, 아래 2개를 실제로 실행하기 전까지 "완료/성공/통과" 같은 완료 표현을 쓰지 않는다:**

```bash
swift test
./scripts/build-macos.sh debug
```

- **금지**: `swift build`만으로 종료 / `swift test`만으로 종료 / "빌드 통과"만 보고 마무리 / 검증 없이 "수정했습니다"
- **이유**: 스크립트가 `~/Applications/RelayConsole.app` 번들 재생성·리소스 재복사·재서명·`open` 재시작까지 함. 생략하면 **구버전 앱이 떠서 육안/크래시 재검증이 전부 무의미** (2026-09-24 구버전 `%s` 크래시 재발 사례)
- **검증 순서**: `swift test` → `./scripts/build-macos.sh debug` → 사용자에게 "앱 재시작 완료" 통보
- **테스트 실패 시**: 먼저 고치고 → 재실행 → 그 후에만 완료 보고
- **사용자가 "안 됐다/테스트 깨졌다"고 되묻는 순간 이미 규칙 위반** — 사전에 검증할 것
- **보고**: 수정 파일 + 실행한 커맨드 + 결과 건수
- 위반 시 작업 미완료로 간주. AI가 스스로 검증을 실행하지 않으면 규칙 위반

---

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
- **버전**: `1.13.0` (기기 그래프 플로팅창 — 이전 1.3.0 브리핑 S1)
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
- **[HARD] 빌드 스크립트는 최상단 참조 — 매 수정 직후 `./scripts/build-macos.sh debug` 필수** (`swift build`/`swift test`만으로 종료 금지)

## 5. 디자인 토큰
- 색/폰트: docs/DESIGN.md
- v2 카드: bg #1c1f2a, radius 16, 숫자 SF Mono, 발열 오렌지 배너
- 아이콘: BrandKit/AppIcons + MenuBarIcons (Black Template = Xcode template)
- 상세: docs/plans/PLAN_v0.1_relayconsole.md §4
