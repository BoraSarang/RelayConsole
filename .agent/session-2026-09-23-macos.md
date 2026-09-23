# session-2026-09-23-macos — v0.4 메뉴바 UX + WindowFocus

1. **범위**: 임의 기기 제거 · 빈 상태 · 기기 상세 힌트 · 메뉴바 상태 아이콘 · z-order(WindowFocus) · 설정/팝오버 토글
2. **아이콘**: 0대 `MenuBar-Off`(흰 안테나) · 1대+ `MenuBar-Online`(흰 Android+초록점) — Downloads `*_white.png` 원본 → 22/44px · `isTemplate=false` (다크 메뉴바)
3. **UI**: 메뉴바 텍스트 제거(아이콘만) · 팝오버 헤더 `n/m`(`relay.menubarMetrics`) · 기기 0 emptyState · 접힘 시 `menubar.device.detailHint` · `SettingsLink` 폐기 → `openSettings`+`WindowFocus`
4. **z-order**: `WindowFocus.swift` — dismiss statusBar/popUpMenu 패널 + activate + makeKeyAndOrderFront(0.08s 재시도) · 콘솔/디버그/설정 진입 시 호출
5. **제거**: `DEBUG-GHOST-2` 주입 · `relay.debugSecondDevice`/`relay.selectedSerial` defaults · adb disconnect
6. **검증**: `swift test` **60/60** · i18n ko/en/xcstrings **72/72/72** · 금지 grep 0 · debug 0.4.0 · 메뉴바 status item 1개(자동) · 아이콘 육안(흰 Android+초록) 사용자 확인 ✓
7. **문서**: TODO 진행중 WindowFocus 육안 1건 · 본 session 기록
8. **다음**: 커밋·푸시·PR·머지 → Apple 플랫폼 확장 조사
