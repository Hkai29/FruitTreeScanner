import importlib.util
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[2]
WORKFLOW = REPOSITORY / ".github" / "workflows" / "build-ipa.yml"

spec = importlib.util.spec_from_file_location(
    "ci_test_registration_gate", REPOSITORY / "tools" / "check_ci_test_registration_gate.py")
ci_gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci_gate)


class CIWiringTests(unittest.TestCase):
    """CI must really run the registration gate, and must keep running it.

    Every negative case mutates a **copy of the real workflow**, so the
    checker is exercised against the shape the repository actually ships.
    """

    def setUp(self):
        self.source = WORKFLOW.read_text()

    def mutated_workflow(self, old, new, count=1):
        self.assertIn(old, self.source, "the real workflow must contain the text this case mutates")
        return self.source.replace(old, new, count)

    def check_text(self, text):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "build-ipa.yml"
            path.write_text(text)
            return ci_gate.check(path)

    def assert_rejected(self, text, expected_fragment):
        ok, findings = self.check_text(text)
        self.assertFalse(ok, "the checker must reject this workflow: %s" % expected_fragment)
        self.assertTrue(any(expected_fragment in finding for finding in findings),
                        "expected a finding about %r, got %r" % (expected_fragment, findings))

    def test_the_real_workflow_runs_the_registration_gate(self):
        ok, findings = self.check_text(self.source)
        self.assertTrue(ok, findings)

    def test_both_events_trigger_on_the_ui_test_sources(self):
        for event in ("push", "pull_request"):
            self.assertIn("FruitTreeScannerUITests/**", self.source,
                          "the %r event must trigger on the UI test sources" % event)

    def test_a_ui_test_path_missing_from_push_is_rejected(self):
        mutated = self.mutated_workflow("      - 'FruitTreeScannerUITests/**'\n", "", 1)
        self.assert_rejected(mutated, "does not trigger on")

    def test_the_registration_script_missing_from_the_trigger_paths_is_rejected(self):
        mutated = self.mutated_workflow(
            "      - 'tools/check_test_target_registration.py'\n", "", 1)
        self.assert_rejected(mutated, "does not trigger on")

    def test_removing_the_registration_step_is_rejected(self):
        mutated = self.mutated_workflow(
            "      - name: UITest target registration gate\n"
            "        shell: bash\n"
            "        run: python3 tools/check_test_target_registration.py\n\n", "")
        self.assert_rejected(mutated, "no step runs")

    def test_removing_the_wiring_check_step_is_rejected(self):
        mutated = self.mutated_workflow(
            "      - name: CI registration gate wiring check\n"
            "        shell: bash\n"
            "        run: python3 tools/check_ci_test_registration_gate.py\n\n", "")
        self.assert_rejected(mutated, "wiring check must stay")

    def test_a_non_blocking_registration_step_is_rejected(self):
        mutated = self.mutated_workflow(
            "      - name: UITest target registration gate\n"
            "        shell: bash\n"
            "        run: python3 tools/check_test_target_registration.py\n",
            "      - name: UITest target registration gate\n"
            "        shell: bash\n"
            "        continue-on-error: true\n"
            "        run: python3 tools/check_test_target_registration.py\n")
        self.assert_rejected(mutated, "continue-on-error")

    def test_a_neutralised_registration_step_is_rejected(self):
        mutated = self.mutated_workflow(
            "      - name: UITest target registration gate\n"
            "        shell: bash\n",
            "      - name: UITest target registration gate\n"
            "        shell: bash\n"
            "        if: always()\n")
        self.assert_rejected(mutated, "neutralised")

    def test_a_registration_step_after_the_xctest_gate_is_rejected(self):
        step = ("      - name: UITest target registration gate\n"
                "        shell: bash\n"
                "        run: python3 tools/check_test_target_registration.py\n\n")
        self.assertIn(step, self.source)
        mutated = self.source.replace(step, "")
        mutated = mutated.replace(
            "      - name: XCTest gate\n"
            "        shell: bash\n"
            "        run: bash tools/ci_xctest_gate.sh\n",
            "      - name: XCTest gate\n"
            "        shell: bash\n"
            "        run: bash tools/ci_xctest_gate.sh\n\n" + step.rstrip("\n") + "\n")
        self.assert_rejected(mutated, "must fail early")

    def test_dropping_the_xctest_gate_is_rejected(self):
        mutated = self.mutated_workflow(
            "      - name: XCTest gate\n"
            "        shell: bash\n"
            "        run: bash tools/ci_xctest_gate.sh\n", "")
        self.assert_rejected(mutated, "XCTest gate")

    def test_widening_the_workflow_permissions_is_rejected(self):
        mutated = self.mutated_workflow("  contents: read\n", "  contents: write\n")
        self.assert_rejected(mutated, "permissions")

    def test_a_broadened_branch_filter_is_rejected(self):
        mutated = self.mutated_workflow("    branches: [ main ]", "    branches: [ main, develop ]")
        self.assert_rejected(mutated, "main branch only")

    def test_evidence_upload_cannot_be_removed_or_skip_failures(self):
        for replacement in ("if: success()", "if: failure()", "if: cancelled()"):
            self.assert_rejected(self.mutated_workflow("if: always()", replacement), "always()")
        self.assert_rejected(self.mutated_workflow("actions/upload-artifact@v7", "actions/cache@v4"),
                             "evidence upload")

    def test_evidence_upload_must_use_the_dedicated_output_and_keep_all_files(self):
        mutations = (
            ("path: ${{ runner.temp }}/FruitTreeScanner-ci-evidence/", "path: ${{ runner.temp }}/", "dedicated"),
            ("FTS_CI_EVIDENCE_DIR: ${{ runner.temp }}/FruitTreeScanner-ci-evidence",
             "FTS_CI_EVIDENCE_DIR: ${{ runner.temp }}/wrong-output", "output directory"),
            ("if-no-files-found: error", "if-no-files-found: ignore", "missing evidence"),
            ("include-hidden-files: true", "include-hidden-files: false", "complete result"),
            ("overwrite: false", "overwrite: true", "overwrite"),
            ("ios-evidence-${{ github.run_id }}-${{ github.run_attempt }}", "ios-evidence", "run identity"),
        )
        for old, new, finding in mutations:
            with self.subTest(finding=finding):
                self.assert_rejected(self.mutated_workflow(old, new), finding)

    def test_xctest_and_upload_cannot_be_made_nonblocking(self):
        for name in ("XCTest gate", "Retain CI evidence"):
            self.assert_rejected(self.mutated_workflow(
                "      - name: " + name + "\n",
                "      - name: " + name + "\n        continue-on-error: true\n"), "continue-on-error")

    def test_new_evidence_helper_triggers_both_events(self):
        self.assert_rejected(self.mutated_workflow("      - 'tools/ci_evidence.py'\n", "", 1),
                             "does not trigger on")


