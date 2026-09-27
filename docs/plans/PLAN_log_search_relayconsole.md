# PLAN_log_search_relayconsole — 로그 뷰어 검색 (macOS)

> 착수: 2026-09-27 · 규모 M (기존 화면 신규 기능) · 상태: **완료 (육안만 대기)**
> 선행: `PLAN_v0.7_relayconsole.md` §4(로그뷰어) · 결함 2건은 그 §8 에 기록

---

## 0. 왜 필요한가 (계측이 먼저다)

로그 창에는 레벨 필터(D/I/W/E)만 있고 **텍스트 검색이 없다.** 그런데 이 기기의 실측은:

| 측정 | 값 |
|---|---|
| `adb logcat '*:W'` 유입 | 3초 42,573줄 = **초당 1.4만 줄** |
| 링 버퍼 2000행이 담는 시간 | 2000 ÷ 14,000 = **0.14초** |
| `--regex` 지원 | 정상 동작(오류 없음) |
| 잘못된 정규식 | stderr `regex_error was thrown in -fno-exceptions mode` → 이미 배수 중 |

즉 **화면에 보이는 2000행은 사람이 읽을 수 있는 시간(0.14초)도 안 된다.**
클라이언트에서만 거르려면 `1.4만 × 0.14초 = 약 2천 줄`을 매 순간 새로 놓친다.
**검색은 기기(adb) 쪽에서 걸어야 실제로 쓸 만해진다.** (`logcat --regex=<패턴>`)

## 1. 결정 (사용자 확정)

- **① adb 측 1차 + 링 버퍼 2차 필터** — 2차는 "디바운스 대기 중 즉시 반응" + "adb 미지원 기기 graceful degradation"
- **② 단순 문자열 + 프리셋 칩 + 대소문자 무시 토글** — 정규식 문법은 사용자가 다룰 일이 없다고 판단 (오류 위험 대비)

## 2. 범위

### IN
- 검색어 입력창 (문자열) · 지우기 버튼 · `Aa` 대소문자 무시 토글
- 프리셋 칩 4종: `ANR` / `FATAL EXCEPTION` / `has died` / `dropbox`
- adb `--regex` 1차 필터 (**300ms 디바운스** — 입력 중 adb 를 새로 띄우지 않는다)
- 링 버퍼 2차 필터(`visibleLines`) — 즉시 반응 + adb 미지원 대비
- 상태 구분 [표시②]: **"일치 없음"** 과 **"데이터 없음"** 을 분리. stderr 이 있으면 adb 오류를 그대로 노출
- 헤더에 `수신 M · 일치 N` 표시 / 푸터에 **"기기 필터 <검색어>"** 배지로 기기 측 필터 사실을 노출

### OUT (의도적 제외 — 이유와 함께)
- **정규식 문법** — 사용자가 오타로 adb 를 죽인다. 잘못된 패턴은 stderr 로 노출되지만 UX 가 나쁘다
- **일치 부분 하이라이트** — 링 2000행 × 초당 1.4만 줄. `AttributedString` 을 행마다 다시 만들면
  이미 CPU 100% 인 앱에 더 얹는다. **성능 예산으로 제외**
- `logcat -b` 버퍼 선택(crash/main/system) — 별도 축. 필요 시 다음 PR

## 3. 설계

### 3.1 필터 로직 (순수 함수 — 테스트 대상)
```
LogcatFilter.pattern(for:caseInsensitive:) -> String?
    · 비어 있으면 nil (= adb 필터 없음)
    · 정규식 메타문자 이스케이프(NSRegularExpression.escapedPattern) — "단순 문자열" 계약의 핵심
    · caseInsensitive → 접두 "(?i)" (logcat --regex 는 Java Pattern 이므로 지원)
LogcatFilter.matches(_ line:, query:, caseInsensitive:) -> Bool
LogcatFilter.silence(query:stderr:isSilent:isStalled:) -> (key, args)?
```
`silence` 를 순수 함수로 뺀 이유: `LogcatStreamer` 가 싱글턴 + `start()` 가 실제 adb 를 필요로 해서
"검색 중 0건" 상태를 단위 테스트로 고정할 방법이 없다. 판단만 떼어 내면 고정된다.

### 3.2 스트림 재기동
- 입력 → `query` 즉시 반영(로컬 필터) → **300ms 후** adb 재기동 (`searchTask` 취소 후 재설정)
- `start()` 인자에 `["--regex=\(pattern)"]` 추가 (Process 배열 인자라 셸 인용 위험 없음)
- 재기동은 기존 경로를 그대로 쓴다 → **종료 알림 경쟁(2026-09-27 e40d1d1) 수정 사항이 그대로 적용**된다
- 디바운스 중에는 이전 스트림이 계속 살아 있어 **"일치 없음" 깜빡임이 없다**

