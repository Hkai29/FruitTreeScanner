#!/usr/bin/env python3
"""Validate actual batch-export Cancel/Retry in an invocation-owned iOS simulator.

Seeds one valid legacy scan and a regular file blocking the managed temporary
directory. Repairs only that fault after the UI test reaches its second alert;
inspects completed CSV bytes before the UI clears them. Also runs the existing
variety confirmation contract and legacy replay-unavailable/CSV restoration.
No production launch hooks or existing devices.
"""
import argparse
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import uuid

sys.dont_write_bytecode = True
from validate_native_ui import REPOSITORY, snapshot, evidence_passed
from code_improvement_workflow import validate_summary

METHOD = "testFailureCancelThenRetryAfterStorageRepairCompletesAndCleansExport"
CASE_ID = "BatchExportRecoveryTests/" + METHOD + "()"
APP_ID = "com.hkai29.fruitscanner"
RUNNER_ID = APP_ID + ".uitests.xctrunner"
FAULT = b"BatchExportRecovery invocation-owned directory fault\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-root", type=Path, required=True)
    args = parser.parse_args()
    parent = args.output_root.resolve()
    if parent == REPOSITORY or REPOSITORY in parent.parents:
        parser.error("Evidence must be outside the repository")
    parent.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix="batch-native-ui-", dir=parent))
    print("Evidence directory: " + str(output), flush=True)
    env = dict(os.environ)
    env.setdefault("DEVELOPER_DIR", "/Users/reece24/Downloads/Xcode-beta.app/Contents/Developer")
    before = snapshot()
    (output / "source-before.json").write_text(json.dumps(before, indent=2))

    def read(*command):
        return subprocess.check_output(command, cwd=REPOSITORY, env=env, text=True).strip()

    runtimes = json.loads(read("xcrun", "simctl", "list", "runtimes", "--json"))["runtimes"]
    runtime = max((r for r in runtimes if r.get("isAvailable") and r.get("platform") == "iOS"),
                  key=lambda r: tuple(int(v) for v in r["version"].split(".")))
    simulator = read("xcrun", "simctl", "create", "FruitTreeScanner-NativeUI-" + str(uuid.uuid4()),
                     "com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation", runtime["identifier"])
    env["TEST_RUNNER_FRUIT_NATIVE_UI_SIMULATOR_ID"] = simulator
    token = str(uuid.uuid4())
    env["TEST_RUNNER_FRUIT_BATCH_UI_TOKEN"] = token
    report = {"simulator": simulator, "runtime": runtime["identifier"], "token": token, "result": "failed"}
    process = None
    (output / "report.json").write_text(json.dumps(report, indent=2))
    common = ["-project", str(REPOSITORY / "FruitTreeScanner.xcodeproj"), "-scheme", "FruitTreeScannerUI",
              "-derivedDataPath", str(output / "DerivedData"), "CODE_SIGNING_ALLOWED=NO",
              "-destination", "platform=iOS Simulator,id=" + simulator, "-parallel-testing-enabled", "NO"]

    def run_build(command, filename):
        report[filename + "_command"] = command
        with (output / (filename + ".log")).open("w") as log:
            result = subprocess.run(command, cwd=REPOSITORY, env=env, stdout=log, stderr=subprocess.STDOUT)
        report[filename + "_exit_code"] = result.returncode
        if result.returncode:
            raise RuntimeError(filename + " failed; inspect its original log")

    try:
        run_build(["xcodebuild", "build-for-testing", *common,
                   "-resultBundlePath", str(output / "build.xcresult")], "build")
        read("xcrun", "simctl", "boot", simulator)
        read("xcrun", "simctl", "bootstatus", simulator, "-b")
        fixture = output / "fixture-originals"
        fixture.mkdir()
        (fixture / "directory-fault").write_bytes(FAULT)
        scans = fault = None
        source_hashes = {}
        command = ["xcodebuild", "test-without-building", *common, "-resultBundlePath", str(output / "ui.xcresult"),
                   "-only-testing:FruitTreeScannerUITests/BatchExportRecoveryTests",
                   "-only-testing:FruitTreeScannerUITests/VarietyConfirmationTests",
                   "-only-testing:FruitTreeScannerUITests/DashboardLayoutUITests"]
        report["ui_command"] = command
        coordination = None
        prepared = repaired = inspected = cleared = unavailable_inspected = False
        exported = None
        with (output / "ui.log").open("w") as log:
            process = subprocess.Popen(command, cwd=REPOSITORY, env=env, stdout=log, stderr=subprocess.STDOUT)
            deadline = time.monotonic() + 420
            while process.poll() is None:
                if time.monotonic() > deadline:
                    raise TimeoutError("Native UI validation exceeded its bounded deadline")
                if coordination is None:
                    found = subprocess.run(["xcrun", "simctl", "get_app_container", simulator, RUNNER_ID, "data"],
                                           cwd=REPOSITORY, env=env, capture_output=True, text=True)
                    if found.returncode == 0:
                        coordination = Path(found.stdout.strip()) / "Documents/BatchExportRecovery" / token
                        report["runner_container"] = found.stdout.strip()
                if coordination is not None:
                    if not prepared and (coordination / "request-fixture").exists():
                        # The UI test has now launched and terminated the app.
                        # Its first XCUIApplication launch installs the app.
                        container = Path(read("xcrun", "simctl", "get_app_container", simulator, APP_ID, "data"))
                        scans = container / "Documents/scans"
                        scans.mkdir(parents=True, exist_ok=True)
                        assert not list(scans.iterdir()), "Fixture must have no existing scans"
                        (scans / "batch-ui-60.ply").write_bytes(b"ply\nformat ascii 1.0\nelement vertex 1\nproperty float x\nproperty float y\nproperty float z\nend_header\n0 0 0\n")
                        (scans / "batch-ui-60_result.json").write_text(json.dumps({"treeID": "batch-ui-60", "fruitCount": 12, "yieldKg": 3.45, "fruitType": "apple"}))
                        for path in scans.iterdir():
                            (fixture / path.name).write_bytes(path.read_bytes())
                        source_hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in scans.iterdir()}
                        fault = container / "tmp/FruitTreeScannerBatchExports"
                        fault.parent.mkdir(parents=True, exist_ok=True)
                        assert not fault.exists(), "Fresh fixture must not contain existing exports"
                        fault.write_bytes(FAULT)
                        report.update(container=str(container), original_archive_sha256=source_hashes)
                        (coordination / "fixture-ready").write_text("fixture-ready")
                        prepared = True
                        print("Installed app fixture prepared before launch", flush=True)
                    if not repaired and (coordination / "request-repair").exists():
                        assert prepared and fault.is_file() and fault.read_bytes() == FAULT
                        fault.unlink()
                        (coordination / "repaired").write_text("repaired")
                        repaired = True
                        print("Storage fault repaired after second native alert", flush=True)
                    if not inspected and (coordination / "request-inspection").exists():
                        files = list(fault.glob("*/*.csv"))
                        assert repaired and len(files) == 1, files
                        exported = files[0]
                        content = exported.read_text(encoding="utf-8-sig")
                        report["completed_export_sha256"] = hashlib.sha256(exported.read_bytes()).hexdigest()
                        (output / "completed-export.csv").write_bytes(exported.read_bytes())
                        rows = list(csv.reader(io.StringIO(content)))
                        # Legacy history derives tree identity from the source
                        # filename. Keep that real contract in the fixture.
                        assert rows[1][:3] == ["batch-ui-60", "12", "3.45"], rows
                        assert len(rows[1]) == 7 and rows[1][3:5] == ["0.000000", "0.000000"] and rows[1][-1] == "apple", rows
                        assert source_hashes == {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in scans.iterdir()}
                        (coordination / "inspected").write_text("inspected")
                        inspected = True
                        print("Completed CSV inspected before clear", flush=True)
                    if not cleared and (coordination / "cleared").exists():
                        assert inspected and exported is not None and not exported.exists()
                        (coordination / "clear-inspected").write_text("clear-inspected")
                        cleared = True
                    if not unavailable_inspected and (coordination / "request-unavailable-inspection").exists():
                        assert cleared and fault.is_dir()
                        assert not [p for p in fault.rglob("*") if p.is_file()], "Failed replay must not leave a partial export"
                        assert source_hashes == {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in scans.iterdir()}
                        (coordination / "unavailable-inspected").write_text("unavailable-inspected")
                        unavailable_inspected = True
                        print("Legacy replay-unavailable preserved archives and left no export", flush=True)
                time.sleep(0.25)
            report["ui_exit_code"] = process.returncode
        summary = json.loads(read("xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(output / "ui.xcresult"), "--compact"))
        tree = json.loads(read("xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(output / "ui.xcresult"), "--compact"))
        (output / "summary.json").write_text(json.dumps(summary, indent=2))
        (output / "tests.json").write_text(json.dumps(tree, indent=2))
        validate_summary(summary)
        stack, methods = list(tree.get("testNodes", [])), {}
        while stack:
            node = stack.pop()
            if node.get("nodeType") == "Test Case":
                assert node["nodeIdentifier"] not in methods
                methods[node["nodeIdentifier"]] = node["result"]
            stack.extend(node.get("children", []))
        report.update(prepared=prepared, repaired=repaired, inspected=inspected, cleared=cleared,
                      unavailable_inspected=unavailable_inspected, methods=methods,
                      archive_preserved=scans is not None and scans.exists() and source_hashes == {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in scans.iterdir()})
        assert evidence_passed(process.returncode, summary, tree), "UI summary and preserved variety contract must pass"
        expected_methods = {
            CASE_ID,
            "VarietyConfirmationTests/testResetConfirmationPreservesCancelAndOtherCategoryThenPersistsReset()",
            "DashboardLayoutUITests/testCompactEnglishAnalyticsMetricsKeepWordsOnOneLine()",
        }
        assert set(methods) == expected_methods and all(result == "Passed" for result in methods.values())
        assert summary["totalTestCount"] == len(expected_methods)
        assert repaired and inspected and cleared and unavailable_inspected and report["archive_preserved"]
        report["result"] = "passed"
    except Exception as error:
        report["error"] = repr(error)
        raise
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=15)
        subprocess.run(["xcrun", "simctl", "shutdown", simulator], env=env, capture_output=True)
        deletion = subprocess.run(["xcrun", "simctl", "delete", simulator], env=env, capture_output=True)
        report["owned_simulator_deleted"] = deletion.returncode == 0
        report["sources_unchanged"] = before == snapshot()
        if not report["owned_simulator_deleted"] or not report["sources_unchanged"]:
            report["result"] = "failed"
        (output / "report.json").write_text(json.dumps(report, indent=2))
        print(json.dumps(report), flush=True)
    return 0 if report["result"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
