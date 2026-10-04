#!/usr/bin/env python3
"""Run native confirmation UI tests in a newly created, disposable iOS simulator."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import uuid

REPOSITORY = Path(__file__).resolve().parents[1]
METHOD = "testResetConfirmationPreservesCancelAndOtherCategoryThenPersistsReset"
CASE_ID = "VarietyConfirmationTests/" + METHOD + "()"
CASE_URL = "test://com.apple.xcode/FruitTreeScanner/FruitTreeScannerUITests/VarietyConfirmationTests/" + METHOD


def snapshot():
    def git(*args):
        return subprocess.check_output(["git", *args], cwd=REPOSITORY)
    paths = git("ls-files", "-m", "-o", "--exclude-standard", "-z").decode().split("\0")
    return {
        "head": git("rev-parse", "HEAD").decode().strip(),
        "status": git("status", "--porcelain=v1", "--untracked-files=all").decode(),
        "diff": hashlib.sha256(git("diff", "--binary", "HEAD")).hexdigest(),
        "files": {p: hashlib.sha256((REPOSITORY / p).read_bytes()).hexdigest()
                  for p in paths if p and (REPOSITORY / p).is_file()},
    }


def case_passed(node):
    if isinstance(node, dict):
        if (node.get("nodeType") == "Test Case" and node.get("nodeIdentifier") == CASE_ID
                and node.get("nodeIdentifierURL") == CASE_URL):
            return node.get("result") == "Passed"
        return any(case_passed(value) for value in node.values())
    if isinstance(node, list):
        return any(case_passed(value) for value in node)
    return False


def evidence_passed(exit_code, summary, tree):
    return (exit_code == 0 and summary.get("result") == "Passed"
            and type(summary.get("passedTests")) is int and summary["passedTests"] > 0
            and type(summary.get("totalTestCount")) is int
            and summary["totalTestCount"] == summary["passedTests"]
            and all(type(summary.get(key)) is int and summary[key] == 0
                    for key in ("failedTests", "skippedTests", "expectedFailures"))
            and case_passed(tree))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-root", type=Path)
    args = parser.parse_args()
    parent = (args.output_root or Path(tempfile.gettempdir())).resolve()
    if parent == REPOSITORY or REPOSITORY in parent.parents:
        parser.error("Evidence must be outside the repository")
    parent.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix="fruit-native-ui-", dir=parent))
    print("Evidence directory:", output, flush=True)
    env = dict(os.environ)
    env.setdefault("DEVELOPER_DIR", "/Users/reece24/Downloads/Xcode-beta.app/Contents/Developer")

    def read(*command):
        return subprocess.check_output(command, env=env, cwd=REPOSITORY, text=True)

    before = snapshot()
    (output / "source-before.json").write_text(json.dumps(before, indent=2))
    runtimes = json.loads(read("xcrun", "simctl", "list", "runtimes", "--json"))["runtimes"]
    available = [r for r in runtimes if r.get("isAvailable") and r.get("platform") == "iOS"]
    runtime = max(available, key=lambda r: tuple(int(v) for v in r["version"].split(".")))
    simulator = read("xcrun", "simctl", "create", "FruitTreeScanner-NativeUI-" + str(uuid.uuid4()),
                     "com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation", runtime["identifier"]).strip()
    report = {"simulator": simulator, "runtime": runtime["identifier"], "result": "failed"}
    env["TEST_RUNNER_FRUIT_NATIVE_UI_SIMULATOR_ID"] = simulator
    (output / "simulator.json").write_text(json.dumps(report, indent=2))
    command = ["xcodebuild", "test", "-project", str(REPOSITORY / "FruitTreeScanner.xcodeproj"),
               "-scheme", "FruitTreeScannerUI", "-derivedDataPath", str(output / "DerivedData"),
               "CODE_SIGNING_ALLOWED=NO", "-destination", "platform=iOS Simulator,id=" + simulator,
               "-parallel-testing-enabled", "NO", "-resultBundlePath", str(output / "ui.xcresult"),
               "-only-testing:FruitTreeScannerUITests/VarietyConfirmationTests/" + METHOD]
    try:
        with (output / "ui.log").open("w") as log:
            execution = subprocess.run(command, cwd=REPOSITORY, env=env, stdout=log, stderr=subprocess.STDOUT)
        report.update(command=command, exit_code=execution.returncode)
        if (output / "ui.xcresult").exists():
            summary = json.loads(read("xcrun", "xcresulttool", "get", "test-results", "summary",
                                      "--path", str(output / "ui.xcresult"), "--compact"))
            tree = json.loads(read("xcrun", "xcresulttool", "get", "test-results", "tests",
                                   "--path", str(output / "ui.xcresult"), "--compact"))
            (output / "summary.json").write_text(json.dumps(summary, indent=2))
            (output / "tests.json").write_text(json.dumps(tree, indent=2))
            valid = evidence_passed(execution.returncode, summary, tree)
            report["critical_method_passed"] = case_passed(tree)
            report["result"] = "passed" if valid else "failed"
    finally:
        # Only this invocation's simulator is removed; existing devices are never reset or erased.
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
