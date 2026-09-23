# PLAN_v0.2_macos.md
> 생성일: 2026-09-22 | 플랫폼: macos | 작성자: opencode+Muse Spark

## 1. 목표 (1줄)
외부 사이트·서비스 감시(Sites) + 크론 하트비트 수신(Jobs) + 알림 파이프(Notify)를 묶은 v0.2.

## 2. 범위
- 플랫폼: macos (v0.1 골격 재사용: ConsoleStore·EventStore·DebugLogger·관제탑 테마)
- 기술 스택: URLSession(HTTP/SSL) + Network.framework TCP/NWListener(하트비트 서버) + /sbin/ping + ntfy HTTP 발행
- design_profile: custom (Uptime Kuma식 90일 상태 바 + 스파크라인, docs/DESIGN.md)
- 명시적 제외: 맥 자체 모니터링 없음, 외부 바이너리 자동 다운로드 없음, 인증서 고정(pinning) 없음

## 3. 문서 위치
- PLAN: 본 문서
- TODO: docs/TODO.md T-006 등록
- DESIGN: docs/DESIGN.md 상태 바·스파크라인 토큰 추가
- API: docs/api/HEARTBEAT.md (하트비트 수신 엔드포인트 명세)

## 4. 성능 예산
- budgets.json 참조 (Cold Start ≤1.5s, 메모리 ≤300MB)
- 체크 주기: 기본 60초/사이트, 하트비트 판정 30초, 전부 백그라운드

## 5. 에러 코드
- E-MAC-NET-0001~ (체크 실패: DNS/연결/타임아웃/HTTP 오류)
- E-MAC-JOB-0001~ (하트비트 서버 시작 실패)
- E-MAC-NOTIFY-0001~ (ntfy 발행 실패)
- 매핑: error_message_ko.json

## 6. 빌드 & 검증 계획
- build_and_run.sh debug macos
- 테스트: unit (파싱·overdue 판정·ntfy 요청 구성) + 실측 (http://localhost 하트비트 1건)
- DebugPanel 검증: 진입점 [INFO] [FEATURE] 로그, ERROR 0

## 7. 예외 규칙 (있으면)
- 하트비트 서버는 127.0.0.1 바인딩 고정 (외부 노출 금지)
- ntfy 기본 서버는 사용자가 직접 입력 (기본값 없음, 시크릿 규칙 준수)
