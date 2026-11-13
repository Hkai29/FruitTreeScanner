"""Run the real verifier/shared gate with controlled result-tool fixtures, not Xcode evidence."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[1]
CLASS = "ArtifactFixtureTests"


def summary():
    return {"result": "Passed", "totalTestCount": 1, "passedTests": 1, "failedTests": 0,
            "skippedTests": 0, "expectedFailures": 0, "runtimeWarnings": []}


def tree():
    return {"testNodes": [{"nodeType": "Unit test bundle", "name": "FruitTreeScannerTests", "children": [
        {"nodeType": "Test Suite", "name": CLASS, "children": [
            {"nodeType": "Test Case", "name": "testFixture", "result": "Passed"}]}]}]}


class VerifyArtifactCLITests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="verify-artifact-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.repo = self.root / "repo"
        (self.repo / "tools").mkdir(parents=True)
        for name in ("ci_verify_xctest_artifact.py", "ci_evidence.py", "ci_result_reader.py", "xctest_gate.py"):
            shutil.copy2(SOURCE / name, self.repo / "tools" / name)
        (self.repo / "FruitTreeScannerTests").mkdir()
        (self.repo / "FruitTreeScannerTests/Fixture.swift").write_text(f"class {CLASS}: XCTestCase {{}}\n")
        # All Git operations below are confined to the disposable test fixture.
        self.git("init", "-q")
        self.git("add", ".")
        self.git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "fixture")
        self.sha = self.git("rev-parse", "HEAD").strip()
        self.artifact = self.root / "artifact"
        self.producer = self.artifact / "tests-fixture"
        self.producer.mkdir(parents=True)
        self.bundle = self.producer / "tests.xcresult"
        self.bundle.mkdir()
        (self.bundle / "controlled-result-marker").write_text("Controlled fixture; not a real XCTest result")
        self.meta = {"phase": "tests", "xctest_mode": "handoff", "gate_consumer_job": "verify", "github_actions": True,
                     "github_run_id": "123456", "github_run_attempt": "2", "github_sha": self.sha}
        self.commands = [{"name": "xctest", "argv": ["xcodebuild", "test", "-resultBundlePath", "/original/tests-fixture/tests.xcresult"],
                          "log": "xctest.log", "stderr": None, "exit_code": 0}]
        self.report = dict(self.meta, primary_exit=0, final_exit=0, evidence_complete=True,
                           strict_gate_pending=True, result_bundle_present=True, commands=self.commands,
                           exports={name: {"exit_code": 0, "json_object_readable": True,
                               "stdout": name + ".json", "stderr": name + ".stderr"} for name in ("summary", "tree")})
        (self.producer / "run.json").write_text(json.dumps(self.meta))
        (self.producer / "xctest.log").write_text("Complete controlled producer log\n")
        tools = {name: {"exit_code": 0, "log": name + ".log"} for name in
                 ("xcode-version", "simulator-sdk-version", "simulator-sdk-path", "simulators")}
        for name, item in tools.items():
            (self.producer / item["log"]).write_text("Controlled original toolchain " + name)
        (self.producer / "toolchain.json").write_text(json.dumps({"developer_dir": "/original/Xcode_16.4", "commands": tools}))
        old = summary()
        old.pop("runtimeWarnings")
        (self.producer / "summary.json").write_text(json.dumps(old))
        (self.producer / "tree.json").write_text(json.dumps(tree()))
        for name in ("summary", "tree"):
            (self.producer / (name + ".stderr")).write_text("")
        self.save_report()
        self.fresh_summary = self.root / "reader-summary.json"
        self.fresh_summary.write_text(json.dumps(summary()))
        self.fresh_tree = self.root / "reader-tree.json"
        self.fresh_tree.write_text(json.dumps(tree()))
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.trace = self.root / "reader-trace.jsonl"
        # On macOS /usr/bin/git is an Xcode launcher. Keep real Git operations
        # on the host toolchain while the controlled reader has a fixture path.
        real_git = shutil.which("git")
        original_developer = os.environ.get("DEVELOPER_DIR")
        self.stub("git", f'''import os, subprocess, sys
environment = dict(os.environ)
original = {original_developer!r}
if original is None: environment.pop("DEVELOPER_DIR", None)
else: environment["DEVELOPER_DIR"] = original
raise SystemExit(subprocess.call([{real_git!r}, *sys.argv[1:]], env=environment))
''')
        self.stub("xcodebuild", 'import sys\nassert sys.argv[1:] == ["-version"]\nprint("Xcode 27 controlled reader")\n')
        self.stub("xcrun", '''import json, os, sys
with open(os.environ["READER_TRACE"], "a") as trace:
    trace.write(json.dumps({"argv": sys.argv[1:], "developer_dir": os.environ.get("DEVELOPER_DIR")}) + "\\n")
if os.environ.get("READER_FAIL"): raise SystemExit(73)
if "--find" in sys.argv:
    print("/controlled/reader/xcresulttool")
elif "--schema" in sys.argv:
    print(json.dumps({"schemas": {}} if os.environ.get("SCHEMA_FAIL") else {"schemas": {
        "Summary": {"type": "object", "required": ["runtimeWarnings"], "properties": {
            "runtimeWarnings": {"type": "array", "items": {"$ref": "#/schemas/Issue"}}}},
        "Issue": {"type": "object", "required": ["message"], "properties": {"message": {"type": "string"}}}}}))
else:
    name = "READER_SUMMARY" if "summary" in sys.argv else "READER_TREE"
    with open(os.environ[name]) as handle: print(handle.read())
''')
        self.environment = dict(os.environ, GITHUB_ACTIONS="true", GITHUB_RUN_ID=self.meta["github_run_id"],
            GITHUB_RUN_ATTEMPT=self.meta["github_run_attempt"], GITHUB_SHA=self.sha,
            DEVELOPER_DIR=str(self.root / "Xcode_27.app/Contents/Developer"),
            PATH=str(self.bin) + os.pathsep + os.environ["PATH"], READER_TRACE=str(self.trace),
            READER_SUMMARY=str(self.fresh_summary), READER_TREE=str(self.fresh_tree), PYTHONDONTWRITEBYTECODE="1")
        self.environment.pop("FTS_XCRESULT_DEVELOPER_DIR", None)
        self.output = self.root / "verification"

    def git(self, *args):
        return subprocess.run(["git", "-C", str(self.repo), *args], capture_output=True, text=True, check=True).stdout

    def stub(self, name, source):
        path = self.bin / name
        path.write_text("#!/usr/bin/env python3\n" + source)
        path.chmod(0o755)

    def save_report(self):
        (self.producer / "report.json").write_text(json.dumps(self.report))
        (self.producer / "commands.jsonl").write_text("".join(json.dumps(item) + "\n" for item in self.commands))

    def invoke(self, **environment):
        before = set(self.output.iterdir()) if self.output.exists() else set()
        result = subprocess.run([sys.executable, str(self.repo / "tools/ci_verify_xctest_artifact.py"),
            "--artifact-dir", str(self.artifact), "--output-root", str(self.output)],
            capture_output=True, text=True, env=dict(self.environment, **environment))
        created = set(self.output.iterdir()) - before if self.output.exists() else set()
        self.assertEqual(len(created), 1, result.stdout + result.stderr)
        run = created.pop()
        report = json.loads((run / "verification-report.json").read_text())
        return result, run, report

    def assert_rejected(self, **environment):
        result, run, report = self.invoke(**environment)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(report["status"], "failed")
        self.assertTrue((run / "verification-error.log").is_file())
        return run, report

    def test_same_attempt_runs_real_shared_gate_and_preserves_input(self):
        before = {str(p.relative_to(self.artifact)): hashlib.sha256(p.read_bytes()).hexdigest()
                  for p in self.artifact.rglob("*") if p.is_file()}
        result, run, report = self.invoke()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr + str(report))
        self.assertEqual(report["status"], "passed")
        self.assertEqual(report["gate_exit"], 0)
        self.assertEqual(report["declared_test_class_count"], 1)
        self.assertTrue(report["input_unchanged"])
        self.assertEqual({key: value["sha256"] for key, value in report["input_files"].items()}, before)
        self.assertEqual(json.loads((run / "producer-report.json").read_text()), self.report)
        commands = [json.loads(line) for line in (run / "commands.jsonl").read_text().splitlines()]
        gate = [item for item in commands if item["name"] == "xctest-gate"]
        self.assertEqual(len(gate), 1)
        self.assertIn(str(self.repo / "tools/xctest_gate.py"), gate[0]["argv"])
        self.assertIn("XCTest gate passed", (run / "gate.stdout").read_text())

    def test_producer_identity_mode_and_required_flags_must_match(self):
        original = dict(self.report)
        changes = {"github_sha": "0" * 40, "github_run_id": "different", "github_run_attempt": "3",
                   "xctest_mode": "strict", "gate_consumer_job": "build", "strict_gate_pending": False,
                   "github_actions": False, "evidence_complete": False, "result_bundle_present": False}
        for key, value in changes.items():
            with self.subTest(key=key):
                self.report = dict(original, **{key: value})
                self.save_report()
                self.assert_rejected()

    def test_missing_environment_and_wrong_checkout_sha_fail(self):
        self.assert_rejected(GITHUB_RUN_ID="")
        self.assert_rejected(GITHUB_SHA="0" * 40)

    def test_missing_and_duplicate_original_bundle_or_report_fail(self):
        self.bundle.rename(self.producer / "hidden-result")
        self.assert_rejected()
        (self.producer / "hidden-result").rename(self.bundle)
        duplicate = self.artifact / "tests-duplicate"
        duplicate.mkdir()
        shutil.copy2(self.producer / "report.json", duplicate / "report.json")
        self.assert_rejected()
        (duplicate / "report.json").unlink()
        (duplicate / "tests.xcresult").mkdir()
        self.assert_rejected()

    def test_primary65_and_filtered_or_failed_xctest_cannot_pass(self):
        self.report["primary_exit"] = 65
        self.save_report()
        self.assert_rejected()
        self.report["primary_exit"] = 0
        self.commands[0]["exit_code"] = 65
        self.save_report()
        self.assert_rejected()
        self.commands[0]["exit_code"] = 0
        for argument in ("-only-testing:FruitTreeScannerTests", "-skip-testing:FruitTreeScannerTests/Any"):
            self.commands[0]["argv"].append(argument)
            self.save_report()
            self.assert_rejected()
            self.commands[0]["argv"].pop()

    def test_missing_original_log_or_export_files_are_rejected(self):
        for name in ("xctest.log", "summary.stderr", "tree.json", "xcode-version.log"):
            with self.subTest(name=name):
                path = self.producer / name
                data = path.read_bytes()
                path.unlink()
                self.assert_rejected()
                path.write_bytes(data)

    def test_reader_and_schema_failures_leave_probe_evidence(self):
        for settings in ({"READER_FAIL": "1"}, {"SCHEMA_FAIL": "1"}):
            with self.subTest(settings=settings):
                run, report = self.assert_rejected(**settings)
                self.assertTrue((run / "reader-selection.json").is_file())
                self.assertTrue(list((run / "reader-probes").iterdir()))

    def test_shared_gate_still_rejects_warning_missing_warning_and_missing_class(self):
        for data in (summary() | {"runtimeWarnings": [{"message": "Publishing changes from within view updates is not allowed"}]},
                     {key: value for key, value in summary().items() if key != "runtimeWarnings"}):
            self.fresh_summary.write_text(json.dumps(data))
            run, report = self.assert_rejected()
            self.assertNotEqual(report.get("gate_exit"), 0)
            self.assertIn("XCTest gate FAILED", (run / "gate.stderr").read_text())
        self.fresh_summary.write_text(json.dumps(summary()))
        missing = tree()
        missing["testNodes"][0]["children"][0]["name"] = "UnrelatedClass"
        self.fresh_tree.write_text(json.dumps(missing))
        run, _ = self.assert_rejected()
        self.assertIn("did not execute", (run / "gate.stderr").read_text())

    def test_wrong_counts_and_old_failed166_cannot_turn_green(self):
        self.fresh_summary.write_text(json.dumps(summary() | {"passedTests": 2, "totalTestCount": 2}))
        _, report = self.assert_rejected()
        self.assertIn("summaries disagree", report["error"])
        (self.producer / "summary.json").write_text(self.fresh_summary.read_text())
        run, report = self.assert_rejected()
        self.assertNotEqual(report.get("gate_exit"), 0)
        self.assertIn("summary and result tree disagree", (run / "gate.stderr").read_text())
        old = summary() | {"result": "Failed", "totalTestCount": 1316, "passedTests": 1150, "failedTests": 166}
        (self.producer / "summary.json").write_text(json.dumps(old))
        self.fresh_summary.write_text(json.dumps(old))
        run, report = self.assert_rejected()
        self.assertNotEqual(report.get("gate_exit"), 0)
        self.assertIn("incomplete", (run / "gate.stderr").read_text())

    def test_symbolic_links_and_escaping_file_references_are_rejected(self):
        (self.producer / "source-link").symlink_to(self.root / "reader-summary.json")
        self.assert_rejected()
        (self.producer / "source-link").unlink()
        self.commands[0]["log"] = "../reader-summary.json"
        self.save_report()
        self.assert_rejected()


if __name__ == "__main__":
    unittest.main()
