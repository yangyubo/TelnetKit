#!/usr/bin/env python3
"""Insert an English | 中文 switch line after the H1 of each English document.

The switch line is required by the bilingual rule in docs/AGENTS.md. The script is
idempotent: a file that already carries the line is left unchanged. Run from the
repository root:

    python3 .doc-tools/add_lang_line.py

It reports every file it edits and every document whose Chinese counterpart is
missing, then exits non-zero when a counterpart is missing.
"""

from __future__ import annotations

import sys
from pathlib import Path

ENGLISH_DOCS = [
    "AGENTS.md",
    "docs/AGENTS.md",
    "docs/architecture.md",
    "docs/public-api.md",
    ".agents/skills/telnetkit-public-api-slice/SKILL.md",
    ".agents/skills/telnetkit-import-c-library/SKILL.md",
    ".agents/skills/telnetkit-doc/SKILL.md",
    ".agents/skills/telnetkit-prose-standard/SKILL.md",
]


def counterpart(path: Path) -> Path:
    """Return the Chinese sibling: foo.md -> foo.zh.md, AGENTS.md -> AGENTS.zh.md."""
    return path.with_suffix(".zh.md")


def switch_line(path: Path) -> str:
    return f"English | [中文]({counterpart(path).name})"


def stale_switch_lines(path: Path) -> set[str]:
    """Return switch lines this script may have written under an older naming rule."""
    name = path.name
    return {
        f"English | [中文]({name}.zh.md)",
        f"English | [中文]({name.rsplit('.', 1)[0]}.md.zh.md)",
    }


def normalize_switch_line(path: Path, lines: list[str]) -> list[str]:
    """Drop every stale switch line, then drop a duplicated blank line left behind."""
    stale = stale_switch_lines(path)
    kept: list[str] = []
    for line in lines:
        if line in stale and line != switch_line(path):
            continue
        if line == "" and kept and kept[-1] == "":
            continue
        kept.append(line)
    return kept


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    edited: list[str] = []
    missing: list[str] = []

    for name in ENGLISH_DOCS:
        path = root / name
        if not path.is_file():
            print(f"missing English document: {name}")
            missing.append(name)
            continue

        lines = path.read_text(encoding="utf-8").splitlines()
        lines = normalize_switch_line(path, lines)
        marker = switch_line(path)
        if marker in lines:
            path.write_text("\n".join(lines) + "\n", encoding="utf-8")
            print(f"unchanged (already paired): {name}")
        else:
            for index, line in enumerate(lines):
                if line.startswith("# "):
                    lines.insert(index + 1, "")
                    lines.insert(index + 2, marker)
                    break
            else:
                print(f"no H1 heading: {name}")
                missing.append(name)
                continue
            path.write_text("\n".join(lines) + "\n", encoding="utf-8")
            print(f"switch line added: {name}")
            edited.append(name)

        if not counterpart(path).is_file():
            print(f"Chinese counterpart missing: {counterpart(path).relative_to(root)}")
            missing.append(name)

    print(f"\nadded: {len(edited)}; unresolved: {len(missing)}")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
