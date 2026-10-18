# PLAN_local_mcp_relayconsole.md — A10 로컬 MCP 서버

> 생성일: 2026-09-24 | 상태: **구현 완료** (사용자 일괄 검토 대기) · bd: `RelayConsole-yzw`
> 모체: `RESEARCH_competitive_v1` §8 **P3** · openstatus·adb-tui
> 앱: **Relay Console** | 목표 버전: **1.10.0** | 최소 OS: **macOS 26.0**

---

## 1. 목표

**읽기 전용 로컬 MCP 서버**(`relay-mcp`)를 제공해 Claude 등 MCP 클라이언트가
기기·사이트·작업·감시 이벤트를 조회한다. 서버·클라우드 없음(stdio).

| 도구 | 데이터 소스 |
|------|-------------|
| `list_devices` | `adb devices -l` 파싱 |
| `list_sites` | `~/Library/Application Support/RelayConsole/sites.json` |
| `list_jobs` | `jobs.json` |
| `list_events` | `watch-events.json` (최신 N) |
| `get_summary` | 위 4종 집계 (down/overdue/critical) |

### OUT
- 쓰기 도구(사이트 추가·ack·기기 실행) · HTTP/SSE 원격 · OAuth · 앱 UI 내 MCP 토글

---

## 2. 범위

| IN | OUT |
|----|-----|
| `RelayMcpCore` 라이브러리 (프로토콜·로직·스토어) | 실시간 DeviceMonitor 연동 |
| `relay-mcp` 실행 파일 (stdio 루프) | 사이드바 MCP 설치 마법사 |
| 읽기 전용 5도구 | 도구 쓰기·인증 |
| Claude Desktop 설정 예시 (README/Settings help) | — |

---

## 3. 설정키

| 키 | 타입 | 기본 | 설명 |
|----|------|------|------|
| — | — | — | CLI 전용 · AppStorage 없음 |

---

## 4. 모델·로직

```swift
// RelayMcpCore (순수 · 테스트)
enum McpJsonRpc: Decodable   // request / notification / response
struct McpTool               // name, description, inputSchema
enum McpRouter               // initialize · tools/list · tools/call · ping
struct RelayDataStore        // load sites/jobs/events from Application Support
enum AdbDevicesParser        // "List of devices attached" + lines → [McpDevice]
```

stdio: **줄바꿈 구분 JSON-RPC 2.0** (MCP 표준). stdout에만 응답, 로그는 stderr.

---

## 5. UI

- 설정 → 연동/정보: `relay-mcp` 경로·Claude `mcpServers` JSON 조각 (읽기 전용 help)

---

## 6. 파일 변경

| 파일 | 변경 |
|------|------|
| `Package.swift` | `RelayMcpCore` library + `relay-mcp` executable |
| `Sources/RelayMcpCore/*` | Protocol · Router · Store · AdbParser (신규) |
| `Sources/RelayMcp/main.swift` | stdio loop (신규) |
| `Tests/RelayConsoleTests/Mcp*Tests.swift` | 프로토콜·파서·집계 |
| `Views/SettingsView.swift` | MCP help 한 줄 |
| i18n 3처 | `settings.mcp.*` |
| 버전 7처 | **1.10.0** |

---

## 7. DoD

- [x] initialize / tools/list / tools/call / ping 회귀 테스트
- [x] sites·jobs·events 로드 + adb devices 파서 테스트
- [x] `relay-mcp` 실행 · echo initialize 파이프 확인
- [x] i18n 3처 parity **499키** · 금지 grep 0 · `%s` 0
- [x] `swift test` **59 + 209** · `build-macos.sh debug` **1.10.0**
- [ ] 사용자 일괄 검토

---

## 8. 버전 1.10.0 동기화처

Info.plist · build-macos.sh(3) · AppDelegate · SettingsView · MenuBarPopoverView · AGENTS.local.md · README.md

---

## 9. 확장 — 진단 축 도구 3종 (1.20.0 · 2026-10-18)

> TODO **T-2026-10-17-7** (리서치 v2 §4.2 M4 · §5.2 P2-2) · bd `RelayConsole-1az`
> 원칙 유지: **읽기 전용 · 쓰기/제어 도구 없음** — mobile-mcp 계열(제어 자동화)과 다른 축은 **진단**.

### 도구 (총 6종)

| 도구 | 데이터 소스 | 인자 |
|---|---|---|
| `list_devices` | `adb devices -l` | — |
| `list_events` | `watch-events.json` | `limit` · `severity` · **`serial`**(신규) |
| **`list_diagnoses`** | `diagnoses.json` (`crash`·`throttling`) | `kind` · `serial` · `limit` |
| **`list_incidents`** | `incidents/<ts>-<kind>-<serial>/manifest.json` | `kind` · `serial` · `limit` |
| **`get_device_history`** | `device-daily.json` | `serial` · `days` |
| `get_summary` | 위 집계 + **`diagnosedCrashes`·`incidentBundles`**(신규) | — |

### 설계 메모

- **지문에서 시리얼 추출**: 지문이 `192.168.86.30:5555:crash:com.x:Exc` 형태라 시리얼 자체가 `:` 를 품는다 →
  `<kind>` 토큰 **앞부분**을 시리얼로 본다(`McpDataStore.fingerprintSerial`). 시리얼 필터는 부분 일치 허용
- **인시던트 번들**: 디렉터리 이름(`yyyyMMdd-HHmmss-…`)이 최신순 정렬 키 → **매니페스트를 상한만큼만 읽는다**(389개 번들에서 전수 파싱 회피).
  크기는 매니페스트가 나열한 파일만 합산(`sizeBytes`)
- **일일 추이**: 기기별 **최신 `days` 일**만 남기고 **오래된 → 최신** 순으로 반환(추세 읽기) · 수치는 소수 1자리 반올림
- 상한 규칙 통일 `1~100`(`days` 는 `1~90`) · 없는 기기·데이터 없음은 **오류가 아니라 빈 배열**

### 검증 (에이전트 실측 · 2026-10-18)

`relay-mcp` 를 stdio 로 파이프해 **실제 앱 데이터**로 확인:

```
{"method":"tools/list"}                                  → 6종(list_devices·list_events·list_diagnoses·list_incidents·get_device_history·get_summary)
list_diagnoses {kind:crash, limit:2}                     → 실제 크래시 2건(최신순)
list_incidents {limit:2}                                 → 20261018-174319-crash-192.168.86.30-5555 (files 3 · sizeBytes)
get_device_history {serial:"RFCM9059YBB", days:3}         → 1행(존재하는 날짜만)
get_device_history {days:1}                              → 14행(기기별 최신 1일)
list_events {serial:"192.168.86.30", limit:1}             → 해당 기기 이벤트 1건
get_summary                                              → diagnosedCrashes 263 · incidentBundles 389 · version 1.20.0
list_diagnoses {serial:"없는기기"} · get_device_history {serial:"없는기기"} → [] (오류 아님)
```

`swift test` — McpProtocolTests **+7**(지문 파싱 · 진단 필터/정렬 · 번들 매니페스트/크기 · 일일 추이 상한·반올림 · 이벤트 시리얼 필터 · 요약 집계 · 라우터 경유).
