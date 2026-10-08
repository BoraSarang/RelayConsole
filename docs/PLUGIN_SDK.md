# Plugin SDK v2 — RelayConsole 소비 표준

> 소유: RelayConsole (`docs/PLUGIN_SDK.md`가 유일 원천).
> 제공자(SpotShift·DroidRelay·향후 앱)는 이 문서만 보고 구현한다. 각 앱 문서는 구현 기록만 남기고 규칙은 여기를 가리킨다.
> 원칙: **제공자는 제공만, 소비자는 사용만.** 어느 한쪽이 꺼져·중단돼도 다른 쪽은 정상 동작. 상시 연결 없음 — adb 요청 시점에만 만남.

## 0. 용어

- 제공자(provider): Android 앱. 능력을 선언하고, 요청을 받고, 로그로 보고한다.
- 소비자(consumer): RelayConsole 등 macOS 측. adb 너머라 푸시를 받을 수 없어 **읽기(스크랩)**만 한다.
- 계약 버전: `[PLUGIN]` 줄의 `version=` 정수. 깨지는 변경마다 올림만.

## 1. 적합 레벨

| 레벨 | 요구 | 비고 |
|---|---|---|
| L1 Basic | §2 프로브 + §4 액션 + §5 `[REMOTE]` + §7·§8·§9 | 당장 동작하는 최소선. 이름·설명은 소비자 명단 폴백 |
| L2 Full | L1 + §3 메타데이터 + §6 `[EVENT]` | 탭에 카드가 rich 하게 나오고 알림까지 가는 완성형 |

v1 앱(SpotShift v1.1, DroidRelay v1)은 L1 상당이다. v2 승격 조건은 §10 체크리스트 전부.

## 2. Discovery (L1)

### 2.1 정적 명찰 (문서용)

`AndroidManifest` application meta-data 3키. 동작에 안 쓰이고 사람이 읽는다.

- `<pkg>.plugin.version=2`
- `<pkg>.plugin.actions=<id 콤마 나열>`
- `<pkg>.plugin.logTag=<TAG>`

### 2.2 프로브 (실제 discovery)

소비자는 명시적 브로드캐스트로 질의한다. 앱이 꺼져 있어도 응답해야 하며 UI를 띄우지 않는다.

```bash
adb -s <serial> shell pm list packages | grep <package>
adb -s <serial> shell am broadcast -a <package>.PLUGIN_PROBE -n <package>/.receiver.PluginProbeReceiver
adb -s <serial> shell logcat -d -s <TAG>:*
```

응답 (한 줄, §5.4 형식 규칙 준수):

```
[PLUGIN] version=2 actions=<id,...> logTag=<TAG> allowed=<true|false> appVersion=<x.y.z>
```

- `allowed=false`여도 응답한다 (꺼짐 상태 전달). 무응답 = 미설치 또는 구버전.
- `appVersion`은 L1부터 필수 (dumpsys를 때리지 않게).
- 액션 id는 `snake_case` 영문. 콤마 구분, 공백 없음.

## 3. 메타데이터 Provider (L2)

한 명령으로 표시 정보를 전부 준다. logcat 한 줄 상한(약 4KB)을 피하기 위한 채널이다.

```bash
adb -s <serial> shell content query --uri content://<package>.plugin/info
```

단일 행, 컬럼:

| 컬럼 | 예 | 필수 |
|---|---|---|
| `label` | `DroidRelay` | 필수 (표시 이름, 공백 허용 — 이 채널은 logcat이 아니라서 자유) |
| `description` | `기기 내 다운로드·토렌트 관제` | 필수 (1줄) |
| `contractVersion` | `2` | 필수 (`[PLUGIN]` version과 동일) |
| `appVersion` | `0.50.0` | 필수 |
| `allowed` | `true` | 필수 (프로브와 동일 값) |
| `iconBase64` | `iVBORw0KGgo…` | 선택 (96px PNG, 비어 있으면 소비자 폴백 아이콘) |
| `actionsJson` | 아래 스키마 | 필수 (L2의 핵심 — 액션 정의를 기기값으로) |

`actionsJson` (JSON 배열, 소비자 제네릭 렌더러의 입력):

```json
[
  {"id":"server_status","title":"서버 상태 조회","kind":"button",
   "invoke":{"via":"broadcast","component":".receiver.PluginActionReceiver","action":"com.x.PLUGIN_ACTION","extra":{"cmd":"server_status"}}},
  {"id":"download_add","title":"URL 추가","kind":"text","hint":"https://…",
   "invoke":{"via":"broadcast","component":".receiver.PluginActionReceiver","action":"com.x.PLUGIN_ACTION","extra":{"cmd":"download_add","arg":"$input"}}},
  {"id":"autorotate","title":"IP 변경 요청","kind":"button",
   "invoke":{"via":"broadcast","component":".receiver.PluginActionReceiver","action":"com.x.PLUGIN_ACTION","extra":{"cmd":"autorotate"}}}
]
```

