# PLAN — S3 관제 규칙 Rules as Code (로컬 YAML) (2026-09-28)

> 성격: **신규 기능(설정 외부화) · TIER S 마지막 미착수** · S1·S2·S4 완료 후 남은 하나
> 관련: `docs/research/RESEARCH_competitive_v1.md` §TIER S **S3** · `docs/TODO.md`
> 브랜치: `feat/macos-rules-yaml` (main 직접 push 금지 — [HARD])

---

## 0. 착수 전 계측 — "무엇이 없나" 를 먼저 잰다

S3 의 정의는 **한 줄**이다: `관제 규칙 Rules as Code (로컬 YAML)`.
문법을 먼저 정하면 **문법이 쓰이기 전에 완성된다.** 그래서 코드부터 봤다.

### 0-1. 이미 있는 것 — 규칙 엔진은 있고, **값만 코드에 박혀 있다**

`WatchEngine.swift` 에 규칙 **7종**이 하드코딩되어 있다.

| 규칙 | 종류 | enter / clear / cooldown | 비고 |
|---|---|---|---|
| `throttling` | 발열 급등 | **3 / 2 / 60** | 절대온도가 아니라 **분당 변화율** |
| `chargeChanged` | 충전 상태 변화 | TransitionGate **5** | enter/clear 없음 (전이만) |
| `protectionChanged` | 보호 상태 변화 | TransitionGate **10** | |
| `lowPowerChanged` | 저전력 모드 변화 | TransitionGate **10** | |
| `psiPressure` | PSI 압력 | **5.0 / 3.0 / 120** | |
| `loadSpike` | load1 급증 | **cores×2 / cores×1 / 60** | **유일하게 파생값** |
| `memoryLow` | 메모리 부족 | **90 / 80 / 60** | |

`ThresholdGate` 는 hysteresis + 쿨다운을 이미 구현해 있다(플래핑 방지 포함).

**→ S3 의 실제 의미는 "규칙 엔진" 이 아니라 "임계값을 사용자가 바깥에서 정하게" 다.**
엔진은 이미 있다. 없는 것은 **입구**뿐이다.

### 0-2. ★ 그리고 아주 위험한 지점이 하나 있다

```swift
// ThresholdGate.swift:22
precondition(enter > clear, "ThresholdGate: enter must be > clear (hysteresis)")
```

`precondition` 은 **실패하면 즉시 죽는다**(`EXC_BREAKPOINT`).
YAML 로 값을 받는 순간, 사용자가 `enter: 3 / clear: 5` 를 쓰면 **앱이 크래시한다.**
사용자가 쓴 파일 때문에 앱이 죽는 것이다.

> **이 작업의 1순위 설계 항목은 YAML 파서가 아니다 — 이 `precondition` 을 죽이지 않는 경로다.**

## 1. 범위 — "확장" 이 아니라 "덮어쓰기"

DSL 을 새로 만드는 것은 위험하다(디버그할 수 없는 규칙 = 없는 규칙). 그래서:

| 한다 | 안 한다 |
|---|---|
| **기존 7종 규칙의 임계값을 YAML 로 덮어쓴다** | 새 규칙 종류를 YAML 로 정의 |
| `enter` / `clear` / `cooldown` 값 | **임의 수식·스크립트** |
| 규칙 **비활성화**(값을 안 주면 기본값 유지) | 규칙 추가(타입 확장) |
| 값이 잘못되면 **적용하지 않고 사유를 보인다** | 조용히 기본값으로 대체 |

- **파일이 없으면 지금과 완전히 동일하게 동작한다** (기본값 = 코드에 박힌 값)
  → 이 파일은 **선택 사항**이고, 없는 것은 정상 상태다
- `loadSpike` 는 파생값(`cores×2`)이므로 **절대값 override** 만 받는다
  (사용자가 `enter: 8` 이라 쓰면 코어수와 무관하게 8 이 된다 — 의도가 명확하다)

## 2. 스키마 (v1) — 작게, 그리고 예외를 만들지 않는다

