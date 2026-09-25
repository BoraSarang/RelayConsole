# RESEARCH_adb_file_browser.md — ADB 기반 파일 브라우저 가능 스펙 조사
> 생성일: 2026-09-25 | 상태: **조사 완료 — PLAN_file_browser로 계획 이관**
> 목적: MTP 제외 · ADB 전용 파일 탐색기의 기술적 가능 스펙 실측 기록
> 모체: `RESEARCH_competitive_v1` §8-A4(파일/스샷 갤러리) 확장 검토 · DroidPort 조사 파생
> bd: `RelayConsole-qy8`

---

## §0 스코프 · 방법

| 항목 | 내용 |
|------|------|
| 질문 | MTP 없이 ADB만으로 "탐색기"를 만들면 어디까지 가능한가 |
| 제외 | MTP(macOS 미내장) · FUSE/adbfs 마운트(프로젝트 방치·macFUSE 이슈) |
| 실측 기기 | SM-S901N · Android 16 (API 36) · 보안패치 2026-08-05 · **보안 빌드**(ro.debuggable=0 · su 없음) |
| 연결 | Wi-Fi ADB `tcpip:5555` (10.x:5555) · adb host 37.0.1 |
| 원칙 | **읽기 전용 실측** (push 미실측 — 구현 단계 검증 예정) |

---

## §1 접근 권한표 (실측)

| 경로 | 목록(ls) | pull | push | 비고 |
|------|:---:|:---:|:---:|------|
| `/sdcard/*` (Download·DCIM·Documents…) | ○ | ○ | ○ | shell 그룹 `sdcard_rw`+`sdcard_r` |
| `/sdcard/Android/data/<pkg>` | ○ | ○ | △ | shell `ext_data_rw` 그룹 — **실측 목록 성공**. 단 API30 일부 기기는 거부 사례(웹) → 기기 변수 |
| `/data/local/tmp` | ○ | ○ | ○ | 자유 쓰기 (스테이징 가능) |
| `/data/app/*/base.apk` | × | ○ | — | 디렉터리 목록 denied, **경로 직접 접근은 가능** → `pm path` + pull 성공 실측 (APK 추출 가능) |
| `/data/data/<pkg>` | × | × | × | 루트 전용. `run-as`는 **디버깅 빌드만** (릴리즈 = "not debuggable") |
| `/system`·`/product` 등 시스템 영역 | ○ | ○ | × | 읽기 가능(world-readable), 쓰기 불가 |

- 단일 유저(0) 실측 — 워크프로필/다중 유저 미검증 (shell 사용자 제한 있음)
- 쓰기(mkdir/mv/rm)는 shell 권한상 가능하나 **범위 OUT** (읽기+전송만 채택, §6)

---

## §2 명령어 스펙 (실측)

| 작업 | 명령 | 실측 결과 |
|------|------|-----------|
| 폴더 목록 | `ls -la --full-time <dir>/` | 이름·권한·소유자·크기·**纳秒 시각+타임존** 1회 조회 · **~70ms/폴더** |
| 재귀 검색 | `find -L <dir> -type f …` | toybox 0.8.12 · `-type -name -size -maxdepth -exec -printf` 전부 지원 · **748파일 / 0.3초** |
| 파일 메타 | `stat -c "%n\|%s\|%Y\|%A"` | 동작 |
| 폴더 크기 | `du -s` | 소규모 즉시 (대형 폴더는 느림 — 상시 호출 금지) |
| 바이너리 출력 | `adb exec-out` | PTY 변환 없음 확인 (쉘 출력 대비 안전) |
| 전송 | `adb pull [-a] [-z brotli\|lz4\|zstd]` / `adb push` | pull 재귀 폴더 지원 · `-a` 모드·시각 유지 |

### ⚠️ 함정 3건 (실측)

1. **`/sdcard`는 심볼릭 링크**(`/sdcard → /storage/self/primary → /storage/emulated/0`)
   - `find /sdcard -type f` → **0건 반환(무오류)** → 반드시 `find -L`
   - `ls -la /sdcard` → 링크自身만 표시 → 목록은 **`ls -la /sdcard/` (.trailing slash)** 로 해야 함
2. **`content query`(MediaStore CLI) 부적합** — 복수 컬럼 projection 미지원 · 느림(219행 1.2초) · 썸네일 URI 실패 → 브라우징은 `ls`/`find`가 정답
3. **`adb shell`은 argv를 인용하지 않고 공백으로만 연결** (2026-09-25 실측)
   - `adb shell ls "/path/Windows 11/"` → 원격 sh가 재분리 → `ls: /path/Windows: No such file or directory`
   - 한글·일본어·공백·`'` 전부 영향 — **명령 전체를 셸 인용한 단일 argv로 전달**해야 함
   - 정상: `adb shell "ls -la --full-time '/path/Windows 11/'"` (POSIX 싱글쿼트, `'`→`'\''`)
   - `adb pull`/`push`는 **sync 프로토콜이라 영향 없음** (공백·한글 파일명 실측 roundtrip OK)

### 파싱 규격 (toybox `ls -la --full-time`)

