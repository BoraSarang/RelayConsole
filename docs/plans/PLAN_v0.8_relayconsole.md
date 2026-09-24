# PLAN_v0.8_relayconsole.md — ANR / 크래시 logcat 감시

> 생성일: 2026-09-24 | 상태: **구현 (검증 진행)**
> 모체: `PLAN_v0.7_relayconsole.md` · `RESEARCH_watch_events.md` Phase3
> 앱: **Relay Console** | 목표 버전: **0.9.0 통합** (v0.8+v0.9 동시) | 최소 OS: **macOS 26.0**

---

## 1. 범위 (IN / OUT)

| IN | OUT |
|----|-----|
| `WatchKind.anr` / `.crash` | 자동 clear (가이드 30분 TTL 의존) |
| DeviceMonitor logcat 2조 키워드 스캔 | 프로세스 사망 이벤트 dumpsys |
| `WatchEngine.feedAnr` / `feedCrash` — 5분 쿨다운 | crash reporter 파일 파싱 |
| 설정 `relay.watch.{anr,crash}` | 임계값/슬랙 |
| remediation 가이드 steps | GRDB 이력 DB |
| DEBUG 주입 ANR/크래시 | |

## 2. 키워드

| kind | keywords (대소문자 무시 부분 매칭) |
|------|-----------------------------------|
| anr | `anr in`, `am_anr`, `application not responding`, `input dispatching timed out` |
| crash | `fatal exception`, `fatal signal`, `has died`, `force finishing` |

## 3. 동작

- 1회성 진입 이벤트 · severity **critical** · clear 자동 없음
- serial별 5분 쿨다운 (`logcatFatalCooldown = 300`)
- 분리 쿨다운: ANR/크래시 독립 (같은 serial 동시 발화 가능)
- `forget(disconnect)` — synthetic clear **없음**, 쿨다운만 재무장
- 가이드: `activeRemediation` warning+ + 30분 TTL으로 표시·소멸
- 메뉴바 critical 배지: ANR/크래시 enter 시 점등, clear 주입/배지해제로 해제

## 4. 검증

- [ ] feedAnr/feedCrash 쿨다운·독립 테스트
- [ ] logcat 키워드 분류 테스트
- [ ] activeRemediation TTL 테스트
- [ ] WatchEvent Codable 직렬화
- [ ] i18n 227키 3곳 · swift test · debug 빌드 0.9.0
