#!/usr/bin/env python3
"""Check PenActor's English/Simplified Chinese documentation pairs and links."""

import argparse
import os
from pathlib import Path
import re
import sys
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[4]
EXCLUDED = {".git", ".agents", ".codex", ".claude", ".github", "build", "DerivedData", "Logs", "node_modules", "vendor"}
INSTRUCTIONS = {"AGENTS.md", "SKILL.md", "CLAUDE.md", "CODEX.md"}


def documents(root):
    paths = []
    for folder, dirs, files in os.walk(root):
        dirs[:] = [name for name in dirs if name not in EXCLUDED]
        for name in files:
            if name.endswith(".md") and name not in INSTRUCTIONS:
                paths.append(Path(folder) / name)
    return sorted(paths)


def split_markdown(text):
    blocks = re.findall(r"^```[^\n]*\n.*?^```[ \t]*$", text, re.MULTILINE | re.DOTALL)
    prose = re.sub(r"^```[^\n]*\n.*?^```[ \t]*$", "", text, flags=re.MULTILINE | re.DOTALL)
    headings = re.findall(r"^(#{1,6})\s+(.+?)\s*#*\s*$", prose, re.MULTILINE)
    anchors = set(re.findall(r'<a\s+(?:id|name)="([^"]+)"', prose))
    seen = {}
    for _, heading in headings:
        slug = re.sub(r"[^\w\- ]", "", heading.lower()).replace(" ", "-")
        count = seen.get(slug, 0)
        seen[slug] = count + 1
        anchors.add(slug + (f"-{count}" if count else ""))
    return blocks, prose, headings, anchors


def validate(root):
    root = root.resolve()
    paths = documents(root)
    errors = []
    content = {path: path.read_text(encoding="utf-8") for path in paths}
    parsed = {path: split_markdown(text) for path, text in content.items()}
    pairs = 0
    for path in paths:
        chinese = path.name.endswith(".zh-CN.md")
        sibling = path.with_name(path.name.replace(".zh-CN.md", ".md") if chinese else path.stem + ".zh-CN.md")
        relative = path.relative_to(root)
        if sibling not in content:
            errors.append(f"{relative}: missing translation {sibling.name}")
            continue
        lines = content[path].splitlines()
        expected = f"[English]({sibling.name}) | 简体中文" if chinese else f"English | [简体中文]({sibling.name})"
        if len(lines) < 3 or not lines[0].startswith("# ") or lines[2] != expected:
            errors.append(f"{relative}: place the language selector below the first heading")
        if not chinese:
            pairs += 1
            if parsed[path][0] != parsed[sibling][0]:
                errors.append(f"{relative}: fenced code blocks differ between languages")
            if [level for level, _ in parsed[path][2]] != [level for level, _ in parsed[sibling][2]]:
                errors.append(f"{relative}: section structure differs between languages")
        for target in re.findall(r"!?\[[^\]]*\]\(([^\s)]+)\)", parsed[path][1]):
            url = urlsplit(target.strip("<>"))
            if url.scheme or url.netloc:
                continue
            destination = (path.parent / unquote(url.path)).resolve() if url.path else path
            if not destination.exists():
                errors.append(f"{relative}: broken local link {target}")
            elif url.fragment and destination.suffix == ".md":
                anchors = parsed.get(destination, split_markdown(destination.read_text(encoding="utf-8")))[3]
                if unquote(url.fragment) not in anchors:
                    errors.append(f"{relative}: missing heading anchor {target}")
            if destination in content and destination != sibling:
                if chinese != destination.name.endswith(".zh-CN.md"):
                    errors.append(f"{relative}: document link switches language unexpectedly: {target}")
    return pairs, errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    args = parser.parse_args()
    pairs, errors = validate(args.root.resolve())
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    if not pairs:
        print("No documentation pairs found.", file=sys.stderr)
        return 1
    print(f"Validated {pairs} documentation pairs, language selectors, code blocks, and local links/anchors.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
