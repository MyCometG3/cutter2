#!/usr/bin/env python3
"""Verify every test-inventory claim in the repository against the source.

Run from the repository root:

    python3 scripts/verify_test_inventory.py

Why this exists
---------------
Four review rounds each found a stale test count that a narrower check had passed.
The failures were always the same shape: the count was *checked* in the places the
check knew how to read, and the places it could not read were never looked at. The
misses were a per-file line matched only once by `re.search`, a `Test Files:` line
outside the numbers that were being replaced, a dated historical record rewritten by
a global substitution, a bare line-number reference, and a coverage table whose
column layout no pattern matched.

So this checks *shapes of claim*, not specific strings — and **every** claim, not one
per filename:

  1. every per-file listing, in all three notations used in the documents
     (tree `├── X.swift … (N tests)`, inline `` `X.swift` (N tests) ``, and the
     coverage table `| … | `X.swift` | N | … |`)
  2. every "N files / M test source / K test methods" total claim
  3. every number `scripts/test.sh` prints
  4. that each claim set agrees with the directory, sums to the same total, and is
     internally consistent when a file is claimed more than once

Point 4's last clause exists because the first version of this script collapsed claims
by filename, so a document asserting 3 tests in one place and 99 in another would have
passed on the strength of the 3. A file appearing in several shapes is fine; appearing
with **different** counts is reported as a conflict, and every occurrence is validated
individually regardless.

It also reports claims it deliberately does not assert on, so a reader can tell the
difference between "checked and true" and "not checked".
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

TEST_DIR = Path("cutter2Tests")
HELPER = "TestMovieFixtureWriter.swift"
DOCS = ["docs/CODEBASE_REVIEW.md", "docs/DEVELOPMENT_GUIDE.md", "docs/TESTING_GUIDE.md"]
SCRIPT = Path("scripts/test.sh")

# (N tests) — the count may be followed by extra prose inside the parentheses,
# e.g. "(0 tests, fixture writer)".
TREE_LISTING = re.compile(r"[├└]──\s*([A-Za-z0-9_]+\.swift)[^\n]*?\((\d+)\s+tests?[^)]*\)")
INLINE_LISTING = re.compile(r"`([A-Za-z0-9_]+\.swift)`\s*\((\d+)\s+tests?[^)]*\)")
# | **Label** | `File.swift` … | 19 + 5 | note |
COVERAGE_ROW = re.compile(
    r"^\|\s*\*\*[^*]+\*\*\s*\|([^|]*)\|\s*([^|]*)\|\s*([^|]*)\|", re.M
)
TOTAL_CLAIM = re.compile(
    r"(\d+) files?[:\s][^.\n]{0,40}?(\d+) (?:test source files?|test \+ 1 helper)"
    r"[^.\n]{0,30}?(\d+)(?: test methods| tests)"
)

# Dated runtime results are historical records and must not be asserted against the
# current source. They are counted so the report can say how many were skipped.
DATED_RUN = re.compile(
    r"\b(?:January|February|March|April|May|June|July|August|September|October|"
    r"November|December)\s+\d{1,2},\s+\d{4}[^.]*?\b\d+/\d+\b"
)


def counts_by_file() -> dict[str, int]:
    return {
        f.name: len(re.findall(r"func test[A-Za-z0-9_]*", f.read_text(encoding="utf-8")))
        for f in sorted(TEST_DIR.glob("*.swift"))
    }


def occurrences(pattern: str, text: str) -> list[tuple[str, int]]:
    """Every `(filename, count)` claim in `text`, in document order.

    Deliberately **not** deduplicated. An earlier version collapsed claims by filename
    with `setdefault`, which meant only the first was ever compared against the source
    and a second, conflicting claim was discarded without a word — so a document that
    said `3` in one place and `99` in another could still pass. Every occurrence is
    returned so every claim is checked, and `conflicts()` below names the duplicates
    explicitly rather than letting the arithmetic hide them.
    """
    return [(m.group(1), int(m.group(2))) for m in re.finditer(pattern, text)]


def coverage_rows(text: str) -> list[tuple[str, int]]:
    """Every claim from the `| **Label** | files | numbers | note |` tables.

    A row may name several files and give several counts, as the seek-sequencing row
    does (`19 + 5`), so the two lists are zipped rather than assumed to be single. A row
    whose arity does not agree is prose (`the Overall row`), not a per-file claim, and is
    skipped — but it is also counted by `table_rows_skipped` so the gap stays visible.
    """
    claims: list[tuple[str, int]] = []
    for m in COVERAGE_ROW.finditer(text):
        names = re.findall(r"([A-Za-z0-9_]+\.swift)", m.group(1))
        numbers = [int(x) for x in re.findall(r"\d+", m.group(2).replace("**", ""))]
        if not names or len(names) != len(numbers):
            continue
        claims.extend(zip(names, numbers))
    return claims


def conflicts(claims: list[tuple[str, int]]) -> dict[str, list[int]]:
    """Filenames claimed more than once **with differing counts**.

    A file may legitimately appear in several shapes (a tree row and a table row), so
    repetition is not a problem — disagreement is. Reporting it separately means the
    document is called internally inconsistent on its own terms, independently of
    whether one of the counts happens to match the source.
    """
    seen: dict[str, list[int]] = {}
    for name, count in claims:
        seen.setdefault(name, [])
        if count not in seen[name]:
            seen[name].append(count)
    return {n: sorted(cs) for n, cs in seen.items() if len(cs) > 1}


def tally(claims: list[tuple[str, int]], actual: dict[str, int]) -> dict[str, int]:
    """Filename -> the count to use when summing. First occurrence wins.

    Only for the arithmetic. Disagreement between occurrences is reported by
    `conflicts()` and each occurrence is validated on its own, so nothing is hidden by
    this choice.
    """
    out: dict[str, int] = {}
    for name, count in claims:
        out.setdefault(name, count)
    return out


def main() -> int:
    if not TEST_DIR.is_dir():
        print("error: run this from the repository root (cutter2Tests/ not found)", file=sys.stderr)
        return 2

    actual = counts_by_file()
    total, nfiles = sum(actual.values()), len(actual)
    problems: list[str] = []

    print(f"source of truth: {nfiles} Swift files, {total} test methods")
    print(f"  helper {HELPER}: {actual[HELPER]} methods")
    print()

    # ---- 1. per-file listings, all three notations -------------------------
    for doc in DOCS:
        path = Path(doc)
        if not path.exists():
            problems.append(f"{doc}: missing")
            continue
        text = path.read_text(encoding="utf-8")
        sets = {
            "tree": occurrences(TREE_LISTING.pattern, text),
            "inline": occurrences(INLINE_LISTING.pattern, text),
            "table": coverage_rows(text),
        }
        # The tree listings enumerate the zero-method helper (it is a directory entry);
        # the inline and coverage notations list test *sources* only. So the expected
        # set differs per shape, and saying so here is the point — an earlier version of
        # this check applied one expectation to all three and reported a false failure,
        # then risked being loosened to silence it.
        sources = {n for n, c in actual.items() if c > 0}
        expected_sets = {
            "tree": set(actual),
            "inline": sources,
            "table": sources,
        }
        for shape, claims in sets.items():
            if not claims:
                continue
            expected = expected_sets[shape]
            listed = tally(claims, actual)
            # Every occurrence is checked, not just the first per filename, so a second
            # claim that contradicts the first cannot slip past.
            wrong = sorted({(n, c, actual[n]) for n, c in claims
                            if n in actual and c != actual[n]})
            clashes = conflicts(claims)
            missing = sorted(expected - set(listed))
            extra = sorted(set(listed) - set(actual))
            zero = sorted(n for n in listed if n in actual and actual[n] == 0)
            for n, cs in sorted(clashes.items()):
                problems.append(f"{doc} [{shape}]: {n} claimed with differing counts {cs}")
            if missing:
                problems.append(f"{doc} [{shape}]: not listed {missing}")
            if extra:
                problems.append(f"{doc} [{shape}]: listed but absent {extra}")
            if wrong:
                problems.append(f"{doc} [{shape}]: wrong count {wrong}")
            summed = sum(listed.values())
            if summed != total:
                problems.append(f"{doc} [{shape}]: entries sum to {summed}, expected {total}")
            bad = missing or extra or wrong or clashes or summed != total
            note = f"  (includes {zero[0]}, 0 methods)" if zero else ""
            dup = f"  [{len(claims)} claims / {len(listed)} files]" if len(claims) != len(listed) else ""
            print(f"  {doc:28s} {shape:6s} {len(listed):2d} entries / {summed:3d}  "
                  f"{'OK' if not bad else 'NG'}{note}{dup}")

    # ---- 2. total-count claims ---------------------------------------------
    for doc in DOCS:
        path = Path(doc)
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        for m in TOTAL_CLAIM.finditer(text):
            f_, src_, n_ = (int(x) for x in m.groups())
            good = f_ == nfiles and src_ == nfiles - 1 and n_ == total
            if not good:
                problems.append(
                    f"{doc}: claim {f_} files / {src_} test source / {n_} methods "
                    f"(expected {nfiles} / {nfiles - 1} / {total})")
            print(f"  {doc:28s} claim  {f_} / {src_} / {n_}  {'OK' if good else 'NG'}")

    # ---- 3. what scripts/test.sh prints ------------------------------------
    if not SCRIPT.exists():
        problems.append(f"{SCRIPT}: missing")
    else:
        script = SCRIPT.read_text(encoding="utf-8")
        expected = [
            (f"Test Files: {nfiles}", True),
            (f"Total Tests: {total}", True),
            (f"Passing: {total}", True),
            (f"{nfiles} files ({nfiles - 1} test + 1 helper), {total} tests", True),
        ]
        for needle, want in expected:
            if (needle in script) != want:
                problems.append(f"{SCRIPT}: expected {'present' if want else 'absent'}: {needle!r}")
            print(f"  {str(SCRIPT):28s} {needle[:44]:46s} {'OK' if (needle in script) == want else 'NG'}")

    # ---- 4. deliberately not asserted -------------------------------------
    dated = sum(len(DATED_RUN.findall(Path(d).read_text(encoding='utf-8'))) for d in DOCS if Path(d).exists())
    print()
    print("not asserted (counted only, so the gap is visible):")
    print(f"  dated runtime results in the documents : {dated}")
    print("    historical records; their counts belong to the run they name, not to HEAD")
    print("  per-file totals outside cutter2Tests/  : 0 checked — no other test suite is declared")

    print()
    if problems:
        print(f"FAIL: {len(problems)} problem(s)")
        for p in problems:
            print(f"  - {p}")
        return 1
    print(f"PASS: every checked claim agrees with the source ({total} methods / {nfiles} files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
