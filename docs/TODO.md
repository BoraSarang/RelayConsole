# TODO.md
> 작업 추적 — bd 연동 (이슈 prefix: RelayConsole)

## 진행 중 (bd ready)
- [ ] T-103~T-105 P0 read 모델·토큰·파서 (bd: RelayConsole-19q/tuc/rtm)
- [ ] T-106~T-109 팝오버·대시보드·인터랙션·DoD (bd: RelayConsole-9mw/c8q/6t7/2jp)

## 완료 (2026-09-23)
- [x] T-101 SwiftPM 스캐폴드 — Package.swift(macOS 26, 0.1.0), Info.plist `com.borasarang.relayconsole` · build_and_run 성공
- [x] T-102 BrandKit 반영 — AppIcon.icns + MenuBarTemplate.png, 앱명 Relay Console, 메뉴바 RELAY
- [x] swift test — AdbParsingTests 5건 통과
- [x] 보강 흡수 — PROMPT-FINAL-V0-2 (i18n·Red 핫픽스·iStats 금지) → PLAN §1·DoD (V0-1 교체)
- [x] 레인보우 픽스 — MenuBarExtra 솔리드 `#0f111a` + ZStack, material/glass 0건, 빌드·실행
- [x] Red 핫픽스 v2 — darkAqua + 콘솔 ZStack 솔리드 + footer opacity 제거 + V0-2 문서 이관
- [x] 다국어 KO/EN — Localizable.xcstrings + ko/en.lproj, UI 키화(L10n), lineLimit
- [x] 버전 시작 — **0.1.0** (신규 · 구 Outpost 아카이브 v0.6 참고용)
- [x] bundleId 확정 — `com.borasarang.relayconsole` (AGENTS 플랫폼 규칙)
- [x] git init + bd init — Repo ID 32308267, 이슈 prefix RelayConsole
- [x] 브랜드 이관 — BrandKit 복사, UI 라벨 Outpost → RELAY / Relay Console
- [x] 문서 이관 — RESEARCH/SkillPack/목업/DESIGN/AGENTS.local/PLAN archive
- [x] 최종 계획 — docs/plans/PLAN_v0.1_relayconsole.md (초안 → 확정 + 보강)

## 참고 (Outpost 유산 — 코드 미이관)
- 구 이슈 Outpost-4ag (콘솔 열기) 등은 원 프로젝트에 남음 — 새 코드에서 P1 재검증
- P0 배터리 미연결 버그는 선결 패턴으로 재발 방지 (PLAN §2)
- UserDefaults 접두어 `outpost.*` → `relay.*` (신규 코드)

## 완료 (새 프로젝트 이후 추가)
