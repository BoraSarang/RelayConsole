# DECISIONS.md — 제품 결정 기록

> 뒤집으려면 이 파일의 사유를 먼저 뒤집어야 한다.
> "다시 쳐다보지 않는다"는 결정도 결정이다.

## D1 — Sites·Jobs 제거, 기기 관제로 집중 (2026-10-05)

- **결정**: 사이트 업타임 감시(Sites)·하트비트 작업 감시(Jobs)를 앱에서 덜어냈다.
  Relay Console은 **기기 관제탑** 한 문장으로 설명된다.
- **사유**:
  1. 쓰는 사람이 없다 — 자운영 서버도 크론도 없으니 쓸 게 없었다.
  2. 기기 이벤트와 만나지 않는다 — 합쳐지는 곳이 브리핑 한 줄뿐이라 세 앱이 메뉴바를 나눠 쓰는 모양이었다.
  3. 기기가 너무 커졌다 — 관제センター로 시작했지만 실사용은 폰 관제에 쏠렸다.
- **다시 보지 않는다**: 사이트·작업 감시를 되살리자는 이야기가 나오면 이 D1을 먼저 읽는다.
  부활 재료는 git 히스토리에 있다 (`git log -- Sources/RelayConsole/Sites`).
  삭제된 것: `Sites/`·`Jobs/`(하트비트 8787 포함)·관련 Views·store·WatchKind 5종·MCP 도구 2종·L10n 111키·
  위젯/브리핑/Alerts/`/metrics`의 사이트·작업 파트. 위젯 스냅샷 스키마 v1 → v2.
- **다음**: 기기 관제 확장 — 자동 진단(원인 추출·범인 파악·리포트). 재료 추출은 `docs/research/`에서.

## D2 — 위젯(WidgetKit 3종) 제거 (2026-10-17)

- **결정**: macOS 위젯 3종(small/medium/large)·App Group 스냅샷 파이프라인·`relayconsole://` 딥링크를 제거했다.
  제거 범위: `Sources/RelayWidget`(529) + `Sources/RelayWidgetCore`(167) + 앱측 `WidgetSnapshotSync`·`WidgetDeepLink`(192)
  + `WidgetSnapshotTests`(244) + `WidgetXcode/`(xcodegen) + `Entitlements/RelayWidget.entitlements` + `widget.*` L10n 12키.
- **사유 (실측)**:
  1. **정보 중복** — 위젯이 보여주는 값(기기·배터리·발열·이벤트·critical)은 팝오버·메뉴바 배지와 같다.
     앱은 이미 메뉴바 상주형이라 "클릭 없이 상시 확인"이라는 위젯의 이점이 팝오버 한 번과 크게 다르지 않다.
  2. **빌드 결합이 비쌌다** — 위젯 appex는 SPM으로 못 만들어 **xcodegen + xcodebuild 필수**(없으면 빌드 실패).
     서명 팀이 어긋나면 위젯 갤러리에 안 뜨는 취약점까지 떠안았다. 제거로 빌드가 SwiftPM 단독으로 돌아온다.
  3. **배포 채널 없음** — 앱은 비샌드박스(adb·scrcpy)라 **Mac App Store 불가** → "위젯 3종"의 마케팅 가치가 0이다.
  4. **변화 없음** — 2026-09-25 도입 후 3주간 위젯 코드 변경 0건(Sites·Jobs 제거에 따른 스냅샷 정리 1건 제외).
- **잃는 것**: 데스크톱/알림센터 상시 노출 표면 1개, `relayconsole://<target>` 외부 딥링크.
  위젯 LOC 1,132(전체의 2.9%)·L10n 12키·경쟁 리서치 M5 문구 1개는 문서에 기록으로 남는다.
- **다시 보지 않는다**: 위젯 부활 재료는 git 히스토리에 있다 (`git log -- Sources/RelayWidget WidgetXcode`).
