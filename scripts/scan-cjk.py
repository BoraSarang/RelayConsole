#!/usr/bin/env python3
"""커밋 전 문자 위생 검사 — 한자 혼입 · U+FFFD · **남은 충돌 마커** (2026-09-28)

왜 이게 필요한가: 문서에 한자가 섞여 들어가는 일이 한 세션에 4회 재발했다.
기억으로 하는 점검이 안 된다. 커밋 훅으로 승격하기 전이라도 스크립트로 고정한다.

충돌 마커를 검사하는 이유 — 2026-09-28 에 **마커가 커밋에 들어갔다.**
rebase 충돌을 "해결"했다고 생각하고 `git add` 했는데 마커가 파일에 남아 있었고,
`swift test` 가 문법 에러로 잡아낼 뿐 **원인이 수백 줄 뒤에 있었다.**
충돌이 났다는 사실 자체는 눈에 보이는데, **해결이 덜었다는 사실은 눈에 보이지 않는다.**

사용: scripts/scan-cjk.py [경로…]   (경로는 파일·디렉터리 모두 가능. 없으면 git tracked 전체)
"""
import subprocess
import sys
import unicodedata
from pathlib import Path

# 혼입으로 판정할 문자 (CJK 통합 한자 + 확장 A + 호환 한자)
RANGES = (
    (0x4E00, 0x9FFF),
    (0x3400, 0x4DBF),
    (0xF900, 0xFAFF),
    (0x20000, 0x2A6DF),
)
ALLOW_MARKER = "scan-cjk: allow"  # 이 표기가 있는 줄은 검사에서 제외한다
# **앞에 # 을 붙이지 않는다** — Swift 의 #warning/#if 같은 지시자로 파싱되어 컴파일이 깨진다 (2026-09-28 실측)
# 충돌 마커 — `<<<<<<< HEAD` / `>>>>>>> branch` 형태만 잡는다.
# `=======` 단독 줄은 마크다운 제목 밑줄과 겹치므로 **쓰지 않는다** (오탐)
CONFLICT_MARKERS = ("<<<<<<< ", ">>>>>>> ")
REPLACEMENT = "\ufffd"  # U+FFFD — 리터럴을 쓰면 이 파일이 자기 자신을 잡는다


def is_hanja(ch: str) -> bool:
    cp = ord(ch)
    return any(lo <= cp <= hi for lo, hi in RANGES)


def targets(paths: list[str]) -> list[Path]:
    if paths:
        out: list[Path] = []
        for raw in paths:
            p = Path(raw)
            # ★ 디렉터리를 받으면 **재귀해서 모은다.**
            # 이 버그가 있었을 때 `scan-cjk.py Sources Tests docs` 는 **파일 하나도 안 보고
            # 0건 으로 통과했다.** "아무것도 안 봤는데 문제가 없다" 는 가장 위험한 보고다.
            out.extend(sorted(p.rglob("*")) if p.is_dir() else [p])
        return out
    out = subprocess.run(
        ["git", "ls-files", "-z"], capture_output=True, text=True, check=True
    ).stdout
    return [Path(p) for p in out.split("\0") if p]


def main() -> int:
    skip_suffix = {".png", ".jpg", ".jpeg", ".gif", ".pdf", ".xcassets", ".stringsdict"}
    hanja_hits, fffd_hits, conflict_hits = [], [], []

    for path in targets(sys.argv[1:]):
        if not path.is_file() or path.suffix in skip_suffix:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for lineno, line in enumerate(text.splitlines(), 1):
            # `# scan-cjk: allow` — 한자를 **인용**해야 하는 문서(실수 사례 기록 등)는 여기서 제외한다.
            # 검출기를 쓸 수 없게 만드는 것보다, 근거를 남기는 자리를 만드는 게 낫다.
            if ALLOW_MARKER in line:
                continue
            if REPLACEMENT in line:
                fffd_hits.append((path, lineno, REPLACEMENT))
            if line.startswith(CONFLICT_MARKERS):
                conflict_hits.append((path, lineno, line.rstrip()))
            for ch in line:
                if is_hanja(ch):
                    name = unicodedata.name(ch, "?")
                    hanja_hits.append((path, lineno, ch, name))

    if hanja_hits:
        print(f"한자 혼입 {len(hanja_hits)}건:")
        for path, lineno, ch, name in hanja_hits:
            print(f"  {path}:{lineno}  {ch!r}  U+{ord(ch):04X} {name}")
    if fffd_hits:
        print(f"U+FFFD(손상) {len(fffd_hits)}건:")
        for path, lineno, ch in fffd_hits:
            print(f"  {path}:{lineno}")

    if conflict_hits:
        print(f"★ 충돌 마커 {len(conflict_hits)}건 — **이대로 커밋되면 안 된다**:")
        for path, lineno, line in conflict_hits:
            print(f"  {path}:{lineno}  {line}")
    if hanja_hits or fffd_hits or conflict_hits:
        return 1
    print("한자 혼입 0건 · U+FFFD 0건 · 충돌 마커 0건")
    return 0


if __name__ == "__main__":
    sys.exit(main())
