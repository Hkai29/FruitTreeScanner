import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY = Path(__file__).resolve().parents[2]


class CIEvidenceExecutionTests(unittest.TestCase):
    """Execute the real Bash entrypoints with controlled command-line tools."""

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="ci evidence ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.repo = self.root / "repo"
        (self.repo / "tools").mkdir(parents=True)
        (self.repo / "FruitTreeScannerTests").mkdir()
        (self.repo / "FruitTreeScannerTests/LocalTests.swift").write_text("class LocalTests: XCTestCase {}")
        for name in ("ci_xctest_gate.sh", "ci_simulator_build.sh", "ci_evidence.py", "xctest_gate.py"):
            source = REPOSITORY / "tools" / name
            if source.exists():
                shutil.copy2(source, self.repo / "tools" / name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.stub("xcodebuild", '''import os, pathlib, sys
if "-version" in sys.argv:
    print("Xcode Stub\\nBuild version stub")
    raise SystemExit(0)
if "-resultBundlePath" in sys.argv and not os.environ.get("STUB_NO_BUNDLE"):
    bundle = pathlib.Path(sys.argv[sys.argv.index("-resultBundlePath") + 1])
    bundle.mkdir()
    (bundle / "original-marker").write_text("original result bytes")
print("EARLY_DIAGNOSTIC_SENTINEL")
for index in range(100): print("error: controlled diagnostic", index)
raise SystemExit(int(os.environ.get("STUB_PRIMARY_EXIT", "0")))
''')
        self.stub("xcrun", '''import json, os, pathlib, sys
args = sys.argv[1:]
if args[0] == "--sdk":
    print("stub-sdk")
elif args[:2] == ["simctl", "bootstatus"]:
    print("Booted stub simulator")
elif args[0] == "simctl":
    print(json.dumps({"devices": {"iOS-stub": [{"isAvailable": True, "name": "iPhone Stub", "udid": "STUB-ID"}]}}))
elif args[0] == "xcresulttool":
    counter = pathlib.Path(os.environ["STUB_COUNTER"])
    number = int(counter.read_text()) + 1 if counter.exists() else 1
    counter.write_text(str(number))
    limit = int(os.environ.get("STUB_EXPORT_FAIL_AFTER", "-1"))
    if limit >= 0 and number > limit:
        print("controlled evidence export failure", file=sys.stderr)
        raise SystemExit(7)
    if "summary" in args:
        bad = bool(os.environ.get("STUB_GATE_FAIL"))
        print(json.dumps({"result": "Failed" if bad else "Passed", "totalTestCount": 1,
                          "passedTests": 0 if bad else 1, "failedTests": 1 if bad else 0,
                          "skippedTests": 0, "expectedFailures": 0, "runtimeWarnings": []}))
    else:
        print(json.dumps({"testNodes": [{"nodeType": "Unit test bundle", "name": "FruitTreeScannerTests", "children": [
            {"nodeType": "Test Suite", "name": "LocalTests", "children": [
                {"nodeType": "Test Case", "name": "testRealGate", "result": "Passed"}]}]}]}))
else: raise SystemExit(9)
''')

    def stub(self, name, source):
        path = self.bin / name
        path.write_text("#!/usr/bin/env python3\n" + source)
        path.chmod(0o755)

    def run_script(self, script="ci_xctest_gate.sh", **overrides):
        environment = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                           DEVELOPER_DIR="/stub/Developer", FTS_CI_BUILD_DIR=str(self.root / "build"),
                           FTS_CI_EVIDENCE_DIR=str(self.root / "evidence"),
                           FTS_CI_TEST_DESTINATION="platform=iOS Simulator,id=STUB-ID",
                           STUB_COUNTER=str(self.root / "counter"))
        environment.pop("GITHUB_ENV", None)
        environment.pop("GITHUB_STEP_SUMMARY", None)
        environment.update(overrides)
        return subprocess.run(["bash", str(self.repo / "tools" / script)], cwd=self.repo,
                              env=environment, capture_output=True, text=True)

    def runs(self):
        root = self.root / "evidence"
        return sorted(path for path in root.iterdir() if path.is_dir()) if root.exists() else []

    def report(self, run):
        return json.loads((run / "report.json").read_text())

    def test_exit65_preserves_full_log_result_and_attempted_exports(self):
        result = self.run_script(STUB_PRIMARY_EXIT="65", STUB_EXPORT_FAIL_AFTER="0")
        self.assertEqual(result.returncode, 65, result.stdout + result.stderr)
        self.assertEqual(len(self.runs()), 1)
        run = self.runs()[0]
        self.assertIn("EARLY_DIAGNOSTIC_SENTINEL", (run / "xctest.log").read_text())
        self.assertEqual((run / "tests.xcresult/original-marker").read_text(), "original result bytes")
        report = self.report(run)
        self.assertEqual(report["primary_exit"], 65)
        self.assertEqual(report["final_exit"], 65)
        for section in ("summary", "tree"):
            self.assertEqual(report["exports"][section]["exit_code"], 7)
            self.assertIn("controlled evidence export failure", (run / (section + ".stderr")).read_text())
        self.assertTrue((run / "toolchain.json").exists())
        self.assertTrue(any(item["name"] == "xctest" and item["exit_code"] == 65
                            for item in report["commands"]))

    def test_failed_compile_without_bundle_records_absence(self):
        result = self.run_script(STUB_PRIMARY_EXIT="65", STUB_NO_BUNDLE="1")
        self.assertEqual(result.returncode, 65, result.stdout + result.stderr)
        report = self.report(self.runs()[0])
        self.assertFalse(report["result_bundle_present"])
        self.assertEqual(report["exports"]["summary"]["status"], "unavailable")

    def test_success_requires_result_bundle(self):
        result = self.run_script(STUB_NO_BUNDLE="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.report(self.runs()[0])["final_exit"], 2)

    def test_shared_gate_rejection_keeps_raw_evidence(self):
        result = self.run_script(STUB_GATE_FAIL="1")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        run = self.runs()[0]
        self.assertIn("XCTest gate FAILED", (run / "gate.log").read_text())
        self.assertEqual(json.loads((run / "summary.json").read_text())["result"], "Failed")
        self.assertTrue((run / "tree.json").exists())

    def test_export_failure_cannot_turn_a_successful_gate_green(self):
        result = self.run_script(STUB_EXPORT_FAIL_AFTER="2")
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertEqual(self.report(self.runs()[0])["primary_exit"], 0)

    def test_repeated_runs_preserve_the_first_directory_and_exclude_build_products(self):
        first = self.run_script()
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
        first_run = self.runs()[0]
        before = {str(path.relative_to(first_run)): path.read_bytes()
                  for path in first_run.rglob("*") if path.is_file()}
        second = self.run_script()
        self.assertEqual(second.returncode, 0, second.stdout + second.stderr)
        self.assertEqual(len(self.runs()), 2)
        self.assertEqual(before, {str(path.relative_to(first_run)): path.read_bytes()
                                  for path in first_run.rglob("*") if path.is_file()})
        self.assertFalse(any(path.name in ("DerivedData", "FruitTreeScanner.app")
                             for path in (self.root / "evidence").rglob("*")))

    def test_preceding_simulator_build_failure_keeps_its_evidence(self):
        result = self.run_script("ci_simulator_build.sh", STUB_PRIMARY_EXIT="65")
        self.assertEqual(result.returncode, 65, result.stdout + result.stderr)
        run = self.runs()[0]
        self.assertIn("EARLY_DIAGNOSTIC_SENTINEL", (run / "simulator-build.log").read_text())
        self.assertEqual(self.report(run)["phase"], "build")
        self.assertEqual(self.report(run)["final_exit"], 65)


if __name__ == "__main__":
    unittest.main()
