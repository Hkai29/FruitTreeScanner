"""Regression tests for the workflow's evidence and failure gates.

Run with PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/tests.
No Xcode, simulator, or app code is executed; Git snapshots use an isolated fixture.
"""

import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


sys.dont_write_bytecode = True
MODULE_PATH = Path(__file__).resolve().parents[1] / "code_improvement_workflow.py"
SPEC = importlib.util.spec_from_file_location("code_improvement_workflow", MODULE_PATH)
workflow = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(workflow)
REAL_SUBPROCESS_RUN = subprocess.run


def passing_summary(count=6):
    # 真实 xcresulttool 的摘要总会带 runtimeWarnings（24/24 份真实证据都有），
    # 模拟载荷也要像真的：门禁现在要求这个键存在，否则「读不出警告证据」即失败。
    return {
        "result": "Passed", "totalTestCount": count, "passedTests": count,
        "failedTests": 0, "skippedTests": 0, "expectedFailures": 0,
        "runtimeWarnings": [],
    }


def passing_tree(classes, bundle="FruitTreeScannerTests"):
    return {"testNodes": [{
        "nodeType": "Unit test bundle", "name": bundle, "children": [{
            "nodeType": "Test Suite", "name": f"FruitTreeScannerTests.{name}",
            "children": [{"nodeType": "Test Case", "name": "testEvidence", "result": "Passed"}],
        } for name in sorted(classes)],
    }]}


class CommandPlanTests(unittest.TestCase):
    def test_combined_profiles_use_exact_union_without_duplicate_selectors(self):
        profiles = ["fusion", "storage", "lifecycle"]
        plan = workflow.command_plan(profiles, Path("/tmp/evidence"), "test-simulator")
        command = dict(plan)["tests"]
        selectors = [arg for arg in command if arg.startswith("-only-testing:")]
        expected_classes = sorted({name for profile in profiles for name in workflow.PROFILES[profile]})
        self.assertEqual(selectors, [f"-only-testing:FruitTreeScannerTests/{name}" for name in expected_classes])
        self.assertEqual(len(selectors), len(set(selectors)))
        self.assertIn("platform=iOS Simulator,id=test-simulator", command)

    def test_full_is_unfiltered_and_includes_release_build(self):
        plan = dict(workflow.command_plan(["fusion", "full", "storage"], Path("/tmp/evidence"), "sim"))
        self.assertIn("tests", plan)
        self.assertFalse(any(arg.startswith("-only-testing:") for arg in plan["tests"]))
        self.assertEqual(plan["tests"][plan["tests"].index("-configuration") + 1], "Debug")
        release = plan["release-build"]
        self.assertEqual(release[release.index("-configuration") + 1], "Release")
        self.assertIn("generic/platform=iOS Simulator", release)
        self.assertEqual(release[-1], "build")

    def test_preflight_contains_only_read_only_diff_checks(self):
        self.assertEqual(workflow.command_plan(["preflight"], Path("/tmp/evidence"), "sim"), [
            ("diff-check", ["git", "diff", "--check"]),
            ("staged-diff-check", ["git", "diff", "--cached", "--check"]),
        ])

    def test_xctest_profiles_wait_for_the_selected_simulator_before_tests(self):
        for profiles in (["fusion"], ["storage"], ["lifecycle"], ["ui"], ["full"],
                         ["quick", "storage"]):
            with self.subTest(profiles=profiles):
                plan = workflow.command_plan(profiles, Path("/tmp/evidence"), "selected-simulator")
                names = [name for name, _ in plan]
                self.assertIn("simulator-bootstatus", names)
                self.assertEqual(names.count("simulator-bootstatus"), 1)
                self.assertLess(names.index("simulator-bootstatus"), names.index("tests"))
                self.assertEqual(dict(plan)["simulator-bootstatus"], [
                    "xcrun", "simctl", "bootstatus", "selected-simulator", "-b",
                ])

    def test_compile_only_profiles_do_not_boot_a_simulator(self):
        for profiles in (["quick"], ["preflight", "quick"]):
            with self.subTest(profiles=profiles):
                plan = workflow.command_plan(profiles, Path("/tmp/evidence"), "sim")
                self.assertFalse(any(command[:2] == ["xcrun", "simctl"] for _, command in plan))


