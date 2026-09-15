#!/usr/bin/env python3
"""Fix 'Lesson NN §X' cross-references after a section renumber.

When sections are inserted or reordered in a lesson, every citation of the form
'Lesson 04 §6' elsewhere points at the wrong section. This rewrites those
citations using a per-lesson old->new mapping.

Edit MAPS below to match the renumber that was applied, then run from the
studies/ directory:

    python tools/fix_section_refs.py

Lessons with an empty mapping were not renumbered and are left alone.
"""

import re
from pathlib import Path

# old section number -> new section number, per lesson
MAPS = {
    "01": {1: 1, 2: 3, 3: 4, 4: 5, 5: 6, 6: 7, 7: 8, 8: 9, 9: 10, 10: 11, 11: 12, 12: 13},
    "02": {1: 1, 2: 3, 3: 4, 4: 5, 5: 6, 6: 7, 7: 8, 8: 9, 9: 10,
           10: 11, 11: 12, 12: 13, 13: 14, 14: 15, 15: 16},
    "03": {},  # not renumbered
    "04": {1: 1, 2: 2, 3: 4, 4: 5, 5: 6, 6: 7, 7: 8, 8: 9, 9: 10, 10: 11, 11: 12, 12: 13},
    "05": {},  # not renumbered
    "06": {},  # not renumbered
}

REF = re.compile(r"Lesson (0\d) §(\d+)(?:–(\d+))?")

TARGETS = ["CURRICULUM.md", "writeups/04-OAuth-redirect-bypass.md"]


def fix(text: str) -> tuple[str, int]:
    count = 0

    def repl(m: re.Match) -> str:
        nonlocal count
        lesson, a, b = m.group(1), int(m.group(2)), m.group(3)
        table = MAPS.get(lesson, {})
        new_a = table.get(a, a)
        if b is not None:
            out = f"Lesson {lesson} §{new_a}–{table.get(int(b), int(b))}"
        else:
            out = f"Lesson {lesson} §{new_a}"
        if out != m.group(0):
            count += 1
        return out

    return REF.sub(repl, text), count


def main() -> int:
    total = 0
    for name in TARGETS:
        path = Path(name)
        if not path.is_file():
            print(f"  {name}: not found, skipped")
            continue
        text = path.read_text(encoding="utf-8")
        new_text, n = fix(text)
        if n:
            path.write_text(new_text, encoding="utf-8")
        print(f"  {name}: {n} reference(s) updated")
        total += n
    print(f"\n{total} reference(s) fixed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
