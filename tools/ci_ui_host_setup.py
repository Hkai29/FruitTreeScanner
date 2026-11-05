#!/usr/bin/env python3
"""Prepare the real XCTest host on a CI simulator before its first launch."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import sys
from uuid import UUID

from ci_evidence import command, stamp, write_json


HOST_BUNDLE_ID = "com.hkai29.fruitscanner"
AX_DOMAIN = "com.apple.Accessibility"
AX_KEYS = ("AccessibilityEnabled", "ApplicationAccessibilityEnabled", "AuditInspectionModeEnabled")


class SetupCommandFailure(RuntimeError):
    def __init__(self, name, status):
        super().__init__(f"{name} exited {status}; see the retained command logs")
        self.status = status


def file_digest(path):
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
            size += len(block)
    if not size:
        raise ValueError(f"Empty host App file: {path.name}")
    return {"sha256": digest.hexdigest(), "bytes": size}


def inspect_app(path):
    app = path.resolve()
    if app.suffix != ".app" or not app.is_dir():
        raise ValueError("The CI host App path is not an actual .app directory")
    info = plistlib.loads((app / "Info.plist").read_bytes())
    if not isinstance(info, dict) or info.get("CFBundleSupportedPlatforms") != ["iPhoneSimulator"]:
        raise ValueError("The CI host App must declare iPhoneSimulator in Info.plist")
    if info.get("CFBundleIdentifier") != HOST_BUNDLE_ID:
        raise ValueError("The CI host App bundle identifier does not match the XCTest host")
    usage = info.get("NSLocationWhenInUseUsageDescription")
    if not isinstance(usage, str) or not usage.strip():
        raise ValueError("The CI host App has no WhenInUse location usage description")
    executable = info.get("CFBundleExecutable")
    if (not isinstance(executable, str) or not executable or Path(executable).name != executable
            or executable in (".", "..")):
        raise ValueError("Invalid XCTest host executable in Info.plist")
    identity_name = "ScanReplayBuildIdentity.json"
    identity = json.loads((app / identity_name).read_text())
    if (not isinstance(identity, dict) or identity.get("schemaVersion") != 1
            or not isinstance(identity.get("sourcesSHA256"), str)
            or not re.fullmatch(r"[0-9a-f]{64}", identity["sourcesSHA256"])
            or type(identity.get("sourceFileCount")) is not int or identity["sourceFileCount"] <= 0):
        raise ValueError("The CI host App has no valid build source identity")
    files = ["Info.plist", executable, identity_name]
    debug_code = executable + ".debug.dylib"
    if (app / debug_code).is_file():
        files.append(debug_code)
    return {"app_path": str(app), "bundle_id": HOST_BUNDLE_ID, "platform": "iPhoneSimulator",
            "location_usage_description_present": True, "source_identity": identity,
            "files": {name: file_digest(app / name) for name in files}}


def publish(app, receipt, github_env):
    data = inspect_app(app)
    if os.environ.get("GITHUB_ACTIONS") == "true" and not github_env:
        raise ValueError("GITHUB_ENV is required to hand the built host App to the CI test step")
    path = data["app_path"]
    if "\n" in path or "\r" in path:
        raise ValueError("The CI host App path contains a line break")
    write_json(receipt, data)
    if github_env:
        with Path(github_env).open("a") as handle:
            handle.write("FTS_CI_HOST_APP_PATH=" + path + "\n")
    print("Published XCTest host App: " + path)


def verify_simulator(simulator, devices_path):
    try:
        concrete = str(UUID(simulator)).upper()
    except (ValueError, TypeError) as error:
        raise ValueError("UI host preparation requires a concrete simulator UUID") from error
    if concrete != simulator.upper():
        raise ValueError("UI host preparation requires a concrete simulator UUID")
    if os.environ.get("GITHUB_ACTIONS") == "true":
        owner = "github_actions_runner"
    elif os.environ.get("FTS_CI_OWNED_SIMULATOR_ID", "").upper() == concrete:
        owner = "explicit_owned_simulator"
    else:
        raise ValueError("UI host preparation requires a CI runner or an explicitly owned simulator")
    payload = json.loads(devices_path.read_text())
    devices = payload.get("devices") if isinstance(payload, dict) else None
    if isinstance(devices, dict):
        for runtime, entries in devices.items():
            if not re.fullmatch(r"com\.apple\.CoreSimulator\.SimRuntime\.(iOS|iPadOS)-[0-9-]+", runtime):
                continue
            if not isinstance(entries, list):
                continue
            for entry in entries:
                if (isinstance(entry, dict) and entry.get("isAvailable") is True
                        and str(entry.get("udid", "")).upper() == concrete):
                    family = entry.get("deviceTypeIdentifier") or entry.get("name", "")
                    if isinstance(family, str) and any(kind in family for kind in ("iPhone", "iPad")):
                        return {"udid": concrete, "runtime": runtime, "name": entry.get("name"), "owner": owner}
    raise ValueError("The selected UUID is not an available iOS simulator in this run's inventory")


def setup(app_path, simulator, devices, output):
    output.mkdir()
    report = {"status": "failed", "simulator_id": simulator, "started_at_utc": stamp()}
    try:
        if not app_path:
            if os.environ.get("GITHUB_ACTIONS") == "true":
                raise ValueError("Missing FTS_CI_HOST_APP_PATH from the preceding CI simulator build")
            report["status"] = "not_requested"
            print("UI host setup not requested for this standalone run")
            return
        report["simulator"] = verify_simulator(simulator, devices)
        report["app"] = inspect_app(Path(app_path))
        udid = report["simulator"]["udid"]

        def step(name, *arguments):
            log = name + ".stdout"
            status = command(output, name, ["xcrun", "simctl", *arguments], log, stderr=name + ".stderr")
            if status:
                raise SetupCommandFailure(name, status)
            return (output / log).read_bytes()

        step("install", "install", udid, report["app"]["app_path"])
        step("location-grant-before-launch", "privacy", udid, "grant", "location", HOST_BUNDLE_ID)
        defaults = ("spawn", udid, "defaults")
        before = plistlib.loads(step("ax-before", *defaults, "export", AX_DOMAIN, "-"))
        if not isinstance(before, dict):
            raise ValueError("AX preference snapshot before writes is not a dictionary")
        for key in AX_KEYS:
            step("enable-" + key, *defaults, "write", AX_DOMAIN, key, "-bool", "YES")
            raw = step("readback-" + key, *defaults, "read", AX_DOMAIN, key)
            if raw.strip() != b"1":
                raise ValueError("AX readback did not confirm the enabled value for " + key)
        after = plistlib.loads(step("ax-after", *defaults, "export", AX_DOMAIN, "-"))
        if not isinstance(after, dict) or not all(type(after.get(key)) in (int, bool) and after[key] == 1 for key in AX_KEYS):
            raise ValueError("Final AX readback snapshot does not contain all three enabled values")
        if ({key: value for key, value in before.items() if key not in AX_KEYS}
                != {key: value for key, value in after.items() if key not in AX_KEYS}):
            raise ValueError("AX setup changed unrelated simulator preference values")
        report["status"] = "prepared"
        print("Prepared the real XCTest host fixture on " + udid)
    except Exception as error:
        report["error"] = str(error)
        raise
    finally:
        commands = output / "commands.jsonl"
        report["commands"] = [json.loads(line) for line in commands.read_text().splitlines()] if commands.exists() else []
        report["finished_at_utc"] = stamp()
        write_json(output / "report.json", report)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_subparsers(dest="action", required=True)
    publish_parser = actions.add_parser("publish")
    publish_parser.add_argument("--app", type=Path, required=True)
    publish_parser.add_argument("--receipt", type=Path, required=True)
    publish_parser.add_argument("--github-env", default="")
    setup_parser = actions.add_parser("setup")
    setup_parser.add_argument("--app", default="")
    setup_parser.add_argument("--simulator", default="")
    setup_parser.add_argument("--devices", type=Path, required=True)
    setup_parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.action == "publish":
            publish(args.app, args.receipt, args.github_env)
        else:
            setup(args.app, args.simulator, args.devices, args.output)
    except SetupCommandFailure as error:
        print(f"CI UI host setup failed: {error}", file=sys.stderr)
        return error.status if 0 < error.status < 126 else 2
    except Exception as error:
        print(f"CI UI host setup failed: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
