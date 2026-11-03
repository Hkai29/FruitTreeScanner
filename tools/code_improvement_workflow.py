#!/usr/bin/env python3
"""Record and validate one code-improvement iteration without changing source."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


REPO = Path(__file__).resolve().parents[1]
DEFAULT_XCODE = "/Users/reece24/Downloads/Xcode-beta.app/Contents/Developer"
DEFAULT_SIMULATOR = "C722B4F0-E16F-4C14-84A1-8C796DB0FE11"
PROFILES = {
    "preflight": (), "quick": (),
    "fusion": (
        "FusionValidatorTests", "DetectionDeduplicatorTests", "ScanFusionYieldBuilderTests",
        "DetectionDebugStateTests", "CandidateCombinerTests", "ScanObservationReplayTests",
        "PointCloudClusterTests", "OcclusionCorrectorTests", "YieldEstimatorTests",
        "ScanDiagnosticsBuilderTests", "DiagnosticRecommendationTests", "FruitModelsTests",
    ),
    "storage": (
        "BatchExportServiceTests", "PointCloudProcessingTests", "CalibrationRecordPersistenceTests",
        "FruitParametersStoreTests", "TagStoreTests", "TreeSurveyCatalogTests", "ScanExportReadinessTests",
        "BatchExportShareLifecycleTests", "BatchExportFailureFeedbackTests",
    ),
    "lifecycle": (
        "ScanReadinessTests", "ScanReadinessRequestControllerTests", "ScanLifecycleControllerTests",
        "ScanSessionSnapshotTests", "ScanCoordinatorSessionRestartTests",
        "ScanCoordinatorARSessionIdentityTests", "MetalViewBindingLifecycleTests",
        "ScanReadinessRecoveryBindingTests", "ScanCoordinatorCameraTrackingTests",
        "ScanCapturedEvidenceConcurrencyTests", "ScanCompletionEvaluatorTests",
        "ScanSessionConfigurationTests", "ScanPlanTests", "ScanFinalizationWorkflowTests",
        "ScanLiveFruitCountTests", "YieldEstimationRequestGateTests", "DetectionDebugStateTests",
        "ScanExportReadinessTests",
    ),
    # UI tests span many classes; also walk navigation manually in iOS Simulator.
    "ui": (), "full": (),
}


class GateFailure(Exception):
    def __init__(self, message, exit_code=1):
        super().__init__(message)
        self.exit_code = exit_code if 0 < exit_code < 126 else 1


try:
    # 判定逻辑只有一份：本地全量关卡与 CI 门禁共用 tools/xctest_gate.py。
    from xctest_gate import (  # noqa: F401
        GateFailure as _SharedGateFailure,
        validate_summary as _shared_validate_summary,
        validate_test_tree as _shared_validate_test_tree,
        declared_test_classes as _shared_declared_test_classes,
    )
except ImportError:  # 被以模块方式加载时（测试用 importlib）
    import importlib.util as _importlib_util

    _spec = _importlib_util.spec_from_file_location(
        "xctest_gate", Path(__file__).with_name("xctest_gate.py")
    )
    _module = _importlib_util.module_from_spec(_spec)
    _spec.loader.exec_module(_module)
    _SharedGateFailure = _module.GateFailure
    _shared_validate_summary = _module.validate_summary
    _shared_validate_test_tree = _module.validate_test_tree
    _shared_declared_test_classes = _module.declared_test_classes


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def test_classes(profiles):
    return sorted({name for profile in profiles for name in PROFILES[profile]})


def command_plan(profiles, output, simulator):
    """Use argument arrays, never shell strings or interpolated commands."""
    plan = [("diff-check", ["git", "diff", "--check"]),
            ("staged-diff-check", ["git", "diff", "--cached", "--check"])]
    if set(profiles) == {"preflight"}:
        return plan
    plan.extend([
        ("xcode-version", ["xcodebuild", "-version"]),
        ("simulator-sdk", ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"]),
        ("domain", ["bash", str(REPO / "tools/validate_fusion_domain.sh")]),
    ])
    common = ["xcodebuild", "-project", str(REPO / "FruitTreeScanner.xcodeproj"),
              "-scheme", "FruitTreeScanner", "-derivedDataPath", str(output / "DerivedData"),
              "CODE_SIGNING_ALLOWED=NO"]
    if "quick" in profiles:
        plan.append(("debug-build", common + ["-configuration", "Debug", "-destination",
                                             "generic/platform=iOS Simulator", "build"]))
    if set(profiles) - {"preflight", "quick"}:
        command = common + ["-configuration", "Debug", "-destination",
                            f"platform=iOS Simulator,id={simulator}",
                            "-parallel-testing-enabled", "NO", "-resultBundlePath",
                            str(output / "tests.xcresult"), "test"]
        if not {"full", "ui"}.intersection(profiles):
            command += [f"-only-testing:FruitTreeScannerTests/{name}" for name in test_classes(profiles)]
        # A cold simulator can launch the hosted tests before a usable app
        # scene exists. Record system boot readiness as a separate fail-fast gate.
        plan.append(("simulator-bootstatus", ["xcrun", "simctl", "bootstatus", simulator, "-b"]))
        plan.append(("tests", command))
    if "full" in profiles:
        plan.append(("release-build", common + ["-configuration", "Release", "-destination",
                                               "generic/platform=iOS Simulator", "build"]))
    return plan


def validate_summary(summary):
    """共享判定：tools/xctest_gate.py（CI 门禁用同一份）。"""
    try:
        _shared_validate_summary(summary)
    except _SharedGateFailure as error:
        raise GateFailure(str(error), error.exit_code) from error


def declared_test_classes():
    """共享判定：tools/xctest_gate.py（CI 门禁用同一份）。"""
    return _shared_declared_test_classes(REPO)


def verify_selectors(profiles):
    declared = declared_test_classes()
    expected = declared if {"full", "ui"}.intersection(profiles) else set(test_classes(profiles))
    missing = expected - declared
    if missing:
        raise GateFailure("Missing XCTest classes: " + ", ".join(sorted(missing)))
    return expected


def validate_test_tree(tree, expected):
    """共享判定：tools/xctest_gate.py（CI 门禁用同一份）。返回执行到并通过的类名。"""
    try:
        executed, _passed_cases = _shared_validate_test_tree(tree, set(expected))
    except _SharedGateFailure as error:
        raise GateFailure(str(error), error.exit_code) from error
    return executed


class Run:
    def __init__(self, output, profiles, simulator):
        self.output = output
        self.env = dict(os.environ, DEVELOPER_DIR=os.environ.get("DEVELOPER_DIR", DEFAULT_XCODE))
        self.report = {
            "started_at_utc": utc_now(), "repo": str(REPO), "profiles": profiles,
            "developer_dir": self.env["DEVELOPER_DIR"], "simulator_id": simulator,
            "validation_status": "running", "steps": [], "human_review_required": True,
            "device_acceptance": "not_run", "output": str(output),
        }

    def save(self):
        destination = self.output / "report.json"
        temporary = destination.with_suffix(".tmp")
        temporary.write_text(json.dumps(self.report, indent=2, ensure_ascii=False) + "\n")
        temporary.replace(destination)

    def step(self, name, command):
        log = self.output / f"{name}.log"
        entry = {"name": name, "command": command, "log": str(log), "started_at_utc": utc_now()}
        self.report["steps"].append(entry)
        self.save()
        print(f"Running {name}; log: {log}", flush=True)
        try:
            with log.open("wb") as stream:
                result = subprocess.run(command, cwd=REPO, env=self.env, stdout=stream,
                                        stderr=subprocess.STDOUT, check=False)
            entry["exit_code"] = result.returncode
        except OSError as error:
            entry.update(exit_code=127, error=str(error))
            self.save()
            raise GateFailure(f"Cannot run {name}: {error}") from error
        entry["finished_at_utc"] = utc_now()
        self.save()
        if result.returncode:
            raise GateFailure(f"{name} failed (exit {result.returncode}); see {log}", result.returncode)

    def git(self, *arguments):
        result = subprocess.run(["git", *arguments], cwd=REPO, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, check=False)
        if result.returncode:
            raise GateFailure(result.stderr.decode(errors="replace").strip(), result.returncode)
        return result.stdout

    def snapshot(self, label):
        state = {"head": self.git("rev-parse", "HEAD").decode().strip(),
                 "branch": self.git("rev-parse", "--abbrev-ref", "HEAD").decode().strip()}
        captures = {
            "status.txt": self.git("status", "--porcelain=v1", "--untracked-files=all"),
            "unstaged.patch": self.git("diff", "--binary"),
            "staged.patch": self.git("diff", "--cached", "--binary"),
        }
        for suffix, content in captures.items():
            (self.output / f"{label}-{suffix}").write_bytes(content)
            state[suffix] = hashlib.sha256(content).hexdigest()
        names = self.git("diff", "--name-only", "HEAD", "-z") + self.git(
            "ls-files", "--others", "--exclude-standard", "-z")
        state["changed_file_sha256"] = {}
        for raw_name in sorted(set(names.split(b"\0")) - {b""}):
            name = os.fsdecode(raw_name)
            source = REPO / name
            digest = None
            if source.is_file():
                hasher = hashlib.sha256()
                with source.open("rb") as stream:
                    for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                        hasher.update(chunk)
                digest = hasher.hexdigest()
            state["changed_file_sha256"][name] = digest
        self.report[label] = state
        self.save()
        return state

    def summarize_tests(self, expected):
        self.step("test-summary", ["xcrun", "xcresulttool", "get", "test-results", "summary",
                                   "--path", str(self.output / "tests.xcresult"), "--compact"])
        try:
            summary = json.loads((self.output / "test-summary.log").read_text())
        except (ValueError, OSError) as error:
            raise GateFailure(f"Cannot read XCTest summary: {error}") from error
        self.report["test_summary"] = summary
        self.save()
        validate_summary(summary)
        if summary["runtimeWarnings"]:
            self.step("runtime-warning-evidence", [sys.executable, str(REPO / "tools/inspect_runtime_warnings.py"),
                str(self.output / "tests.xcresult"), "--summary", str(self.output / "test-summary.log")])
            try:
                evidence = json.loads((self.output / "runtime-warning-evidence.log").read_text())
                if (type(evidence.get("schema_version")) is not int or evidence["schema_version"] != 1
                        or evidence.get("warning_count") != len(summary["runtimeWarnings"])
                        or any(type(evidence.get(key)) is not int or evidence[key] < 0
                               for key in ("warning_count", "raw_frame_count", "warnings_without_frames"))
                        or evidence["warnings_without_frames"] > evidence["warning_count"]):
                    raise ValueError("invalid runtime warning evidence counts/schema")
            except (ValueError, OSError, AttributeError) as error:
                raise GateFailure(f"Cannot read runtime warning evidence: {error}") from error
            self.report["runtime_warning_evidence"] = {
                "log": str(self.output / "runtime-warning-evidence.log"),
                **{key: evidence[key] for key in ("warning_count", "raw_frame_count", "warnings_without_frames")},
            }
            self.save()
        self.step("test-tree", ["xcrun", "xcresulttool", "get", "test-results", "tests",
                                "--path", str(self.output / "tests.xcresult"), "--compact"])
        try:
            tree = json.loads((self.output / "test-tree.log").read_text())
        except (ValueError, OSError) as error:
            raise GateFailure(f"Cannot read XCTest test tree: {error}") from error
        self.report["executed_test_classes"] = validate_test_tree(tree, expected)
        self.save()
        # 摘要与结果树必须对上：摘要说通过了多少用例，树里就要有同样多的通过用例。
        _, passed_cases = _shared_validate_test_tree(tree, set(expected))
        if summary.get("passedTests") != passed_cases:
            raise GateFailure(
                "XCTest summary and result tree disagree: summary reports "
                f"{summary.get('passedTests')} passed tests, the tree contains {passed_cases}."
            )


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("profiles", nargs="*", choices=tuple(PROFILES), default=None,
                        help="Default: preflight. Combine risk profiles; full covers all tests.")
    parser.add_argument("--dry-run", action="store_true", help="Print command arrays without executing.")
    parser.add_argument("--output-root", type=Path, default=Path(tempfile.gettempdir()),
                        help="Existing directory outside the checkout for unique evidence.")
    parser.add_argument("--simulator", default=os.environ.get("FTS_SIMULATOR_ID", DEFAULT_SIMULATOR))
    arguments = parser.parse_args(argv)
    profiles = list(dict.fromkeys(arguments.profiles or ["preflight"]))
    parent = arguments.output_root.resolve()
    if parent == REPO or REPO in parent.parents:
        parser.error("--output-root must be outside the repository, including through symlinks.")
    if not parent.is_dir():
        parser.error("--output-root must be an existing directory.")
    if arguments.dry_run:
        print(json.dumps({"profiles": profiles, "steps": command_plan(
            profiles, parent / "<unique-run>", arguments.simulator),
            "note": "Execution also records baseline/end snapshots and checks XCTest counts."}, indent=2))
        return 0

    output = Path(tempfile.mkdtemp(prefix="fruit-code-improvement-", dir=parent))
    run = Run(output, profiles, arguments.simulator)
    print(f"Evidence directory: {output}", flush=True)
    status = 1
    baseline = None
    expected = set()
    try:
        baseline = run.snapshot("baseline")
        if set(profiles) != {"preflight"}:
            if not Path(run.env["DEVELOPER_DIR"]).is_dir():
                raise GateFailure("Configured DEVELOPER_DIR does not exist.")
            expected = verify_selectors(profiles)
            run.report["required_test_classes"] = sorted(expected)
        for name, command in command_plan(profiles, output, arguments.simulator):
            try:
                run.step(name, command)
            except GateFailure:
                # Extract failure evidence when available; preserve the original test exit.
                if name == "tests" and (output / "tests.xcresult").exists():
                    try:
                        run.summarize_tests(expected)
                    except GateFailure as evidence_error:
                        run.report["test_evidence_error"] = str(evidence_error)
                raise
            if name == "tests":
                run.summarize_tests(expected)
        run.report["validation_status"] = "passed"
        status = 0
    except GateFailure as error:
        run.report.update(validation_status="failed", error=str(error))
        status = error.exit_code
        print(str(error), file=sys.stderr)
    except KeyboardInterrupt:
        run.report.update(validation_status="interrupted", error="Interrupted; evidence is retained.")
        status = 130
    except OSError as error:
        run.report.update(validation_status="failed", error=str(error))
        print(str(error), file=sys.stderr)
    finally:
        try:
            final = run.snapshot("final")
            if baseline is not None and final != baseline:
                run.report["workspace_changed_during_validation"] = True
                if status == 0:
                    status = 1
                    run.report.update(validation_status="failed", error="Workspace changed during validation; rerun.")
        except (GateFailure, OSError) as error:
            run.report["final_snapshot_error"] = str(error)
            if status == 0:
                status = 1
                run.report["validation_status"] = "failed"
        run.report.update(finished_at_utc=utc_now(), exit_code=status)
        run.save()
        print(f"Validation {run.report['validation_status']}; report: {output / 'report.json'}", flush=True)
        print("Code review and any required device acceptance remain separate.", flush=True)
    return status


if __name__ == "__main__":
    sys.exit(main())
