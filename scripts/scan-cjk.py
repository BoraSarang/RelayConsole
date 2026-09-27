#!/usr/bin/env python3
"""한자(CJK 한자) 혼입 + U+FFFD 전수 스캔 — 2026-09-28

왜 이게 필요한가: 문서에 한자가 섞여 들어가는 일이 한 세션에 4회 재발했다.
기억으로 하는 점검이 안 된다. 커밋 훅으로 승격하기 전이라도 스크립트로 고정한다.

사용: scripts/scan-cjk.py [경로…]   (인자 없으면 git tracked 파일 전체)
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
REPLACEMENT = "\ufffd"  # U+FFFD — 리터럴을 쓰면 이 파일이 자기 자신을 잡는다


def is_hanja(ch: str) -> bool:
    cp = ord(ch)
    return any(lo <= cp <= hi for lo, hi in RANGES)


def targets(paths: list[str]) -> list[Path]:
    if paths:
        return [Path(p) for p in paths]
    out = subprocess.run(
        ["git", "ls-files", "-z"], capture_output=True, text=True, check=True
    ).stdout
    return [Path(p) for p in out.split("\0") if p]


def main() -> int:
    skip_suffix = {".png", ".jpg", ".jpeg", ".gif", ".pdf", ".xcassets", ".stringsdict"}
    hanja_hits, fffd_hits = [], []

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

    if hanja_hits or fffd_hits:
        return 1
    print("한자 혼입 0건 · U+FFFD 0건")
    return 0


if __name__ == "__main__":
    sys.exit(main())
