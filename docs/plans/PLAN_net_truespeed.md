# PLAN_net_truespeed — 네트워크 "진짜 속도" (합계 live·adb제외 + uid행 60초)

> 규모 S/M · 2026-10-13 · 사용자 실측 보고로 착수 (Router 테더 vs S22, uid -5 ↓250 vs 합계 ↓6.4)

## 1. 관측 (실측, adb 직접 대조)

- S22는 Router 테더가 아니라 **Home AP**에 붙어 있음 (`dumpsys wifi` SSID "Home AP", IP 192.168.198.49) — 기기 간 순간값 비교 자체가 성립 안 했음.
- Router 카드 안의 모순은 진짜 결함: 합계 ↓6.4 (`/proc/net/dev` live) vs `uid -5` ↓250 (`dumpsys netstats` 버킷).
- 원인 확정: netstats history 버킷은 15초마다 갱신 안 됨 — live 트래픽 1.7MB가 흐른 ~25초 구간에 `uid=-5` 버킷 합계가 **완전 동일** (`rb=3075447982 → 동일`). flush가 두 폴 사이에 떨어지면 `밀린 N분치 ÷ 15초`로 뻥튀기됨.
- `uid -5` = 테더링 귀속 (Router `swlan0 TetheredState` + rmnet 위 GB 단위 카운터로 확인).
- Xt live 대안은 기기 파편화로 폐기: Router(구형)엔 있음, S22(신형)엔 없음 (`xt_qtaguid` 삭제, eBPF는 root 필요, BpfCoordinator 섹션 비어 있음).
- 테더 클라이언트 다운은 Router 입장에서 TX라 카드 **"업"** 에 잡힘 (`swlan0 tx +1.69MB` ≈ 업 82.6 정합).
- `com.android.shell ↑23.8` = 앱 자신의 adb 폴링 오버헤드 (내부용이므로 제외 대상).

## 2. 결정

- ③ A' 적용 (합계 live·adb제외 확정 + uid행 60초 평균·shell 필터). ① 헬퍼(TrafficStats Provider 확장)는 제품 결정으로 보류 — 에이전트리스 원칙 충돌, SDK v3급.
- uid행은 "실시간"이 아니라 **"60초 평균·참고용"** 으로 격하 표시. 한계를 숨기지 않음.

## 3. 변경 (런타임 추가 부하 0 — 전부 호스트 연산, adb 호출·주기·전송량 불변)

- `AdbClient`: `shellUid = 2000` (AID_SHELL 고정값) · `appNetRates(..., excluding:)` · `shellRate(prev:curr:seconds:)` ·
  `excludeShell(up:down:shellUp:shellDown:)` (0 클램프) · `appNetBaselineIndex(ages:minAge:)` (45초 이상 가장 오래된 샘플).
- `DeviceMonitor`: slow틱마다 샘플 5개 링 유지 → 45~60초 전 기준선과 델타 (미성숙 시 직전 샘플 폴백 = 종전 동작).
  shell 속도는 같은 윈도우로 스무딩 후 캐시 → netdev 합계에서 차감 (직전 틱 캐시 사용, 초기값 0).
  `prevAppNet/prevAppNetAt`는 히스토리로 대체 (사용처는 netstats 블록뿐).
- 표시: 카드에 `droid.card.network.note` 1줄 (합계 실시간·adb 제외·앱별 60초 평균) ·
  `droid.appnet.hint` 문구 갱신 (같은 키) · 누적(부팅 이후)은 버킷 합이라 정확 — 그대로.
- 파급 자동 반영: 차트·Insights·`/metrics`·Daily 롤업은 같은 캐시를 읽으므로 손대지 않음.

## 4. 검증 [HARD]

- `swift test` (신규: shell 제외·클램프·기준선 선택) · `./scripts/build-macos.sh debug` ·
  L10n en/ko 키 1:1 (신규 1키 양쪽 동시, hint는 문구만) · 한자·U+FFFD 0건.
- 실기 (MANUAL_VERIFY 38번): shell 행 사라짐 · 합계 ≈ 수동 netdev 계산 · uid행이 flush 타이밍에 튀지 않음.
