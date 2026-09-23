# PLAN_v0.6_macos.md
> 생성일: 2026-09-22 | 플랫폼: macos | 작성자: opencode+Muse Spark
> T-011~T-016: 전수분석 후속 경화 (버그·설정·UI/UX)

## 1. 목표 (1줄)
전수분석에서 발견된 치명 3건·보통 18건·UI High 9건을 수정하고 테스트 32→43건으로 보강한다.

## 2. 범위
- T-011 치명: EventStore force unwrap 제거, ping 데드라인 kill, SettingWatch 메인 차단 제거
  - 정정: macOS ping `-t`는 timeout이 맞음(TTL은 `-m`). 플래그는 유지, 대기 kill만 추가
- T-012 동시성: 6 모니터 타이머 중복 정리 + 세대 가드(stop 후 덮어쓰기 방지), adb/apple terminate 후 wait + stderr 드레인, logcat/syslog fd close + 버퍼 64KB 상한, UDID 에러행 제외(16진+대시), 모델명 내부 `-_.` 보존
- T-013 저장소·네트워크: EventStore 단일 트랜잭션 + E-MAC-STORE-0002(쓰기 실패) 로깅, URLSession invalidate, IPv6 host:port, Heartbeat 바인드 실패 UI 노출(onBindFailed→lastError), 404 문구·percent-decode, ntfy 재시도·Bearer·토픽 인코딩·Title MIME
- T-014 도움말·빌드: Package.swift 리소스 선언 + Bundle.module 폴백, HelpCenter 성공 위장 제거(Bool 실반환), ko 데드링크 상대경로 수정, build-macos pipefail + 서명실패 중단 + rm 가드, 포그라운드 알림 delegate, 종료 동기 정리, UserDefaults outpost.* 마이그레이션
- T-015 UI: 라이트 텍스트 색 4종(AA 4.5:1 실측 통과) + 20여 호출 교체, 팝오버 스크롤·높이제한·잘림, trash 접근성·클릭영역, 상태바 툴팁·요약·스파크라인 숫자병기, StatusDot 라벨, Jobs 렌더중 markDone→onAppear, 리셋 대칭(s2ok/copied), Cmd+Shift+D 단축키(DEBUG 한정 유지), NSApp 활성화, 시각 locale 7곳
- T-016 테스트·문서: V06 11건 추가, 미러 tautology 강화, TODO/PLAN 오기 수정

## 3. 명시적 제외 (다음 차수)
- 게이트 탈출구(기기 없는 사용자용 건너뛰기): 정책 결정 필요, 미구현
- App Nap 억제 키: 배터리 정책과 연계, 사용자 확인 후
- FK cascade 스키마 마이그레이션: 수동 삭제 순서로 동작 중, 위험 대비 효용 낮음
- 릴리스 DebugPanel: DEBUG 한정 유지 (의도적)
- Dynamic Type 전면 대응·고아 shizuku 진입점: 별도 UX 차수

## 4. 문서 위치
- PLAN: 본 문서, TODO: docs/TODO.md T-011~T-016, DESIGN: 텍스트 안전색 토큰 1절

## 5. 성능 예산
- budgets.json 참조, 영향 없음 (폴링 주기·DB 상한 변경 없음, 로그 실패 경로만 추가)

## 6. 에러 코드
- 신규 1종: E-MAC-STORE-0002 (쓰기 실패), ko/en json + L10n + 테스트 12종 매핑 완료

## 7. 빌드 & 검증 계획
- `swift build` 통과, `swift test` 43건 통과 (기존 32 + 신규 11)
- `./build_and_run.sh debug macos` 실기 구동은 사용자 환경에서 확인

## 8. 예외 규칙
- 외부 다운로드 없음. 기기 쓰기 없음 (읽기 전용 유지). 파괴적 변경 없음.
