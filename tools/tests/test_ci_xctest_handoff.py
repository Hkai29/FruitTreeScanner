"""A producer may defer strict validation only to the mandatory CI consumer."""
import json
from pathlib import Path
import unittest

import test_ci_ui_host_setup as host_fixtures


class XCTestHandoffTests(unittest.TestCase):
    def setUp(self):
        self.fixture = host_fixtures.CIUIHostSetupTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.environment = dict(GITHUB_ACTIONS="true", GITHUB_RUN_ID="1234", GITHUB_RUN_ATTEMPT="1",
            GITHUB_SHA="a" * 40, FTS_CI_XCTEST_MODE="handoff", FTS_CI_XCTEST_CONSUMER="verify",
            FTS_CI_HOST_APP_PATH=str(self.fixture.app), STUB_REQUIRE_SETUP="1")

    def execute(self, **overrides):
        environment = dict(self.environment, **overrides)
        return self.fixture.shell("ci_xctest_gate.sh", **environment)

    def report(self):
        return json.loads((self.fixture.run_path("tests") / "report.json").read_text())

    def test_producer_executes_full_tests_without_claiming_strict_validation(self):
        stub = self.fixture.bin / "xcrun"
        stub.write_text(stub.read_text().replace('"required": ["runtimeWarnings"]', '"required": []'))
        result = self.execute()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        report = self.report()
        self.assertEqual(report.get("xctest_mode"), "handoff")
        self.assertEqual(report.get("gate_consumer_job"), "verify")
        self.assertTrue(report.get("strict_gate_pending"))
        self.assertTrue(report["evidence_complete"])
        self.assertEqual(report["primary_exit"], 0)
        self.assertFalse(any(item["name"] == "xctest-gate" for item in report["commands"]))
        self.assertFalse(any("--schema" in item["argv"] for item in report["commands"]))
        tests = [item for item in report["commands"] if item["name"] == "xctest"]
        self.assertEqual(len(tests), 1)
        self.assertFalse(any(arg.startswith(("-skip-testing", "-only-testing")) for arg in tests[0]["argv"]))
        self.assertIn("strict validation is pending", result.stdout)

    def test_handoff_requires_ci_identity_and_the_required_consumer(self):
        for overrides in ({"GITHUB_ACTIONS": "false"}, {"GITHUB_SHA": ""},
                          {"GITHUB_RUN_ID": ""}, {"GITHUB_RUN_ATTEMPT": ""},
                          {"FTS_CI_XCTEST_CONSUMER": ""}, {"FTS_CI_XCTEST_CONSUMER": "optional"}):
            with self.subTest(overrides=overrides):
                self.fixture.trace.unlink(missing_ok=True)
                result = self.execute(**overrides)
                self.assertNotEqual(result.returncode, 0)
                self.fixture.assert_no_test_launch()

    def test_unknown_mode_is_not_a_gate_bypass(self):
        result = self.execute(FTS_CI_XCTEST_MODE="ignore")
        self.assertNotEqual(result.returncode, 0)
        self.fixture.assert_no_test_launch()

    def test_handoff_preserves_test_process_failure(self):
        stub = self.fixture.bin / "xcodebuild"
        stub.write_text(stub.read_text() + '\nif "test" in args: raise SystemExit(65)\n')
        result = self.execute()
        self.assertEqual(result.returncode, 65, result.stdout + result.stderr)
        self.assertEqual(self.report()["primary_exit"], 65)
        self.assertEqual(self.report()["final_exit"], 65)


if __name__ == "__main__":
    unittest.main()