class XCTestSummaryTests(unittest.TestCase):
    def test_executed_passing_summary_is_accepted(self):
        workflow.validate_summary(passing_summary())

    def test_swiftui_view_update_publication_warning_is_rejected(self):
        summary = passing_summary()
        summary["runtimeWarnings"] = [{
            "issueType": "Runtime Warning",
            "message": "Publishing changes from within view updates is not allowed, this will cause undefined behavior.",
        }]
        with self.assertRaisesRegex(workflow.GateFailure, "Publishing changes"):
            workflow.validate_summary(summary)

    def test_other_runtime_warning_is_retained_for_review(self):
        summary = passing_summary()
        summary["runtimeWarnings"] = [{
            "issueType": "Runtime Warning", "message": "Thread running at User-initiated quality-of-service class waiting on a lower QoS thread.",
        }]
        original = json.loads(json.dumps(summary))
        workflow.validate_summary(summary)
        self.assertEqual(summary, original)

    def test_malformed_runtime_warning_evidence_is_rejected(self):
        for warnings in (None, {}, [None], [{}], [{"message": 12}]):
            with self.subTest(warnings=warnings):
                summary = passing_summary()
                summary["runtimeWarnings"] = warnings
                with self.assertRaisesRegex(workflow.GateFailure, "runtime warnings"):
                    workflow.validate_summary(summary)

    def test_zero_tests_are_rejected(self):
        with self.assertRaises(workflow.GateFailure):
            workflow.validate_summary(passing_summary(0))

    def test_skipped_failed_expected_failure_or_inconsistent_counts_are_rejected(self):
        for field in ("skippedTests", "failedTests", "expectedFailures", "totalTestCount"):
            with self.subTest(field=field):
                summary = passing_summary()
                summary[field] += 1
                with self.assertRaises(workflow.GateFailure):
                    workflow.validate_summary(summary)
        summary = passing_summary()
        summary["result"] = "Failed"
        with self.assertRaises(workflow.GateFailure):
            workflow.validate_summary(summary)

    def test_invalid_or_missing_counts_are_rejected(self):
        invalid = [None, [], {}, {"result": "Passed"}]
        for field in ("totalTestCount", "passedTests", "failedTests", "skippedTests", "expectedFailures"):
            for value in (None, True, -1, 1.0, "0"):
                summary = passing_summary()
                summary[field] = value
                invalid.append(summary)
            summary = passing_summary()
            del summary[field]
            invalid.append(summary)
        for summary in invalid:
            with self.subTest(summary=summary), self.assertRaises(workflow.GateFailure):
                workflow.validate_summary(summary)


class XCTestTreeTests(unittest.TestCase):
    def setUp(self):
        self.expected = {"FusionValidatorTests", "DetectionDeduplicatorTests"}

    def test_valid_tree_records_each_selected_class(self):
        self.assertEqual(workflow.validate_test_tree(passing_tree(self.expected), self.expected),
                         sorted(self.expected))

    def test_one_omitted_selected_class_is_rejected_while_other_classes_pass(self):
        tree = passing_tree({"FusionValidatorTests"})
        with self.assertRaisesRegex(workflow.GateFailure, "DetectionDeduplicatorTests"):
            workflow.validate_test_tree(tree, self.expected)

    def test_same_classes_in_wrong_bundle_are_rejected(self):
        with self.assertRaises(workflow.GateFailure):
            workflow.validate_test_tree(passing_tree(self.expected, bundle="OtherTests"), self.expected)

    def test_suite_result_without_passing_test_case_does_not_count(self):
        for descendants in ([], [{"nodeType": "Test Case", "name": "testEvidence", "result": "Skipped"}],
                            [{"nodeType": "Test Case", "name": "testEvidence", "result": "Failed"}],
                            [{"nodeType": "Test Suite", "name": "EmptyNestedSuite", "result": "Passed"}]):
            with self.subTest(descendants=descendants):
                tree = passing_tree(self.expected)
                suite = tree["testNodes"][0]["children"][0]
                suite.update(result="Passed", children=descendants)
                with self.assertRaises(workflow.GateFailure):
                    workflow.validate_test_tree(tree, self.expected)

    def test_malformed_tree_is_rejected(self):
        invalid = [None, [], {}, {"testNodes": {}}, {"testNodes": [None]},
                   {"testNodes": [{"nodeType": "Unit test bundle", "name": "FruitTreeScannerTests",
                                   "children": {}}]}]
        for name in (None, 12, [], {}):
            tree = passing_tree(self.expected)
            tree["testNodes"][0]["children"][0]["name"] = name
            invalid.append(tree)
        for tree in invalid:
            with self.subTest(tree=tree), self.assertRaises(workflow.GateFailure):
                workflow.validate_test_tree(tree, self.expected)


class WorkflowExecutionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="fruit-workflow-regression-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.git_env = dict(os.environ)
        self.repo = self.root / "checkout"
        self.repo.mkdir()
        self.output_root = self.root / "evidence"
        self.output_root.mkdir()
        self.developer_dir = self.root / "fake-xcode"
        self.developer_dir.mkdir()
        self.source = self.repo / "scan.swift"
        self.source.write_text("// tracked scan source\n")
        tests = self.repo / "FruitTreeScannerTests"
        tests.mkdir()
        classes = sorted({name for names in workflow.PROFILES.values() for name in names})
        (tests / "FixtureTests.swift").write_text("\n".join(
            f"class {name}: XCTestCase {{}}" for name in classes
        ) + "\n")
        self.git("init", "--quiet")
        self.git("add", ".")
        self.git("-c", "user.name=Workflow Test", "-c", "user.email=workflow@example.invalid",
                 "commit", "--quiet", "-m", "fixture")
        self.addCleanup(mock.patch.stopall)
        mock.patch.object(workflow, "REPO", self.repo).start()
        mock.patch.dict(os.environ, {"DEVELOPER_DIR": str(self.developer_dir)}).start()

    def git(self, *arguments):
        return REAL_SUBPROCESS_RUN(["git", *arguments], cwd=self.repo, env=self.git_env,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)

    def files(self):
        """Capture file content and paths, including Git, without changing the fixture."""
        return {str(path.relative_to(self.root)): hashlib.sha256(path.read_bytes()).hexdigest()
                for path in self.root.rglob("*") if path.is_file() and not path.is_symlink()}

    def execute(self, profiles=("fusion",), *, summary_bytes=None, tree_bytes=None, fail_command=None,
                exit_code=65, on_test=None, summary_exit=0, tests_exit=0,
                runtime_evidence_exit=0):
        expected = workflow.verify_selectors(profiles)
        if summary_bytes is None:
            summary_bytes = json.dumps(passing_summary(len(expected))).encode()
        if tree_bytes is None:
            tree_bytes = json.dumps(passing_tree(expected)).encode()
        commands = []

        def fake_run(command, **kwargs):
            commands.append(command)
            if command[0] == "git":
                if command == fail_command:
                    return subprocess.CompletedProcess(command, exit_code)
                # macOS's Git shim consults DEVELOPER_DIR; use the real environment
                # for Git while all Xcode commands remain mocked.
                kwargs["env"] = self.git_env
                return REAL_SUBPROCESS_RUN(command, **kwargs)
            is_result = command[:4] == ["xcrun", "xcresulttool", "get", "test-results"]
            if is_result:
                kwargs["stdout"].write(summary_bytes if command[4] == "summary" else tree_bytes)
                return subprocess.CompletedProcess(command, summary_exit if command[4] == "summary" else 0)
            if command[0] == "xcodebuild" and "test" in command:
                kwargs["stdout"].write(b"** TEST SUCCEEDED **\n")
                Path(command[command.index("-resultBundlePath") + 1]).mkdir()
                if on_test:
                    on_test()
                return subprocess.CompletedProcess(command, tests_exit)
            if len(command) > 1 and Path(command[1]).name == "inspect_runtime_warnings.py":
                kwargs["stdout"].write(json.dumps({
                    "schema_version": 1, "warning_count": 1, "raw_frame_count": 41,
                    "warnings_without_frames": 0,
                }).encode())
                return subprocess.CompletedProcess(command, runtime_evidence_exit)
            return subprocess.CompletedProcess(command, exit_code if command == fail_command else 0)

        with mock.patch.object(workflow.subprocess, "run", side_effect=fake_run), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            result = workflow.main([*profiles, "--output-root", str(self.output_root)])
        reports = list(self.output_root.glob("fruit-code-improvement-*/report.json"))
        self.assertEqual(len(reports), 1)
        return result, json.loads(reports[0].read_text()), commands

    def test_nonzero_command_exit_is_preserved_in_report(self):
        result, report, commands = self.execute(
            profiles=("preflight",), fail_command=["git", "diff", "--check"], exit_code=65,
        )
        self.assertEqual(result, 65)
        self.assertEqual(report["exit_code"], 65)
        self.assertEqual(report["validation_status"], "failed")
        self.assertEqual(report["steps"][0]["exit_code"], 65)
        self.assertNotIn(["git", "diff", "--cached", "--check"], commands)

    def test_high_command_exit_remains_in_step_evidence(self):
        result, report, _ = self.execute(
            profiles=("preflight",), fail_command=["git", "diff", "--check"], exit_code=137,
        )
        self.assertNotEqual(result, 0)
        self.assertEqual(report["steps"][0]["exit_code"], 137)
        self.assertIn("137", report["error"])

    def test_failed_boot_readiness_preserves_exit_and_stops_tests_and_release(self):
        simulator = os.environ.get("FTS_SIMULATOR_ID", workflow.DEFAULT_SIMULATOR)
        boot = ["xcrun", "simctl", "bootstatus", simulator, "-b"]
        result, report, commands = self.execute(profiles=("full",), fail_command=boot, exit_code=73)
        self.assertEqual(result, 73)
        self.assertEqual(report["validation_status"], "failed")
        self.assertEqual(report["steps"][-1]["name"], "simulator-bootstatus")
        self.assertEqual(report["steps"][-1]["exit_code"], 73)
        self.assertIn(boot, commands)
        self.assertFalse(any(command[0] == "xcodebuild" and "test" in command for command in commands))
        self.assertFalse(any("Release" in command for command in commands))
        self.assertNotIn("test_summary", report)
        self.assertEqual(report["baseline"], report["final"])

    def test_complete_passing_tests_are_recorded_with_review_still_required(self):
        result, report, _ = self.execute()
        self.assertEqual(result, 0)
        self.assertEqual(report["validation_status"], "passed")
        expected = workflow.verify_selectors(["fusion"])
        self.assertEqual(report["test_summary"], passing_summary(len(expected)))
        self.assertEqual(report["executed_test_classes"], sorted(expected))
        self.assertTrue(report["human_review_required"])
        self.assertEqual(report["device_acceptance"], "not_run")
        self.assertEqual(report["baseline"], report["final"])

    def test_qos_warnings_require_raw_stack_evidence_before_release(self):
        summary = passing_summary(len(workflow.verify_selectors(["full"])))
        summary["runtimeWarnings"] = [{"message": "QoS waiting on a lower priority thread"}]
        result, report, commands = self.execute(profiles=("full",), summary_bytes=json.dumps(summary).encode())
        self.assertEqual(result, 0)
        self.assertEqual(report["runtime_warning_evidence"]["raw_frame_count"], 41)
        self.assertEqual(report["runtime_warning_evidence"]["warning_count"], 1)
        names = [step["name"] for step in report["steps"]]
        self.assertLess(names.index("runtime-warning-evidence"), names.index("release-build"))
        self.assertTrue(any(len(cmd) > 1 and Path(cmd[1]).name == "inspect_runtime_warnings.py" for cmd in commands))

    def test_unreadable_runtime_stack_stops_release_and_preserves_test_failure(self):
        summary = passing_summary(len(workflow.verify_selectors(["full"])))
        summary["runtimeWarnings"] = [{"message": "QoS waiting on a lower priority thread"}]
        for test_exit in (0, 65):
            with self.subTest(test_exit=test_exit):
                # Each execution has its own output and fixture, as in a real run.
                self.output_root = self.root / f"runtime-evidence-{test_exit}"
                self.output_root.mkdir()
                result, report, commands = self.execute(profiles=("full",),
                    summary_bytes=json.dumps(summary).encode(), tests_exit=test_exit, runtime_evidence_exit=2)
                self.assertEqual(result, test_exit or 2)
                self.assertEqual(report["validation_status"], "failed")
                self.assertFalse(any("Release" in cmd for cmd in commands))
                self.assertEqual(next(s for s in report["steps"] if s["name"] == "runtime-warning-evidence")["exit_code"], 2)
                if test_exit:
                    self.assertIn("runtime-warning-evidence", report["test_evidence_error"])

    def test_success_log_without_result_summary_cannot_pass(self):
        result, report, _ = self.execute(summary_bytes=b"")
        self.assertNotEqual(result, 0)
        self.assertEqual(report["validation_status"], "failed")
        self.assertIn("Cannot read XCTest summary", report["error"])
        self.assertNotIn("test_summary", report)

    def test_malformed_result_summary_cannot_pass(self):
        result, report, _ = self.execute(summary_bytes=b"{\"result\":")
        self.assertNotEqual(result, 0)
        self.assertEqual(report["validation_status"], "failed")
        self.assertIn("Cannot read XCTest summary", report["error"])

    def test_failed_summary_tool_exit_cannot_pass_even_with_valid_counts(self):
        result, report, _ = self.execute(summary_exit=70)
        self.assertEqual(result, 70)
        self.assertEqual(report["validation_status"], "failed")
        summary_step = next(step for step in report["steps"] if step["name"] == "test-summary")
        self.assertEqual(summary_step["exit_code"], 70)
        self.assertNotIn("test_summary", report)

    def test_skipped_summary_fails_the_complete_run(self):
        summary = passing_summary()
        summary.update(totalTestCount=7, skippedTests=1)
        result, report, _ = self.execute(summary_bytes=json.dumps(summary).encode())
        self.assertNotEqual(result, 0)
        self.assertEqual(report["validation_status"], "failed")
        self.assertEqual(report["test_summary"]["skippedTests"], 1)

    def test_swiftui_view_update_warning_fails_run_and_preserves_evidence(self):
        summary = passing_summary()
        summary["runtimeWarnings"] = [{
            "issueType": "Runtime Warning",
            "message": "Publishing changes from within view updates is not allowed, this will cause undefined behavior.",
        }]
        result, report, _ = self.execute(summary_bytes=json.dumps(summary).encode())
        self.assertEqual(result, 1)
        self.assertEqual(report["validation_status"], "failed")
        self.assertEqual(report["test_summary"], summary)
        self.assertIn("Publishing changes", report["error"])

    def test_passing_summary_with_omitted_selected_class_cannot_pass(self):
        expected = workflow.verify_selectors(["fusion"])
        omitted = sorted(expected)[0]
        result, report, _ = self.execute(tree_bytes=json.dumps(passing_tree(expected - {omitted})).encode())
        self.assertNotEqual(result, 0)
        self.assertEqual(report["validation_status"], "failed")
        self.assertIn(omitted, report["error"])
        self.assertNotIn("executed_test_classes", report)

    def test_malformed_test_tree_cannot_pass(self):
        result, report, _ = self.execute(tree_bytes=b"not JSON")
        self.assertNotEqual(result, 0)
        self.assertIn("Cannot read XCTest test tree", report["error"])

    def test_full_and_ui_require_every_declared_class(self):
        extra = self.repo / "FruitTreeScannerTests" / "Nested" / "AdditionalTests.swift"
        extra.parent.mkdir()
        extra.write_text("class AdditionalCoverageTests: XCTestCase {}\n")
        for profiles in (["full"], ["ui"], ["fusion", "full"]):
            with self.subTest(profiles=profiles):
                expected = workflow.verify_selectors(profiles)
                self.assertIn("AdditionalCoverageTests", expected)
                self.assertEqual(expected, workflow.declared_test_classes())

    def test_failure_evidence_error_preserves_original_xcode_exit(self):
        result, report, _ = self.execute(tests_exit=65, summary_exit=70)
        self.assertEqual(result, 65)
        self.assertEqual(report["exit_code"], 65)
        self.assertIn("tests failed (exit 65)", report["error"])
        self.assertIn("test-summary failed (exit 70)", report["test_evidence_error"])
        self.assertEqual(next(step for step in report["steps"] if step["name"] == "tests")["exit_code"], 65)

    def test_passing_failure_evidence_does_not_override_failed_xcode_exit(self):
        result, report, _ = self.execute(tests_exit=65)
        self.assertEqual(result, 65)
        self.assertEqual(report["validation_status"], "failed")
        self.assertEqual(report["executed_test_classes"], sorted(workflow.verify_selectors(["fusion"])))

    def test_tracked_source_edit_invalidates_successful_tests(self):
        result, report, _ = self.execute(on_test=lambda: self.source.write_text("// changed scan source\n"))
        self.assertEqual(result, 1)
        self.assertEqual(report["validation_status"], "failed")
        self.assertTrue(report["workspace_changed_during_validation"])
        self.assertIn("Workspace changed", report["error"])
        self.assertEqual(report["test_summary"], passing_summary(len(workflow.verify_selectors(["fusion"]))))

    def test_untracked_source_edit_is_detected_even_when_git_status_matches(self):
        draft = self.repo / "draft.swift"
        draft.write_text("// first draft\n")
        result, report, _ = self.execute(on_test=lambda: draft.write_text("// revised draft\n"))
        self.assertEqual(result, 1)
        self.assertTrue(report["workspace_changed_during_validation"])
        self.assertEqual(report["baseline"]["status.txt"], report["final"]["status.txt"])
        self.assertNotEqual(report["baseline"]["changed_file_sha256"]["draft.swift"],
                            report["final"]["changed_file_sha256"]["draft.swift"])

    def test_dry_run_executes_nothing_and_changes_no_files(self):
        before = self.files()
        with mock.patch.object(workflow.subprocess, "run") as command, \
                mock.patch.object(workflow.tempfile, "mkdtemp") as create, \
                contextlib.redirect_stdout(io.StringIO()) as output:
            result = workflow.main(["fusion", "storage", "--dry-run", "--output-root", str(self.output_root)])
        self.assertEqual(result, 0)
        command.assert_not_called()
        create.assert_not_called()
        self.assertEqual(self.files(), before)
        self.assertEqual(json.loads(output.getvalue())["profiles"], ["fusion", "storage"])

    def test_repository_and_symlink_output_roots_are_rejected_before_mutation(self):
        nested = self.repo / "evidence"
        nested.mkdir()
        link = self.root / "checkout-link"
        link.symlink_to(nested, target_is_directory=True)
        before = self.files()
        for output_root in (self.repo, nested, link):
            with self.subTest(output_root=output_root), \
                    mock.patch.object(workflow.subprocess, "run") as command, \
                    mock.patch.object(workflow.tempfile, "mkdtemp") as create, \
                    contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
                workflow.main(["--output-root", str(output_root)])
            self.assertEqual(error.exception.code, 2)
            command.assert_not_called()
            create.assert_not_called()
        self.assertEqual(self.files(), before)


if __name__ == "__main__":
    unittest.main()
