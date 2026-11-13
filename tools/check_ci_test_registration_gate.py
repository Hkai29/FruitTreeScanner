#!/usr/bin/env python3
"""Check that CI actually runs the UI-test registration gate — and keeps running it.

Why this exists: `tools/check_test_target_registration.py` finds UI test sources
that live in the repository but are never compiled into their target. The
XCTest gate cannot catch that, because CI does not build the UI test target at
all. So the check needs its own step in CI, and that step has to stay a real
gate:

* both `push` and `pull_request` must be triggered by the UI test sources and
  by the check scripts themselves, otherwise a change that breaks registration
  never runs the gate at all;
* the registration step must exist, must run before the expensive build and
  before the XCTest gate, and must not be made non-blocking
  (`continue-on-error`) or neutralised with a condition such as `always()`;
* the original CI policy must stay in place: the XCTest gate step, the
  read-only permission and the branch filters are not to be dropped.

This tool only uses the standard library, so it can run on the CI runner
without installing anything.

Usage:
    python3 tools/check_ci_test_registration_gate.py
    python3 tools/check_ci_test_registration_gate.py --workflow <path> --json
"""
import argparse
import json
import re
import sys
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parents[1]
DEFAULT_WORKFLOW = REPOSITORY / ".github" / "workflows" / "build-ipa.yml"

REGISTRATION_CHECK = "tools/check_test_target_registration.py"
WIRING_CHECK = "tools/check_ci_test_registration_gate.py"
UI_TEST_SOURCES = "FruitTreeScannerUITests/**"
XCTest_GATE_MARKER = "tools/ci_xctest_gate.sh"
SIMULATOR_BUILD_MARKER = "tools/ci_simulator_build.sh"
EVIDENCE_HELPER = "tools/ci_evidence.py"
RESULT_READER_HELPER = "tools/ci_result_reader.py"
UI_HOST_SETUP_HELPER = "tools/ci_ui_host_setup.py"
VERIFICATION_HELPER = "tools/ci_verify_xctest_artifact.py"
EVIDENCE_DIRECTORY = "${{ runner.temp }}/FruitTreeScanner-ci-evidence"
VERIFICATION_DIRECTORY = "${{ runner.temp }}/FruitTreeScanner-ci-verification"
INPUT_DIRECTORY = "${{ runner.temp }}/FruitTreeScanner-ci-input"
EVIDENCE_NAME = "ios-evidence-${{ github.run_id }}-${{ github.run_attempt }}"
VERIFICATION_NAME = "ios-verification-${{ github.run_id }}-${{ github.run_attempt }}"
VERIFICATION_COMMAND = ('python3 ' + VERIFICATION_HELPER + ' --artifact-dir "' + INPUT_DIRECTORY
                        + '" --output-root "' + VERIFICATION_DIRECTORY + '"')
EVIDENCE_EXPORT = "printf 'FTS_CI_EVIDENCE_DIR=%s/FruitTreeScanner-ci-evidence\\n' \"$RUNNER_TEMP\" >> \"$GITHUB_ENV\""
REQUIRED_EVENTS = ("push", "pull_request")


class WorkflowShapeError(RuntimeError):
    """The workflow does not have the shape this checker understands."""


def _indent(line):
    return len(line) - len(line.lstrip(" "))


def _scalar(value):
    value = value.strip()
    if len(value) >= 2 and value[0] in "'\"" and value[-1] == value[0]:
        return value[1:-1]
    return value


def _flow_list(value):
    """Read a YAML flow sequence (``[ main ]``) or a single scalar."""
    value = value.strip()
    if value.startswith("[") and value.endswith("]"):
        value = value[1:-1]
        return [part.strip().strip("'\"") for part in value.split(",") if part.strip()]
    return [value.strip("'\"")] if value else []


def _strip_comment(line):
    """Drop a trailing YAML comment that is not inside quotes."""
    out = []
    quote = None
    for index, character in enumerate(line):
        if quote:
            out.append(character)
            if character == quote:
                quote = None
            continue
        if character in "'\"":
            quote = character
            out.append(character)
            continue
        if character == "#" and (index == 0 or line[index - 1] in " \t"):
            break
        out.append(character)
    return "".join(out).rstrip()