- `kind`: `button` (인자 없음) | `text` (1줄 입력, `$input` 치환).
- `via`: `broadcast` 권장. `component`는 패키지 기준 상대 경로 (명시적 발송용, §4.1). `activity` (NoDisplay 트램펄린 한정, §4.3) 허용.
- `title·hint`는 제공자 로케일 1종(ko 권장). 소비자 L10n이 덮지 않는다 — 제공자가 말하는 이름 그대로 보여준다.
- 쿼리 실패·Provider 부재 = L1 폴백 (소비자가 죽지 않는다).

## 4. 액션 호출

fire-and-forget. 결과 대기 없음 — 결과는 §5 로그로만 온다.

### 4.1 권장: 브로드캐스트 (UI 없음, 명시적 필수)

```bash
adb -s <serial> shell am broadcast -a <package>.PLUGIN_ACTION -n <package>/.receiver.PluginActionReceiver --es cmd <action_id> [--es arg "<값>"]
```

`-n` 컴포넌트 지정 필수 — 암시적 브로드캐스트는 백그라운드 실행 제한으로
매니페스트 리시버에 배달되지 않는다 (실측: `-n` 없이 무응답, `-n` 명시 즉시 동작).
실행 주체는 Receiver. Activity를 거치지 않으므로 전면 전환이 없다.

### 4.2 허용: NoDisplay 트램펄린

`Theme.NoDisplay` Activity가 받아 실행 후 즉시 `finish()`. 화면이 뜨지 않는다.

### 4.3 금지: MainActivity 전면 경로 (v1 잔재, 폐지 예정)

v1(SpotShift·DroidRelay)이 쓰던 `am start …/.MainActivity`는 요청 때마다 앱이 전면으로 뜬다 — 실측 확인. **신규 구현 금지**, 기존은 L2 승격 시 제거.

### 4.4 입력 검증

빈 값·형식 위반은 실행 없이 실패 로그 (§5 `ok=false`). 검증 규칙은 `actionsJson` 문서가 아니라 **실패 로그가 말해준다** (소비자는 규칙을 하드코딩하지 않는다).

## 5. `[REMOTE]` 결과 로그 (L1)

태그: `<TAG>` (`logcat -d -s <TAG>:*`).

```
[REMOTE] action=<id> ok=<true|false> <필드…> [note=<꼬리 자유문>]
[REMOTE] 거부됨 (연동 OFF)
```

- `action=`·`ok=` 필수 (단일 액션 앱도 생략 금지 — v1 SpotShift 잔재, v2에서 메움).
- 성공 필드는 액션별 자유 (`running=`·`ip=`·`port=`·`version=`·`id=`·`duplicate=` 등). `duplicate=true`는 실패가 아니다.
- 실패는 `errorCode=` 필수 + `note=` 원인 한 줄. 원인 없는 실패 금지.
- 거부 형식 고정 (`거부됨 (연동 OFF)`). OFF여도 이 줄은 낸다.
- 같은 요청의 답은 여러 줄일 수 있으나 소비자는 **마지막 한 줄을 진실**로 본다.

### 5.1 에러코드

형식 `E-<SRC>-PLG-<4자리>`. 공통 의미 고정, SRC는 제공자 식별:

| 코드 | 의미 |
|---|---|
| `E-*-PLG-0001` | 연동 거부 (OFF·권한) |
| `E-*-PLG-0002` | 입력 무효 (빈 값·형식 위반·중복 아님) |
| `E-*-PLG-0003` | 실행 실패 (원인 포함) |

(DroidRelay `E-AND-PLG-0001~0003`은 그대로 적합 예시.)

### 5.2 형식 규칙 (파서 계약)

- `key=value`, 값은 **공백·콤마·대괄호 전까지**. 사람 문장은 맨 뒤 `note=` 꼬리에만.
- 필드 추가는 기존 파서가 안 깨지는 선에서 허용 (뒤에 붙이기만). 순서 변경·이름 변경·삭제 = 계약 버전 올림.
- 정규식으로 파싱 가능해야 한다. 예시를 스펙에 박지 않고 테스트 벡터(§11)로 고정한다.

## 6. `[EVENT]` 이벤트 로그 (L2, 제공자발)

완료 알림은 요청의 답이 아니라 제공자가 먼저 내는 소식이다. 소비자는 구독 없이 같은 덤프에서 긁는다.

```
[EVENT] type=<id> id=<중복제거키> level=<info|warning|critical> <필드…>
```

