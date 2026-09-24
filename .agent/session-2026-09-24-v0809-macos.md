# session-2026-09-24-v0809-macos.md

## 1. 목표
- v0.7 커밋·PR·머지 → v0.8 ANR/크래시 → v0.9 카드 On/Off → EventStore 1차

## 2. 검증
- `swift test` **108/108**
- `./build_and_run.sh debug macos` 0 error · 번들 **0.9.0**
- i18n **227/227/227** · 사용 키 missing 0
- 금지 단어: 코드 주석에만 "no material" 표현(기존, UI 미적용) · Scrcpy 허용

## 3. 산출
- v0.7 PR **#4** 머지 main `39c4115` (`feat/v07-scrcpy-watch`)
- v0.8: `WatchKind.{anr,crash}` · `anrKeywords`/`crashKeywords` · `feedAnr`/`feedCrash` 5분 쿨다운·kind 독립 · clear 자동 없음 · `relay.watch.{anr,crash}` · remediation · DEBUG 주입
- v0.9: `relay.cards.*` 8종 On/Off · 대시보드·팝오버 공통 · `cards.empty`
- EventStore: JSON(Application Support, 500건, ISO8601) · `WatchEvent: Codable` · 시작 로드 / ingest 저장
- 문서: `PLAN_v0.8` / `PLAN_v0.9` / TODO / AGENTS.local 0.9.0

## 4. 미해결
- 실기기 육안 (ANR 주입·카드 토글·이력 복원)
