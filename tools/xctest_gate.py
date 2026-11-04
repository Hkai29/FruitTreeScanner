#!/usr/bin/env python3
"""FruitTreeScanner · XCTest 结果判定的**共享实现**。

仓库里只保留一份判定逻辑：本地全量关卡（`code_improvement_workflow.py`）与
CI 门禁（`ci_xctest_gate.sh`）都从这里取，避免出现第二套更宽松的门槛。

判定条件（与既有 workflow 严格规则一致，不放宽）：

* 计数字段必须是非负 ``int``（``bool`` 不算 ``int``），缺一个字段即失败；
* ``result == "Passed"``、``passedTests > 0``、``totalTestCount == passedTests``；
* ``failedTests`` / ``skippedTests`` / ``expectedFailures`` 必须为 0（**零跳过**）；
* ``runtimeWarnings`` 必须是 ``list[dict]`` 且每条 ``message`` 是字符串；
* 「Publishing changes from within view updates is not allowed」是**阻塞警告**，命中即失败；
  其余警告（例如 QoS 优先级倒置）保留并打印，由复审判断，不静默吞掉；
* 结果树里每个**声明的**测试类都要有真实通过的用例，缺类 / 错 bundle / 空树都失败；
* 多 run 或摘要与结果树不一致时失败：证明不了就不放行。

命令行：

    python3 tools/xctest_gate.py <tests.xcresult> [--repo <path>]

退出码：0 = 通过；1 = 判定失败；2 = 证据读不到 / 解析不了。
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

BLOCKING_WARNING_MARKERS = (
    "Publishing changes from within view updates is not allowed",
)
COUNT_FIELDS = ("totalTestCount", "passedTests", "failedTests", "skippedTests", "expectedFailures")
TEST_BUNDLE = "FruitTreeScannerTests"


class GateFailure(Exception):
    """判定失败。exit_code 用于把失败状态原样传给调用方。"""

    def __init__(self, message, exit_code=1):
        super().__init__(message)
        self.exit_code = exit_code if 0 < exit_code < 126 else 1


# ───────────────────────────── 摘要判定 ─────────────────────────────


def _summary_runs(summary):
    """只接受**单次运行**的扁平摘要。

    真实的 ``xcresulttool get test-results summary`` 永远不产出 ``testRuns``（24/24 份
    真实证据都没有这个键）；出现它就说明载荷形状不可预期 —— 一律拒绝，
    不用「取第一个 run」去绕过顶层计数。
    """
    if not isinstance(summary, dict):
        raise GateFailure("Invalid XCTest summary: payload is not an object.")
    if "testRuns" in summary:
        raise GateFailure(
            "Invalid XCTest summary: multiple test runs in one payload are not accepted; "
            "run one configuration at a time."
        )
    return [summary]


def validate_summary(summary):
    """严格判定结果摘要。字段缺失、类型不对、计数不自洽都算失败。"""
    for run in _summary_runs(summary):
        if not isinstance(run, dict):
            raise GateFailure("Invalid XCTest summary: test run is not an object.")
        for key in COUNT_FIELDS:
            value = run.get(key)
            if type(value) is not int or value < 0:
                raise GateFailure(f"Invalid XCTest summary: missing or invalid count '{key}'.")
        if (run.get("result") != "Passed"
                or run["passedTests"] == 0
                or run["totalTestCount"] != run["passedTests"]
                or any(run[key] for key in ("failedTests", "skippedTests", "expectedFailures"))):
            raise GateFailure(
                "XCTest gate incomplete: requires executed passing tests with no failures or skips."
            )
        if "runtimeWarnings" not in run:
            raise GateFailure("Invalid XCTest runtime warnings: cannot inspect warning evidence.")
        warnings = run["runtimeWarnings"]
        if not isinstance(warnings, list) or any(
            not isinstance(warning, dict) or not isinstance(warning.get("message"), str)
            for warning in warnings
        ):
            raise GateFailure("Invalid XCTest runtime warnings: cannot inspect warning evidence.")
        for warning in warnings:
            if any(marker in warning["message"] for marker in BLOCKING_WARNING_MARKERS):
                raise GateFailure("Unsafe SwiftUI runtime warning: " + warning["message"])


# ───────────────────────────── 结果树判定 ─────────────────────────────


def declared_test_classes(repo_root):
    """仓库里声明的 XCTest 类（按 ``class X: XCTestCase`` 扫描）。"""
    repo_root = Path(repo_root)
    declared = set()
    for source in sorted((repo_root / "FruitTreeScannerTests").rglob("*.swift")):
        declared.update(re.findall(r"\bclass\s+(\w+)\s*:\s*XCTestCase\b", source.read_text()))
    return declared


def validate_test_tree(tree, expected):
    """结果树里每个要求的测试类都要有真实通过的用例。

    返回 (执行到的类, 通过的用例数) —— 调用方要拿它和摘要里的 passedTests 对账。
    树里自己带的 ``Runtime Warning`` 节点也会被检查：摘要干净但树上挂着阻塞警告，
    不能算通过。
    """
    if not isinstance(tree, dict) or not isinstance(tree.get("testNodes"), list):
        raise GateFailure("Invalid XCTest test tree.")
    if not expected:
        raise GateFailure("Invalid XCTest test tree: no required test classes were declared.")
    executed = set()
    passed_cases = 0
    stack = [(node, None, None) for node in tree["testNodes"]]
    while stack:
        node, bundle, suite = stack.pop()
        if (not isinstance(node, dict)
                or not isinstance(node.get("nodeType"), str)
                or not isinstance(node.get("name"), str)):
            raise GateFailure("Invalid XCTest node.")
        node_type = node.get("nodeType")
        if node_type == "Unit test bundle":
            bundle = node.get("name")
        if node_type == "Test Suite":
            suite = node.get("name", "").rsplit(".", 1)[-1]
        if node_type == "Runtime Warning":
            message = node.get("name", "")
            if any(marker in message for marker in BLOCKING_WARNING_MARKERS):
                raise GateFailure("Unsafe SwiftUI runtime warning: " + message)
        if (node_type == "Test Case" and node.get("result") == "Passed"
                and bundle == TEST_BUNDLE):
            passed_cases += 1
            if suite in expected:
                executed.add(suite)
        children = node.get("children", [])
        if not isinstance(children, list):
            raise GateFailure("Invalid XCTest children.")
        stack.extend((child, bundle, suite) for child in children)
    missing = set(expected) - executed
    if missing:
        raise GateFailure(
            "Required XCTest classes did not execute passing cases: " + ", ".join(sorted(missing))
        )
    return sorted(executed), passed_cases


# ───────────────────────────── 结果包判定 ─────────────────────────────


def _xcresulttool(*args):
    command = ["xcrun", "xcresulttool", *args]
    environment = dict(os.environ)
    reader_directory = environment.get("FTS_XCRESULT_DEVELOPER_DIR")
    if reader_directory is not None:
        if not reader_directory.strip():
            raise GateFailure("FTS_XCRESULT_DEVELOPER_DIR must name a result reader toolchain.", 2)
        # A newer official result reader may expose fields absent from the
        # compiling Xcode's API. Only this child uses it; compilation stays put.
        environment["DEVELOPER_DIR"] = reader_directory
    result = subprocess.run(command, capture_output=True, text=True, env=environment)
    if result.returncode != 0:
        raise GateFailure(
            "Cannot read XCTest evidence via xcresulttool: "
            + (result.stderr or result.stdout).strip(),
            result.returncode or 2,
        )
    return result.stdout


def _load_json(payload, what):
    try:
        return json.loads(payload)
    except Exception as error:  # noqa: BLE001 - 解析不了就判失败
        raise GateFailure(f"Cannot parse XCTest {what}: {error}", 2)


def check_result_bundle(bundle_path, expected_classes):
    """读结果包并同时判定摘要与结果树。返回一份可留存的报告。"""
    bundle_path = Path(bundle_path)
    if not bundle_path.is_dir():
        raise GateFailure(f"XCTest result bundle not found: {bundle_path}", 2)
    summary = _load_json(
        _xcresulttool("get", "test-results", "summary", "--path", str(bundle_path), "--format", "json"),
        "summary",
    )
    tree = _load_json(
        _xcresulttool("get", "test-results", "tests", "--path", str(bundle_path), "--format", "json"),
        "test tree",
    )
    validate_summary(summary)
    executed, passed_cases = validate_test_tree(tree, set(expected_classes))
    run = _summary_runs(summary)[0]
    counts = {key: run[key] for key in COUNT_FIELDS}
    if counts["passedTests"] != passed_cases:
        raise GateFailure(
            "XCTest summary and result tree disagree: summary reports "
            f"{counts['passedTests']} passed tests, the tree contains {passed_cases}."
        )
    return {
        "bundle": str(bundle_path),
        "executedTestClasses": executed,
        "declaredTestClasses": sorted(expected_classes),
        "runtimeWarnings": run["runtimeWarnings"],
        "counts": counts,
        "result": run["result"],
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description="FruitTreeScanner XCTest gate")
    parser.add_argument("bundle", help="path to tests.xcresult")
    parser.add_argument("--repo", default=str(Path(__file__).resolve().parents[1]),
                        help="repository root (default: the repository this tool lives in)")
    args = parser.parse_args(argv)
    try:
        expected = declared_test_classes(args.repo)
        if not expected:
            raise GateFailure("No XCTest classes declared in the repository.", 2)
        report = check_result_bundle(args.bundle, expected)
    except GateFailure as error:
        print(f"XCTest gate FAILED: {error}", file=sys.stderr)
        return error.exit_code
    except Exception as error:  # noqa: BLE001 - 证据读不出来就不放行
        print(f"XCTest gate FAILED: cannot evaluate the result bundle: {error}", file=sys.stderr)
        return 2
    counts = report["counts"]
    print(
        "total={totalTestCount} passed={passedTests} failed={failedTests} "
        "skipped={skippedTests} result='{result}'".format(result=report["result"], **counts)
    )
    print(f"declared test classes: {len(report['declaredTestClasses'])}, "
          f"executed with passing cases: {len(report['executedTestClasses'])}")
    if report["runtimeWarnings"]:
        print(f"runtimeWarnings: {len(report['runtimeWarnings'])} (kept for review)")
        for warning in report["runtimeWarnings"]:
            message = warning.get("message", "") if isinstance(warning, dict) else str(warning)
            print("  - " + message[:200])
    print("XCTest gate passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
