# PLAN — 외부(인터넷) 트래픽 분리 표시 · T-2026-10-13-6

> 작성: 2026-10-13 · 선행: `PLAN_net_truespeed.md` (합계 live + shell 제외)

## 1. 배경 — Router down은 "외부"가 아니었다 (실측 확정)

`parseNetDev` 가 `lo` 빼고 전 인터페이스 합산이라, 테더링 Router(.8) 실측에서 3종 혼입 + 뻥튀기:

- `rmnet_data2` RX +4.01MB ≈ `rmnet_ipa0` RX +4.17MB (10초 델타) — **같은 패킷 중복 계측**
- `swlan0` TX +3.93MB ≈ LTE RX — Mac으로 전달분. 전달 X는 **down에 2X, up에 X**로 잡힘
- Mac→Router 업로드는 `swlan0` RX로 down에 잡힘 (내부망인데 down)

## 2. 결정 — 기준은 활성 기본 경로 (사용자 정의 그대로)

- **Router** (활성=CELLULAR/LTE/NR) → 외부 = `rmnet_*` 합
- **S22** (활성=Wi-Fi, Router 테더) → 외부 = wifi (`wlan*/swlan*`) 합
- 같은 `swlan0` 이름이라도 모드(AP vs station)가 다르므로 **이름이 아니라 활성 경로가 기준**이다.
  활성 경로는 기존 `parseNetworkType` 값 재사용 ("Wi-Fi" | "LTE" | "NR" | "CELLULAR" | …).

### ① ipa 중복 제외 (측정 수정 — 표시 숫자 바뀜)

- `rmnet_data*` 중 누적 nonzero가 하나라도 있으면 `rmnet_ipa*` 제외.
- 없으면(ipa 단독 기기 가드) ipa 유지 — 0으로 만드는 쪽이 거짓말이다.
- 합계(total)도 제외 후 값. Router down은 대략 절반으로 내려간다 (정상화).

### ② 외부 분리 표시 (표시 추가 — 합계는 유지)

- `NetSample` += cellRx/cellTx (`rmnet_*`, ipa 제외 후) + wifiRx/wifiTx
  (wifi 판정은 기존 `isWifiInterface` 재사용 — `wlan*/swlan*/wlp*`).
- 속도도 3종 (total·cell·wifi, 같은 seconds) + shell 제외는 3종 대칭 적용 (0 클램프 기존).
- 스냅샷 += `netCellUp/DownMBps` · `netWifiUp/DownMBps` (optional + merge 폴백, 기존 관례).
- **외부 선택은 순수 함수** `BriefingLogic.externalNetRates(...)`:
  Wi-Fi→wifi쌍, LTE/NR/CELLULAR→cell쌍, 그 외·nil→nil (숨김, [표시②]).
- 네트워크 카드에 "외부" 행 1줄 (값+단위, 해석 불가면 행 없음). L10n 키 en/ko 동시.
- 차트·`/metrics`·메뉴바·플로팅은 total 유지 (범위 고정 — 메뉴바 정의 변경 아님).

## 3. 검증 게이트 [HARD]

1. `swift test` 0 failed (신규: ipa 제외 3종 픽스처(.8 실측값) · 3종 속도 · external 선택).
2. `./scripts/build-macos.sh debug` EXIT=0 · L10n en/ko 1:1 (신규 1키 양쪽).
3. **라이브 대조**: 재시작 30초 후 adb 10초 델타 수계산 vs 앱 외부값 — ipa 제외분 일치.
4. 메뉴바 캡처: Router down이 종전 대비 절반 수준으로 정상화됐는지.
5. 육안(사용자): 콘솔 네트워크 카드 "외부" 행 — Router는 LTE값, S22는 Wi-Fi값과 일치.

## 4. 제외

- 메뉴바 표시 정의 변경 (total 유지) · uid행 변경 없음 · Ethernet 기기는 외부 숨김 (nil).
