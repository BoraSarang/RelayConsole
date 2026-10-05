# PLAN_auto_diagnose — 자동 진단 (2026-10-05)

> 재료: `docs/research/RESEARCH_auto_diagnose.md` (S22 실측 완료).
> 이름: **자동 진단**. 상태가 발생하면 앱이 스스로 원인을 캐내어 리포트한다.
> 원칙: 무거운 명령은 이상 감지 시 1회만. 상시 폴링 금지. 모르는 건 "원인 불명"으로 ([표시②]).

## 범위

- Phase 1 (이 PLAN): **크래시 진단** — 패키지·예외·빈도·dropbox 요약 → Alerts 확장 영역 "진단" 섹션
- Phase 2 (다음): 발열 진단 — throttling enter 시점 CPU 상위 스냅샷 + 충전/핫스팟 조합 + 최고온 센서 3종
- Phase 3 (다음): 신호·배터리 패턴 리포트 — 빈도·시간대·셀 변경 (DeviceDaily 집계)
- 비목표: ANR 스택 (권한 없음), 신호 저하 근본 원인 (기지국은 모름), 자동 조치 (읽기 전용 유지)

## Phase 1 설계 — 크래시 진단

### 트리거
- `ConsoleStore.ingestWatch`에서 kind == .crash && !isClear && errorFingerprint 있음 →
  백그라운드 Task 1회 (지문당 1회 · `diagnosedFingerprints` 메모리 + 영속).

### 진단 파이프라인 (`CrashDiagnose`, 순수 + Runner 분리)
1. **입력 확정** (순수): event.packageName · exceptionClass · errorFingerprint (없으면 진단 안 함 — 추측 금지)
2. **dropbox 1회** (Runner, 상한): `dumpsys dropbox --print` 기기 내 grep `data_app_crash` →
   해당 패키지 최신 1건의 첫 10줄만 전송 (4KB cap · 20초 타임아웃 · ProcessRunner)
3. **빈도** (순수, 메모리): recentWatchEvents에서 동 package+exception 건수 + 최초/최근 시각 →
   "7일 N회 · 첫 {d} · 마지막 {t}" (없으면 "첫 관측")
4. **정황** (순수, 메모리): metricsHistory에서 발생 시각 ±60초 CPU·온도 (있으면만, 없으면 생략 — 없는 값 지어내지 않음)
5. **출력**: `DiagnoseResult` (causeLine · frequencyLine · contextLine? · sourceLines) —
   문장이 아니라 **필드**. 표시는 View가 조합.

### 저장·표시
- `DiagnoseStore` (소형 JSON 영속, 지문→결과): Alerts 확장 영역이 조회해 "진단" 섹션 표시.
  - 영속 이유: Alerts는 EventStore에서 다시 읽는다 — 메모리만이면 재시작 시 진단이 사라진다.
- L10n 키: 진단 섹션 라벨 + 필드 라벨 (en/ko 1:1).

### 테스트
- 파서: dropbox 행 파싱 (패키지·시각·예외 첫줄) — 순수 함수
- 빈도 집계: 동일 지문 N회 · 다른 패키지 제외 · clear 무시
- Runner 미발동 조건: errorFingerprint 없음 · 이미 진단됨 · 패키지 없음
- L10n en/ko 1:1 (신규 키)

### 검증 [HARD]
- `swift test` → `./scripts/build-macos.sh debug`
- 실기: 크래시 발생(또는 debugInject) → Alerts 확장 영역에 진단 섹션 → dropbox 1회만 (adb 자식 폭증 없음)

## Phase 2 예고 — 발열 진단
- 트리거: throttling enter. `top -n 1 -b` 1회 + 충전/핫스팟 + 최고온 thermal zone 3종 →
  "주범 후보: com.foo (CPU 38%) · 충전+핫스팟 중 · pa 47.1℃".
- WatchEngine throttling 경로에 후크 (게이트 판정 뒤, 진단 Task 분리).
