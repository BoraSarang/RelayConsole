# PLAN_app_manage_relayconsole.md — 앱 설치·삭제 + 아이콘 (A/B/C)

> 생성일: 2026-10-24 | 상태: **PR #123 머지(`fbd2fd5`) — A·B·C + 배터리 표시(1.25.0), 실기기 확인 대기** | 앱: Relay Console
> 목표 버전: A **1.22.0** → B **1.23.0** → C **1.24.0** | 최소 OS: macOS 26.0
> 선행: `PLAN_app_hub_relayconsole.md` (목록·런치·강제종료·삭제 — 설치/백업은 OUT 이었음)

---

## 1. 목표

메뉴바 콘솔에서 **APK 설치·앱 삭제**를 끝낸다. 기존 앱 허브는 삭제가 `pm uninstall -k`(데이터 유지)라
"삭제했는데 용량이 그대로"였다 — 의미를 바로잡고, 설치·분할 번들·백업·다기기·아이콘까지 확장한다.

| 사용자 결정 (2026-10-24) | 값 |
|---|---|
| 범위 | A + B + C 전부 |
| 삭제 기본값 | **앱 + 데이터 완전 삭제** (`-k` 없음), 데이터 유지는 보조 |
| 분할·번들 | `install-multiple` · `.apks` · `.xapk`(OBB) · `.apkm` 전부 |
| 아이콘 | **기본 ON**, B에 포함 (별도 단계 아님) |
| 아이콘 캐시 | 256px@2x · 30일 · 50MB 상한 |

### OUT
- 앱 데이터 백업/복원 (APK 백업은 **앱만** 복원 — UI에 명시)
- 루트 권한 기능, 시스템 앱 완전 제거 (C는 `--user 0` + 복원만)
- MCP 쓰기 도구 — **추가 금지** (읽기 전용 계약, DECISIONS D6)
- 기기 설정 변경 (`settings put`, Play 프로텍트 해제 자동화)

---

## 2. UX

```
대시보드 [Apps] → 앱 관리 시트
  탭: 설치된 앱 · 설치 이력 · 백업
  헤더: 아이콘 토글(기본 ON) · 시스템 앱 · 새로고침 · [APK 설치]
  드롭: 시트 어디든 .apk / .apks / .xapk / .apkm
  확인: 파일명 · 크기 · SHA-256 앞 12자 · 대상 기기 · 옵션(-r 고정, -g/-d/-t 기본 OFF)
  진행: 파일별·기기별 행, 경과초, 취소(전송 단계만)
  결과: 성공 = 확인된 versionName / 실패 = adb 원문 코드 + 다음 행동
삭제: 행 [⋯] → ① 앱과 데이터 모두 삭제(기본) ② 앱만 삭제(데이터 유지)
      확인창에 회수 용량(앱 크기)과 "데이터 복원 불가" 명시
```

목업: `docs/mockups/app_manage_v1.html` · `app_manage_v1.png`

---

## 3. 단계

### A — 단일 APK + 삭제 교정 (1.22.0)
| 항목 | 구현 |
|---|---|
| adb 경로 | `ProcessRunner` 로 교체 (stderr 보존·600초 데드라인·취소) |
| 설치 | `adb -s <serial> install -r [-d] [-g] [-t] <abs path>` |
| 검증 | 설치 전/후 `pm list packages -3 --show-versioncode` diff → 1건이면 `dumpsys package` versionName |
| 실패 | `Failure [CODE]` → 코드별 한국어 행동 지침, 원문은 로그 |
| 삭제 | `pm uninstall`(완전) / `-k`(보존), 기본 완전 삭제 |
| 감사 | `IssueLog` `app.install` · `app.uninstall` (파일명·SHA-256·serial·결과) |
| 안전 | 절대경로·`.apk`·일반파일·크기>0, 셸 문자열 조합 금지 |