- `type=`·`id=`·`level=` 필수. `id`는 작업·사건 단위 키 (소비자 중복 제거용).
- `level`이 오면 소비자는 타입별 매핑표 없이 알림 심각도를 정한다.
- 보장 배송 아님 (logcat 링버퍼, 폴링 사이 유실 가능). 소비자는 `id` 중복 제거 + 마지막 한 건을 진실로 본다.
- 제공자 측 폴링 없음 — 상태 전이 지점에서 1회 emit. `allowed=false`면 미발행.
- 최소 요구: 자율 동작이 있는 앱은 그 완료를 최소 1종 EVENT로 낸다 (예: SpotShift `type=ip_changed`).

## 7. ON/OFF

- 제공자 설정 `연동 허용` (기본 ON). OFF면 액션 무시 + 거부 로그 + 이벤트 미발행.
- 소비자도 자체 토글 보유. **양쪽 AND** — 한쪽이라도 OFF면 조용히 각자.
- 거부·미지원은 에러코드 + 원인 포함.

## 8. 릴리즈·단일 emit (계약 조건)

- 계약 로그(`[PLUGIN]`·`[REMOTE]`·`[EVENT]`)는 **`android.util.Log` 직접 출력**. 로거 래퍼 경유 금지 (릴리즈에서 `DEBUG` 조기반환으로 증발하는 함정 — 실측 계열).
- **한 사건 한 줄.** 래퍼 포맷 중복 출력 금지 (DroidRelay 이중로그 실측 — 스크랩 노이즈 2배).

## 9. 버전 규칙

- 계약 버전은 정수 올림만. 필드 추가는 §5.2 범위에서 허용.
- 모르는 버전·모르는 액션을 만나면 소비자는 연동 끄고 `미지원` 표시. 추측 실행 금지.
- v1 형태 폴백: 소비자는 v1 줄(`action=` 없음 등)도 읽되, v2 승격 전까지 L1로만 취급한다.

## 10. L2 승격 체크리스트 (제공자용)

- [ ] §2 프로브 (앱 미실행 응답, UI 없음)
- [ ] §3 Provider (`info` 1행, `actionsJson` 전 액션 기술)
- [ ] §4 브로드캐스트/NoDisplay (전면 전환 없음 — `brought to the front` 실측 0건)
- [ ] §5 `[REMOTE]` (`action=`·`ok=` 전부, 실패 `errorCode=`)
- [ ] §6 `[EVENT]` (자율 동작 최소 1종, `type`·`id`·`level=`)
- [ ] §8 직접 로그 + 단일 emit (릴리즈 서명 APK에서 `logcat -d -s <TAG>:*`로 계약 줄 확인)
- [ ] 거부 경로 (`연동 OFF` → 거부 로그, 이벤트 침묵)

## 11. 테스트 벡터 (실측)

```
[PLUGIN] version=1 actions=autorotate logTag=SpotShift allowed=true
[REMOTE] 원격 변경 결과 changed=true 118.235.3.241 → 39.7.46.252 측정 2.16Mbps ≥ 기준 2.0Mbps — 달성
[PLUGIN] version=1 actions=server_status,server_control,download_add,torrent_add logTag=DroidRelay allowed=true
[REMOTE] action=server_status ok=true running=true ip=10.112.134.138 port=3000 version=0.50.0
[REMOTE] action=download_add ok=false errorCode=E-AND-PLG-0002 note=invalid url
[REMOTE] 거부됨 (연동 OFF)
[EVENT] type=download_complete id=abc123 filename=a.mp4 bytes=12345
```

## 12. 소비자 동작 (RelayConsole 바인딩)

- 검색 버튼 1회 스윕만 (`pm 1` → 프로브 일괄 → 2초 → `logcat 1`). 폴링 없음.
- 명단은 패키지 + 메타 URI만. 표시·액션 전부 기기값 제네릭 렌더.
- 아이콘은 versionCode 키 캐시, 없으면 SF Symbol.
- EVENT → 알림: `(plugin,type,id)` 영속 중복제거 + `level` 매핑 + 기존 쿨다운·토글. 스윕 때만 수집(실시간 아님)임을 UI에 명시.
- 실패 표시는 stderr·에러코드 원문 유지, 기기 지칭은 serial 원문.

## 13. 변경 이력

- v1 (2026-10-08): SpotShift `autorotate` 1액션 + 로그 보고. (SpotShift T-32/33)
- v1 (2026-10-08): DroidRelay 액션 4종 + 결과/이벤트 로그. (DroidRelay T-1095)
- v2 초안 (2026-10-08): 본 문서. L1/L2 분리, 메타데이터 Provider, `action=`·`errorCode=`·`level=` 필수화, 전면 금지, 단일 emit. v1 잔재 4건 (§4.3·§5·§8) 명시.
- v2 적용 (2026-10-08): SpotShift PR #18 — Provider에 96px PNG `iconBase64` 제공 (어댑티브 벡터 렌더, 실패 시 `""` 폴백).
- v2 적용 (2026-10-08): DroidRelay — ProbeReceiver 신 경로 응답 부활 + 96px PNG `iconBase64` 제공. 양쪽 L2 메타데이터 완비.