def parse_workflow(text):
    """Parse the parts of the workflow this checker needs.

    This is a deliberately small, strict reader — not a YAML engine. It knows
    the shape of this repository's workflow and refuses to guess: an
    unreadable shape raises instead of silently reporting "nothing found".
    """
    lines = [(index + 1, _strip_comment(raw)) for index, raw in enumerate(text.splitlines())]
    lines = [(number, line) for number, line in lines if line.strip()]

    events = {}
    permissions = {}
    steps = []
    jobs = {}
    job_environment_sources = []

    section = None
    event = None
    in_paths = False
    in_steps = False
    current_step = None
    run_block_indent = None
    in_job_environment = False
    current_job = None
    job_mapping = None
    step_mapping = None

    for number, line in lines:
        indent = _indent(line)
        stripped = line.strip()

        if run_block_indent is not None:
            # inside a "run: |" block: keep the raw command text
            if indent > run_block_indent:
                if current_step is not None:
                    current_step["run"].append(stripped)
                continue
            run_block_indent = None

        if indent == 0 and stripped.endswith(":"):
            section = stripped[:-1]
            event = None
            in_paths = False
            in_steps = False
            current_step = None
            continue

        if section == "on":
            if indent == 2 and stripped.endswith(":"):
                event = stripped[:-1]
                events.setdefault(event, {"paths": [], "branches": []})
                in_paths = False
                continue
            if event is None:
                continue
            if indent == 4 and stripped.startswith("paths:"):
                in_paths = True
                continue
            if indent == 4 and stripped.startswith("branches:"):
                in_paths = False
                events[event]["branches"] = _flow_list(stripped.split(":", 1)[1])
                continue
            if in_paths and indent >= 6 and stripped.startswith("-"):
                events[event]["paths"].append(stripped[1:].strip().strip("'\""))
                continue
            in_paths = False
            continue

        if section == "permissions":
            if indent == 2 and ":" in stripped:
                key, value = stripped.split(":", 1)
                permissions[key.strip()] = value.strip()
            continue

        if section == "jobs":
            if indent == 2 and stripped.endswith(":"):
                job_name = stripped[:-1]
                if job_name in jobs:
                    raise WorkflowShapeError("duplicate job: " + job_name)
                current_job = {"job_id": job_name, "name": "", "steps": [], "needs": [], "env": {}, "permissions": {},
                               "if": None, "continue-on-error": None, "runs-on": ""}
                jobs[job_name] = current_job
                in_steps = False
                current_step = None
                in_job_environment = False
                job_mapping = None
                continue
            if current_job is None:
                raise WorkflowShapeError("job content has no owning job")
            if indent == 4:
                in_job_environment = stripped.startswith("env:")
                if in_job_environment:
                    job_environment_sources.append(stripped)
                key, separator, value = stripped.partition(":")
                if not separator:
                    raise WorkflowShapeError("invalid job property at line %s" % number)
                job_mapping = key if key in ("env", "permissions", "needs") else None
                value = _scalar(value)
                if key == "needs":
                    current_job[key] = _flow_list(value)
                elif key in ("name", "runs-on", "if", "continue-on-error"):
                    current_job[key] = value
                elif key in ("env", "permissions") and value:
                    if key == "permissions":
                        raise WorkflowShapeError("job permissions must use a mapping")
            if in_job_environment and indent > 4:
                job_environment_sources.append(stripped)
                if indent == 6 and ":" in stripped:
                    key, value = stripped.split(":", 1)
                    current_job["env"][key.strip()] = _scalar(value)
                continue
            if indent == 6 and job_mapping in ("permissions", "needs") and not in_steps:
                if job_mapping == "needs" and stripped.startswith("- "):
                    current_job["needs"].append(stripped[2:].strip().strip("'\""))
                elif job_mapping == "permissions" and ":" in stripped:
                    key, value = stripped.split(":", 1)
                    current_job["permissions"][key.strip()] = _scalar(value)
                else:
                    raise WorkflowShapeError("invalid job mapping at line %s" % number)
                continue
            if indent == 4 and stripped == "steps:":
                in_steps = True
                continue
            if not in_steps:
                continue
            if indent == 6 and stripped.startswith("- "):
                current_step = {"line": number, "name": "", "run": [], "uses": "", "shell": "",
                                "continue-on-error": None, "if": None, "with": {}, "env": {},
                                "job": current_job["job_id"]}
                steps.append(current_step)
                current_job["steps"].append(current_step)
                step_mapping = None
                first = stripped[2:].strip()
                if ":" not in first:
                    raise WorkflowShapeError("invalid step at line %s" % number)
                key, value = first.split(":", 1)
                value = _scalar(value)
                if key not in current_step or key in ("with", "env", "job", "line"):
                    raise WorkflowShapeError("unsupported first step property at line %s" % number)
                if key == "run":
                    if value in ("|", ">", "|-", ">-"):
                        run_block_indent = indent
                    else:
                        current_step["run"].append(value)
                else:
                    current_step[key] = value
                continue
            if current_step is not None and indent == 10 and ":" in stripped:
                if step_mapping not in ("with", "env"):
                    raise WorkflowShapeError("step values must belong to with or env")
                key, value = stripped.split(":", 1)
                if key.strip() in current_step[step_mapping]:
                    raise WorkflowShapeError("duplicate step mapping key: " + key.strip())
                current_step[step_mapping][key.strip()] = _scalar(value)
                continue
            if current_step is None:
                continue
            if indent == 8 and ":" in stripped:
                key, value = stripped.split(":", 1)
                key = key.strip()
                value = _scalar(value)
                step_mapping = key if key in ("with", "env") else None
                if key in ("with", "env") and value:
                    raise WorkflowShapeError("step with/env must use a mapping")
                if key == "name":
                    current_step["name"] = value
                elif key == "uses":
                    current_step["uses"] = value
                elif key == "shell":
                    current_step["shell"] = value
                elif key == "continue-on-error":
                    current_step["continue-on-error"] = value
                elif key == "if":
                    current_step["if"] = value
                elif key == "run":
                    if value in ("|", ">", "|-", ">-"):
                        run_block_indent = indent
                    else:
                        current_step["run"].append(value)
                continue

    if not events:
        raise WorkflowShapeError("no event block found in the workflow")
    if not steps:
        raise WorkflowShapeError("no steps found in the workflow")
    return {"events": events, "permissions": permissions, "steps": steps,
            "jobs": jobs, "job_environment_sources": job_environment_sources}


