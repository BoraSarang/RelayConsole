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