```
total 6591
drwxrws--- 2 u0_a300 media_rw    3452 2026-07-06 19:54:01.793999998 +0900 Alarms
-rw-rw---- 1 u0_a300 media_rw   69602 2026-08-25 11:28:20.728804402 +0900 dl_tab.png
lrw-r--r-- 1 root    root          21 2022-01-01 09:00:00.000000000 +0900 /sdcard -> /storage/self/primary
```
- 8필드 고정(perms·links·owner·group·size·date·time·tz) 후 나머지 = 이름 (공백 포함 이름 가능)
- 심링크는 `이름 -> 타깃` → ` -> ` 분리
- 오류 줄(`ls: …: No such file…`, exit≠0)은 필터 + **stderr를 그대로 사용자 노출** ([표시②])

---

## §3 성능 실측 (Wi-Fi ADB)

| 항목 | 실측치 |
|------|--------|
| pull 지속 (467MB dmg) | **54.9 MB/s** (8.1초) |
| pull 소파일 (12MB apk) | 16.5 MB/s (초기 오버헤드 포함) |
| 폴더 목록 | ~70ms |
| 전체 트리 검색 (748파일) | 0.3초 |
| 참고 (공개 벤치) | USB2 ~36–70MB/s(압축) · USB3 ~115–125MB/s |

→ **Wi-Fi만으로 탐색기 체감 가능**. push는 미실측 (구현 시 `adb push`로 검증 예정).

---

## §4 미리보기 · 썸네일 전략

| 항목 | 결론 |
|------|------|
| 기기側 썸네일 도구 | **없음** — MediaStore 썸네일 URI 실패 · 이미지 변환 도구 없음 |
| adb sync | **범위 읽기 없음** (파일 단위 전체 이동만) |
| 이미지 미리보기 | 전체 pull → 로컬 축소·캐시 (`GalleryStore` 패턴 계승) 또는 즉시 pull 후 시스템 앱 열기 |
| 영상 썸네일 | **불가** (기기側 추출 불가) — 파일 정보(크기·시각)만 표시 |
| 대용량 가드 | 50MB 초과 파일은 더블클릭 열기 거부 + "가져오기 후 확인" 안내 |

---

## §5 경쟁 비교

| 도구 | 성격 | 차이 |
|------|------|------|
| Android Studio Device File Explorer | 개발 도구 부속 — 탐색·pull·push·delete | "연결했을 때 여는" 창 |
| ADB Studio · ADBOSS | 풀 ADB GUI 유틸 | 메뉴바 상주·감시 없음 |
| MacDroid/OpenMTP | **MTP** 전용 | 범위에서 제외 |
| **Relay Console 파일 탐색기** | **메뉴바 상주 + 감시 창에서 동일 기기 탐색·전송** | A+C 교차 공백 (competitive_v1 §1 유지) |

---

## §6 범위 (채택: 읽기 + 전송)

**IN**
- 폴더 탐색 (`ls -la --full-time`) · 사이드바 즐겨찾기 · 경로 이동(상위/직접 입력)
- 정렬(이름·크기·수정일, 폴더 우선) · 현재 폴더 이름 필터 · `find` 기반 검색(후속)
- **pull**: 선택 파일/폴더 → Mac 지정 폴더 (중복 파일명 자동 회피)
- **push**: Finder → 창 드래그로 현재 폴더에 전송 (APK 포함 일반 파일)
- 더블클릭 파일 → pull 후 시스템 앱으로 열기 (≤50MB)

**OUT**
- APK **설치**(`adb install`) — AppHub PLAN의 OUT 유지 · 백로그
- 삭제·mv·mkdir 등 파괴적 쓰기 (기존 "감시(읽기) 전용" 선언 유지)
- FUSE 마운트 · 영상 썸네일 · 전체 텍스트 검색(후속 검토)

**충돌 확인**: `PLAN_gallery` OUT "전체 파일 탐색기 아님(TIER B)" — 본 기능은 **읽기+전송 한정 탐색기**로 재정의. 갤러리(스크랩북)와 기능·화면 분리 유지.

---

## §7 UI 형식 (채택: 별도 창)

| 후보 | 판정 |
|------|------|
| 메뉴바 팝오버 | ❌ 면적 부족 (사이드바+컬럼+드래그 불가) |
| 시트 (GallerySheet류) | ❌ 임시 오버레이 — 상시 탐색 부적합 |
| **별도 `Window(id: "files")`** | ✅ **채택** — `console`·`processes`·`logs`·`appnetwork` 동일 패턴 (`openWindow` + `WindowFocus.present`) |

- 진입: **메뉴바 팝오버 푸터 버튼** (기기 연결 시) + 콘솔 헤더(후속)
- 레이아웃: 사이드바(즐겨찾기) + 헤더(경로·상위·새로고침·가져오기) + 컬럼 목록 + 상태줄
- 토큰: 기존 다크 관제탑 (`OPColor`/`OPFont`/`OPSpace`) — DESIGN.md 변경 없음

---

## §8 남은 확인 사항

- [ ] push 실측 (구현 단계에서 `/data/local/tmp` 1바이트 테스트 + 정리)
- [ ] API30 기기의 `Android/data` 접근 변수 — 사이드바 해당 항목은 실패 시 원인 노출
- [ ] 대용량 폴더(수천 파일) 목록 렌더 성능 — LazyVStack 유지 관찰
