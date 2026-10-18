# PLAN_dropbox_recovery_relayconsole.md — dropbox 기반 ANR·크래시 회수

> 생성일: 2026-10-18 | 상태: **구현 완료** (기기 복귀 대기 — 육안 69~71) · bd: `RelayConsole-r07`
> 모체: `RESEARCH_competitive_v2` §4.2 **M3**(인시던트 번들) · §5.2 **P2-3**(T-2026-10-17-8)
> 앱: **Relay Console** | 목표 버전: **1.21.0** | 최소 OS: **macOS 26.0**

---

## 1. 문제 — logcat 은 링 버퍼다

`logcat` 은 원형 버퍼다. 폴링 주기(5초)와 덤프 상한(50KB) 사이로 밀려나면 **ANR·크래시가 통째로
사라진다.** 실측(2026-09-27 · SM-S901N): 초당 3만 줄 기기에서 `-t 500` 은 **약 2초분**이었다.

`dropbox` 는 시스템이 남기는 **영속 큐**(기본 1000건 · 재부팅 생존)라, 로그가 롤아웃된 뒤에도
원문이 남는다. 종전 코드는 이 큐를 **"크래시/ANR N건 발견" 문자열 알림 1건**으로만 썼다 —
몇 건인지는 말하고 **무엇이·어느 앱이·왜** 는 말하지 않았다(행동 불가).

## 2. 스파이크 실측 (2026-10-18)

| 확인 | 명령 | 결과 |
|---|---|---|
| 목록 크기 | `dumpsys dropbox` | SM-A908N **75건 / 10.5KB** · SM-S901N **33건 / 3.8KB** — 매 스캔에 써도 되는 비용 |
| 전건 본문 | `dumpsys dropbox --print` | **206KB / 33건**(S901N) — 무관한 항목까지 실린다 → **쓰지 않는다** |
| 시각 필터 | `--print '2026-10-18 04:50:23'` | **정확 일치**(이후 시각이 아니다). 실측: `--print '2026-10-18 00:00:00'` 은 0건 |
| 인용 필요 | `--print` + 공백 든 시각 | 인용하지 않으면 기기 셸이 **두 인자로 쪼갠다** → `'…'` 필수(폰 찾기와 동일 함정) |
| 상한 | `--print '<시각>' \| head -c 200000` | Android toybox `head -c` 지원 확인(실측). ANR 본문은 수십~수백 KB |
| 태그 | `data_app_crash`(A908N 5건) · `system_server_wtf`(70건) · `storage_trim`·`SYSTEM_BOOT` | 잡음 태그가 대부분 → **회수 대상은 `*_anr`·`*_crash`·`<pkg>.crash` 계열만** |
| 본문 형식 | `--print '<시각>'` | 헤더 4줄 → `====` 구분선 → `2026-10-18 04:50:23 data_app_crash (text, 1871 bytes)` → `Process:`·`Package: com.x v1 (0.1.0)`·`Foreground:`·메타 → 빈 줄 → 예외 머리 |
| 사유 필드 | ANR vs 크래시 | ANR = `Subject: …` / 크래시 = 메타 뒤 **첫 줄**(예외 머리). 실측 A908N: `java.util.IllegalFormatConversionException: d != java.lang.String` |

## 3. 설계

```
매 폴링(tick) — DeviceMonitor.recoverFromDropbox(serial)   [5분 쿨다운]
  ├─ dumpsys dropbox                        (목록, 3.8~10.5KB)
  ├─ parseList → recoveryPlan(since: 기준선)
  │     · 첫 스캔 = 기준선만 설정, 발행 0 (과거 전건 폭주 방지)
  │     · 기준선은 **해당 태그 항목의 최신 시각** — 잡음이 쌓여도 밀리지 않는다
  │     · 같은 초의 여러 항목은 1회 조회로 함께 처리
  └─ 새 시각마다: --print '<시각>' | head -c 200000
        └─ parseBlocks → kind(forTag:) → packageName/reason
              └─ WatchEngine.feedAnr/feedCrash (5분 쿨다운) → ConsoleStore.ingestWatch
                    = Alerts·알림·자동 번들·진단 파이프라인에 **정상 이벤트**로 편입
```

### 중복 방지 (2중)

1. **시각 기준선** — 이미 본 시각 이하는 다시 보지 않는다. 발행 여부와 무관하게 매 스캔 전진.
2. **WatchEngine 5분 쿨다운** — logcat 이 같은 사건을 이미 발행했다면 여기서 걸린다.
   → logcat 이 먼저 보면 상세가 풍부한 logcat 이벤트가 남고, **놓쳤을 때만** dropbox 이벤트가 산다.

### 사건 시각은 dropbox 시각

`feedAnr/feedCrash` 에 `now: <dropbox 시각>` 을 넘긴다. 종전 logcat 경로는 *발행 시각*을 썼지만
(폴링 지연 2~12초), dropbox 는 **사건 시각을 직접 갖고 있다** → Alerts 정렬·일자 집계가 정확해진다.
미래 시각은 `min(시각, now)` 로 자른다.

## 4. 범위

| IN | OUT |
|----|-----|
| `DropboxLogLogic` (파싱·회수 선별·커맨드 조립, 순수) | `SYSTEM_TOMBSTONE`(네이티브 크래시) — 태그 체계가 다르다(다음 후보) |
| `DeviceMonitor.recoverFromDropbox` (5분 쿨다운 · 구조화 이벤트 발행) | dropbox 정리(`--clear`)·항목 삭제(커맨드 없음) |
| 매 폴링 1회 목록 스캔 | 상시 `--print` 전건 스캔(206KB/회 — 쓰지 않는다) |
| 스캔 결과 로그(대상 건수·기준선) | 사용자 설정 토글(현행 감시와 동일하게 항상 켬) |

## 5. 검증

- **순수 로직 30건** — `Tests/RelayConsoleTests/DropboxLogTests.swift`
  (픽스처는 **실기기 출력 그대로**: A908N `--print '2026-10-18 04:50:23'`, S901N 목록)
- **실기기 대조(에이전트 실측, 2026-10-18)** — 실측 출력 파일로 파서·선별 검증:
  A908N 75건 중 회수 대상 5건 · `since 04:50:23` → 발행 대상 3건(최신 우선) · 기준선 `04:53:00`
  · 실제 크래시 블록 → `pkg=com.borasarang.zenfreeproxy`, 사유 `IllegalFormatConversionException…`
  · S901N 33건 중 대상 0건 → 기준선 `없음`(잡음만 있어도 안전)
- **육안 69~71** — `docs/MANUAL_VERIFY.md` §28 (기기가 네트워크에 복귀하면 확인)

### 한계 (숨기지 않는다)

- 이벤트 발행은 **5분 쿨다운**을 공유한다 → 5분 안에 두 앱이 각각 ANR 나면 1건만 남는다(기존 logcat 경로와 동일 규칙).
- 기준선은 **5분 스캔**이라 새 ANR 이 최대 5분 늦게 뜬다(즉시성은 logcat 이 담당).
- 같은 초에 `data_app_anr`·`data_app_crash` 가 함께 있으면 1회 조회로 둘 다 처리하지만, 쿨다운 때문에 1건만 발행된다.
