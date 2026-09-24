# session 2026-09-24 — v0.6 Phase2 감시 (macOS)

1. **범위**: feedPsi/feedLoad/feedMemory + DeviceMonitor 연결 + 설정 3토글 + remediation + DEBUG 주입
2. **검증**: `swift test` 88/88 · debug 빌드 0.6.0 · i18n 151/151/151 · 금지 grep 0 · print 0
3. **육안**: 대기 (사용자 — 주입 PSI/load/mem)
4. **본문**: `feat/phase2-watch` · PLAN_v0.6 · 버전 0.6.0
5. **정리**: 머지된 feat/watch-events·menubar 브랜치 삭제/prune
6. **Gate**: PSI 5/3/120s · load cores×2/×1/60s · mem usedPct 90/80/60s
7. **금지 유지**: Outpost·iStat·Scrcpy·gfxinfo·material 0
8. **메모**: mem은 usedPct(100−avail)로 enter>clear 유지 · load는 coreCount 확정 후 feed
