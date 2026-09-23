# PLAN_v0.1_macos.md
> 생성일: 2026-09-22 | 플랫폼: macos | 작성자: opencode+Muse Spark

## 1. 목표 (1줄)
맥 메뉴바에 상주하며 ADB 연결 안드로이드를 감시하는 외부 관제 콘솔 v0.1 (Droid 모듈).

## 2. 범위
- 플랫폼: macos (SwiftUI + AppKit 메뉴바, LSUIElement)
- 기술 스택: SwiftPM + GRDB(SQLite) + 시스템 adb 외부 호출 — 선정 이유 1줄: TetherLens와 동일 골격으로 검증된 조합, 기기 쓰기 없이 읽기 전용이라 안전
- design_profile: custom (관제탑: docs/DESIGN.md 토큰)
- 명시적 제외: 맥 자체 모니터링 없음, 기기 설정 쓰기 없음, scrcpy 화면 내장 없음 (v0.1), iOS 없음 (v0.3)

## 3. 문서 위치
- PLAN: 본 문서
- TODO: docs/TODO.md T-001~T-005 등록
- DESIGN: docs/DESIGN.md 갱신
- API: 해당 없음 (v0.1)

## 4. 성능 예산
- budgets.json 참조 (Cold Start ≤1.5s, 메모리 ≤300MB)
- ADB 폴링: 인벤토리 5초·배터리 30초·설정 5초, 전부 백그라운드 스레드

## 5. 에러 코드
- E-MAC-ADB-0001~0003 (바이너리 없음·연결 실패·파싱 실패)
- E-MAC-STORE-0001 (DB 초기화 실패)
- E-MAC-WATCH-0001 (감시 시작 실패)
- 매핑: error_message_ko.json

## 6. 빌드 & 검증 계획
- build_and_run.sh debug macos
- 테스트: smoke 빌드 + unit (AdbParsingTests 5건)
- DebugPanel 검증: 진입점 [INFO] [FEATURE] 로그, ERROR 0

## 7. 예외 규칙 (있으면)
- 외부 바이너리 자동 다운로드 금지 — PATH 사용 + 안내만 (HARD 2·3 준수)
- 시리얼 로그 마스킹 (뒤 4자리만)
