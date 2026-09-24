# PLAN_v0.9_relayconsole.md — 카드 On/Off + EventStore 1차

> 생성일: 2026-09-24 | 상태: **완료 (검증 ✓ · 실기기 육안 ✓ 2026-09-24)**
> 모체: `PLAN_v0.8_relayconsole.md` · 백로그 카드 표시 / 이력 영구화
> 앱: **Relay Console** | 목표 버전: **0.9.0** | 최소 OS: **macOS 26.0**

---

## 1. 범위 (IN / OUT)

| IN | OUT |
|----|-----|
| 8카드 개별 On/Off (`relay.cards.*`) | 카드 재정렬/크기 조절 |
| 대시보드·팝오버 공통 필터링 | 카드 커스텀 레이아웃 저장 |
| 설정 섹션 카드 표시 · 기본 전체 ON | |
| 빈 카드 선택 가드 메시지 | |
| EventStore JSON 1차 (`Application Support/RelayConsole/watch-events.json`) | GRDB / SQLite |
| `WatchEvent: Codable` · 최대 500건 · ISO8601 | |
| 시작 시 로드 · ingest 시 저장 | |

## 2. 설정키

| 키 | 기본 | 카드 |
|----|------|------|
| `relay.cards.cpu` | true | CPU |
| `relay.cards.gpu` | true | GPU |
| `relay.cards.memory` | true | MEM |
| `relay.cards.sensors` | true | SENSORS |
| `relay.cards.battery` | true | BATTERY |
| `relay.cards.network` | true | NETWORK |
| `relay.cards.thermal` | true | THERMAL |
| `relay.cards.storage` | true | STORAGE |

## 3. EventStore 1차

- 위치: `~/Library/Application Support/RelayConsole/watch-events.json`
- 형식: `JSONEncoder` ISO8601 · sortedKeys · atomic write
- 적재: `ConsoleStore.init` 시 `EventStore.shared.load()`
- 기록: `ingestWatch` 직후 `save(recentWatchEvents)` (메모리 상한 500)
- 무의존 SPM 유지 (GRDB 미채택 — 백로그 2차 후속)

## 4. 검증

- [x] 카드 토글 시 대시보드·팝오버 동시 반영
- [x] 전체 OFF 시 `cards.empty` 표시
- [x] 이력 JSON 저장·재시작 복원
- [x] i18n · swift test · debug 빌드 0.9.0
- [x] 실기기 육안 (사용자 확인 ✓ 2026-09-24)
