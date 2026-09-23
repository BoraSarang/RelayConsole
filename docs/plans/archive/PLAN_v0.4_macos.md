# PLAN_v0.4_macos.md
> 생성일: 2026-09-22 | 플랫폼: macos | 작성자: opencode+Muse Spark
> 1차: 다국어 기반(ko+en, 앱내 수동선택) + 테마 3종(시스템/다크/화이트)

## 1. 목표 (1줄)
앱 표시 언어 ko+en 수동 선택과 관제탑 다크/라이트 테마를 시스템 추종 기본으로 제공한다.

## 2. 범위
- 플랫폼: macos (기존 v0.1~v0.3 골격 유지)
- 다국어: 앱 전체+알림 범위, ko 기본·en 추가, 설정에서 시스템/한국어/English 선택 (문서·커밋은 한국어 유지 [HARD])
- 테마: 전체 적용(콘솔+팝오버+설정+디버그), 관제탑 라이트 커스텀, 기본 시스템 추종
- 명시적 제외: DB 기존 한국어 이벤트 번역 없음(원문 표시), ntfy 발송 시점 언어 고정, RTL 없음

## 3. 문서 위치
- PLAN: 본 문서
- TODO: docs/TODO.md T-009·T-010 등록
- DESIGN: docs/DESIGN.md 토큰표 다크/라이트 2단
- API: 해당 없음

## 4. 성능 예산
- budgets.json 참조 (Cold Start ≤1.5s, 메모리 ≤300MB)
- L10n 딕셔너리 상주(수백 키, 수십KB), 테마 전환은 View 리렌더만 — 예산 영향 없음

## 5. 에러 코드
- 기존 E-MAC-* 11종 유지, `error_message_ko.json` + 신규 `error_messages_en.json` 언어별 매핑
- 매핑 누락 시 ko 폴백 (테스트로 보장)

## 6. 빌드 & 검증 계획
- `./build_and_run.sh debug macos`
- 테스트: 기존 17건 + 신규 L10nTests(키 누락·폴백·수동전환)·ThemeTests(다크/라이트 해석·저장복원·대비 4.5:1) 8건
- 확인: 언어 3상태 × 테마 3상태 전환 후 콘솔/팝오버/설정 스냅샷, DebugPanel ERROR 0

## 7. 예외 규칙
- 외부 다운로드 없음, 설치 행위 없음 (HARD 2·3 준수)
- 파괴적 변경 없음 (bundleId·권한·DB 스키마 변경 없음)
