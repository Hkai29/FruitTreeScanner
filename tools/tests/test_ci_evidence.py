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
        for name in ("ci_xctest_gate.sh", "ci_simulator_build.sh", "ci_evidence.py", "xctest_gate.py",
                     "ci_result_reader.py", "ci_ui_host_setup.py"):
            source = REPOSITORY / "tools" / name
            if source.exists():
                shutil.copy2(source, self.repo / "tools" / name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.stub("xcodebuild", '''import os, pathlib, sys
if os.environ.get("STUB_TOOL_TRACE"):
    import json
    with pathlib.Path(os.environ["STUB_TOOL_TRACE"]).open("a") as trace:
        print(json.dumps({"tool": "xcodebuild", "argv": sys.argv[1:],
                          "developer_dir": os.environ.get("DEVELOPER_DIR")}), file=trace)
if os.environ.get("STUB_MISSING_READER") and os.environ.get("DEVELOPER_DIR") == os.environ.get("STUB_EXPECTED_READER"):
    print("Explicit result reader is unavailable", file=sys.stderr)
    raise SystemExit(127)
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
if os.environ.get("STUB_TOOL_TRACE"):
    with pathlib.Path(os.environ["STUB_TOOL_TRACE"]).open("a") as trace:
        print(json.dumps({"tool": "xcrun", "argv": args,
                          "developer_dir": os.environ.get("DEVELOPER_DIR")}), file=trace)
if os.environ.get("STUB_MISSING_READER") and os.environ.get("DEVELOPER_DIR") == os.environ.get("STUB_EXPECTED_READER"):
    print("Explicit result reader is unavailable", file=sys.stderr)
    raise SystemExit(127)
if args[0] == "--sdk":
    version = os.environ.get("STUB_SDK_VERSION", "18.5")
    if os.environ.get("DEVELOPER_DIR") == os.environ.get("STUB_EXPECTED_READER"):
        version = os.environ.get("STUB_READER_SDK_VERSION", "26.2")
    print(version if "--show-sdk-version" in args else "stub-sdk")
elif args[:2] == ["--find", "xcresulttool"]:
    print(os.environ["DEVELOPER_DIR"] + "/usr/bin/xcresulttool")
elif args[:2] == ["simctl", "bootstatus"]:
    print("Booted stub simulator")
elif args[0] == "simctl":
    print(os.environ.get("STUB_SIMULATORS_JSON") or json.dumps({"devices": {
        "com.apple.CoreSimulator.SimRuntime.iOS-18-5": [
            {"isAvailable": True, "name": "iPhone Stub", "udid": "STUB-ID"}]}}))
elif args[0] == "xcresulttool":
    if "--schema" in args:
        required = [] if os.environ.get("STUB_UNSUPPORTED_SCHEMA") else ["runtimeWarnings"]
        print(json.dumps({"schemas": {
            "Summary": {"type": "object", "required": required, "properties": {
                "runtimeWarnings": {"type": "array", "items": {"$ref": "#/schemas/Issue"}}}},
            "Issue": {"type": "object", "required": ["message"], "properties": {
                "message": {"type": "string"}}}}}))
        raise SystemExit(0)
    counter = pathlib.Path(os.environ["STUB_COUNTER"])
    number = int(counter.read_text()) + 1 if counter.exists() else 1
    counter.write_text(str(number))
    limit = int(os.environ.get("STUB_EXPORT_FAIL_AFTER", "-1"))
    if limit >= 0 and number > limit:
        print("controlled evidence export failure", file=sys.stderr)
        raise SystemExit(7)
    if "summary" in args:
        bad = bool(os.environ.get("STUB_GATE_FAIL"))
        summary = {"result": "Failed" if bad else "Passed", "totalTestCount": 1,
                   "passedTests": 0 if bad else 1, "failedTests": 1 if bad else 0,
                   "skippedTests": 0, "expectedFailures": 0}
        old_reader = (os.environ.get("STUB_OMIT_WARNINGS_UNLESS_READER") and
                      os.environ.get("DEVELOPER_DIR") != os.environ.get("STUB_EXPECTED_READER"))
        if not os.environ.get("STUB_ALWAYS_OMIT_WARNINGS") and not old_reader:
            summary["runtimeWarnings"] = []
        print(json.dumps(summary))
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
        environment.pop("GITHUB_ACTIONS", None)
        environment.pop("FTS_CI_HOST_APP_PATH", None)
        environment.pop("FTS_CI_OWNED_SIMULATOR_ID", None)
        environment.pop("FTS_XCRESULT_DEVELOPER_DIR", None)
        environment.pop("FTS_CI_XCTEST_MODE", None)
        environment.pop("FTS_CI_XCTEST_CONSUMER", None)
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

    def test_xctest_run_pins_chinese_baseline_without_selection_filters(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        command = next(item for item in self.report(self.runs()[0])["commands"]
                       if item["name"] == "xctest")
        argv = command["argv"]
        self.assertEqual(argv.count("-testLanguage"), 1,
                         "The Chinese golden tests require an explicit app language")
        self.assertEqual(argv[argv.index("-testLanguage") + 1], "zh-Hans")
        self.assertNotIn("-testRegion", argv)
        self.assertFalse(any(argument.startswith(("-only-testing", "-skip-testing",
                                                 "-only-test-configuration", "-skip-test-configuration"))
                             for argument in argv), "The language baseline must keep the full test selection")

    def test_default_destination_prefers_sdk_runtime_over_newer_installed_runtimes(self):
        devices = {"devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-18-5": [
                {"isAvailable": True, "name": "iPhone 16", "udid": "SDK-18-5"}],
            "com.apple.CoreSimulator.SimRuntime.iOS-18-6": [
                {"isAvailable": True, "name": "iPhone 16", "udid": "NEWER-18-6"}],
            "com.apple.CoreSimulator.SimRuntime.iOS-26-2": [
                {"isAvailable": True, "name": "iPhone 17 Pro", "udid": "NEWER-26-2"}],
        }}
        result = self.run_script(FTS_CI_TEST_DESTINATION="", STUB_SDK_VERSION="18.5",
                                 STUB_SIMULATORS_JSON=json.dumps(devices))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        run = self.runs()[0]
        argv = next(item["argv"] for item in self.report(run)["commands"] if item["name"] == "xctest")
        self.assertEqual(argv[argv.index("-destination") + 1], "platform=iOS Simulator,id=SDK-18-5")
        self.assertEqual(argv[argv.index("-testLanguage") + 1], "zh-Hans")
        self.assertFalse(any(argument.startswith(("-only-testing", "-skip-testing")) for argument in argv))
        selection = json.loads((run / "selection.json").read_text())
        self.assertEqual(selection["sdk_version"], "18.5")
        self.assertEqual(selection["runtime"], "com.apple.CoreSimulator.SimRuntime.iOS-18-5")
        self.assertEqual(selection["device"]["udid"], "SDK-18-5")
        self.assertEqual(selection["reason"], "exact_sdk_runtime")

    def test_default_destination_orders_versions_numerically_when_exact_runtime_is_absent(self):
        devices = {"devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-18-9": [
                {"isAvailable": True, "name": "iPhone Stub", "udid": "OLDER-18-9"}],
            "com.apple.CoreSimulator.SimRuntime.iOS-18-10": [
                {"isAvailable": True, "name": "iPhone Stub", "udid": "SDK-18-10"}],
        }}
        result = self.run_script(FTS_CI_TEST_DESTINATION="", STUB_SDK_VERSION="18.11",
                                 STUB_SIMULATORS_JSON=json.dumps(devices))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        run = self.runs()[0]
        argv = next(item["argv"] for item in self.report(run)["commands"] if item["name"] == "xctest")
        self.assertEqual(argv[argv.index("-destination") + 1], "platform=iOS Simulator,id=SDK-18-10")
        selection = json.loads((run / "selection.json").read_text())
        self.assertEqual(selection["runtime_version"], "18.10")
        self.assertEqual(selection["reason"], "newest_compatible_runtime")

    def test_default_destination_fails_before_tests_when_no_compatible_runtime_exists(self):
        devices = {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-2": [
            {"isAvailable": True, "name": "iPhone 17 Pro", "udid": "NEWER-26-2"}]}}
        result = self.run_script(FTS_CI_TEST_DESTINATION="", STUB_SDK_VERSION="18.5",
                                 STUB_SIMULATORS_JSON=json.dumps(devices))
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        run = self.runs()[0]
        report = self.report(run)
        self.assertEqual(report["primary_exit"], 2)
        self.assertFalse(any(item["name"] == "xctest" for item in report["commands"]))
        selection = json.loads((run / "selection.json").read_text())
        self.assertEqual(selection["sdk_version"], "18.5")
        self.assertIn("No SDK-compatible", selection["error"])

    def test_default_destination_excludes_other_platforms_unavailable_devices_and_nonphones(self):
        devices = {"devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-18-5": [
                {"isAvailable": False, "name": "iPhone 16", "udid": "UNAVAILABLE"},
                {"isAvailable": True, "name": "Apple TV", "udid": "WRONG-FAMILY"}],
            "com.apple.CoreSimulator.SimRuntime.tvOS-18-5": [
                {"isAvailable": True, "name": "iPhone Misnamed", "udid": "WRONG-PLATFORM"}],
            "com.apple.CoreSimulator.SimRuntime.iPadOS-18-4": [
                {"isAvailable": True, "name": "iPad Stub", "udid": "COMPATIBLE-IPAD"}],
        }}
        result = self.run_script(FTS_CI_TEST_DESTINATION="", STUB_SDK_VERSION="18.5",
                                 STUB_SIMULATORS_JSON=json.dumps(devices))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        argv = next(item["argv"] for item in self.report(self.runs()[0])["commands"] if item["name"] == "xctest")
        self.assertEqual(argv[argv.index("-destination") + 1], "platform=iOS Simulator,id=COMPATIBLE-IPAD")

    def test_explicit_destination_preserves_the_callers_runtime_override(self):
        explicit = "platform=iOS Simulator,id=EXPLICIT-26-2"
        result = self.run_script(FTS_CI_TEST_DESTINATION=explicit, STUB_SDK_VERSION="18.5")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        argv = next(item["argv"] for item in self.report(self.runs()[0])["commands"] if item["name"] == "xctest")
        self.assertEqual(argv[argv.index("-destination") + 1], explicit)

    def test_explicit_result_reader_preserves_compiler_sdk_and_handles_gate_and_exports(self):
        trace = self.root / "tool-trace.jsonl"
        devices = {"devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-18-5": [
                {"isAvailable": True, "name": "iPhone 16", "udid": "SDK-18-5"}],
            "com.apple.CoreSimulator.SimRuntime.iOS-26-2": [
                {"isAvailable": True, "name": "iPhone 17 Pro", "udid": "NEWER-26-2"}],
        }}
        result = self.run_script(FTS_CI_TEST_DESTINATION="", STUB_SDK_VERSION="18.5",
                                 STUB_SIMULATORS_JSON=json.dumps(devices), STUB_TOOL_TRACE=str(trace),
                                 FTS_XCRESULT_DEVELOPER_DIR="/stub/Reader", STUB_EXPECTED_READER="/stub/Reader",
                                 STUB_OMIT_WARNINGS_UNLESS_READER="1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        run = self.runs()[0]
        report = self.report(run)
        compiler = next(item for item in report["commands"] if item["name"] == "xctest")
        self.assertEqual(compiler["developer_dir"], "/stub/Developer")
        self.assertEqual(compiler["argv"][compiler["argv"].index("-destination") + 1],
                         "platform=iOS Simulator,id=SDK-18-5")
        self.assertEqual((run / "simulator-sdk-version.log").read_text().strip(), "18.5")
        selection = json.loads((run / "selection.json").read_text())
        self.assertEqual(selection["sdk_version"], "18.5")
        for name in ("reader-xcode-version", "reader-xcresulttool-path", "export-summary", "export-tree"):
            entry = next(item for item in report["commands"] if item["name"] == name)
            self.assertEqual(entry["developer_dir"], "/stub/Reader")
            self.assertEqual(entry["exit_code"], 0)
        calls = [json.loads(line) for line in trace.read_text().splitlines()]
        readers = [item for item in calls if item["tool"] == "xcrun" and item["argv"][0] == "xcresulttool"
                   and "--schema" not in item["argv"]]
        self.assertEqual(len(readers), 4, "The real gate and retained exports must each read summary and tree")
        self.assertTrue(all(item["developer_dir"] == "/stub/Reader" for item in readers))
        actual_tests = [item for item in calls if item["tool"] == "xcodebuild" and "test" in item["argv"]]
        self.assertEqual(len(actual_tests), 1)
        self.assertEqual(actual_tests[0]["developer_dir"], "/stub/Developer")

    def test_explicit_result_reader_does_not_accept_a_missing_warning_schema(self):
        result = self.run_script(FTS_XCRESULT_DEVELOPER_DIR="/stub/Reader", STUB_EXPECTED_READER="/stub/Reader",
                                 STUB_ALWAYS_OMIT_WARNINGS="1")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        run = self.runs()[0]
        self.assertEqual(self.report(run)["primary_exit"], 1)
        self.assertIn("cannot inspect warning evidence", (run / "gate.log").read_text())

    def test_unavailable_explicit_reader_fails_before_running_tests(self):
        result = self.run_script(FTS_XCRESULT_DEVELOPER_DIR="/stub/Reader", STUB_EXPECTED_READER="/stub/Reader",
                                 STUB_MISSING_READER="1")
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        report = self.report(self.runs()[0])
        self.assertFalse(any(item["name"] == "xctest" for item in report["commands"]))
        self.assertTrue(any(item["name"].startswith("reader-summary-schema-") and item["exit_code"] == 127
                            for item in report["commands"]))

    def test_executable_reader_without_required_schema_fails_before_running_tests(self):
        result = self.run_script(FTS_XCRESULT_DEVELOPER_DIR="/stub/Reader", STUB_UNSUPPORTED_SCHEMA="1")
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        run = self.runs()[0]
        self.assertFalse(any(item["name"] == "xctest" for item in self.report(run)["commands"]))
        reader = json.loads((run / "reader-selection.json").read_text())
        self.assertEqual(reader["status"], "failed")
        self.assertIn("not required", reader["probes"][0]["rejection_reason"])

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
