#!/usr/bin/env python3
"""Check that every UI test source file is really registered in its target.

A UI test file that is not in the target's Sources build phase compiles
nowhere: the class exists in the repository but the runner can never execute
it, and the entry point silently reports "no tests". That is a protection
defect, not a cosmetic one.

This check is structural, not textual. It reads the project with plutil and
asks the project itself:

* does the file exist on disk?
* is there a PBXFileReference for it?
* is that reference a child of the expected PBXGroup?
* is there a PBXBuildFile that points at that reference?
* is that build file in the Sources build phase of the expected target?

A file that fails any of those steps is reported as unregistered.

Usage:
    python3 tools/check_test_target_registration.py
    python3 tools/check_test_target_registration.py --project <path> --json
"""
import argparse
import json
import plistlib
import subprocess
import sys
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parents[1]
DEFAULT_PROJECT = REPOSITORY / "FruitTreeScanner.xcodeproj" / "project.pbxproj"

# (group path, target name, source directory)
UI_TEST_GROUP = "FruitTreeScannerUITests"
UI_TEST_TARGET = "FruitTreeScannerUITests"
UI_TEST_SOURCES = "FruitTreeScannerUITests"


def load_project(project_path):
    """Parse the pbxproj into plain Python objects via plutil."""
    result = subprocess.run(
        ["plutil", "-convert", "json", "-o", "-", str(project_path)],
        capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError("plutil could not parse %s: %s"
                           % (project_path, result.stderr.strip()))
    return json.loads(result.stdout)


def _objects_of_type(project, isa):
    return {key: value for key, value in project["objects"].items()
            if value.get("isa") == isa}


def find_group(project, name):
    """The PBXGroup whose path (or name) matches."""
    matches = [value for value in _objects_of_type(project, "PBXGroup").values()
               if value.get("path") == name or value.get("name") == name]
    if len(matches) != 1:
        raise RuntimeError("expected exactly one group named %r, found %d"
                           % (name, len(matches)))
    return matches[0]


def find_target(project, name):
    matches = [value for value in _objects_of_type(project, "PBXNativeTarget").values()
               if value.get("name") == name]
    if len(matches) != 1:
        raise RuntimeError("expected exactly one target named %r, found %d"
                           % (name, len(matches)))
    return matches[0]


def sources_phase_ids(project, target):
    phases = []
    for phase_id in target.get("buildPhases", []):
        phase = project["objects"].get(phase_id, {})
        if phase.get("isa") == "PBXSourcesBuildPhase":
            phases.append(phase_id)
    return phases


def registered_files(project, group_name, target_name):
    """Map every registered source file name to its registration details."""
    group = find_group(project, group_name)
    target = find_target(project, target_name)
    phases = sources_phase_ids(project, target)
    if len(phases) != 1:
        raise RuntimeError("target %r must have exactly one Sources phase, found %d"
                           % (target_name, len(phases)))
    phase = project["objects"][phases[0]]

    file_references = _objects_of_type(project, "PBXFileReference")
    build_files = _objects_of_type(project, "PBXBuildFile")

    # file reference id -> file name
    reference_names = {}
    for reference_id, reference in file_references.items():
        name = reference.get("path") or reference.get("name")
        if name:
            reference_names[reference_id] = Path(name).name

    # build file id -> file reference id
    build_file_targets = {build_id: value.get("fileRef")
                          for build_id, value in build_files.items()}

    phase_files = set(phase.get("files", []))
    group_children = set(group.get("children", []))

    # Every reference that any build file points at, mapped to its name.
    referenced_by_build_file = {}
    for build_id in phase_files:
        reference_id = build_file_targets.get(build_id)
        name = reference_names.get(reference_id)
        if name is None:
            continue
        referenced_by_build_file[name] = {
            "in_sources": True,
            "in_group": reference_id in group_children,
            "reference_id": reference_id,
            "build_file_id": build_id,
        }

    # Every reference that sits in the group, whether or not it is compiled.
    in_group_only = {}
    for reference_id in group_children:
        name = reference_names.get(reference_id)
        if name is None:
            continue
        in_group_only[name] = {
            "in_sources": False,
            "in_group": True,
            "reference_id": reference_id,
            "build_file_id": None,
        }

    # Every reference that exists in the project at all, even if it is
    # orphaned: an orphan still cannot be compiled or run.
    known = {}
    for reference_id, name in reference_names.items():
        known[name] = {
            "in_sources": False,
            "in_group": reference_id in group_children,
            "reference_id": reference_id,
            "build_file_id": None,
        }

    registered = {}
    for name in set(list(referenced_by_build_file) + list(in_group_only) + list(known)):
        entry = dict(known.get(name) or {})
        entry.update(referenced_by_build_file.get(name) or {})
        entry.update({k: v for k, v in in_group_only.get(name, {}).items()
                      if k in ("in_group", "reference_id")})
        registered[name] = entry
    return registered


def check(project_path, sources_dir, group_name, target_name):
    """Return (ok, findings). findings lists the unregistered source files."""
    project = load_project(project_path)
    registered = registered_files(project, group_name, target_name)
    directory = Path(project_path).resolve().parents[1] / sources_dir
    if not directory.is_dir():
        raise RuntimeError("source directory not found: %s" % directory)

    findings = []
    for path in sorted(directory.glob("*.swift")):
        entry = registered.get(path.name)
        if entry is None:
            findings.append({
                "file": path.name,
                "reason": "no PBXFileReference for this file",
                "in_sources": False,
                "in_group": False,
            })
            continue
        problems = []
        if not entry["in_sources"]:
            problems.append("not in the target's Sources build phase")
        if not entry["in_group"]:
            problems.append("not a child of the %s group" % group_name)
        if problems:
            findings.append({
                "file": path.name,
                "reason": "; ".join(problems),
                "in_sources": entry["in_sources"],
                "in_group": entry["in_group"],
            })
    return not findings, findings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=DEFAULT_PROJECT)
    parser.add_argument("--group", default=UI_TEST_GROUP)
    parser.add_argument("--target", default=UI_TEST_TARGET)
    parser.add_argument("--sources", default=UI_TEST_SOURCES)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    try:
        ok, findings = check(args.project, args.sources, args.group, args.target)
    except RuntimeError as error:
        print("Registration check failed: %s" % error, file=sys.stderr)
        return 2

    if args.json:
        print(json.dumps({"ok": ok, "findings": findings}, indent=2, ensure_ascii=False))
    elif ok:
        print("Every %s source file is registered in target %s."
              % (args.sources, args.target))
    else:
        for finding in findings:
            print("UNREGISTERED: %s (%s)" % (finding["file"], finding["reason"]),
                  file=sys.stderr)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