def references_runner_context(value):
    # GitHub expression string literals use single quotes ('' escapes a quote).
    # Removing literals preserves runner.temp, runner['temp'] and bare runner,
    # without confusing a legal literal such as format('runner.temp') for access.
    for expression in re.findall(r"\$\{\{(.*?)\}\}", value, re.DOTALL):
        code = re.sub(r"'(?:''|[^'])*'", "", expression)
        code = re.sub(r"\s+", "", code)
        if re.search(r"(?<![\w.])runner\b", code):
            return True
    return False


def _require_hard_step(step, findings, label):
    if step["continue-on-error"] not in (None, "false"):
        findings.append(label + " must not set continue-on-error")
    if step["if"] is not None:
        findings.append(label + " must be unconditional and hard-failing")


def _check_verification(workflow, test_steps, findings):
    jobs = workflow["jobs"]
    build = jobs.get("build")
    verify = jobs.get("verify")
    if not build or not verify:
        findings.append("the handoff requires a mandatory verification job named verify")
        return
    if build["name"] != "Execute compatibility XCTest" or verify["name"] != "build":
        findings.append("the strict required check named build must belong to verify; the producer must use its distinct display name")
    for name, job in (("build", build), ("verify", verify)):
        if job["if"] is not None or job["continue-on-error"] not in (None, "false"):
            findings.append("the %s job must be unconditional and hard-failing" % name)
        if any(value not in ("read", "none") for value in job["permissions"].values()):
            findings.append("the %s job permissions must remain read-only" % name)
        if job["permissions"] and job["permissions"].get("contents") != "read":
            findings.append("the %s job permissions require contents: read" % name)
    if build["runs-on"] != "macos-15":
        findings.append("the build job must retain its macos-15 compiler runner")
    if verify["runs-on"] != "xcode-27":
        findings.append("the verification job must use the standard xcode-27 reader runner")
    if verify["needs"] != ["build"]:
        findings.append("the verification job needs the successful build job")
    if build["needs"]:
        findings.append("the build job must remain the initial producer")
    for job in (build, verify):
        if any(key in job["env"] for key in ("FTS_CI_XCTEST_MODE", "FTS_CI_XCTEST_CONSUMER")):
            findings.append("XCTest handoff configuration belongs only in the producer step env")
    for step in test_steps:
        if step["env"] != {"FTS_CI_XCTEST_MODE": "handoff", "FTS_CI_XCTEST_CONSUMER": "verify"}:
            findings.append("the producer step env must name handoff mode and its verify consumer")
        if step["run"] != ["bash " + XCTest_GATE_MARKER] or step["shell"] != "bash":
            findings.append("the producer must directly run the full XCTest gate")
    steps = verify["steps"]
    checkout = [step for step in steps if step["uses"] == "actions/checkout@v4"]
    downloads = [step for step in steps if step["uses"] == "actions/download-artifact@v8"]
    consumers = [step for step in steps if any(VERIFICATION_HELPER in line for line in step["run"])]
    uploads = [step for step in steps if step["uses"] == "actions/upload-artifact@v7"]
    for selected, label in ((checkout, "checkout"), (downloads, "download"),
                            (consumers, "strict consumer"), (uploads, "verification upload")):
        if len(selected) != 1:
            findings.append("the verification job requires exactly one " + label)
    for step in checkout + downloads + consumers:
        _require_hard_step(step, findings, "verification " + step["name"])
    for step in checkout:
        if step["with"] != {"ref": "${{ github.sha }}"}:
            findings.append("verification checkout must use the same github.sha source")
    expected_download = {"name": EVIDENCE_NAME, "path": INPUT_DIRECTORY + "/", "digest-mismatch": "error"}
    for step in downloads:
        if step["with"] != expected_download:
            findings.append("verification download must use the same run/attempt artifact and digest-mismatch: error")
    for step in consumers:
        if step["run"] != [VERIFICATION_COMMAND] or step.get("shell") != "bash":
            findings.append("verification must directly run the strict consumer on the dedicated input/output directories")
    if len(checkout) == len(downloads) == len(consumers) == len(uploads) == 1:
        if not steps.index(checkout[0]) < steps.index(downloads[0]) < steps.index(consumers[0]) < steps.index(uploads[0]):
            findings.append("verification order must be checkout, download, strict consumer, then upload")
    for upload in uploads:
        if upload["continue-on-error"] not in (None, "false"):
            findings.append("verification upload must not set continue-on-error")
        if upload["if"] not in ("always()", "${{ always() }}"):
            findings.append("verification upload requires if: always()")
        expected = {"name": VERIFICATION_NAME, "path": VERIFICATION_DIRECTORY + "/",
                    "if-no-files-found": "error", "retention-days": "14",
                    "overwrite": "false", "include-hidden-files": "true"}
        if upload["with"] != expected:
            findings.append("verification upload must retain only complete dedicated verification evidence with run identity")


