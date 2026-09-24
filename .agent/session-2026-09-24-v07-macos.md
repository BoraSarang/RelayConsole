# session-2026-09-24-v07-macos.md

1. **모드**: Build · 플랫폼: macos · 브랜치: main (작업 브랜치 없이 진행 — PR 시 분리 권장)
2. **검증**: `swift test` 101/101 · debug 빌드 0.7.0 · i18n 201/201/201 · 금지(Outpost/gfxinfo/print) 0 · Scrcpy 허용
3. **미완/차기**: 실기 육안(스로틀링 해제→가이드·스샷 시트 포함) · ANR logcat(v0.8) · 카드 On/Off(v0.9) · scrcpy B안 백로그
4. **본문**:
   - v0.7: scrcpy A안(외부 실행) + 설치 유도(brew 1회 확인) + feedBsoh/RSRP + 복구 알림 + 썸네일 + 로그 뷰어
   - **scrcpy 창 포커스**: 런치 후 activate 리트라이 + System Events · 실행 중 클릭=창 앞으로(종료=창 닫기)
   - **후속조치 잔류 A+B**: thermal clear ≤2 · TransitionGate 해제 쿨다운 무시 · disconnect synthetic clear · battery 충전 clear · Bsoh 회복 clear · 저전력 warning · 가이드 최신 우선+30분 TTL
   - **헤더 썸네일 A안**: 미니 썸네일 제거 · `[스샷]` → 미리보기 시트
   - 정책: C3 Scrcpy 해제 · 금지 grep Scrcpy 제거 · AGENTS.local 0.7.0
   - 문서: PLAN_v0.7 · TODO · AGENTS.local
5. **테스트/빌드**: 101/101 · `./build_and_run.sh debug macos` OK
6. **i18n**: 201키 3곳
7. **금지**: Outpost·iStat·gfxinfo·material 0 · **Scrcpy 허용**
8. **다음**: 실기 육안 → PR
