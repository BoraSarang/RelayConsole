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
- **버전**: `1.15.0` (macOS 위젯 WidgetKit 3종 · App Group 스냅샷 · 딥링크 — 이전 1.14.0 네트워크 업/다운 그래프)
- UserDefaults·설정 키 접두어: `relay.*` (구 `outpost.*` 계승 금지 — 코드 신규)

## 3. 성능 예산 Override
- ADB 폴링: 백그라운드 스레드, 메인 스레드 차단 금지
- 무거운 dumpsys(meminfo·batterystats 등) 상시 폴링 금지 — RESEARCH §2-3

## 4. 프로젝트 특화 예외 규칙
- 외부 바이너리(adb, scrcpy)는 시스템 PATH 우선, 없으면 안내·사용자 확인 brew 설치만 (자동 다운로드 금지)
- scrcpy **외부 프로세스 실행은 허용** (A안) · 내장 미러링·Android 설정 쓰기는 금지 — 감시(읽기) 전용
- C3 "Scrcpy 버튼 없음" **해제** (PLAN_v0.7 사용자 승인) · 금지 grep `Scrcpy` 제거
- **[표시 ①] 기기 식별이 가능하도록 정확하게 표시** — 화면·알림·내보내기·번들/파일명에서 기기를 지칭할 때 **식별 가능한 원문**을 쓴다
  - 네트워크 기기: `IP:PORT` (serial 원문) / USB: `기기명 또는 모델 · 시리얼 원문` / Apple: `deviceName 또는 productType · udid 원문`
  - `…5555` 같은 마스킹·축약 표시는 **화면·알림·내보내기에 금지** (`…5555`는 USB·Wi-Fi 기기를 구분할 수 없음 — Wi-Fi는 전부 `…5555`로 동일)
  - 통일 진입점: `DeviceSnapshot.identLabel` · `AppleSnapshot.identLabel` · `ConsoleStore.identLabel(for:)` — 신규 표시는 반드시 이것만 사용, 임의 문자열 조합 금지
  - 마스킹은 `DebugLogger`·로그 파일 출력에만 허용 (뒤 4자리)
- **[표시 ②] 에러 내용과 상태를 정확하게 알 수 있도록 표시** — 실패 시 실제 원인(외부 명령 stderr · 에러 코드 · HTTP 상태)을 사용자에게 보여준다
  - 금지: 성공 문구로 실패 표시 / `catch`에서 원인 삭제 / 조용한 `return` / 내부 토큰·영문 원시값 노출 / "오류 발생" 같은 원인 없는 일반 문구만 남기기
  - 상태는 반드시 구분: 성공 · 실패(+원인) · 미측정/미수집 · 권한 없음 · 기기 미연결 — 같은 "—" 또는 `0`으로 뭉뚱그리지 않음
  - 오프라인·이전 수치를 병치하면 "마지막 스냅샷"임을 명시 (`apple.offline.banner`와 동일 패턴)
  - 새 상태/에러 문구는 en·ko L10n 키를 **같은 키명으로 동시 추가** (키 개수 1:1 유지)
- **팝오버·Droid 대시보드 표시: 다크 전용** (밝은 테마/웹風 버튼/print 금지)
- **[HARD] 빌드 스크립트는 최상단 참조 — 매 수정 직후 `./scripts/build-macos.sh debug` 필수** (`swift build`/`swift test`만으로 종료 금지)
- **위젯 구조 (1.15.0)**: `Sources/RelayWidget`는 **SPM 미등록** — `WidgetXcode/project.yml`(xcodegen)+`xcodebuild`로만 빌드 (SPM appex는 WidgetKit bootstrap 크래시, 가이드 §2.3). `Sources/RelayWidgetCore`만 SPM 타깃(공유·public). 앱·위젯 **서명은 Apple Development(6GPJQ7BQC9) 통일 유지** — ad-hoc/팀 불일치면 위젯 갤러리 미표시. 앱은 **비샌드박스 유지**(adb/scrcpy), 위젯 appex만 sandbox. 공유 데이터는 App Group `6GPJQ7BQC9.com.borasarang.relayconsole`의 `widget-snapshot.json` (`WidgetSnapshotStore`)

## 5. 디자인 토큰
- 색/폰트: docs/DESIGN.md
- v2 카드: bg #1c1f2a, radius 16, 숫자 SF Mono, 발열 오렌지 배너
- 아이콘: BrandKit/AppIcons + MenuBarIcons (Black Template = Xcode template)
- 상세: docs/plans/PLAN_v0.1_relayconsole.md §4
