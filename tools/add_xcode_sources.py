#!/usr/bin/env python3
"""Add Swift source files to the Xcode project without disturbing existing entries.

Usage:  python3 tools/add_xcode_sources.py <group-path> <file.swift> [...]

<group-path> is a path relative to the app source root, e.g. "Design" or "Views".
The group must already exist in the project. Files are registered in the main app
target's Sources build phase only.
"""
from __future__ import annotations

import hashlib
import os
import re
import sys
from pathlib import Path

PROJECT = Path("FruitTreeScanner.xcodeproj/project.pbxproj")
SOURCE_ROOT = Path("FruitTreeScanner")


def make_ids(stem: str, salt: str) -> tuple[str, str]:
    digest = hashlib.sha1(f"{stem}::{salt}::{PROJECT.stat().st_size}".encode()).hexdigest().upper()
    return digest[:24], digest[24:][:24]


def find_group(text: str, group_path: str) -> str:
    """Return the pbx group id for a slash separated path like 'Design'."""
    current = None
    for part in group_path.split("/"):
        pattern = re.compile(
            r"([0-9A-F]{24}|[A-Z][A-Z0-9_]{9,}) /\* " + re.escape(part) + r" \*/ = \{\n"
            r"\s*isa = PBXGroup;",
        )
        matches = pattern.findall(text)
        if not matches:
            raise SystemExit(f"group not found: {part}")
        gid = matches[0]
        # narrow to the child list of this group
        block = re.search(
            re.escape(gid) + r" /\* " + re.escape(part) + r" \*/ = \{.*?\};", text, re.S
        )
        if block is None:
            raise SystemExit(f"group block not found: {part}")
        inner = re.search(r"children = \((.*?)\);", block.group(0), re.S)
        if inner is None:
            raise SystemExit(f"group has no children: {part}")
        current = gid
    return current


def add_file(text: str, group_path: str, rel_path: str, sources_anchor: str) -> str:
    name = Path(rel_path).name
    if f"/* {name} in Sources */" in text:
        print(f"skip (already registered): {rel_path}")
        return text

    gid = find_group(text, group_path)
    file_id, build_id = make_ids(rel_path, "file")
    # guarantee uniqueness
    while file_id in text:
        file_id, build_id = make_ids(rel_path, file_id)

    # 1. PBXBuildFile
    anchor = "/* Begin PBXBuildFile section */"
    entry = (
        f"\t\t{build_id} /* {name} in Sources */ = {{isa = PBXBuildFile; "
        f"fileRef = {file_id} /* {name} */; }};\n"
    )
    text = text.replace(anchor, anchor + "\n" + entry.rstrip("\n"), 1)

    # 2. PBXFileReference
    anchor = "/* Begin PBXFileReference section */"
    entry = (
        f"\t\t{file_id} /* {name} */ = {{isa = PBXFileReference; "
        f"lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = \"<group>\"; }};\n"
    )
    text = text.replace(anchor, anchor + "\n" + entry.rstrip("\n"), 1)

    # 3. add to group children
    block_re = re.compile(
        r"(" + re.escape(gid) + r" /\* " + re.escape(group_path.split("/")[-1])
        + r" \*/ = \{\n\s*isa = PBXGroup;\n\s*children = \((.*?)\);)",
        re.S,
    )
    match = block_re.search(text)
    if match is None:
        raise SystemExit(f"could not locate children list for group {group_path}")
    children = match.group(2)
    if name in children:
        print(f"skip (already in group): {rel_path}")
        return text
    separator = "\n\t\t\t\t" if "\n" in children else " "
    new_children = children + separator + f"{file_id} /* {name} */,"
    text = text[: match.start(2)] + new_children + text[match.end(2):]

    # 4. add to Sources build phase (app target only)
    phase_re = re.compile(
        r"([0-9A-F]{24}|[A-Z][A-Z0-9_]{9,})(?: /\* [^\n]* \*/)? = \{\n"
        r"\s*isa = PBXSourcesBuildPhase;.*?files = \((.*?)\);",
        re.S,
    )
    target = None
    for match in phase_re.finditer(text):
        if sources_anchor in match.group(2):
            target = match
            break
    if target is None:
        raise SystemExit(f"could not identify a Sources build phase containing {sources_anchor!r}")
    files = target.group(2)
    separator = "\n\t\t\t\t" if "\n" in files else " "
    new_files = files + separator + f"{build_id} /* {name} in Sources */,"
    text = text[: target.start(2)] + new_files + text[target.end(2):]

    print(f"added: {rel_path}  file={file_id} build={build_id}")
    return text


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    group_path = sys.argv[1]
    files = sys.argv[2:]
    anchor = os.environ.get("XCODE_SOURCES_ANCHOR", "Theme.swift in Sources")
    text = PROJECT.read_text()
    for rel in files:
        if not Path(rel).exists():
            raise SystemExit(f"missing source file: {rel}")
        text = add_file(text, group_path, rel, anchor)
    # 不要留下行尾空白（git diff --check 会报）。
    text = "\n".join(line.rstrip() if line.strip() == "" else line for line in text.split("\n"))
    PROJECT.write_text(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
