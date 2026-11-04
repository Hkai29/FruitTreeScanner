#!/usr/bin/env python3
"""Retain CI diagnostics without changing the shared XCTest acceptance policy."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import tempfile


def stamp():
    return datetime.now(timezone.utc).isoformat()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def command(run, name, argv, log, stderr=None, developer_dir=None):
    environment = dict(os.environ)
    if developer_dir is not None:
        environment["DEVELOPER_DIR"] = developer_dir
    record = {"name": name, "argv": argv, "started_at_utc": stamp(),
              "log": log, "stderr": stderr, "developer_dir": environment.get("DEVELOPER_DIR")}
    status = 2
    try:
        with (run / log).open("w") as output:
            if stderr:
                with (run / stderr).open("w") as errors:
                    status = subprocess.run(argv, stdout=output, stderr=errors, env=environment).returncode
            else:
                status = subprocess.run(argv, stdout=output, stderr=subprocess.STDOUT, env=environment).returncode
    except OSError as error:
        record["launch_error"] = str(error)
        print(f"Cannot execute {name}: {error}", file=sys.stderr)
        status = 127
    if status < 0:
        status = 128 - status
    record.update(exit_code=status, finished_at_utc=stamp())
    try:
        with (run / "commands.jsonl").open("a") as handle:
            handle.write(json.dumps(record) + "\n")
    except OSError as error:
        print(f"Cannot retain command evidence: {error}", file=sys.stderr)
        return status if status else 2
    return status


def prepare(args):
    root = args.root.resolve()
    repo = args.repo.resolve()
    build_root = args.build_root.resolve()
    if root == repo or repo in root.parents:
        raise ValueError("CI evidence must be outside the repository")
    if build_root == root or root in build_root.parents:
        raise ValueError("DerivedData/build root must be outside the uploaded evidence root")
    root.mkdir(parents=True, exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix=args.phase + "-", dir=root))
    write_json(run / "run.json", {"phase": args.phase, "repo": str(repo),
        "started_at_utc": stamp(), "python": sys.version, "platform": platform.platform(),
        "github_run_id": os.environ.get("GITHUB_RUN_ID"),
        "github_run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT"),
        "github_sha": os.environ.get("GITHUB_SHA")})
    print(run)
    return 0


def toolchain(run):
    commands = (
        ("xcode-version", ["xcodebuild", "-version"]),
        ("simulator-sdk-version", ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"]),
        ("simulator-sdk-path", ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"]),
        ("simulators", ["xcrun", "simctl", "list", "devices", "available", "-j"]),
    )
    results = {}
    for name, argv in commands:
        results[name] = {"exit_code": command(run, name, argv, name + ".log"), "log": name + ".log"}
    reader = os.environ.get("FTS_XCRESULT_DEVELOPER_DIR") or None
    if reader:
        for name, argv in (("reader-xcode-version", ["xcodebuild", "-version"]),
                           ("reader-xcresulttool-path", ["xcrun", "--find", "xcresulttool"])):
            results[name] = {"exit_code": command(run, name, argv, name + ".log", developer_dir=reader),
                             "log": name + ".log"}
    write_json(run / "toolchain.json", {"developer_dir": os.environ.get("DEVELOPER_DIR"),
                                        "reader_developer_dir": reader, "commands": results})
    return 2 if any(value["exit_code"] for value in results.values()) else 0


def version_tuple(value):
    if not isinstance(value, str) or not re.fullmatch(r"\d+(?:\.\d+){0,2}", value):
        raise ValueError("Invalid simulator SDK/runtime version: " + repr(value))
    parts = tuple(int(part) for part in value.split("."))
    return parts + (0,) * (3 - len(parts))


def runtime_version(identifier):
    if not isinstance(identifier, str):
        return None
    match = re.search(r"(?:^|\.)(iOS|iPadOS)-(\d+(?:-\d+){0,2})$", identifier)
    return match.group(2).replace("-", ".") if match else None


def select_simulator(sdk_version, payload):
    sdk = version_tuple(sdk_version)
    devices = payload.get("devices") if isinstance(payload, dict) else None
    if not isinstance(devices, dict):
        raise ValueError("Available simulator evidence has no devices object")
    candidates = []
    for runtime, entries in devices.items():
        version = runtime_version(runtime)
        if version is None or version_tuple(version) > sdk or not isinstance(entries, list):
            continue
        for device in entries:
            if not isinstance(device, dict) or device.get("isAvailable") is not True:
                continue
            name = device.get("name", "")
            udid = device.get("udid", "")
            device_type = device.get("deviceTypeIdentifier", "")
            family = device_type if device_type else name
            if not isinstance(family, str) or not any(kind in family for kind in ("iPhone", "iPad")):
                continue
            if not isinstance(udid, str) or not udid:
                continue
            candidates.append({"runtime": runtime, "runtime_version": version,
                               "device": {"name": name, "udid": udid, "device_type": device_type}})
    if not candidates:
        raise ValueError("No SDK-compatible available iPhone/iPad runtime at or below simulator SDK " + sdk_version)
    selected = max(candidates, key=lambda item: version_tuple(item["runtime_version"]))
    return dict(selected, sdk_version=sdk_version, mode="automatic",
                reason="exact_sdk_runtime" if version_tuple(selected["runtime_version"]) == sdk
                       else "newest_compatible_runtime",
                destination="platform=iOS Simulator,id=" + selected["device"]["udid"])


def destination(run, override):
    selection = {"source_logs": {"sdk": "simulator-sdk-version.log", "devices": "simulators.log"},
                 "mode": "explicit" if override else "automatic"}
    try:
        sdk = (run / "simulator-sdk-version.log").read_text().strip()
        selection["sdk_version"] = sdk
        if override:
            # Preserve the caller's destination verbatim, including an intentional
            # runtime override. xcodebuild remains responsible for validating it.
            selection.update(destination=override, reason="explicit_caller_override")
        else:
            payload = json.loads((run / "simulators.log").read_text())
            selection.update(select_simulator(sdk, payload))
    except (OSError, ValueError) as error:
        selection["error"] = str(error)
        write_json(run / "selection.json", selection)
        raise
    write_json(run / "selection.json", selection)
    print(selection["destination"])
    return 0


def finish(run, primary):
    metadata = json.loads((run / "run.json").read_text())
    exports = {}
    try:
        tools = json.loads((run / "toolchain.json").read_text())["commands"]
        evidence_failed = not tools or any(value["exit_code"] or not (run / value["log"]).is_file()
                                           for value in tools.values())
    except (OSError, ValueError, KeyError, TypeError):
        evidence_failed = True
    bundle = run / "tests.xcresult"
    if metadata["phase"] == "tests":
        for section, kind in (("summary", "summary"), ("tree", "tests")):
            if not bundle.is_dir():
                exports[section] = {"status": "unavailable", "reason": "xcodebuild produced no result bundle"}
                evidence_failed = True
                continue
            status = command(run, "export-" + section,
                ["xcrun", "xcresulttool", "get", "test-results", kind, "--path", str(bundle), "--format", "json"],
                section + ".json", section + ".stderr",
                developer_dir=os.environ.get("FTS_XCRESULT_DEVELOPER_DIR") or None)
            valid = False
            try:
                valid = isinstance(json.loads((run / (section + ".json")).read_text()), dict)
            except (OSError, ValueError):
                pass
            exports[section] = {"exit_code": status, "json_object_readable": valid,
                                "stdout": section + ".json", "stderr": section + ".stderr"}
            evidence_failed |= status != 0 or not valid
    commands_path = run / "commands.jsonl"
    commands = [json.loads(line) for line in commands_path.read_text().splitlines()] if commands_path.exists() else []
    expected = "xctest" if metadata["phase"] == "tests" else "simulator-build"
    evidence_failed |= not any(item["name"] == expected for item in commands)
    evidence_failed |= any(not (run / item["log"]).is_file() for item in commands)
    if metadata["phase"] == "tests" and primary == 0:
        evidence_failed |= not any(item["name"] == "xctest-gate" and item["exit_code"] == 0 for item in commands)
    final = primary if primary else (2 if evidence_failed else 0)
    write_json(run / "report.json", dict(metadata, finished_at_utc=stamp(), primary_exit=primary,
        final_exit=final, result_bundle_present=bundle.is_dir(), exports=exports,
        commands=commands, evidence_complete=not evidence_failed))
    print(f"CI evidence: {run} (primary exit {primary}, final exit {final})")
    return final


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    init = sub.add_parser("prepare")
    init.add_argument("--root", type=Path, required=True)
    init.add_argument("--build-root", type=Path, required=True)
    init.add_argument("--repo", type=Path, required=True)
    init.add_argument("--phase", choices=("build", "tests"), required=True)
    for action in ("toolchain", "destination", "finish", "run"):
        item = sub.add_parser(action)
        item.add_argument("directory", type=Path)
        if action == "finish":
            item.add_argument("--status", type=int, required=True)
        elif action == "destination":
            item.add_argument("--override", default="")
        elif action == "run":
            item.add_argument("--name", required=True)
            item.add_argument("--log", required=True)
            item.add_argument("argv", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    try:
        if args.action == "prepare":
            return prepare(args)
        if args.action == "toolchain":
            return toolchain(args.directory)
        if args.action == "destination":
            return destination(args.directory, args.override)
        if args.action == "finish":
            return finish(args.directory, args.status)
        argv = args.argv[1:] if args.argv[:1] == ["--"] else args.argv
        if not argv:
            raise ValueError("A command is required")
        return command(args.directory, args.name, argv, args.log)
    except Exception as error:
        print(f"CI evidence failure: {error}", file=sys.stderr)
        if args.action == "finish" and args.status:
            return args.status
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
