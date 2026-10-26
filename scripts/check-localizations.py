#!/usr/bin/env python3
"""Validate the shipping catalog without third-party dependencies."""

import argparse
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
LANGUAGES = {"zh-Hans", "en"}
FORMAT = re.compile(r"%(?:(\d+)\$)?[-+ #0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(hh|h|ll|l|L|z|t|j)?([@diuoxXfFeEgGaAcCsSp])")


def signature(value):
    """Compare argument positions and types, allowing positional reordering."""
    result = []
    value = value.replace("%%", "")
    for position, match in enumerate(FORMAT.finditer(value), start=1):
        result.append((int(match[1] or position), (match[2] or "") + match[3]))
    return sorted(result)


def validate(path):
    catalog = json.loads(path.read_text())
    errors = []
    if catalog.get("sourceLanguage") != "en":
        errors.append("The source language must remain en.")
    for key, row in catalog["strings"].items():
        if re.search(r"[\u4e00-\u9fff]", key):
            errors.append(f"{key!r}: use an English source key")
        units = row.get("localizations", {})
        if set(units) != LANGUAGES:
            errors.append(f"{key!r}: expected complete en and zh-Hans coverage")
        for language, unit in units.items():
            string = unit.get("stringUnit", {})
            value = string.get("value", "")
            if not value.strip() or string.get("state") != "translated":
                errors.append(f"{key!r} ({language}): translation is empty or unfinished")
            if language == "en" and value != key:
                errors.append(f"{key!r}: English source value must match its key")
            if signature(value) != signature(key):
                errors.append(f"{key!r} ({language}): format arguments differ")
        if row.get("extractionState") == "stale":
            errors.append(f"{key!r}: stale entry; review its usage before removing")
    return catalog, errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, default=ROOT / "PenActor/Localizable.xcstrings")
    args = parser.parse_args()
    catalog, errors = validate(args.catalog)
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"Validated {len(catalog['strings'])} entries: English and Simplified Chinese, with matching format arguments.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