### 3.3 필터 캐시
`visibleLines` 는 body 평가마다(초당 수십 회) 다시 계산되면 안 된다.
`(lines.count, first?.id, last?.id, query, caseInsensitive)` 를 키로 하는 메모를 둔다.
`body` 는 필터를 **한 번도 직접 계산하지 않는다**(읽기만).

### 3.4 L10n (en/ko 1:1 · 8키)
| 키 | ko | 비고 |
|---|---|---|
| `droid.logs.search.placeholder` | 검색 (ANR, FATAL, 태그) | |
| `droid.logs.search.clear` | 지우기 | |
| `droid.logs.search.ci` | 대소문자 무시 | `Aa` 로도 표시 |
| `droid.logs.search.none` | ‘%@’ 와 일치하는 줄이 아직 없습니다 | `%@` |
| `droid.logs.search.none.err` | 일치 없음 — adb 오류: %@ | `%@` (잘못된 패턴이 여기에 뜬다) |
| `droid.logs.matched` | 일치 %d줄 | `%d` — 숫자 키 규칙 준수 |
| `droid.logs.ring.filtered` | 기기 필터 %@ · 최근 2000행 | `%@` — **기기에서 걸린다는 사실을 숨기지 않는다** |
| 프리셋 4종 | ANR / FATAL EXCEPTION / has died / dropbox | |

`%d` 로 줄 수를 표현하는 규칙은 이번 크래시(`%@` 에 숫자 → SIGSEGV) 교훈의 직접 반영이다.

## 4. UI

```
┌ 기기명 · ● LIVE · 수신 1,234줄 · 일치 12줄 · [닫기]
├ [🔍 검색 (ANR, FATAL, 태그)…      ] [Aa] [지우기]
├ [ANR] [FATAL EXCEPTION] [has died] [dropbox]        ← 활성 칩 강조
├ ─────────────── 스트림(일치만) 또는 상태 문구 ───────────────
├ [시작/중지] [D I W E] [☑ 자동 스크롤]   기기 필터 ANR · 최근 2000행
```

- 다크 전용 유지(AGENTS.local §4) · `OPFont` 토큰만 사용 · 임의 색상 금지
- 칩은 AlertsView `filterChip` 과 같은 형태(라운드 + border) → **여러 화면이 같은 문법**

## 5. 테스트 (신규 8건 + 기존 539 유지)
1. `pattern` — 메타문자 이스케이프 (`a.b` → `a\.b`) · `(?i)` 접두 · 빈 문자열 → nil
2. `matches` — 부분 일치 / 대소문자 구분 / 무시
3. `silence` — 검색 중 + 0줄 + stderr 없음 → `search.none` / stderr 있으면 `search.none.err` / 검색 없으면 기존 키
4. L10n en/ko 키 대칭 + **변환자 나열** 대조 (기존 전수 스캔이 새 호출부까지 자동 검증)
5. 소스 스캔 — 새 `L10n.format` 호출부의 인자 수 == 변환자 수 (자동)

## 6. 검증 (DoD)
- [x] `swift test` **447 + 104 = 551 / 0 failed** (기존 539 유지 + 신규 12)
- [x] `./scripts/build-macos.sh debug` **EXIT=0** (앱 + appex 팀 `6GPJQ7BQC9` 일치)
- [x] L10n **755키 en/ko 1:1** · U+FFFD 0건 · 신규 컴파일 경고 0
- [x] **계측**: 자식 adb argv 가 `*:W --regex=<검색어>` 로 바뀜 = 기기에서 실제로 걸러짐
- [x] **계측(성능)**: 검색 전 CPU **89~104%** → 검색 중 **1.4~14%** = 볼륨이 실제로 줄었다
- [x] **계측(누산)**: 타이핑 중에도 자식 adb **1개 유지** = 디바운스 + `LogcatProcessSlot` 둘 다 작동
- [ ] **육안** (사용자): 검색어 타이핑 → 즉시 필터링 / 프리셋 칩 4종 / `Aa` / 지우기 / 0건 문구

## 7. 남기는measurable 사실

- CPU 104% 는 **검색과 무관한** 현상이다(링 2000행 렌더 × 초당 1.4만 줄).
  검색으로 유입량이 줄면 **곧장 CPU도 내려간다** — 이 기능을 계측 계기로도 쓴다.
- `--regex` 는 **기기(logcat) 측** 필터다. 필터 중에는 그 이전 구간이 **되돌아오지 않는다**
  (ADB 로그 버퍼가 롤링). "지금 이 순간"만 볼 수 있다는 사실을 UI 배지로 밝힌다.