### B — 분할·번들·백업 + 아이콘 (1.23.0)
| 항목 | 구현 |
|---|---|
| ZIP 리더 | 중앙 디렉터리 + raw DEFLATE 스트리밍, 상한(**150,000** 엔트리·8GB·경로순회 거부) |
| `.apks` | `universal.apk` 우선 → 기기 ABI/밀도/로케일 매칭 split → 실패 시 전체 폴백 |
| `.xapk` | `manifest.json` 파싱, OBB → `/sdcard/Android/obb/<pkg>/` |
| `.apkm` | `info.json` + APK 세트 |
| 진행률 | `push → pm install-multiple` 2단계, 크기 폴링(% 표시)·전송 단계만 취소 |
| 백업 | `pm path` → split 별 `adb pull` → `~/Downloads/RelayConsole/APKs/<pkg>/<ver>/` + `meta.json` |
| 아이콘 | AXML(`android:icon`) + ARSC → 최적 밀도 PNG/WebP → 512px 캐시, 행 단위 지연 로딩·동시 2. **벡터·적응형 XML 직접 렌더**(`AndroidDrawable.swift`) · 확장자 없는 엔트리(WebP) 포함 |
| 앱 이름 | `android:label` → ARSC 문자열(**참조 체인** 포함) → 행에 이름 1줄 + 패키지명 2줄, 검색도 이름 매칭. 아이콘과 **APK pull 1회 공유** |
| 아이콘 실패 | 결정적 색+이니셜 타일 유지 (빈칸 금지), 사유는 로그만 |
| 아이콘 OFF | pull 자체를 하지 않음 |

### C — 다기기·시스템 앱 (1.24.0) — **구현·테스트·빌드 완료 (2026-10-24)**

| 항목 | 구현 |
|---|---|
| 다기기 | 확인 시트에서 체크, 기기당 순차, 기기별 결과 행 |
| 폴링 간섭 | 설치 중 heavy 카드 폴링 완화 + `adb devices` 하트비트 유지 |
| 시스템 앱 | `pm uninstall --user 0` + `cmd package install-existing` 복원 |
| 위험 차단 | 런처·SystemUI·GMS·Settings·PackageInstaller 하드 블록, 그 외 2단계 확인 |
| 드롭 | Finder → 메뉴바 아이콘 드롭 → 대상 기기 선택 |
| 아이콘·이름 후속 | `versionCode` 오염 · ZIP 상한 · ARSC UTF-8 이중 길이 · 문자열 풀 상한 · sparse/offset16 표 · 벡터·적응형 렌더 — 6건 수정 후 실측 **10/10 정상 렌더** |

검증: `swift test` **859/0**(`AppSystemTests` 14 · 아이콘/이름 17 · 파서 회귀 2) · `./scripts/build-macos.sh debug` · 앱 1.24.0 · L10n 916/916.
실기기 확인은 `docs/MANUAL_VERIFY.md` §31·§32(89~101).

---

## 4. 모델·로직 (A)

```swift
struct InstallOptions: Equatable, Sendable {
    var reinstall = true
    var grantAllPermissions = false
    var allowDowngrade = false
    var allowTestOnly = false
}

enum InstallOutcome: Equatable {
    case installed
    case failed(code: String?, detail: String)
    case timedOut
}

// AppHubLogic (순수)
static func installArgs(path:options:) -> [String]
static func uninstallArgs(package:keepData:) -> [String]
static func isApkFile(_ path: String) -> Bool
static func parseInstallResult(stdout:stderr:exitCode:timedOut:) -> InstallOutcome
static func failureCode(in:) -> String?
static func failureKey(code:) -> String
static func versionName(fromDumpsys:) -> String?
static func parsePackageVersionCodes(_:) -> [String: Int64]
static func changedPackages(before:after:) -> [String]
```

`ProcessRunner.capture` 에 `onStart: ((Process) -> Void)? = nil` 를 추가해
설치 취소(전송 단계)를 가능하게 한다. 취소는 `Process.terminate()` 1회.

---

## 5. 검증

- 단위: 위 순수 함수 전부 + 실제 adb 출력 픽스처(성공/실패/타임아웃)
- L10n: en/ko 1:1, 포맷 인자 수 일치 (`L10nFormatTests` 전수 스캔)
- 실기기: 정상·재설치·서명 불일치·저장공간 부족·취소·`.apks`·`.xapk` OBB·백업 복원·2대·시스템 앱 복원
- 게이트 [HARD]: `swift test` → `./scripts/build-macos.sh debug` → 앱 재시작

---

## 6. 리스크

| 리스크 | 대응 |
|---|---|
| `adb install` 진행률 없음 | B에서 push+pm 2단계, A는 경과초+취소 |
| `.apks` split 오선택 | universal 우선·전체 폴백·설치 후 `pm path` 검증 |
| ARSC/AXML 형식 차이 | 실패 시 타일 폴백, 파서는 픽스처 테스트 |
| 완전 삭제 = 데이터 손실 | 기본값이지만 회수 용량·복원 불가 문구 고정, 보조 메뉴 제공 |
| 설치 취소 중 패키지 반쯤 설치 | `pm install` 구간은 취소 비활성, 완료 후 상태 재조회 |
| 아이콘 일괄 pull로 대역폭 폭주 | 보이는 행만·동시 2·캐시·토글 OFF |
