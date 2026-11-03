#!/usr/bin/env python3
"""XCTest 门禁的回归矩阵（tools/xctest_gate.py）。

目的：旧门禁在下面这些输入上会放行，现在必须一律拒绝。
每一类都必须有「红」——即把门禁换成旧行为时这些用例会失败。

Run with PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/tests
不需要 Xcode、模拟器或 App 代码。
"""

import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


sys.dont_write_bytecode = True
MODULE_PATH = Path(__file__).resolve().parents[1] / "xctest_gate.py"
SPEC = importlib.util.spec_from_file_location("xctest_gate", MODULE_PATH)
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)

CLASS = "ArchiveGateTests"


def summary(**overrides):
    payload = {
        "result": "Passed", "totalTestCount": 1, "passedTests": 1,
        "failedTests": 0, "skippedTests": 0, "expectedFailures": 0,
        "runtimeWarnings": [],
    }
    payload.update(overrides)
    return payload


def tree(classes=(CLASS,), bundle="FruitTreeScannerTests", case_result="Passed"):
    return {"testNodes": [{
        "nodeType": "Unit test bundle", "name": bundle, "children": [{
            "nodeType": "Test Suite", "name": f"FruitTreeScannerTests.{name}",
            "children": [{"nodeType": "Test Case", "name": "testEvidence", "result": case_result}],
        } for name in classes]
    }]}


class SummaryGateTests(unittest.TestCase):
    """摘要判定：缺字段、类型错、计数不自洽、警告不可解析，一律失败。"""

    def assertRejected(self, payload, fragment=None):
        with self.assertRaises(gate.GateFailure) as caught:
            gate.validate_summary(payload)
        if fragment:
            self.assertIn(fragment, str(caught.exception))

    def test_valid_summary_passes(self):
        gate.validate_summary(summary())          # 不抛 = 通过

    def test_failed_tests_are_rejected(self):
        self.assertRejected(summary(failedTests=1, passedTests=0, totalTestCount=1), "gate incomplete")

    def test_skipped_tests_are_rejected(self):
        self.assertRejected(summary(skippedTests=1, passedTests=0, totalTestCount=1), "gate incomplete")

    def test_expected_failures_are_rejected(self):
        self.assertRejected(summary(expectedFailures=1, passedTests=0, totalTestCount=1), "gate incomplete")

    def test_empty_run_is_rejected(self):
        self.assertRejected(summary(totalTestCount=0, passedTests=0), "gate incomplete")

    def test_missing_count_fields_are_rejected(self):
        payload = summary()
        del payload["failedTests"]
        self.assertRejected(payload, "missing or invalid count")

    def test_boolean_counts_are_rejected(self):
        self.assertRejected(summary(passedTests=True, totalTestCount=True), "missing or invalid count")

    def test_string_counts_are_rejected(self):
        self.assertRejected(summary(totalTestCount="1"), "missing or invalid count")

    def test_negative_counts_are_rejected(self):
        self.assertRejected(summary(failedTests=-1), "missing or invalid count")

    def test_result_must_be_passed(self):
        self.assertRejected(summary(result="Failed"), "gate incomplete")

    def test_counts_must_reconcile(self):
        self.assertRejected(summary(totalTestCount=2, passedTests=1), "gate incomplete")

    def test_unparseable_warning_payload_is_rejected(self):
        self.assertRejected(summary(runtimeWarnings={"message": "x"}), "cannot inspect warning evidence")

    def test_warning_without_message_is_rejected(self):
        self.assertRejected(summary(runtimeWarnings=[{"issueType": "Runtime Warning"}]), "cannot inspect warning evidence")

    def test_publishing_changes_warning_blocks(self):
        self.assertRejected(
            summary(runtimeWarnings=[{"message": "Publishing changes from within view updates is not allowed, "
                                                  "this will cause undefined behavior."}]),
            "Unsafe SwiftUI runtime warning")

    def test_qos_warning_is_kept_but_not_blocking(self):
        payload = summary(runtimeWarnings=[{"message": "[Internal] Thread running at User-interactive "
                                                     "quality-of-service class waiting on a lower QoS thread"}])
        gate.validate_summary(payload)           # 非阻塞：保留但不拦

    def test_multiple_test_runs_are_rejected(self):
        self.assertRejected({"testRuns": [summary(), summary()]}, "multiple test runs")

    def test_empty_test_runs_are_rejected(self):
        self.assertRejected({"testRuns": []}, "multiple test runs")

    def test_missing_runtime_warnings_key_is_rejected(self):
        payload = summary()
        del payload["runtimeWarnings"]
        self.assertRejected(payload, "cannot inspect warning evidence")

    def test_tree_with_blocking_warning_node_is_rejected(self):
        blocked = {"testNodes": [{
            "nodeType": "Unit test bundle", "name": "FruitTreeScannerTests", "children": [
                {"nodeType": "Runtime Warning",
                 "name": "Publishing changes from within view updates is not allowed, "
                         "this will cause undefined behavior."},
                {"nodeType": "Test Suite", "name": f"FruitTreeScannerTests.{CLASS}",
                 "children": [{"nodeType": "Test Case", "name": "t", "result": "Passed"}]}]}]}
        with self.assertRaises(gate.GateFailure) as caught:
            gate.validate_test_tree(blocked, {CLASS})
        self.assertIn("Unsafe SwiftUI runtime warning", str(caught.exception))

    def test_empty_expected_class_set_is_rejected(self):
        with self.assertRaises(gate.GateFailure):
            gate.validate_test_tree(tree(), set())


