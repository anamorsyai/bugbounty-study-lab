#!/usr/bin/env python3
"""Renumber '## N. Title' headings sequentially within markdown files.

Keeps lesson files consistent as sections are inserted, removed or reordered.
Numbers are assigned in document order starting at 1. Heading text is preserved
verbatim; only the number is rewritten. Fenced code blocks are skipped so a
'## ' line inside a code sample is never touched.

Usage:
    python renumber_sections.py FILE [FILE ...]
    python renumber_sections.py --check FILE [FILE ...]   # report only, no writes
"""

import re
import sys
from pathlib import Path

HEADING = re.compile(r"^##\s+(\d+)\.\s+(.*)$")
FENCE = re.compile(r"^\s*(```|~~~)")


def renumber(path: Path, check_only: bool = False) -> int:
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)

    out = []
    in_fence = False
    counter = 0
    changes = []

    for lineno, line in enumerate(lines, start=1):
        if FENCE.match(line):
            in_fence = not in_fence
            out.append(line)
            continue

        match = None if in_fence else HEADING.match(line.rstrip("\n"))
        if match:
            counter += 1
            old, title = match.group(1), match.group(2)
            new_line = f"## {counter}. {title}\n"
            if old != str(counter):
                changes.append((lineno, old, counter, title))
            out.append(new_line)
        else:
            out.append(line)

    if not check_only and changes:
        path.write_text("".join(out), encoding="utf-8")

    label = "would change" if check_only else "renumbered"
    if changes:
        for lineno, old, new, title in changes:
            print(f"  {path.name}:{lineno}  {old} -> {new}  {title[:60]}")
    else:
        print(f"  {path.name}: already sequential ({counter} sections)")

    return len(changes)


def main() -> int:
    args = [a for a in sys.argv[1:] if a != "--check"]
    check_only = "--check" in sys.argv
    if not args:
        print(__doc__)
        return 1

    total = 0
    for name in args:
        path = Path(name)
        if not path.is_file():
            print(f"  {name}: not a file, skipped")
            continue
        total += renumber(path, check_only)

    verb = "would be fixed" if check_only else "fixed"
    print(f"\n{total} heading(s) {verb}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
