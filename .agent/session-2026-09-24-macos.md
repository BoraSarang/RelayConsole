# session 2026-09-24 — v0.5 감시 이벤트 + 프로세스 목록 (macOS)

1. **범위**: ThresholdGate/WatchEngine/배너·배지 + 프로세스 목록(CPU/RAM/PID/커맨드)·독립 윈도우
2. **검증**: `swift test` 84/84 · debug 빌드 0.5.0 · i18n 129/129/129 · 금지 grep 0
3. **육안**: WindowFocus 포커스 ✓ · 주입/배너/배지/충전 전이 ✓ · 프로세스 목록 ✓
4. **본문**: `feat/watch-events` A0–A4·A6 + 프로세스 시트/윈도우 · 라벨 위치→커맨드
5. **머지**: PR #2 → main `64d84e4` ✓
6. **미완**: Phase2 A5(PSI·load·MemAvailable) 보류 — 다음 스프린트
7. **금지 유지**: Outpost·iStat·com.relay.console·Scrcpy·gfxinfo·material 0
8. **메모**: ps ARGS — 앱=패키지ID, 네이티브=경로 · 아이콘 adb 제한 · 오늘 여기까지