class RegistrationGateExecutionTests(unittest.TestCase):
    """The step CI runs must fail the job when a UI test file is unregistered."""

    def setUp(self):
        self.directory = Path(tempfile.mkdtemp(prefix="ci-registration-gate-"))
        self.addCleanup(shutil.rmtree, self.directory, ignore_errors=True)
        self.project = self.directory / "FruitTreeScanner.xcodeproj"
        self.project.mkdir(parents=True)
        self.sources = self.directory / "FruitTreeScannerUITests"
        self.sources.mkdir()

    def test_the_real_project_passes_the_step(self):
        result = subprocess.run(
            [sys.executable, str(REPOSITORY / "tools" / "check_test_target_registration.py")],
            cwd=REPOSITORY, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_dropping_a_file_from_the_sources_phase_fails_the_step(self):
        """A real project copy whose Sources phase lost a file must be rejected."""
        import json
        parsed = json.loads(subprocess.run(
            ["plutil", "-convert", "json", "-o", "-",
             str(REPOSITORY / "FruitTreeScanner.xcodeproj" / "project.pbxproj")],
            capture_output=True, text=True, check=True).stdout)
        objects = parsed["objects"]
        target = [key for key, value in objects.items()
                  if value.get("isa") == "PBXNativeTarget"
                  and value.get("name") == "FruitTreeScannerUITests"][0]
        phases = [objects[phase] for phase in objects[target]["buildPhases"]
                  if objects[phase].get("isa") == "PBXSourcesBuildPhase"]
        self.assertEqual(len(phases), 1)
        removed = phases[0]["files"][0]
        phases[0]["files"] = [item for item in phases[0]["files"] if item != removed]
        (self.project / "project.pbxproj").write_text(json.dumps(parsed))
        for source in (REPOSITORY / "FruitTreeScannerUITests").glob("*.swift"):
            shutil.copy2(source, self.sources / source.name)

        result = subprocess.run(
            [sys.executable, str(REPOSITORY / "tools" / "check_test_target_registration.py"),
             "--project", str(self.project / "project.pbxproj"),
             "--sources", str(self.sources)],
            cwd=REPOSITORY, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0,
                            "the CI step must fail when a UI test file is unregistered")
        self.assertIn("UNREGISTERED", result.stderr)


if __name__ == "__main__":
    unittest.main()
