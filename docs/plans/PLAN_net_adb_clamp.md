# PLAN_net_adb_clamp — 네트워크 합계 0.0 회귀 (adb 과차감) 제거

> 규모 S · 2026-10-17 · 사용자 보고로 착수 ("droidrelay 에서 1M 으로 다운로드 받는데 위 합계 다운로드는 0?")

## 1. 관측 (실측 재현)

- 증상: NETWORK 카드 **합계 다운 0.0 KB/s** 인데 바로 아래 행은 `com.borasarang.droidrelay ↓1.2 MB/s` — 같은 카드가 서로 다른 말을 했다.
- 재현 (수정 전 코드): S22(`192.168.86.49`)에서 droidrelay 다운로드가 2초 간격 150초 내내 **200~415 KB/s 로 정지 없이** 흐르는 것을 `/proc/net/dev`로 확인한 상태에서 `adb push` 100MB 1회.

  | 시점 | 카드 "다운" |
  |---|---|
  | push 전 | 285 KB/s |
  | push 직후 | 5.7 MB/s (차감 반영 전) |
  | +25초 | **0.0 KB/s** |
  | +65초 | **0.0 KB/s** |
  | +165초 | 331 KB/s (창이 지나 복구) |

- 기전(코드): 합계 = `/proc/net/dev` **15초 live** − `shell`(uid 2000) 추정 **45~60초 창** → `max(0, …)` 클램프.
  추정 창이 live 창보다 4배 길어, 버스트 1회가 **약 60초 동안** 가짜 adb 트래픽으로 남는다. 그 값이 live를 넘으면 클램프로 **정확히 0.0**.
- 앱별 행(`appNetRates`)은 같은 뺄셈을 하지 않는다(60초 평균 · shell uid만 필터) — 그래서 아래 행은 멀쩡했다. "위 0, 아래 1.2M" 의 정체.
- 실측 근거(netstats 플러시 지연): push 80MB 직후 `uid=2000` 누적이 한 샘플에서 **39 MB/s** 로 튐. 같은 값을 60초 창으로 빼면 그 1분의 live를 전부 먹는다 (`PLAN_net_truespeed` §1 의 "밀린 N분치 ÷ 15초" 와 같은 현상).

## 2. 결정 (사용자 선택: B + D)

- **B — 차감은 "상시 오버헤드"만**: shell 추정을 합계와 **같은 틱(≈15초)** 으로 계산해 최근 5개 링의 **최소값**만 뺀다.
  - 버스트는 그 틱 하나만 크므로 최소값에서 빠진다 → **사용자가 직접 시작한 전송이 합계에 그대로 보인다**(조용히 지워지지 않는다).
  - 상시 트래픽(미러링 등)은 모든 틱이 커져 종전처럼 차감된다 — "합계 live · adb 제외" 의도는 유지.
  - 플러시 지연으로 한 틱이 튀는 것도 최소값이 흡수한다(39 MB/s 1회가 차감을 오염시키지 않음).
- **D — 0을 지어내지 않는다**: 과차감으로 실측이 0이 되면 0 대신 **그 순간의 실측**을 표시하고, 각주를 `합계 실시간(adb 포함) · 앱별 60초 평균` 으로 바꾼다. 0.0 은 "트래픽 없음"이 아니라 거짓말이었다.

## 3. 변경

- `AdbClient`
  - `netTotal(up:down:shellUp:shellDown:) -> (up, down, adbDominant)` — 차감 후 0이 되는 방향은 실측 유지, `adbDominant` 로 각주 전환.
  - `steadyShellRate(from:)` — 링에서 방향별 최소값(상시 오버헤드) ← 차감용.
  - `meanShellRate(from:)` — 링 평균 ← "adb(내부)" 행 표시용(앱별 행과 같은 60초 창).
  - `excludeShell` 은 **그대로**(순수 클램프) — 기존 의미·테스트 보존, 새 규칙은 `netTotal` 이 감싼다.
- `DeviceMonitor`
  - netdev 합계·경로별 그룹(cell/wifi)이 `netTotal` 사용. `state.cacheNetAdbDominant` → 스냅샷.
  - netstats 블록에서 **직전 틱 델타**로 shell 추정 → `shellRateHistory`(최대 5) → `steadyShellRate` → 캐시. 앱별 60초 창(`appNetBaselineIndex`)은 그대로.
- `DeviceSnapshot.netAdbDominant: Bool?` + merge 폴백(5초 틱이 15초 값을 덮지 않음) · `DroidCards.network` 각주 분기 · L10n 1키 양쪽(`droid.card.network.note.adb`).
- **카드 "adb(내부)" 행** — 합계에서 뺀 adb 트래픽을 숨기지 않고 목록에 세운다(`AdbClient.meanShellRate`).
  - 값은 링 **평균(≈60초)**: 바로 아래 앱별 행과 같은 창·통계로 맞춰 비교 가능하게 하고, 플러시가 밀리는 기기(Router 실측 — 틱 값이 대부분 0.0)에서 행이 죽어 보이는 것을 막는다.
  - 그래서 **버스트가 행과 합계에서 함께 보인다**: push 중 합계가 3.4 MB/s 로 튀는 순간 행도 ↓620 KB/s 로 올라간다 — "이 스파이크가 adb 때문" 이 카드 안에서 설명된다.
  - `DeviceSnapshot.netAdbUp/DownMBps` + merge 폴백 · L10n 1키 양쪽(`droid.card.network.adb`).

## 4. 검증 [HARD]

- `swift test` **XCTest 184/0 + Swift Testing 659/0** — 신규 2건: `netTotal`(과차감 시 실측 유지 · 실측 0이면 0 유지 · 정상 차감은 그대로) · `steadyShellRate`/`meanShellRate`(차감=최소값, 표시=평균 · 빈 링 0).
- `./scripts/build-macos.sh debug` **EXIT=0** · L10n **782키 en/ko 1:1** · 한자 0건.
- **실기 재현 대조** (S22 · `adb push` 80MB = 4.4초 · 18 MB/s):

  | 항목 | 실측(폰) | 카드 표시 |
  |---|---|---|
  | push 버스트 | 다운 18.6 MB/s | 1.8 MB/s (틱이 버스트 꼬리를 포함 — 정직한 평균) |
  | 이후 지속 다운로드 | 400 KB/s (지속) | **+60초 412 KB/s** ← 수정 전 0.0 이던 자리 |
  | uid 2000 버킷 | 39 MB/s 1회 튐 | 합계를 오염시키지 않음(최소값 차감) |
  | 앱별 행 | droidrelay ↓400 KB/s | ↓402 KB/s (방향·크기 일치) |
  | **adb 행** | push 60MB (3.5초) | 평소 `adb(내부) ↓1.0 KB/s` → push 틱 `↓620 KB/s`(60초 평균) — 합계 3.4 MB/s 스파이크의 출처가 카드 안에서 설명됨 |

## 5. 남은 것

- 육안: `docs/MANUAL_VERIFY.md` **45번** (사용자 확인 대기).
