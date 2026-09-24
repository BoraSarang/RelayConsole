# PLAN_v0.7_relayconsole.md — scrcpy 미러링(A) + 감시 마감 + 썸네일·로그뷰어

> 생성일: 2026-09-24 | 상태: **완료 (DoD · 실기 육안 ✓ 2026-09-24)**
> 모체: `PLAN_v0.6_relayconsole.md` · `RESEARCH_droid_devicecare.md` · 사용자 `scrcpy_run.sh`
> 앱: **Relay Console** | bundleId: **`com.borasarang.relayconsole`** | 목표 버전: **0.7.0** | 최소 OS: **macOS 26.0**

---

## 0. 확정 사항 (사용자)

| # | 항목 | 결정 |
|---|------|------|
| 1 | scrcpy | **A안(외부 프로세스 실행)** — B안 내장 미러링은 백로그 |
| 2 | 설치 | 미설시 → 시트에서 **Homebrew 원클릭 설치** (사용자 확인 1회) · 설치 후 버튼 활성 |
| 3 | 기본 옵션 | `scrcpy_run.sh` 8개 디폴트 · 설정에서 noControl·추가 옵션·경로 편집 |
| 4 | 범위 | 표 1–5 **전부 포함** (Bsoh·RSRP·복구알림·썸네일·로그뷰어) |
| 5 | 정책 | **C3 "Scrcpy 버튼 없음" 공식 해제** (승인) · 금지 grep `Scrcpy` 해제 |

## 1. 범위 (IN / OUT)

| IN | OUT (백로그) |
|----|----------------|
| `[미러링]` 헤더 버튼 (팝오버·대시보드) — A안 | B안 내장 미러링 |
| 설치 감지 → brew 원클릭 → 활성화 | ANR/크래시 logcat 확장 (v0.8) |
| 기본 opts = 스크립트 흡수 · `relay.scrcpy.*` | 카드 On/Off (v0.9) |
| `feedBsoh` — Δ≥5pt 하락 1회성 | GRDB / ntfy / Apple |
| `feedRsrp` — Δ≤−6 / level 하락 | WiFi/tcpip 연결 복구 (스크립트 로직) |
| 복구 자동 알림 토글 (`relay.watch.recovery`) | 임계값 슬라이더 |
| screencap 썸네일 (수동·연결 시 1회) | 스크린 레코딩 |
| 로그 뷰어 창 `id:"logs"` (logcat 스트림) | 플로팅 오버레이 |
| C3·금지 Scrcpy 해제 · AGENTS.local 정정 | |

## 2. scrcpy A안

### 설치·활성화

```
findScrcpy(): relay.scrcpy.path → /opt/homebrew/bin → /usr/local/bin → PATH
  ├ 있음 → [미러링] (serial 지정 실행)
  └ 없음 → [미러링 설치…] 시트
       [Homebrew로 설치] → brew install scrcpy (확인 후)
       [터미널에서 열기] / [나중에]
       종료 → 재탐지 → 성공 시 활성 + 알림
```

- 자동 curl/다운로드 **금지** 유지 — brew는 **사용자 확인 1회**만
- AGENTS.local: 외부 scrcpy **호출 허용**, 내장 미러링·Android 쓰기는 범위 밖

### 실행

| 항목 | 값 |
|------|-----|
| 명령 | `scrcpy -s {serial} {opts}` |
| 기본 opts | `--show-touches --stay-awake --legacy-paste --max-size=1024 --video-bit-rate=2M --max-fps=30 --screen-off-timeout=3600 --turn-screen-off` |
| 설정 | `relay.scrcpy.path` · `relay.scrcpy.noControl` (기본 OFF → `--no-control` 추가) · `relay.scrcpy.customOpts` |
| 종료 | `terminationHandler` → 상태 복귀 · serial당 1개 |

### UI 상태

| 상태 | 버튼 |
|------|------|
| 미설치 | `미러링 설치…` |
| 설치 | `미러링` |
| 설치중 | `설치 중…` |
| 실행중 | `미러링 중` (클릭 시 종료 확인 없이 종료 토글) |

## 3. 감시 3종

| feed | enter | clear | cooldown | severity | 설정 |
|------|-------|-------|----------|----------|------|
| `feedBsoh` | 하락 Δ≥5pt | 없음 (1회성, baseline 갱신) | fingerprint | warning | `relay.watch.bsoh` |
| `feedRsrp` | Δ≤−6 (악화) | 회복 Δ≥+6 | 60s | warning | `relay.watch.rsrp` |
| 복구 알림 | — | Gate clear 시 시스템 알림 토글 | 기존 | — | `relay.watch.recovery` 기본 ON |

- Bsoh/RSRP **수집·표시 이미 완료** → feed + DeviceMonitor 연결만
- Bsoh 필드 부재: feed 생략

## 4. 썸네일 · 로그뷰어

| 기능 | 접근 | 노출 |
|------|------|------|
| 썸네일 | `adb exec-out screencap -p` 수동/연결 시 | **A안**: 헤더 `[스샷]` → 미리보기 시트 (400pt·시각·새로고침·미러링) · 미니 썸네일 제거 |
| scrcpy 포커스 | 런치 후 0.35/0.9/1.8/3s `activate` + System Events frontmost | 실행 중 헤더 클릭 = **창 앞으로** (정지 아님 · 종료=창 닫기) |
| 로그뷰어 | `logcat -v time` 스트림, 200행 링 | 창 `id:"logs"` |

## 5. 정책 갱신

| 문서 | 변경 |
|------|------|
| C3 (PLAN_v0.1/0.3 역사) | **해제** — 본 문서가 대체 |
| 금지 grep | `Scrcpy` **제거** (Outpost/iStat/gfxinfo/material 유지) |
| `AGENTS.local` | §1 미러링 문구 정정 · 버전 0.7.0 |

## 6. 구현 순서

| 단계 | 작업 |
|------|------|
| V1 | ScrcpyController + 설치 시트 + 헤더 버튼 |
| V2 | feedBsoh·feedRsrp·복구 토글 + DEBUG 주입 |
| V3 | screencap 썸네일 |
| V4 | 로그 뷰어 창 |
| V5 | i18n · 테스트 · 버전 0.7.0 · 문서 · DoD |

## 7. 검증 (DoD)

- [x] `swift test` — **91/91** (Bsoh/RSRP/forget 신규 3 포함)
- [x] `./build_and_run.sh debug macos` — 0 error · 번들 **0.7.0**
- [x] i18n 3곳 키 수 일치 — **201/201/201**
- [x] 금지 grep — Outpost/gfxinfo 0 · material 주석만 · print Views/App 0 · **Scrcpy 허용**
- [x] scrcpy 창 포커스 — 런치 리트라이 + 실행 중 토글=포커스 (stopHint 제거)
- [x] 후속조치 잔류 수정 — thermal clear ≤2 · TransitionGate clear 쿨다운 무시 · forget synthetic clear · battery/bsoh clear · 가이드 TTL 30분 · 테스트 101/101
- [x] 헤더 썸네일 A안 — 미니 썸네일 제거 · `ScreenshotPreviewSheet`
- [x] 실기 육안 — scrcpy 설치→미러링 / Bsoh·RSRP 주입 / 복구 알림 / 썸네일 / 로그창 (사용자 확인 ✓)
- [x] TODO · AGENTS.local · 세션로그 갱신
