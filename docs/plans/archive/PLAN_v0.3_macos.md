# PLAN_v0.3_macos.md
> 생성일: 2026-09-22 | 플랫폼: macos | 작성자: opencode+Muse Spark

## 1. 목표 (1줄)
연결된 iPhone/iPad 감시(Apple 모듈): 기기 인벤토리·배터리·로그 워치 + 미러링 핸드오프.

## 2. 범위
- 플랫폼: macos (v0.1·v0.2 골격 재사용: ConsoleStore·EventStore·스켈레톤 UI)
- 기술 스택: libimobiledevice CLI (idevice_id/ideviceinfo/idevicesyslog, 미설치 시 안내만) + xcrun devicectl 보조 + NSWorkspace 미러링 핸드오프
- design_profile: custom (스켈레톤 컴포넌트 재사용, 구조 확정 후 디자인 다듬기는 별도 작업)
- 명시적 제외: iPhone 화면 미러링 내장 (Apple 독점, 시스템 앱으로 핸드오프만), 외부 바이너리 자동 설치 없음, 탈옥 필요 기능 없음

## 3. 문서 위치
- PLAN: 본 문서
- TODO: docs/TODO.md T-007 등록
- DESIGN: 스켈레톤 재사용, 변경 없음
- API: 해당 없음

## 4. 성능 예산
- budgets.json 참조 (Cold Start ≤1.5s, 메모리 ≤300MB)
- 폴링: 인벤토리 10초·배터리 60초, 백그라운드

## 5. 에러 코드
- E-MAC-APL-0001~ (도구 없음·연결 실패·파싱 실패)
- 매핑: error_message_ko.json

## 6. 빌드 & 검증 계획
- build_and_run.sh debug macos
- 테스트: unit (ideviceinfo 파싱·도메인 조회 파싱)
- 실측: libimobiledevice 미설치 + iOS 기기 미연결 상태라 불가 → 도구 설치 후 사용자에게 확인 요청 (안내 카드 동작은 코드 리뷰로 검증)

## 7. 예외 규칙 (있으면)
- brew install 등 설치 행위는 사용자 명령 후에만 (HARD 2)
