"""Real CI entrypoints with controlled Simulator commands; no local device access."""
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY = Path(__file__).resolve().parents[2]
SIMULATOR_ID = "01234567-89AB-4CDE-8FAB-0123456789AB"
HOST_ID = "com.hkai29.fruitscanner"
AX_KEYS = ("AccessibilityEnabled", "ApplicationAccessibilityEnabled", "AuditInspectionModeEnabled")


class CIUIHostSetupTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="ci ui host ")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.repo = self.root / "repo"
        (self.repo / "tools").mkdir(parents=True)
        (self.repo / "FruitTreeScannerTests").mkdir()
        (self.repo / "FruitTreeScannerTests/LocalTests.swift").write_text("class LocalTests: XCTestCase {}")
        for name in ("ci_evidence.py", "ci_result_reader.py", "ci_ui_host_setup.py", "ci_simulator_build.sh",
                     "ci_xctest_gate.sh", "xctest_gate.py"):
            source = REPOSITORY / "tools" / name
            if source.is_file():
                shutil.copy2(source, self.repo / "tools" / name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.trace = self.root / "trace.jsonl"
        self.state = self.root / "state.json"
        self.env_file = self.root / "github-env"
        self.state.write_text(json.dumps({"prefs": {"ReduceMotionEnabled": 0}, "installed": False, "granted": False}))
        self.devices = self.root / "simulators.log"
        self.devices.write_text(json.dumps({"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-18-5": [
            {"isAvailable": True, "name": "iPhone Stub", "udid": SIMULATOR_ID,
             "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-16"}]}}))
        self.app = self.root / "build product" / "FruitTreeScanner.app"
        self.make_app(self.app)
        self.stub("xcrun", '''import json, os, pathlib, plistlib, sys
args = sys.argv[1:]
with pathlib.Path(os.environ["STUB_TRACE"]).open("a") as trace:
    print(json.dumps({"tool": "xcrun", "argv": args}), file=trace)
state_path = pathlib.Path(os.environ["STUB_STATE"])
state = json.loads(state_path.read_text())
if args[0] == "--sdk":
    print("18.5" if "--show-sdk-version" in args else "/stub/SDK")
elif args[:2] == ["--find", "xcresulttool"]:
    print("/stub/Developer/usr/bin/xcresulttool")
elif args[:2] == ["simctl", "list"]:
    print(pathlib.Path(os.environ["STUB_DEVICES"]).read_text())
elif args[:2] == ["simctl", "bootstatus"]:
    print("Boot complete")
elif args[:2] == ["simctl", "install"]:
    if os.environ.get("STUB_INSTALL_FAILURE"):
        print("controlled install error", file=sys.stderr)
        raise SystemExit(7)
    state["installed"] = True
elif args[:2] == ["simctl", "privacy"]:
    if not state["installed"] or args[3:] != ["grant", "location", "com.hkai29.fruitscanner"]:
        raise SystemExit(8)
    state["granted"] = True
elif args[:2] == ["simctl", "spawn"] and args[3] == "defaults":
    if not state["granted"]:
        raise SystemExit(9)
    if args[4] == "export":
        sys.stdout.buffer.write(plistlib.dumps(state["prefs"]))
    elif args[4] == "write":
        state["prefs"][args[6]] = args[7:] == ["-bool", "YES"]
    elif args[4] == "read":
        print(int(state["prefs"].get(args[6], False) and not os.environ.get("STUB_BAD_READBACK")))
    else:
        raise SystemExit(10)
elif args[0] == "xcresulttool":
    if "--schema" in args:
        print(json.dumps({"schemas": {
            "Summary": {"type": "object", "required": ["runtimeWarnings"], "properties": {
                "runtimeWarnings": {"type": "array", "items": {"$ref": "#/schemas/Issue"}}}},
            "Issue": {"type": "object", "required": ["message"], "properties": {"message": {"type": "string"}}}}}))
    elif "summary" in args:
        print(json.dumps({"result": "Passed", "totalTestCount": 1, "passedTests": 1,
                          "failedTests": 0, "skippedTests": 0, "expectedFailures": 0, "runtimeWarnings": []}))
    else:
        print(json.dumps({"testNodes": [{"nodeType": "Unit test bundle", "name": "FruitTreeScannerTests", "children": [
            {"nodeType": "Test Suite", "name": "LocalTests", "children": [
                {"nodeType": "Test Case", "name": "testEvidence", "result": "Passed"}]}]}]}))
else:
    raise SystemExit(11)
state_path.write_text(json.dumps(state))
''')
        self.stub("xcodebuild", '''import json, os, pathlib, shutil, sys
args = sys.argv[1:]
with pathlib.Path(os.environ["STUB_TRACE"]).open("a") as trace:
    print(json.dumps({"tool": "xcodebuild", "argv": args}), file=trace)
if "-version" in args:
    print("Xcode Stub")
elif "build" in args:
    app = pathlib.Path(args[args.index("-derivedDataPath") + 1]) / "Build/Products/Debug-iphonesimulator/FruitTreeScanner.app"
    if not os.environ.get("STUB_NO_BUILD_PRODUCT"):
        shutil.copytree(os.environ["STUB_BUILD_PRODUCT"], app)
elif "test" in args:
    state = json.loads(pathlib.Path(os.environ["STUB_STATE"]).read_text())
    keys = ("AccessibilityEnabled", "ApplicationAccessibilityEnabled", "AuditInspectionModeEnabled")
    if os.environ.get("STUB_REQUIRE_SETUP") and not (
            state["installed"] and state["granted"] and all(state["prefs"].get(k) for k in keys)):
        print("Test host started without the required fixture", file=sys.stderr)
        raise SystemExit(77)
    pathlib.Path(args[args.index("-resultBundlePath") + 1]).mkdir()
else:
    raise SystemExit(12)
''')

    def make_app(self, path, **overrides):
        path.mkdir(parents=True, exist_ok=True)
        info = {"CFBundleSupportedPlatforms": ["iPhoneSimulator"], "CFBundleIdentifier": HOST_ID,
                "CFBundleExecutable": "FruitTreeScanner", "NSLocationWhenInUseUsageDescription": "记录扫描坐标"}
        info.update(overrides)
        (path / "Info.plist").write_bytes(plistlib.dumps(info))
        (path / "FruitTreeScanner").write_bytes(b"compiled loader stub")
        (path / "FruitTreeScanner.debug.dylib").write_bytes(b"compiled app code stub")
        (path / "ScanReplayBuildIdentity.json").write_text(json.dumps(
            {"schemaVersion": 1, "sourcesSHA256": "a" * 64, "sourceFileCount": 1}))

    def stub(self, name, source):
        path = self.bin / name
        path.write_text("#!/usr/bin/env python3\n" + source)
        path.chmod(0o755)

    def execute(self, argv, **overrides):
        env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                   DEVELOPER_DIR="/stub/Developer", FTS_CI_BUILD_DIR=str(self.root / "build"),
                   FTS_CI_EVIDENCE_DIR=str(self.root / "evidence"), FTS_CI_TEST_DESTINATION="",
                   STUB_TRACE=str(self.trace), STUB_STATE=str(self.state), STUB_DEVICES=str(self.devices),
                   STUB_BUILD_PRODUCT=str(self.app))
        for name in ("GITHUB_ENV", "GITHUB_ACTIONS", "GITHUB_STEP_SUMMARY", "FTS_CI_HOST_APP_PATH",
                     "FTS_CI_OWNED_SIMULATOR_ID", "FTS_XCRESULT_DEVELOPER_DIR", "FTS_CI_XCTEST_MODE",
                     "FTS_CI_XCTEST_CONSUMER"):
            env.pop(name, None)
        env.update(overrides)
        return subprocess.run(argv, cwd=self.repo, env=env, capture_output=True, text=True)

    def shell(self, script, **overrides):
        return self.execute(["bash", str(self.repo / "tools" / script)], **overrides)

    def helper(self, simulator=SIMULATOR_ID, **overrides):
        return self.execute(["python3", str(self.repo / "tools/ci_ui_host_setup.py"), "setup",
                             "--app", str(self.app), "--simulator", simulator,
                             "--devices", str(self.devices), "--output", str(self.root / "host")], **overrides)

    def calls(self):
        return [json.loads(line) for line in self.trace.read_text().splitlines()] if self.trace.exists() else []

    def run_path(self, phase):
        return next((self.root / "evidence").glob(phase + "-*"))

    def assert_no_test_launch(self):
        self.assertFalse(any(call["tool"] == "xcodebuild" and "test" in call["argv"] for call in self.calls()))

    def test_real_ci_shell_hands_off_the_built_app_and_prepares_it_before_the_full_host_launch(self):
        build = self.shell("ci_simulator_build.sh", GITHUB_ACTIONS="true", GITHUB_ENV=str(self.env_file))
        self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
        entries = dict(line.split("=", 1) for line in self.env_file.read_text().splitlines())
        self.assertIn("FTS_CI_HOST_APP_PATH", entries)
        actual_app = Path(entries["FTS_CI_HOST_APP_PATH"])
        self.assertTrue(actual_app.is_dir())
        published = json.loads((self.run_path("build") / "host-app.json").read_text())
        self.assertEqual(published["app_path"], str(actual_app))
        self.assertEqual(published["source_identity"]["sourcesSHA256"], "a" * 64)

        tests = self.shell("ci_xctest_gate.sh", GITHUB_ACTIONS="true", FTS_CI_HOST_APP_PATH=str(actual_app),
                           STUB_REQUIRE_SETUP="1")
        self.assertEqual(tests.returncode, 0, tests.stdout + tests.stderr)
        setup = json.loads((self.run_path("tests") / "ui-host" / "report.json").read_text())
        self.assertEqual(setup["status"], "prepared")
        self.assertEqual(setup["app"], published)
        calls = self.calls()
        actions = [(call["tool"], call["argv"]) for call in calls]
        boot = actions.index(("xcrun", ["simctl", "bootstatus", SIMULATOR_ID, "-b"]))
        install = actions.index(("xcrun", ["simctl", "install", SIMULATOR_ID, str(actual_app)]))
        grant = actions.index(("xcrun", ["simctl", "privacy", SIMULATOR_ID, "grant", "location", HOST_ID]))
        test_index, test_args = next((i, args) for i, (tool, args) in enumerate(actions)
                                     if tool == "xcodebuild" and "test" in args)
        self.assertLess(boot, install)
        self.assertLess(install, grant)
        for key in AX_KEYS:
            write = actions.index(("xcrun", ["simctl", "spawn", SIMULATOR_ID, "defaults", "write",
                                             "com.apple.Accessibility", key, "-bool", "YES"]))
            read = actions.index(("xcrun", ["simctl", "spawn", SIMULATOR_ID, "defaults", "read",
                                            "com.apple.Accessibility", key]))
            self.assertLess(grant, write)
            self.assertLess(write, read)
            self.assertLess(read, test_index)
        self.assertEqual(test_args[test_args.index("-testLanguage") + 1], "zh-Hans")
        self.assertFalse(any(arg.startswith(("-only-testing", "-skip-testing")) for arg in test_args))
        self.assertEqual(json.loads(self.state.read_text())["prefs"]["ReduceMotionEnabled"], 0)

    def test_ci_missing_host_path_fails_before_tests(self):
        result = self.shell("ci_xctest_gate.sh", GITHUB_ACTIONS="true")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_no_test_launch()

    def test_local_without_host_path_keeps_the_unmodified_simulator_entrypoint(self):
        result = self.shell("ci_xctest_gate.sh")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(any(call["argv"][:2] in (["simctl", "install"], ["simctl", "privacy"], ["simctl", "spawn"])
                             for call in self.calls()))
        report = json.loads((self.run_path("tests") / "ui-host" / "report.json").read_text())
        self.assertEqual(report["status"], "not_requested")

    def test_invalid_bundle_or_physical_platform_never_executes_setup_commands(self):
        for overrides, fragment in (
            ({"CFBundleIdentifier": "wrong.bundle"}, "bundle identifier"),
            ({"CFBundleSupportedPlatforms": ["iPhoneOS"]}, "iPhoneSimulator"),
            ({"NSLocationWhenInUseUsageDescription": " "}, "location usage description"),
        ):
            with self.subTest(overrides=overrides):
                self.make_app(self.app, **overrides)
                result = self.helper(GITHUB_ACTIONS="true")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(fragment, result.stderr)
                self.assertEqual(self.calls(), [])
                if (self.root / "host").exists():
                    shutil.rmtree(self.root / "host")

    def test_requires_owned_local_simulator_and_a_concrete_available_simulator_uuid(self):
        for simulator, env, fragment in (
            (SIMULATOR_ID, {}, "owned simulator"),
            ("booted", {"GITHUB_ACTIONS": "true"}, "concrete simulator UUID"),
            ("FFFFFFFF-FFFF-4FFF-8FFF-FFFFFFFFFFFF", {"GITHUB_ACTIONS": "true"}, "available iOS simulator"),
        ):
            with self.subTest(simulator=simulator):
                result = self.helper(simulator, **env)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(fragment, result.stderr)
                self.assertEqual(self.calls(), [])
                if (self.root / "host").exists():
                    shutil.rmtree(self.root / "host")

    def test_readback_mismatch_is_hard_failure_before_the_test_host_launches(self):
        result = self.shell("ci_xctest_gate.sh", GITHUB_ACTIONS="true", FTS_CI_HOST_APP_PATH=str(self.app),
                            STUB_BAD_READBACK="1")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_no_test_launch()
        report = json.loads((self.run_path("tests") / "ui-host/report.json").read_text())
        self.assertIn("readback", report["error"])

    def test_ambiguous_destination_cannot_mutate_a_simulator(self):
        destinations = (
            f"platform=iOS Simulator,name=embedded-id={SIMULATOR_ID}",
            f"platform=iOS Simulator,id=other,id={SIMULATOR_ID}",
            f"platform=iOS Simulator,name=Conflicting device,id={SIMULATOR_ID}",
            f"platform=macOS,id={SIMULATOR_ID}",
        )
        for destination in destinations:
            with self.subTest(destination=destination):
                self.trace.unlink(missing_ok=True)
                result = self.shell("ci_xctest_gate.sh", GITHUB_ACTIONS="true", FTS_CI_HOST_APP_PATH=str(self.app),
                                    FTS_CI_TEST_DESTINATION=destination)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assert_no_test_launch()
                self.assertFalse(any(call["argv"][:2] in (["simctl", "bootstatus"], ["simctl", "install"], ["simctl", "privacy"],
                                                           ["simctl", "spawn"]) for call in self.calls()))

    def test_command_failure_retains_actual_exit_and_does_not_launch_tests(self):
        result = self.shell("ci_xctest_gate.sh", GITHUB_ACTIONS="true", FTS_CI_HOST_APP_PATH=str(self.app),
                            STUB_INSTALL_FAILURE="1")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_no_test_launch()
        run = self.run_path("tests") / "ui-host"
        report = json.loads((run / "report.json").read_text())
        self.assertEqual(report["commands"][-1]["exit_code"], 7)
        self.assertIn("controlled install error", (run / report["commands"][-1]["stderr"]).read_text())


if __name__ == "__main__":
    unittest.main()