class TestTreeGateTests(unittest.TestCase):
    """结果树判定：空树、错 bundle、缺类、畸形节点一律失败。"""

    def test_matching_class_passes(self):
        executed, passed_cases = gate.validate_test_tree(tree(), {CLASS})
        self.assertEqual(executed, [CLASS])
        self.assertEqual(passed_cases, 1)

    def test_empty_test_nodes_are_rejected(self):
        with self.assertRaises(gate.GateFailure):
            gate.validate_test_tree({"testNodes": []}, {CLASS})

    def test_missing_test_nodes_key_is_rejected(self):
        with self.assertRaises(gate.GateFailure):
            gate.validate_test_tree({}, {CLASS})

    def test_wrong_bundle_is_rejected(self):
        with self.assertRaises(gate.GateFailure) as caught:
            gate.validate_test_tree(tree(bundle="OtherTests"), {CLASS})
        self.assertIn("did not execute passing cases", str(caught.exception))

    def test_missing_declared_class_is_rejected(self):
        with self.assertRaises(gate.GateFailure) as caught:
            gate.validate_test_tree(tree(), {CLASS, "NeverDeclaredTests"})
        self.assertIn("NeverDeclaredTests", str(caught.exception))

    def test_failed_case_does_not_count_as_executed(self):
        with self.assertRaises(gate.GateFailure):
            gate.validate_test_tree(tree(case_result="Failed"), {CLASS})

    def test_malformed_node_is_rejected(self):
        broken = {"testNodes": [{"nodeType": "Test Case", "name": 7, "result": "Passed"}]}
        with self.assertRaises(gate.GateFailure):
            gate.validate_test_tree(broken, {CLASS})

    def test_malformed_children_are_rejected(self):
        broken = {"testNodes": [{"nodeType": "Test Suite", "name": "X", "children": "not-a-list"}]}
        with self.assertRaises(gate.GateFailure):
            gate.validate_test_tree(broken, {CLASS})


