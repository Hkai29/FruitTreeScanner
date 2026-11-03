#!/usr/bin/env python3
"""用 Codex 的原始反例夹具复跑门禁（修复前 → 修复后）。

夹具来自 codex-minimax-review-20261025/：
  - valid.json                       合法样例，必须放行
  - missing_counters.json            缺三项计数字段，必须拦下
  - publishing_warning.json          含阻塞级 SwiftUI 警告，必须拦下
  - fixture-bin/xcrun                明确隔离的 stub：正摘要 + 空结果树，必须拦下
    （它不是一次真实 XCTest，也没有改动产品工具）

跑法：python3 tools/tests/replay_review_counterexamples.py
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

REPO = Path(__file__).resolve().parents[2]
GATE = REPO / "tools" / "xctest_gate.py"
DEFAULT_REVIEW = Path("/Users/reece24/Library/Logs/FruitTreeScanner/codex-minimax-review-20261025")
REVIEW = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_REVIEW
if not REVIEW.is_dir():
    print(f"review fixtures not found: {REVIEW}", file=sys.stderr)
    raise SystemExit(2)


def run_summary_payload(payload_path):
    """把一份摘要 JSON 交给共享判定的摘要入口。"""
    sys.path.insert(0, str(REPO / "tools"))
    import importlib.util

    spec = importlib.util.spec_from_file_location("xctest_gate", GATE)
    gate = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gate)
    with open(payload_path, "r", encoding="utf-8") as handle:
        payload = json.load(handle)
    try:
        gate.validate_summary(payload)
    except gate.GateFailure as error:
        return 1, str(error)
    return 0, "passed"


def run_stub_bundle():
    """用 Codex 的 xcrun stub（正摘要 + 空结果树）跑完整门禁命令行。"""
    with tempfile.TemporaryDirectory() as directory:
        stub_dir = Path(directory) / "bin"
        stub_dir.mkdir()
        stub = stub_dir / "xcrun"
        stub.write_text((REVIEW / "fixture-bin" / "xcrun").read_text())
        stub.chmod(0o755)
        bundle = Path(directory) / "tests.xcresult"
        bundle.mkdir()
        repo = Path(directory) / "repo"
        (repo / "FruitTreeScannerTests").mkdir(parents=True)
        (repo / "FruitTreeScannerTests" / "Sample.swift").write_text(
            "final class ArchiveGateTests: XCTestCase {}\n"
        )
        environment = dict(os.environ)
        environment["PATH"] = str(stub_dir) + os.pathsep + environment["PATH"]
        result = subprocess.run(
            [sys.executable, str(GATE), str(bundle), "--repo", str(repo)],
            capture_output=True, text=True, env=environment,
        )
        return result.returncode, (result.stderr or result.stdout).strip()


def main():
    cases = [
        ("valid", REVIEW / "valid.json", 0, "合法样例"),
        ("missing_counters", REVIEW / "missing_counters.json", 1, "缺计数字段"),
        ("publishing_warning", REVIEW / "publishing_warning.json", 1, "阻塞级 SwiftUI 警告"),
    ]
    failures = []
    for name, path, expected, why in cases:
        code, detail = run_summary_payload(path)
        status = "OK " if code == expected else "FAIL"
        print(f"{status} {name:<22} exit={code} (期望 {expected}) — {why}")
        if code != expected:
            failures.append((name, code, expected, detail))
    code, detail = run_stub_bundle()
    status = "OK " if code != 0 else "FAIL"
    print(f"{status} summary_positive_but_empty_result_tree  exit={code} (期望非 0) — 正摘要配空结果树")
    if code == 0:
        failures.append(("summary_positive_but_empty_result_tree", code, "non-zero", detail))
    if failures:
        print("\n反例仍被放行：")
        for item in failures:
            print("  ", item)
        return 1
    print("\n四个反例全部按预期判定（合法放行，其余拦下）。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