```yaml
# ~/Library/Application Support/RelayConsole/rules.yaml
version: 1
rules:
  throttling:  { enter: 3,   clear: 2,   cooldown: 60 }   # 분당 °C — 절대온도가 아니다
  psiPressure: { enter: 5.0, clear: 3.0, cooldown: 120 }
  memoryLow:   { enter: 90,  clear: 80,  cooldown: 60 }
  loadSpike:   { enter: 8,   clear: 4,   cooldown: 60 }   # 비우면 코어수 파생값 사용
  chargeChanged:   { cooldown: 5 }
  protectionChanged: { cooldown: 10 }
  lowPowerChanged:   { cooldown: 10 }
```

- **전이 전용 규칙**(charge·protection·lowPower)은 `cooldown` 만 갖는다 → 스키마가 규칙마다 달라진다
  → 그래서 **검증기가 규칙 종류를 알아야 한다** (= 코드 knowledge). 이 정합성이 깨지면 조용히 무시된다.
- 미지의 키는 **오류로 보고한다**(조용한 무시는 [표시②] 위반)

## 3. 검증 — 파일은 사용자 입력이다

`rules.yaml` 은 **사용자가 손으로 쓴 텍스트**다. 앱 밖에서 온 데이터와 같다.

| 규칙 | 이유 |
|---|---|
| `enter > clear` 를 **생성 전에** 검사 | `precondition` 크래시 방지(§0-2) |
| `cooldown ≥ 0` · 값은 유한수(NaN/Inf 금지) | NaN 은 비교가 항상 false → 게이트가 조용히 죽는다 |
| 파싱 실패 → **적용 안 함 + 사유 표시** | 조용히 기본값으로 대체하면 "내 설정이 적용됐는데 안 된다" |
| 스키마 버전 불일치 → **적용 안 함 + 사유** | 조용히 무시하면 낡은 파일이 조용히 버려진다 |
| 파일 크기 상한 (예: 64KB) | 무한정 파싱은 DoS |

**적용 실패는 앱을 죽이지 않고 화면에 남긴다** — `storeProblem` 패턴(2026-09-26 도입)을 그대로 재사용.

## 4. 변경 범위 (예상)

| 파일 | 변경 |
|---|---|
| `Sources/RelayConsole/Droid/RulesConfig.swift` | **신규** — 파서·검증기·스키마 (순수 로직) |
| `Sources/RelayConsole/Droid/WatchEngine.swift` | 게이트를 하드코딩 대신 주입된 설정으로 |
| `Sources/RelayConsole/App/ConsoleStore.swift` | 기동 시 1회 로드 + `rulesProblem` 표시 |
| `Resources/{en,ko}.lproj/Localizable.strings` | 오류 문구 en/ko 1:1 |
| `Tests/RelayConsoleTests/RulesConfigTests.swift` | **신규** — 검증기 (crash 회귀 포함) |

## 5. 하지 않는 것 (기록)

- **YAML 라이브러리 도입** — 외부 의존성은 [HARD] 검토 대상. 우선순위 낮은 키만
  제한된 파서로 읽고, **파서가 모르는 것은 오류로 보고** 한다
- 설정 UI(편집 화면) — 파일을 직접 편집한다. v1 은 **읽기만**
- 규칙 추가/삭제 — 7종 고정
- 원격 동기화 — 로컬 파일

## 6. 착수 순서 (계측 우선, 이 계획대로)

1. `RulesConfig` 순수 파서 + 검증기 + **크래시 회귀 테스트** (`enter ≤ clear` 로 죽지 않는지)
2. `WatchEngine` 이 하드코딩 대신 설정을 받게 — **값이 없으면 지금과 동일**함을 테스트로 고정
3. 기동 시 1회 로드 + 오류 표시
4. 검증: `swift test` → `build-macos.sh` → **실기에서 파일을 실제로 만들어** 반영 확인
   (정상 파일 · 잘못된 값 · 깨진 YAML 3종)

## 7. 열려 있는 질문 (착수 시 답을 정한다)

- `rules.yaml` 를 **사용자가 어디서 아는가** — 앱이 경로를 화면에 보여 주고
  "기본 파일 내려쓰기" 버튼을 둘까, 아니면 문서로만 알려 줄까
  → 표시② 관점에서 **경로를 보이는 곳에 보여 주는 것**이 최소 요건
- ThresholdGate 의 `precondition` 을 **오류로 바꾸어야 하는가** —
  지금은 죽는다. `assert` 로 낮출지, `init` 이 실패를 반환하게 바꿀지.
  → **계측 전에 건드리지 않는다.** YAML 경로에서만 사전 검증하고, 그 사실을 코드에 적는다