def check(workflow_path):
    """Return (ok, findings)."""
    text = Path(workflow_path).read_text()
    workflow = parse_workflow(text)
    findings = []
    steps = workflow["jobs"].get("build", {}).get("steps", [])
    if not steps:
        findings.append("the build job must own the production gates")

    # 1. both events must exist and must be triggered by the right paths
    for name in REQUIRED_EVENTS:
        event = workflow["events"].get(name)
        if event is None:
            findings.append("the workflow has no %r event" % name)
            continue
        paths = event["paths"]
        for required in (UI_TEST_SOURCES, REGISTRATION_CHECK, WIRING_CHECK, EVIDENCE_HELPER,
                         RESULT_READER_HELPER, UI_HOST_SETUP_HELPER, VERIFICATION_HELPER):
            if required not in paths:
                findings.append("the %r event does not trigger on %r" % (name, required))

    # 2. the registration check must actually be executed by a step
    registration_steps = [step for step in steps
                           if any(REGISTRATION_CHECK in command for command in step["run"])]
    if not registration_steps:
        findings.append("no step runs %s" % REGISTRATION_CHECK)
        return not findings, findings

    # 2b. the wiring check itself must stay in CI, so that deleting it is
    # visible to anyone running this checker (locally or from the tool tests).
    # It cannot fail the CI job by itself once it is gone — that limit is
    # inherent to a self-check, and is why the registration gate above is the
    # one that actually blocks a build.
    if not any(any(WIRING_CHECK in command for command in step["run"]) for step in steps):
        findings.append("no step runs %s (the wiring check must stay in CI)" % WIRING_CHECK)
    for marker, command in ((REGISTRATION_CHECK, "python3 " + REGISTRATION_CHECK),
                             (WIRING_CHECK, "python3 " + WIRING_CHECK),
                             (SIMULATOR_BUILD_MARKER, "bash " + SIMULATOR_BUILD_MARKER),
                             ("tools/validate_fusion_domain.sh", "bash tools/validate_fusion_domain.sh")):
        selected = [step for step in steps if any(marker in line for line in step["run"])]
        if len(selected) != 1:
            findings.append("the build job requires exactly one gate running " + marker)
        for step in selected:
            _require_hard_step(step, findings, "the build gate running " + marker)
            if step["run"] != [command] or step["shell"] != "bash":
                findings.append("the build gate must directly execute " + marker)

    # 3. the step must not be made non-blocking
    for step in registration_steps:
        if step["continue-on-error"] not in (None, "false"):
            findings.append("the step running %s sets continue-on-error: %s"
                            % (REGISTRATION_CHECK, step["continue-on-error"]))
        condition = step["if"]
        if condition is not None:
            findings.append("the step running %s is neutralised by if: %s"
                            % (REGISTRATION_CHECK, condition))

    # 4. it must fail early: before the expensive build and before the XCTest gate
    registration_index = steps.index(registration_steps[0])
    for marker, label in ((SIMULATOR_BUILD_MARKER, "the simulator build"),
                           (XCTest_GATE_MARKER, "the XCTest gate")):
        indexes = [index for index, step in enumerate(steps)
                   if any(marker in command for command in step["run"])]
        if not indexes:
            findings.append("%s is gone from the workflow" % label)
            continue
        if registration_index > indexes[0]:
            findings.append("the registration gate runs after %s; it must fail early"
                            % label)

    # 5. the original CI policy must stay in place
    if not any(XCTest_GATE_MARKER in command for step in steps for command in step["run"]):
        findings.append("the XCTest gate step is gone")
    if workflow["permissions"].get("contents") != "read":
        findings.append("the workflow permissions changed: contents=%s (expected read)"
                        % workflow["permissions"].get("contents"))
    if any(value not in ("read", "none") for value in workflow["permissions"].values()):
        findings.append("all workflow permissions must remain read-only")
    for name in REQUIRED_EVENTS:
        event = workflow["events"].get(name)
        if event is not None and event["branches"] != ["main"]:
            findings.append("the %r event no longer targets the main branch only: %s"
                            % (name, event["branches"]))

    # Diagnostics remain available when compilation, tests or the shared gate fail.
    test_steps = [step for step in steps if any(XCTest_GATE_MARKER in line for line in step["run"])]
    if len(test_steps) != 1:
        findings.append("exactly one full XCTest gate producer is required in the build job")
    for step in test_steps:
        _require_hard_step(step, findings, "the XCTest gate producer")
    _check_verification(workflow, test_steps, findings)
    uploads = [step for step in steps if step["uses"] == "actions/upload-artifact@v7"]
    if len(uploads) != 1:
        findings.append("exactly one CI evidence upload is required")
    for step in test_steps + uploads:
        if step["continue-on-error"] not in (None, "false"):
            findings.append("CI gate/evidence step must not set continue-on-error")
    if references_runner_context("\n".join(workflow["job_environment_sources"])):
        findings.append("runner context is unavailable in job env; export it at step runtime")
    exporters = [index for index, step in enumerate(steps) if EVIDENCE_EXPORT in step["run"]]
    producers = [index for index, step in enumerate(steps)
                 if any(marker in line for marker in (XCTest_GATE_MARKER, SIMULATOR_BUILD_MARKER)
                        for line in step["run"])]
    if len(exporters) != 1:
        findings.append("exactly one runtime evidence output directory export is required")
    else:
        export_index = exporters[0]
        if producers and export_index >= min(producers):
            findings.append("CI evidence export must precede both build and XCTest gate")
        exporter = steps[export_index]
        if exporter["continue-on-error"] not in (None, "false") or exporter["if"] is not None:
            findings.append("runtime evidence output directory export must be unconditional and hard-failing")
    for upload in uploads:
        if upload["if"] not in ("always()", "${{ always() }}"):
            findings.append("CI evidence upload requires if: always()")
        if upload["with"].get("path") != EVIDENCE_DIRECTORY + "/":
            findings.append("CI evidence upload must use only the dedicated evidence directory")
        if upload["with"].get("if-no-files-found") != "error":
            findings.append("CI upload must fail on missing evidence")
        if upload["with"].get("include-hidden-files") != "true":
            findings.append("CI upload must retain complete result bundles, including hidden files")
        if upload["with"].get("overwrite") != "false":
            findings.append("CI evidence upload must not overwrite earlier artifacts")
        name = upload["with"].get("name", "")
        if "${{ github.run_id }}" not in name or "${{ github.run_attempt }}" not in name:
            findings.append("CI evidence artifact name must retain run identity and attempt")
        preceding = [index for index, step in enumerate(steps)
                     if any(marker in line for marker in (XCTest_GATE_MARKER, SIMULATOR_BUILD_MARKER)
                            for line in step["run"])]
        if not preceding or steps.index(upload) <= max(preceding):
            findings.append("CI evidence upload must follow both build and XCTest gate")
    return not findings, findings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workflow", type=Path, default=DEFAULT_WORKFLOW)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    try:
        ok, findings = check(args.workflow)
    except (OSError, WorkflowShapeError) as error:
        print("CI wiring check failed: %s" % error, file=sys.stderr)
        return 2

    if args.json:
        print(json.dumps({"ok": ok, "findings": findings}, indent=2, ensure_ascii=False))
    elif ok:
        print("CI runs %s as an early, hard-failing step for both events."
              % REGISTRATION_CHECK)
    else:
        for finding in findings:
            print("CI WIRING PROBLEM: %s" % finding, file=sys.stderr)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
