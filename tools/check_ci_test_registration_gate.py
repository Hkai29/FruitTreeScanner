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
REQUIRED_EVENTS = ("push", "pull_request")


class WorkflowShapeError(RuntimeError):
    """The workflow does not have the shape this checker understands."""


def _indent(line):
    return len(line) - len(line.lstrip(" "))


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

    section = None
    event = None
    in_paths = False
    in_steps = False
    current_step = None
    run_block_indent = None

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
            if indent == 4 and stripped == "steps:":
                in_steps = True
                continue
            if not in_steps:
                continue
            if indent == 6 and stripped.startswith("- "):
                current_step = {"line": number, "name": "", "run": [], "uses": "",
                                "continue-on-error": None, "if": None}
                steps.append(current_step)
                first = stripped[2:].strip()
                if first.startswith("name:"):
                    current_step["name"] = first.split(":", 1)[1].strip().strip("'\"")
                continue
            if current_step is None:
                continue
            if indent == 8 and ":" in stripped:
                key, value = stripped.split(":", 1)
                key = key.strip()
                value = value.strip().strip("'\"")
                if key == "name":
                    current_step["name"] = value
                elif key == "uses":
                    current_step["uses"] = value
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
    return {"events": events, "permissions": permissions, "steps": steps}


def check(workflow_path):
    """Return (ok, findings)."""
    text = Path(workflow_path).read_text()
    workflow = parse_workflow(text)
    findings = []
    steps = workflow["steps"]

    # 1. both events must exist and must be triggered by the right paths
    for name in REQUIRED_EVENTS:
        event = workflow["events"].get(name)
        if event is None:
            findings.append("the workflow has no %r event" % name)
            continue
        paths = event["paths"]
        for required in (UI_TEST_SOURCES, REGISTRATION_CHECK, WIRING_CHECK):
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

    # 3. the step must not be made non-blocking
    for step in registration_steps:
        if step["continue-on-error"] in ("true", "True", "yes"):
            findings.append("the step running %s sets continue-on-error: %s"
                            % (REGISTRATION_CHECK, step["continue-on-error"]))
        condition = step["if"]
        if condition and re.search(r"always\(\)|failure\(\)|cancelled\(\)", condition):
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
    for name in REQUIRED_EVENTS:
        event = workflow["events"].get(name)
        if event is not None and event["branches"] != ["main"]:
            findings.append("the %r event no longer targets the main branch only: %s"
                            % (name, event["branches"]))
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
