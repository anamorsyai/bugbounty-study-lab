#!/usr/bin/env python3
"""Link bare HackerOne report IDs so they're clickable.

The lessons cite report IDs constantly — in tables, prose, subsection headings and
the source-material header. A bare `#1234567` renders as dead text; it should be a
link to https://hackerone.com/reports/1234567.

This rewrites any bare `#<5+ digits>` into a markdown link, while leaving alone:

  * IDs already inside a markdown link  ([#123](https://...))
  * IDs inside inline code              (`#1234567`)
  * anything inside a fenced code block
  * short fragments and heading anchors (#1-access-control, #top)

Usage:
    python link_report_ids.py FILE [FILE ...]
    python link_report_ids.py --check FILE [FILE ...]   # report only, no writes
"""

import re
import sys
from pathlib import Path

ID = re.compile(r"#(\d{5,})")
FENCE = re.compile(r"^\s*(```|~~~)")
# ranges we must not touch: markdown links, autolinks, and inline code
PROTECTED = re.compile(r"\[[^\]]*\]\([^)]*\)|<[^>]+>|`[^`]*`")
REPORT_URL = "https://hackerone.com/reports/"


def protected_spans(line: str) -> list[tuple[int, int]]:
    return [(m.start(), m.end()) for m in PROTECTED.finditer(line)]


def is_protected(pos: int, spans: list[tuple[int, int]]) -> bool:
    return any(start <= pos < end for start, end in spans)


def link_line(line: str) -> tuple[str, int]:
    """Link bare report IDs in one line. Returns (new_line, count)."""
    spans = protected_spans(line)
    if not spans and not ID.search(line):
        return line, 0

    out = []
    last = 0
    count = 0
    for m in ID.finditer(line):
        if is_protected(m.start(), spans):
            continue
        out.append(line[last:m.start()])
        out.append(f"[#{m.group(1)}]({REPORT_URL}{m.group(1)})")
        last = m.end()
        count += 1

    if not count:
        return line, 0
    out.append(line[last:])
    return "".join(out), count


def process(path: Path, check_only: bool = False) -> int:
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    out = []
    in_fence = False
    total = 0
    samples = []

    for lineno, line in enumerate(lines, start=1):
        if FENCE.match(line):
            in_fence = not in_fence
            out.append(line)
            continue
        if in_fence:
            out.append(line)
            continue

        new_line, n = link_line(line)
        if n:
            total += n
            if len(samples) < 4:
                samples.append((lineno, new_line.rstrip("\n")[:100]))
        out.append(new_line)

    if not check_only and total:
        path.write_text("".join(out), encoding="utf-8")

    if total:
        for lineno, txt in samples:
            print(f"    L{lineno}: {txt}")
        if total > len(samples):
            print(f"    ... and {total - len(samples)} more")
    print(f"  {path.name}: {total} id(s) {'to link' if check_only else 'linked'}")
    return total


def main() -> int:
    check_only = "--check" in sys.argv
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        print(__doc__)
        return 1

    grand = 0
    for name in args:
        path = Path(name)
        if not path.is_file():
            print(f"  {name}: not a file, skipped")
            continue
        grand += process(path, check_only)

    verb = "would be linked" if check_only else "linked"
    print(f"\n{grand} report id(s) {verb}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
