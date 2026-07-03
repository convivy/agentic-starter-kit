#!/usr/bin/env python3
"""validate — enforce the doc frontmatter schema, so a malformed doc is caught
at save time rather than discovered missing from the index later.

Run from anywhere: `python3 <knowledge>/scripts/validate.py`. Exits non-zero on
any error, so it works as a pre-commit check.
"""
import pathlib
import re
import sys

KINDS = {"runbook", "decision", "reference", "agent", "profile"}
STATUS = {"active", "draft", "deprecated"}
ROOT = pathlib.Path(__file__).resolve().parent.parent / "projects"


def frontmatter(text):
    if not text.startswith("---"):
        return None
    parts = text.split("---", 2)
    if len(parts) < 3:
        return None
    fm = {}
    for line in parts[1].splitlines():
        line = line.strip()
        if not line or line.startswith("#") or ":" not in line:
            continue
        key, _, value = line.partition(":")
        fm[key.strip()] = _clean_value(value)
    return fm


def _clean_value(value):
    """A quoted value is taken verbatim (its quotes delimit it, so a '#' inside
    is content); an unquoted value has a trailing ` #comment` stripped."""
    value = value.strip()
    if value[:1] in ("\"", "'"):
        q = value[0]
        end = value.find(q, 1)
        return value[1:end] if end != -1 else value[1:]
    return re.sub(r"\s+#.*$", "", value).strip()


def main():
    errs = 0
    checked = 0
    for md in sorted(ROOT.rglob("*.md")):
        checked += 1
        fm = frontmatter(md.read_text(encoding="utf-8"))
        if fm is None:
            print(f"ERROR {md}: missing frontmatter")
            errs += 1
            continue
        for key in ("id", "kind", "status", "title"):
            if key not in fm:
                print(f"ERROR {md}: missing '{key}'")
                errs += 1
        if fm.get("kind") not in KINDS:
            print(f"ERROR {md}: bad kind {fm.get('kind')!r}")
            errs += 1
        if fm.get("status") not in STATUS:
            print(f"ERROR {md}: bad status {fm.get('status')!r}")
            errs += 1
    print(f"checked {checked} docs, {errs} error(s)")
    sys.exit(1 if errs else 0)


if __name__ == "__main__":
    main()
