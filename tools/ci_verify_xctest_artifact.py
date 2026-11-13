#!/usr/bin/env python3
"""Verify this workflow attempt's unchanged XCTest producer artifact with the shared gate."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile
import traceback

from ci_evidence import command
from ci_result_reader import select_reader
from xctest_gate import COUNT_FIELDS, declared_test_classes


REPOSITORY = Path(__file__).resolve().parents[1]
IDENTITIES = {"github_run_id": "GITHUB_RUN_ID", "github_run_attempt": "GITHUB_RUN_ATTEMPT", "github_sha": "GITHUB_SHA"}


def write_new(path, value):
    with path.open("x") as handle:
        json.dump(value, handle, indent=2)
        handle.write("\n")


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def read_object(path):
    value = json.loads(path.read_text())
    require(isinstance(value, dict), f"Expected a JSON object: {path.name}")
    return value


def input_files(root):
    """Hash regular inputs only; never follow an artifact link or special file."""
    files = {}
    def unreadable(error):
        raise error
    for directory, children, names in os.walk(root, followlinks=False, onerror=unreadable):
        for name in children + names:
            path = Path(directory) / name
            mode = path.lstat().st_mode
            require(not stat.S_ISLNK(mode), f"Artifact symbolic link rejected: {path.relative_to(root)}")
            require(stat.S_ISDIR(mode) or stat.S_ISREG(mode), f"Artifact special file rejected: {path.relative_to(root)}")
            require(path.resolve().is_relative_to(root), "Artifact path escapes its root")
            if stat.S_ISREG(mode):
                digest = hashlib.sha256()
                size = 0
                with path.open("rb") as source:
                    while chunk := source.read(64 * 1024):
                        digest.update(chunk)
                        size += len(chunk)
                files[str(path.relative_to(root))] = {"bytes": size, "sha256": digest.hexdigest()}
    return files


def artifact_file(producer, relative, nonempty=False):
    require(isinstance(relative, str) and relative and not Path(relative).is_absolute()
            and ".." not in Path(relative).parts, "Invalid artifact file reference")
    path = producer / relative
    require(path.resolve().is_relative_to(producer), "Artifact file reference escapes producer directory")
    require(path.is_file() and not path.is_symlink(), f"Required producer file is missing: {relative}")
    require(not nonempty or path.stat().st_size > 0, f"Required producer file is empty: {relative}")
    return path


def zero(value):
    return type(value) is int and value == 0


def validate_producer(artifact, expected):
    reports = list(artifact.glob("tests-*/report.json"))
    require(len(reports) == 1, "Exactly one tests-*/report.json is required")
    producer = reports[0].parent
    report = read_object(reports[0])
    for key, value in {"phase": "tests", "xctest_mode": "handoff", "gate_consumer_job": "verify"}.items():
        require(report.get(key) == value, f"Producer {key} must be {value!r}")
    for key in ("github_actions", "strict_gate_pending", "evidence_complete", "result_bundle_present"):
        require(report.get(key) is True, f"Producer {key} must be true")
    require(zero(report.get("primary_exit")) and zero(report.get("final_exit")), "Producer must have actual zero exits")
    for key, value in expected.items():
        require(report.get(key) == value, f"Producer {key} does not match this workflow attempt")
    metadata = read_object(artifact_file(producer, "run.json", True))
    for key in (*expected, "phase", "xctest_mode", "gate_consumer_job", "github_actions"):
        require(metadata.get(key) == report.get(key), f"Producer run/report metadata disagree: {key}")
    bundle = producer / "tests.xcresult"
    bundles = list(artifact.glob("tests-*/tests.xcresult"))
    require(bundles == [bundle] and bundle.is_dir() and any(bundle.rglob("*")), "Exactly one nonempty original tests.xcresult is required")
    commands = report.get("commands")
    require(isinstance(commands, list) and commands, "Producer command evidence is missing")
    recorded = [json.loads(line) for line in artifact_file(producer, "commands.jsonl", True).read_text().splitlines()]
    require(recorded == commands, "Producer command log and report disagree")
    for item in commands:
        require(isinstance(item, dict) and zero(item.get("exit_code")), "Producer has a failed or invalid command")
        artifact_file(producer, item.get("log"), item.get("name") == "xctest")
        if item.get("stderr") is not None:
            artifact_file(producer, item["stderr"])
    tests = [item for item in commands if item.get("name") == "xctest"]
    require(len(tests) == 1, "Exactly one actual xctest command is required")
    argv = tests[0].get("argv")
    require(isinstance(argv, list) and argv and all(isinstance(value, str) for value in argv)
            and Path(argv[0]).name == "xcodebuild" and "test" in argv, "Producer must run xcodebuild test")
    require(not any(re.match(r"^-{1,2}(only|skip)-(testing|test-configuration)(?:$|[:=])", arg) for arg in argv),
            "Filtered producer test runs are not accepted")
    require("-resultBundlePath" in argv and argv.index("-resultBundlePath") + 1 < len(argv), "Producer result bundle argument is missing")
    original_bundle = Path(argv[argv.index("-resultBundlePath") + 1])
    require(original_bundle.name == bundle.name and original_bundle.parent.name == producer.name,
            "Producer command refers to a different result bundle")
    toolchain = read_object(artifact_file(producer, "toolchain.json", True))
    tools = toolchain.get("commands")
    require(isinstance(tools, dict) and {"xcode-version", "simulator-sdk-version", "simulator-sdk-path", "simulators"} <= tools.keys(),
            "Producer toolchain evidence is incomplete")
    for item in tools.values():
        require(isinstance(item, dict) and zero(item.get("exit_code")), "Producer toolchain command failed")
        artifact_file(producer, item.get("log"), True)
    exports = report.get("exports")
    require(isinstance(exports, dict), "Producer exports are missing")
    exported = {}
    for name in ("summary", "tree"):
        item = exports.get(name)
        require(isinstance(item, dict) and zero(item.get("exit_code")) and item.get("json_object_readable") is True,
                f"Producer {name} export is incomplete")
        exported[name] = read_object(artifact_file(producer, item.get("stdout"), True))
        artifact_file(producer, item.get("stderr"))
    return producer, bundle, report, toolchain, exported


def verify(artifact_dir, output_root):
    artifact = artifact_dir.resolve()
    output = output_root.resolve()
    require(output != REPOSITORY and not output.is_relative_to(REPOSITORY), "Verification output must be outside the checkout")
    require(output != artifact and not output.is_relative_to(artifact), "Verification output must be outside the artifact")
    output.mkdir(parents=True, exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix="verify-", dir=output))
    result = {"status": "failed", "artifact_dir": str(artifact), "output": str(run), "final_exit": 2}
    before = None
    try:
        require(not artifact_dir.is_symlink(), "Artifact root cannot be a symbolic link")
        require(artifact.is_dir(), "Artifact directory is missing")
        before = input_files(artifact)
        result["input_files"] = before
        expected = {}
        for field, variable in IDENTITIES.items():
            value = os.environ.get(variable)
            require(isinstance(value, str) and value.strip(), f"Required workflow identity is missing: {variable}")
            expected[field] = value
        result["workflow_identity"] = expected
        status = command(run, "checkout-identity", ["git", "-C", str(REPOSITORY), "rev-parse", "HEAD"],
                         "checkout-identity.stdout", stderr="checkout-identity.stderr")
        require(zero(status) and (run / "checkout-identity.stdout").read_text().strip() == expected["github_sha"],
                "Current checkout does not match GITHUB_SHA")
        status = command(run, "checkout-gate-sources", ["git", "-C", str(REPOSITORY), "diff", "--exit-code", "HEAD", "--",
                         "tools/xctest_gate.py", "FruitTreeScannerTests"], "checkout-gate-sources.stdout", stderr="checkout-gate-sources.stderr")
        require(zero(status), "Shared gate or declared test sources differ from the checkout commit")
        producer, bundle, original, tools, exports = validate_producer(artifact, expected)
        result.update(producer_directory=str(producer), producer=original, producer_toolchain=tools)
        write_new(run / "producer-report.json", original)
        compiler = os.environ.get("DEVELOPER_DIR")
        if not compiler:
            status = command(run, "selected-xcode", ["xcode-select", "-p"], "selected-xcode.stdout", stderr="selected-xcode.stderr")
            require(zero(status), "Cannot determine the current result reader Xcode")
            compiler = (run / "selected-xcode.stdout").read_text().strip()
        selected = select_reader(run, compiler, os.environ.get("FTS_XCRESULT_DEVELOPER_DIR"),
                                 "FTS_XCRESULT_DEVELOPER_DIR" in os.environ, command)
        directory = selected["developer_dir"]
        result["reader"] = selected
        for name, argv in (("reader-version", ["xcodebuild", "-version"]),
                           ("reader-path", ["xcrun", "--find", "xcresulttool"])):
            status = command(run, name, argv, name + ".stdout", stderr=name + ".stderr", developer_dir=directory)
            require(zero(status), f"Cannot retain {name}")
        fresh = {}
        for name, kind in (("summary", "summary"), ("tree", "tests")):
            status = command(run, "export-" + name,
                ["xcrun", "xcresulttool", "get", "test-results", kind, "--path", str(bundle), "--format", "json"],
                name + ".json", stderr=name + ".stderr", developer_dir=directory)
            require(zero(status), f"Cannot read original result bundle {name}")
            fresh[name] = read_object(run / (name + ".json"))
        for key in (*COUNT_FIELDS, "result"):
            old = exports["summary"].get(key)
            new = fresh["summary"].get(key)
            require(key in exports["summary"] and key in fresh["summary"] and type(old) is type(new) and old == new,
                    f"Producer and reader summaries disagree: {key}")
        result["reader_counts"] = {key: fresh["summary"][key] for key in (*COUNT_FIELDS, "result")}
        result["declared_test_class_count"] = len(declared_test_classes(REPOSITORY))
        gate_argv = [sys.executable, str(REPOSITORY / "tools/xctest_gate.py"), str(bundle), "--repo", str(REPOSITORY)]
        status = command(run, "xctest-gate", gate_argv, "gate.stdout", stderr="gate.stderr", developer_dir=directory)
        result["gate_exit"] = status
        require(zero(status), f"Shared XCTest gate rejected original result bundle (exit {status})")
        require(input_files(artifact) == before, "Original producer artifact changed during verification")
        result.update(status="passed", final_exit=0, input_unchanged=True)
    except Exception as error:
        result["error"] = str(error)
        with (run / "verification-error.log").open("x") as handle:
            handle.write(traceback.format_exc())
    finally:
        if before is not None and result["status"] != "passed":
            try:
                result["input_unchanged"] = input_files(artifact) == before
            except Exception as error:
                result["input_recheck_error"] = str(error)
        write_new(run / "verification-report.json", result)
    print(f"XCTest artifact verification {result['status']}: {run}")
    return result["final_exit"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifact-dir", required=True, type=Path)
    parser.add_argument("--output-root", type=Path, default=Path(os.environ.get("RUNNER_TEMP", tempfile.gettempdir())) / "FruitTreeScanner-ci-verification")
    args = parser.parse_args()
    try:
        return verify(args.artifact_dir, args.output_root)
    except (OSError, ValueError) as error:
        print(f"Cannot initialize artifact verification: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
