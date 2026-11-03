#!/usr/bin/env python3
"""Validate complete synthetic replay export through actual compact iOS UI.

One owned simulator: production XCTest generates committed fixture attachments;
host seeds their exact bytes after XCUIApplication installs; native UI exports;
host checks payload bytes and cleanup; production reader/builder verifies golden.
No production launch hooks, uploads or existing simulator changes.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import uuid

sys.dont_write_bytecode = True
from validate_native_ui import REPOSITORY, snapshot, evidence_passed
from code_improvement_workflow import validate_summary

APP_ID = "com.hkai29.fruitscanner"
RUNNER_ID = APP_ID + ".uitests.xctrunner"
GOLDEN = "ScanObservationReplayTests/testLocalReplayBundlePreservesSixEvidenceCasesAndGoldenResults"
NATIVE = "ReplayExportUITests/testCompleteReplayExportPresentsShareAndCleansOnlyTemporaryFile()"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-root", type=Path, required=True)
    args = parser.parse_args()
    parent = args.output_root.resolve()
    if parent == REPOSITORY or REPOSITORY in parent.parents:
        parser.error("Evidence must be outside the repository")
    parent.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix="replay-native-ui-", dir=parent))
    print("Evidence directory: " + str(output), flush=True)
    env = dict(os.environ)
    env.setdefault("DEVELOPER_DIR", "/Users/reece24/Downloads/Xcode-beta.app/Contents/Developer")
    before = snapshot()
    (output / "source-before.json").write_text(json.dumps(before, indent=2))
    report = {"result": "failed", "synthetic_fixture": True}
    process = None
    simulator = None

    def read(*command):
        return subprocess.check_output(command, cwd=REPOSITORY, env=env, text=True).strip()

    def run(command, label, phase_env=None):
        print("Running " + label, flush=True)
        report[label + "_command"] = command
        with (output / (label + ".log")).open("w") as log:
            result = subprocess.run(command, cwd=REPOSITORY, env=phase_env or env, stdout=log, stderr=subprocess.STDOUT)
        report[label + "_exit_code"] = result.returncode
        if result.returncode:
            raise RuntimeError(label + " failed; original result retained")

    def result(label, count):
        package = output / (label + ".xcresult")
        summary = json.loads(read("xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(package), "--compact"))
        tree = json.loads(read("xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(package), "--compact"))
        (output / (label + "-summary.json")).write_text(json.dumps(summary, indent=2))
        (output / (label + "-tests.json")).write_text(json.dumps(tree, indent=2))
        validate_summary(summary)
        stack, methods = list(tree.get("testNodes", [])), {}
        while stack:
            node = stack.pop()
            if node.get("nodeType") == "Test Case":
                assert node["nodeIdentifier"] not in methods
                methods[node["nodeIdentifier"]] = node["result"]
            stack.extend(node.get("children", []))
        assert len(methods) == summary["totalTestCount"] == count and set(methods.values()) == {"Passed"}
        report[label + "_methods"] = methods
        return summary, tree, methods

    try:
        runtimes = json.loads(read("xcrun", "simctl", "list", "runtimes", "--json"))["runtimes"]
        runtime = max((r for r in runtimes if r.get("isAvailable") and r.get("platform") == "iOS"),
                      key=lambda r: tuple(int(v) for v in r["version"].split(".")))
        simulator = read("xcrun", "simctl", "create", "FruitTreeScanner-NativeUI-" + str(uuid.uuid4()),
                         "com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation", runtime["identifier"])
        token = str(uuid.uuid4())
        env["TEST_RUNNER_FRUIT_NATIVE_UI_SIMULATOR_ID"] = simulator
        env["TEST_RUNNER_FRUIT_REPLAY_UI_TOKEN"] = token
        report.update(simulator=simulator, runtime=runtime["identifier"], token=token)
        (output / "report.json").write_text(json.dumps(report, indent=2))
        read("xcrun", "simctl", "boot", simulator)
        read("xcrun", "simctl", "bootstatus", simulator, "-b")
        common = ["-project", str(REPOSITORY / "FruitTreeScanner.xcodeproj"),
                  "-derivedDataPath", str(output / "DerivedData"), "CODE_SIGNING_ALLOWED=NO",
                  "-destination", "platform=iOS Simulator,id=" + simulator, "-parallel-testing-enabled", "NO"]
        capture_env = dict(env, TEST_RUNNER_FRUIT_REPLAY_UI_CAPTURE_TOKEN=token)
        run(["xcodebuild", "test", *common, "-scheme", "FruitTreeScanner", "-resultBundlePath", str(output / "fixture.xcresult"),
             "-only-testing:FruitTreeScannerTests/" + GOLDEN], "fixture", capture_env)
        _, _, methods = result("fixture", 1)
        assert methods.get(GOLDEN + "()") == "Passed"
        run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(output / "fixture.xcresult"),
             "--output-path", str(output / "fixture-attachments")], "fixture-attachments")
        attachments = [a for entry in json.loads((output / "fixture-attachments/manifest.json").read_text())
                       for a in entry["attachments"]]

        def attachment(alias, entries=attachments, directory="fixture-attachments"):
            found = [a for a in entries if a["suggestedHumanReadableName"].startswith(alias + "_")]
            assert len(found) == 1, (alias, found)
            filename = found[0]["exportedFileName"]
            assert Path(filename).name == filename
            return output / directory / filename

        manifest = json.loads(attachment("ReplayUI-" + token + "-manifest").read_bytes())
        assert len(manifest) == 6
        fixture = output / "fixture"
        fixture.mkdir()
        for entry in manifest:
            assert Path(entry["name"]).name == entry["name"] and entry["name"] not in {".", ".."}
            data = attachment(entry["attachment"]).read_bytes()
            assert len(data) == entry["bytes"] and hashlib.sha256(data).hexdigest() == entry["sha256"]
            destination = fixture / entry["name"]
            assert not destination.exists()
            destination.write_bytes(data)
        source_hashes = {p.name: digest(p) for p in fixture.iterdir()}
        assert len([p for p in fixture.iterdir() if p.suffix == ".ply"]) == 1
        report["original_archive_sha256"] = source_hashes
        ui_common = [*common, "-scheme", "FruitTreeScannerUI"]
        run(["xcodebuild", "build-for-testing", *ui_common, "-resultBundlePath", str(output / "build.xcresult")], "build")
        command = ["xcodebuild", "test-without-building", *ui_common, "-resultBundlePath", str(output / "ui.xcresult"),
                   "-only-testing:FruitTreeScannerUITests/ReplayExportUITests",
                   "-only-testing:FruitTreeScannerUITests/VarietyConfirmationTests"]
        report["ui_command"] = command
        coordination = scans = exports = container = exported = None
        prepared = inspected = cleared = False
        with (output / "ui.log").open("w") as log:
            process = subprocess.Popen(command, cwd=REPOSITORY, env=env, stdout=log, stderr=subprocess.STDOUT)
            deadline = time.monotonic() + 420
            while process.poll() is None:
                if time.monotonic() > deadline:
                    raise TimeoutError("Native replay validation exceeded its bounded deadline")
                if coordination is None:
                    found = subprocess.run(["xcrun", "simctl", "get_app_container", simulator, RUNNER_ID, "data"], env=env, capture_output=True, text=True)
                    if found.returncode == 0:
                        coordination = Path(found.stdout.strip()) / "Documents/ReplayExport" / token
                if coordination is not None:
                    if not prepared and (coordination / "request-fixture").exists():
                        container = Path(read("xcrun", "simctl", "get_app_container", simulator, APP_ID, "data"))
                        scans = container / "Documents/scans"
                        scans.mkdir(parents=True, exist_ok=True)
                        assert not list(scans.iterdir()), "Owned fixture must start without existing scans"
                        for p in fixture.iterdir(): shutil.copy2(p, scans / p.name)
                        assert source_hashes == {p.name: digest(p) for p in scans.iterdir()}
                        exports = container / "tmp/FruitTreeScannerBatchExports"
                        (coordination / "fixture-ready").write_text("ready")
                        prepared = True
                        print("Production-committed synthetic fixture installed", flush=True)
                    if not inspected and (coordination / "request-inspection").exists():
                        files = [p for p in exports.rglob("*") if p.is_file()]
                        assert prepared and len(files) == 1 and files[0].suffix == ".ftsreplay", files
                        exported = files[0]
                        data = exported.read_bytes()
                        assert data[:8] == b"FTSRSET1" and struct.unpack_from("<I", data, 8)[0] == 1
                        size = struct.unpack_from("<I", data, 12)[0]
                        assert 0 < size <= 16384
                        header = json.loads(data[16:16 + size])
                        descriptor = header["descriptor"]
                        cursor = 16 + size
                        for suffix, count_key, sha_key in [("_replay.json", "inputByteCount", "inputSHA256"),
                                                           ("_replay.f32", "pointsByteCount", "pointsSHA256")]:
                            originals = [p for p in fixture.iterdir() if p.name.endswith(suffix)]
                            assert len(originals) == 1
                            count = descriptor[count_key]
                            payload = data[cursor:cursor + count]
                            assert count > 0 and payload == originals[0].read_bytes()
                            assert hashlib.sha256(payload).hexdigest() == descriptor[sha_key]
                            cursor += count
                        golden = data[cursor:]
                        assert len(golden) == header["goldenByteCount"] and hashlib.sha256(golden).hexdigest() == header["goldenSHA256"]
                        for private in [b"PRIVATE_FILENAME", b"PRIVATE_TREE_SENTINEL", b"PRIVATE_PLOT_SENTINEL", b"PRIVATE_TAG_SENTINEL", b"12.345678", b"67.891234"]:
                            assert private not in data
                        assert source_hashes == {p.name: digest(p) for p in scans.iterdir()}
                        shutil.copy2(exported, output / "native-export.ftsreplay")
                        verification = container / "Documents/ReplayUIVerification" / token
                        verification.mkdir(parents=True, exist_ok=False)
                        for p in fixture.iterdir(): shutil.copy2(p, verification / p.name)
                        shutil.copy2(exported, verification / "export.ftsreplay")
                        report["native_export_sha256"] = digest(exported)
                        (coordination / "inspected").write_text("inspected")
                        inspected = True
                        print("Actual native export payload bytes verified and saved", flush=True)
                    if not cleared and (coordination / "cleared").exists():
                        assert inspected and not exported.exists()
                        assert not [p for p in exports.rglob("*") if p.is_file()]
                        assert source_hashes == {p.name: digest(p) for p in scans.iterdir()}
                        (coordination / "clear-inspected").write_text("clear-inspected")
                        cleared = True
                time.sleep(0.25)
            report["ui_exit_code"] = process.returncode
        summary, tree, methods = result("ui", 2)
        assert evidence_passed(process.returncode, summary, tree) and methods.get(NATIVE) == "Passed"
        assert prepared and inspected and cleared
        verify_env = dict(env, TEST_RUNNER_FRUIT_REPLAY_UI_VERIFY_TOKEN=token)
        run(["xcodebuild", "test", *common, "-scheme", "FruitTreeScanner", "-resultBundlePath", str(output / "golden.xcresult"),
             "-only-testing:FruitTreeScannerTests/" + GOLDEN], "golden", verify_env)
        _, _, methods = result("golden", 1)
        assert methods.get(GOLDEN + "()") == "Passed"
        run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(output / "golden.xcresult"),
             "--output-path", str(output / "golden-attachments")], "golden-attachments")
        golden_attachments = [a for entry in json.loads((output / "golden-attachments/manifest.json").read_text())
                              for a in entry["attachments"]]
        # This token-specific attachment is emitted only after the actual native
        # package passed reader/builder checks; a skipped environment branch fails.
        proof = attachment("NativeReplay66-GoldenVerified-" + token, golden_attachments, "golden-attachments")
        assert proof.read_text() == "Native export matches original identity/revision/golden; correctedCount=2; fusedEvidence=1; 0.48540313 kg"
        report["golden_proof_sha256"] = digest(proof)
        # xcodebuild may reinstall the host and move its data container. Resolve
        # the current path before checking the preserved archive after readback.
        current_container = Path(read("xcrun", "simctl", "get_app_container", simulator, APP_ID, "data"))
        report["container_relocated_after_golden"] = current_container != container
        scans = current_container / "Documents/scans"
        assert source_hashes == {p.name: digest(p) for p in scans.iterdir()}
        report.update(prepared=prepared, inspected=inspected, cleared=cleared, golden_verified=True, archive_preserved=True, result="passed")
    except Exception as error:
        report["error"] = repr(error)
        raise
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try: process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=15)
        if simulator is not None:
            subprocess.run(["xcrun", "simctl", "shutdown", simulator], env=env, capture_output=True)
            deletion = subprocess.run(["xcrun", "simctl", "delete", simulator], env=env, capture_output=True)
            report["owned_simulator_deleted"] = deletion.returncode == 0
        report["sources_unchanged"] = before == snapshot()
        if not report.get("owned_simulator_deleted") or not report["sources_unchanged"]:
            report["result"] = "failed"
        (output / "report.json").write_text(json.dumps(report, indent=2))
        print(json.dumps(report), flush=True)
    return 0 if report["result"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
