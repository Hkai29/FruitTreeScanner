import importlib.util
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[2]
WORKFLOW = REPOSITORY / ".github" / "workflows" / "build-ipa.yml"
XCTEST_STEP = ("      - name: XCTest gate\n"
               "        shell: bash\n"
               "        env:\n"
               "          FTS_CI_XCTEST_MODE: handoff\n"
               "          FTS_CI_XCTEST_CONSUMER: verify\n"
               "        run: bash tools/ci_xctest_gate.sh\n")

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

    def test_handoff_mode_requires_a_mandatory_consumer_job(self):
        producer = self.source.split("\n  verify:", 1)[0]
        if "FTS_CI_XCTEST_MODE: handoff" not in producer:
            producer = producer.replace(
                "      - name: XCTest gate\n        shell: bash\n",
                "      - name: XCTest gate\n        shell: bash\n"
                "        env:\n          FTS_CI_XCTEST_MODE: handoff\n"
                "          FTS_CI_XCTEST_CONSUMER: verify\n")
        self.assert_rejected(producer, "verification job")

    def test_strict_consumer_preserves_the_required_build_check_name(self):
        without_names = self.source.replace("    name: build\n", "")
        for name in ("", "    name: Unprotected verification\n"):
            with self.subTest(name=name):
                self.assert_rejected(without_names.replace("  verify:\n", "  verify:\n" + name),
                                     "strict required check")
        for replacement in ("", "    name: build\n"):
            with self.subTest(producer_name=replacement):
                self.assert_rejected(self.mutated_workflow("    name: Execute compatibility XCTest\n", replacement),
                                     "strict required check")

    def test_parser_preserves_job_ownership_needs_and_step_environment(self):
        parsed = ci_gate.parse_workflow(self.source)
        self.assertEqual(set(parsed["jobs"]), {"build", "verify"})
        self.assertEqual(parsed["jobs"]["build"]["name"], "Execute compatibility XCTest")
        self.assertEqual(parsed["jobs"]["verify"]["name"], "build")
        self.assertEqual(parsed["jobs"]["verify"]["job_id"], "verify")
        self.assertEqual(parsed["jobs"]["verify"]["needs"], ["build"])
        producer = next(step for step in parsed["jobs"]["build"]["steps"] if step["name"] == "XCTest gate")
        self.assertEqual(producer["env"], {"FTS_CI_XCTEST_MODE": "handoff", "FTS_CI_XCTEST_CONSUMER": "verify"})
        download = next(step for step in parsed["jobs"]["verify"]["steps"] if "download-artifact" in step["uses"])
        self.assertEqual(download["env"], {})
        self.assertEqual(download["with"]["digest-mismatch"], "error")
        self.assertTrue(all(step["job"] == name for name, job in parsed["jobs"].items() for step in job["steps"]))

    def test_broken_consumer_dependency_or_runner_is_rejected(self):
        for old, new, finding in (
            ("    needs: build\n", "", "needs the successful build"),
            ("    needs: build\n", "    needs: unrelated\n", "needs the successful build"),
            ("    runs-on: xcode-27\n", "    runs-on: macos-15\n", "standard xcode-27"),
            ("    runs-on: xcode-27\n", "    runs-on: xcode-27-xlarge\n", "standard xcode-27"),
            ("    runs-on: macos-15\n", "    runs-on: xcode-27\n", "compiler runner"),
        ):
            with self.subTest(new=new):
                self.assert_rejected(self.mutated_workflow(old, new), finding)
        ok, findings = self.check_text(self.mutated_workflow("    needs: build\n", "    needs: [ build ]\n"))
        self.assertTrue(ok, findings)

    def test_required_jobs_cannot_be_skipped_or_made_nonblocking(self):
        for job in ("build", "verify"):
            for option in ("    if: false\n", "    if: ${{ success() }}\n", "    continue-on-error: true\n"):
                with self.subTest(job=job, option=option):
                    self.assert_rejected(self.mutated_workflow("  " + job + ":\n", "  " + job + ":\n" + option),
                                         "job must be unconditional and hard-failing")

    def test_handoff_mode_and_consumer_are_scoped_to_the_xctest_step(self):
        for old, new in (("FTS_CI_XCTEST_MODE: handoff", "FTS_CI_XCTEST_MODE: strict"),
                         ("FTS_CI_XCTEST_CONSUMER: verify", "FTS_CI_XCTEST_CONSUMER: other"),
                         ("          FTS_CI_XCTEST_CONSUMER: verify\n", "")):
            with self.subTest(new=new):
                self.assert_rejected(self.mutated_workflow(old, new), "producer step env")
        outside = self.source.replace("          FTS_CI_XCTEST_MODE: handoff\n", "")
        outside = outside.replace("    runs-on: macos-15\n",
            "    runs-on: macos-15\n    env:\n      FTS_CI_XCTEST_MODE: handoff\n")
        self.assert_rejected(outside, "only in the producer step env")

    def test_required_verification_steps_cannot_be_skipped_or_softened(self):
        for name in ("Checkout tested source", "Download XCTest evidence", "Verify XCTest evidence"):
            for option in ("        if: false\n", "        if: ${{ success() }}\n", "        continue-on-error: true\n"):
                with self.subTest(name=name, option=option):
                    self.assert_rejected(self.mutated_workflow("      - name: " + name + "\n",
                        "      - name: " + name + "\n" + option),
                        "continue-on-error" if "continue-on-error" in option else "unconditional")

    def test_consumer_source_and_artifact_identity_cannot_be_redirected(self):
        self.assert_rejected(self.mutated_workflow("ref: ${{ github.sha }}", "ref: main"), "same github.sha")
        download = "        uses: actions/download-artifact@v8\n        with:\n"
        for extra in ("          run-id: 123\n", "          repository: other/repo\n",
                      "          github-token: ${{ github.token }}\n", "          pattern: '*'\n",
                      "          artifact-ids: '123'\n", "          merge-multiple: true\n"):
            with self.subTest(extra=extra):
                self.assert_rejected(self.mutated_workflow(download, download + extra), "same run/attempt")
        for old, new in (("digest-mismatch: error", "digest-mismatch: warn"),
                         ("          digest-mismatch: error\n", ""),
                         ("path: ${{ runner.temp }}/FruitTreeScanner-ci-input/", "path: ${{ runner.temp }}/"),
                         ("actions/download-artifact@v8", "actions/download-artifact@v4")):
            with self.subTest(new=new):
                self.assert_rejected(self.mutated_workflow(old, new), "download")
        producer, consumer = self.source.split("\n  verify:", 1)
        consumer = consumer.replace("ios-evidence-${{ github.run_id }}-${{ github.run_attempt }}", "ios-evidence-old")
        self.assert_rejected(producer + "\n  verify:" + consumer, "same run/attempt")

    def test_strict_consumer_cannot_be_removed_swallowed_or_repointed(self):
        command = ci_gate.VERIFICATION_COMMAND
        for new in ("true", command + " || true", command + " | cat",
                    command.replace("FruitTreeScanner-ci-input", "another-input")):
            with self.subTest(new=new):
                finding = "strict consumer" if new == "true" else "directly run"
                self.assert_rejected(self.mutated_workflow(command, new), finding)

    def test_verification_upload_is_required_and_preserves_failure_evidence(self):
        producer, consumer = self.source.split("\n  verify:", 1)
        for old, new in (("actions/upload-artifact@v7", "actions/cache@v4"),
                         ("if: always()", "if: success()"),
                         ("path: ${{ runner.temp }}/FruitTreeScanner-ci-verification/", "path: ${{ runner.temp }}/"),
                         ("overwrite: false", "overwrite: true"),
                         ("if-no-files-found: error", "if-no-files-found: ignore"),
                         ("include-hidden-files: true", "include-hidden-files: false"),
                         ("ios-verification-${{ github.run_id }}-${{ github.run_attempt }}", "ios-verification")):
            with self.subTest(new=new):
                self.assertIn(old, consumer)
                self.assert_rejected(producer + "\n  verify:" + consumer.replace(old, new, 1), "verification")

    def test_gate_cannot_be_moved_into_an_unrelated_job(self):
        mutated = self.source.replace(XCTEST_STEP, "") + "\n  unrelated:\n    runs-on: macos-15\n    steps:\n" + XCTEST_STEP
        self.assert_rejected(mutated, "XCTest gate")

    def test_job_permission_override_must_remain_read_only(self):
        for job in ("build", "verify"):
            self.assert_rejected(self.mutated_workflow("  " + job + ":\n",
                "  " + job + ":\n    permissions:\n      contents: write\n"), "permissions")

    def test_existing_build_gates_remain_unconditional_and_hard_failing(self):
        for name in ("CI registration gate wiring check", "Validate Domain dependencies", "Build for iOS Simulator"):
            for option in ("        if: false\n", "        continue-on-error: true\n"):
                with self.subTest(name=name, option=option):
                    self.assert_rejected(self.mutated_workflow("      - name: " + name + "\n",
                        "      - name: " + name + "\n" + option), "build gate")

    def test_verification_download_must_precede_the_consumer(self):
        download = ("      - name: Download XCTest evidence\n"
                    "        uses: actions/download-artifact@v8\n"
                    "        with:\n"
                    "          name: ios-evidence-${{ github.run_id }}-${{ github.run_attempt }}\n"
                    "          path: ${{ runner.temp }}/FruitTreeScanner-ci-input/\n"
                    "          digest-mismatch: error\n\n")
        self.assertIn(download, self.source)
        mutated = self.source.replace(download, "")
        mutated = mutated.replace("      - name: Retain XCTest verification\n",
                                  download + "      - name: Retain XCTest verification\n")
        self.assert_rejected(mutated, "verification order")

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
        self.assertIn(XCTEST_STEP, mutated)
        mutated = mutated.replace(XCTEST_STEP, XCTEST_STEP + "\n" + step)
        self.assert_rejected(mutated, "must fail early")

    def test_dropping_the_xctest_gate_is_rejected(self):
        mutated = self.mutated_workflow(XCTEST_STEP, "")
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
            ("FTS_CI_EVIDENCE_DIR=%s/FruitTreeScanner-ci-evidence",
             "FTS_CI_EVIDENCE_DIR=%s/wrong-output", "output directory"),
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

    def test_reader_and_ui_host_helpers_trigger_both_events(self):
        for name in ("ci_result_reader.py", "ci_ui_host_setup.py", "ci_verify_xctest_artifact.py"):
            line = "      - 'tools/" + name + "'\n"
            for occurrence in (0, 1):
                with self.subTest(name=name, occurrence=occurrence):
                    before, first, middle = self.source.partition(line)
                    self.assertEqual(first, line)
                    mutated = before + middle if occurrence == 0 else before + first + middle.replace(line, "", 1)
                    self.assert_rejected(mutated, "does not trigger on")

    def test_job_environment_rejects_runner_context_property_and_index_forms(self):
        job_env = "    env:\n      FTS_CI_EVIDENCE_DIR: ${{ runner.temp }}/FruitTreeScanner-ci-evidence\n"
        without = self.source.replace(job_env, "")
        base = without.replace("    steps:\n", job_env + "    steps:\n", 1)
        self.assert_rejected(base, "runner context is unavailable in job env")
        for value in ("${{ runner['temp'] }}", "${{ runner [ 'temp' ] }}", "${{ runner }}"):
            with self.subTest(value=value):
                self.assert_rejected(base.replace(job_env,
                    "    env:\n      BAD_CONTEXT: " + value + "\n"),
                    "runner context is unavailable in job env")
        for env in ("    env: { BAD_CONTEXT: \"${{ runner['temp'] }}\" }\n",
                    "    env:\n      BAD_CONTEXT: >-\n        ${{ runner.temp }}\n"):
            self.assert_rejected(without.replace("    steps:\n", env + "    steps:\n", 1),
                                 "runner context is unavailable in job env")

    def test_job_environment_can_contain_runner_as_a_string_literal(self):
        for expression in ("format('runner.temp')", "vars.runner", "needs . runner . outputs . value"):
            with self.subTest(expression=expression):
                text = self.source.replace("    steps:\n",
                    "    env:\n      LEGAL_VALUE: ${{ " + expression + " }}\n    steps:\n", 1)
                ok, findings = self.check_text(text)
                self.assertTrue(ok, findings)

    def test_runtime_evidence_export_is_required_before_build_and_tests(self):
        export = "          printf 'FTS_CI_EVIDENCE_DIR=%s/FruitTreeScanner-ci-evidence\\n' \"$RUNNER_TEMP\" >> \"$GITHUB_ENV\"\n"
        without = self.source.replace(export, "")
        self.assert_rejected(without, "runtime evidence output directory export")
        # A valid export after XCTest is too late for either producer.
        producer, consumer = without.split("\n  verify:", 1)
        late = producer + "\n      - name: Too late export\n        run: |\n" + export + "\n  verify:" + consumer
        self.assert_rejected(late, "evidence export must precede")


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