class CommandLineGateTests(unittest.TestCase):
    """命令行入口：坏 JSON、坏 bundle、上游 xcresulttool 失败都要非零退出。"""

    def run_gate(self, args, env=None):
        environment = dict(os.environ)
        environment.update(env or {})
        return subprocess.run(
            [sys.executable, str(MODULE_PATH), *args],
            capture_output=True, text=True, env=environment,
        )

    def test_missing_bundle_exits_non_zero(self):
        result = self.run_gate(["/nonexistent/tests.xcresult"])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not found", result.stderr)

    def test_upstream_xcresulttool_failure_propagates(self):
        with tempfile.TemporaryDirectory() as directory:
            stub = Path(directory) / "xcrun"
            stub.write_text("#!/bin/sh\nexit 70\n")
            stub.chmod(0o755)
            bundle = Path(directory) / "tests.xcresult"
            bundle.mkdir()
            result = self.run_gate([str(bundle)], env={"PATH": directory + os.pathsep + os.environ["PATH"]})
            self.assertNotEqual(result.returncode, 0)

    def test_valid_fixture_bundle_passes(self):
        with tempfile.TemporaryDirectory() as directory:
            stub = Path(directory) / "xcrun"
            stub.write_text(
                "#!/bin/sh\n"
                "case \"$*\" in\n"
                "  *\"test-results summary\"*) cat \"$SUMMARY_JSON\" ;;\n"
                "  *\"test-results tests\"*) cat \"$TREE_JSON\" ;;\n"
                "  *) exit 0 ;;\n"
                "esac\n"
            )
            stub.chmod(0o755)
            summary_json = Path(directory) / "summary.json"
            summary_json.write_text(json.dumps(summary()))
            tree_json = Path(directory) / "tree.json"
            tree_json.write_text(json.dumps(tree()))
            bundle = Path(directory) / "tests.xcresult"
            bundle.mkdir()
            repo = Path(directory) / "repo"
            (repo / "FruitTreeScannerTests").mkdir(parents=True)
            (repo / "FruitTreeScannerTests" / "Sample.swift").write_text(
                "final class ArchiveGateTests: XCTestCase {}\n"
            )
            result = self.run_gate(
                [str(bundle), "--repo", str(repo)],
                env={
                    "PATH": directory + os.pathsep + os.environ["PATH"],
                    "SUMMARY_JSON": str(summary_json),
                    "TREE_JSON": str(tree_json),
                },
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("XCTest gate passed", result.stdout)

    def test_blocking_warning_bundle_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            stub = Path(directory) / "xcrun"
            stub.write_text(
                "#!/bin/sh\n"
                "case \"$*\" in\n"
                "  *\"test-results summary\"*) cat \"$SUMMARY_JSON\" ;;\n"
                "  *\"test-results tests\"*) cat \"$TREE_JSON\" ;;\n"
                "  *) exit 0 ;;\n"
                "esac\n"
            )
            stub.chmod(0o755)
            summary_json = Path(directory) / "summary.json"
            summary_json.write_text(json.dumps(summary(runtimeWarnings=[{
                "message": "Publishing changes from within view updates is not allowed, "
                           "this will cause undefined behavior."}])))
            tree_json = Path(directory) / "tree.json"
            tree_json.write_text(json.dumps(tree()))
            bundle = Path(directory) / "tests.xcresult"
            bundle.mkdir()
            repo = Path(directory) / "repo"
            (repo / "FruitTreeScannerTests").mkdir(parents=True)
            (repo / "FruitTreeScannerTests" / "Sample.swift").write_text(
                "final class ArchiveGateTests: XCTestCase {}\n"
            )
            result = self.run_gate(
                [str(bundle), "--repo", str(repo)],
                env={
                    "PATH": directory + os.pathsep + os.environ["PATH"],
                    "SUMMARY_JSON": str(summary_json),
                    "TREE_JSON": str(tree_json),
                },
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Unsafe SwiftUI runtime warning", result.stderr)

    def test_bad_json_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            stub = Path(directory) / "xcrun"
            stub.write_text("#!/bin/sh\necho 'not json'\n")
            stub.chmod(0o755)
            bundle = Path(directory) / "tests.xcresult"
            bundle.mkdir()
            result = self.run_gate([str(bundle)], env={"PATH": directory + os.pathsep + os.environ["PATH"]})
            self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
