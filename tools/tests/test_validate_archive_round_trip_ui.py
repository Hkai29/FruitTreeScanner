import ast
import copy
import hashlib
import importlib.util
import os
from pathlib import Path
import stat
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).parents[1]))

RUNNER_PATH = Path(__file__).parents[1] / "validate_archive_round_trip_ui.py"
RUNNER_SOURCE = RUNNER_PATH.read_text()

spec = importlib.util.spec_from_file_location(
    "archive_roundtrip_ui", RUNNER_PATH)
archive_roundtrip_ui = importlib.util.module_from_spec(spec)
spec.loader.exec_module(archive_roundtrip_ui)


class ArchiveRoundTripUIEvidenceTests(unittest.TestCase):
    """运行器自己的门禁必须有反例覆盖：漏判一条用例就不能算通过。"""

    def setUp(self):
        self.expected = {archive_roundtrip_ui.TEST_CLASS + "/" + method + "()"
                         for method in archive_roundtrip_ui.METHODS}
        # 摘要必须与**本次期望的用例集合**自洽：METHODS 有几条，正例就得跑了几条。
        # 写死一个数字（例如 2）会让正例在 METHODS 增长后悄悄失去意义。
        count = len(self.expected)
        self.summary = {"result": "Passed", "totalTestCount": count, "passedTests": count,
                        "failedTests": 0, "skippedTests": 0, "expectedFailures": 0}
        self.tree = {"testNodes": [{"children": [
            {"nodeType": "Test Case", "nodeIdentifier": case_id, "result": "Passed"}
            for case_id in sorted(self.expected)]}]}

    def test_accepts_a_clean_run(self):
        self.assertTrue(archive_roundtrip_ui.evidence_passed(
            0, self.summary, self.tree, self.expected))

    def test_rejects_renamed_case(self):
        tree = copy.deepcopy(self.tree)
        tree["testNodes"][0]["children"][0]["nodeIdentifier"] = "OtherTests/renamed()"
        self.assertFalse(archive_roundtrip_ui.evidence_passed(
            0, self.summary, tree, self.expected))

    def test_rejects_missing_case(self):
        tree = copy.deepcopy(self.tree)
        tree["testNodes"][0]["children"] = tree["testNodes"][0]["children"][:1]
        self.assertFalse(archive_roundtrip_ui.evidence_passed(
            0, self.summary, tree, self.expected))

    def test_rejects_failed_or_skipped_case(self):
        for result in ("Failed", "Skipped", "Expected Failure"):
            tree = copy.deepcopy(self.tree)
            tree["testNodes"][0]["children"][0]["result"] = result
            self.assertFalse(archive_roundtrip_ui.evidence_passed(
                0, self.summary, tree, self.expected), result)

    def test_rejects_non_zero_exit_code(self):
        self.assertFalse(archive_roundtrip_ui.evidence_passed(
            65, self.summary, self.tree, self.expected))

    def test_requires_explicit_zero_failure_counts(self):
        for key in ("failedTests", "skippedTests", "expectedFailures"):
            for value in (None, True, 1, "0"):
                summary = copy.deepcopy(self.summary)
                summary[key] = value
                self.assertFalse(archive_roundtrip_ui.evidence_passed(
                    0, summary, self.tree, self.expected), key)
            summary = copy.deepcopy(self.summary)
            del summary[key]
            self.assertFalse(archive_roundtrip_ui.evidence_passed(
                0, summary, self.tree, self.expected), key)

    def test_requires_complete_execution_count(self):
        # 计数必须与本次期望的用例集合一致：多、少都不算这次运行的证据。
        for count in (len(self.expected) + 1, len(self.expected) - 1):
            summary = copy.deepcopy(self.summary)
            summary["totalTestCount"] = count
            summary["passedTests"] = count
            self.assertFalse(archive_roundtrip_ui.evidence_passed(
                0, summary, self.tree, self.expected), count)
        summary = copy.deepcopy(self.summary)
        del summary["totalTestCount"]
        self.assertFalse(archive_roundtrip_ui.evidence_passed(
            0, summary, self.tree, self.expected))
        summary = copy.deepcopy(self.summary)
        summary["passedTests"] = 0
        self.assertFalse(archive_roundtrip_ui.evidence_passed(
            0, summary, self.tree, self.expected))

    def test_requires_passed_result(self):
        summary = copy.deepcopy(self.summary)
        summary["result"] = "Failed"
        self.assertFalse(archive_roundtrip_ui.evidence_passed(
            0, summary, self.tree, self.expected))

    def test_case_result_reads_the_result_tree(self):
        self.assertEqual(
            archive_roundtrip_ui.case_result(self.tree, sorted(self.expected)[0]), "Passed")
        self.assertIsNone(archive_roundtrip_ui.case_result(self.tree, "Missing/case()"))

    def test_fixture_covers_the_same_tree_twice_and_more_than_one_plot(self):
        """夹具必须覆盖 main 真正播种的那一份。

        夹具工厂是 ``fixture_archives()``：今天/昨天的时间戳只能在**播种那一刻**
        算出来，所以静态常量做不到。这里的断言钉的是 main 实际使用的那个工厂，
        不是另一个没人用的常量。
        """
        archives, today_stamp, yesterday_stamp = archive_roundtrip_ui.fixture_archives()
        trees = [entry[1] for entry in archives]
        plots = {entry[2] for entry in archives}
        self.assertGreaterEqual(len(plots), 2, "夹具必须至少有两个地块")
        self.assertGreater(len(trees), len(set(trees)), "夹具必须有一棵树的两次扫描")
        self.assertEqual(
            [entry[0] for entry in archives if entry[0] == archive_roundtrip_ui.TARGET],
            [archive_roundtrip_ui.TARGET])
        self.assertTrue(any(not entry[4] for entry in archives),
                        "夹具必须有一份没有结果文件的存档（降级成不可用）")
        # 同一棵树的两份必须是「目标」和「同树的另一份」这一对，缺一恢复位置就证明不了。
        same_tree = sorted(entry[0] for entry in archives
                           if entry[1] == archive_roundtrip_ui.TARGET_TREE)
        self.assertEqual(same_tree, sorted([archive_roundtrip_ui.TARGET,
                                             archive_roundtrip_ui.SAME_TREE_OTHER]))
        # 今天/昨天各至少一份，否则日期分组那一段证明不了任何东西。
        self.assertTrue(any(today_stamp in entry[0] for entry in archives),
                        "夹具必须有一份今天的扫描")
        self.assertTrue(any(yesterday_stamp in entry[0] for entry in archives),
                        "夹具必须有一份昨天的扫描")

    def test_broad_query_counts_match_the_seeded_fixture(self):
        """宽查询的份数必须真的数自这份夹具 —— UI 用例就是拿它断言组标题的。"""
        archives, today_stamp, yesterday_stamp = archive_roundtrip_ui.fixture_archives()
        counts = archive_roundtrip_ui.broad_query_counts(
            archives, today_stamp, yesterday_stamp, archive_roundtrip_ui.BROAD_QUERY)
        hits = [entry for entry in archives
                if archive_roundtrip_ui.BROAD_QUERY in entry[0]
                and entry[2] == archive_roundtrip_ui.PLOT]
        self.assertGreater(len(hits), 1, "宽查询必须命中多条，否则分组证明不了什么")
        self.assertEqual(counts["today"] + counts["yesterday"] + counts["earlier"], len(hits))
        self.assertGreater(counts["today"], 0, "宽查询必须命中今天的分组")
        self.assertGreater(counts["yesterday"], 0, "宽查询必须命中昨天的分组")

    def test_main_seeds_the_fixture_factory_under_test(self):
        """main 必须调用被测试的这几个夹具工厂，不能另走一条旁路。"""
        tree = ast.parse(RUNNER_SOURCE)
        main = next(node for node in tree.body
                    if isinstance(node, ast.FunctionDef) and node.name == "main")
        for helper in ("fixture_archives", "broad_query_counts"):
            calls = [node for node in ast.walk(main)
                     if isinstance(node, ast.Call)
                     and isinstance(node.func, ast.Name)
                     and node.func.id == helper]
            self.assertEqual(len(calls), 1,
                             "main 必须且只能调用一次 %s()" % helper)

    def test_broad_query_spans_month_and_year_boundaries(self):
        for stamps in (("20261103_090000", "20261102_090000"),
                       ("20270101_090000", "20261231_090000")):
            with self.subTest(stamps=stamps), mock.patch.object(
                    archive_roundtrip_ui, "fixture_day_stamps", return_value=stamps):
                archives, today, yesterday = archive_roundtrip_ui.fixture_archives()
                query = archive_roundtrip_ui.BROAD_QUERY
                counts = archive_roundtrip_ui.broad_query_counts(
                    archives, today, yesterday, query)
                self.assertEqual(counts["today"], 2)
                self.assertEqual(counts["yesterday"], 1)
                self.assertGreater(counts["earlier"], 1)
                self.assertIn(query, archive_roundtrip_ui.TARGET)
                self.assertNotIn(query, archive_roundtrip_ui.SAME_TREE_OTHER,
                                 "宽查询也必须排除一份同树档案，不能退化成全部命中")


class SeededArchivePreservationTests(unittest.TestCase):
    """原档保留门禁的反例覆盖。

    Codex 第 17 轮复核证明：旧判定只比较「仍然存在的同名文件」的摘要，
    被播种文件被删除后 ``archive_preserved`` 仍然是 true、``result`` 仍然是
    passed。这些用例把「少一份 / 全删 / 字节改变 / 读不出来 / 允许旁路新增」
    全部钉成会失败。
    """

    ORIGINALS = {
        "a.ply": b"original-a",
        "a_result.json": b"original-b",
    }

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="archive-preservation-test-")
        self.scans = Path(self.directory.name)
        self.addCleanup(self.directory.cleanup)
        self.source_hashes = {
            name: hashlib.sha256(data).hexdigest() for name, data in self.ORIGINALS.items()}
        for name, data in self.ORIGINALS.items():
            (self.scans / name).write_bytes(data)

    def tearDown(self):
        # A deliberately unreadable file must not block the cleanup.
        if not self.scans.is_dir():
            return
        for path in self.scans.iterdir():
            try:
                path.chmod(stat.S_IRUSR | stat.S_IWUSR)
            except OSError:
                pass

    def test_intact_archives_are_preserved(self):
        report = archive_roundtrip_ui.inspect_seeded_archives(self.scans, self.source_hashes)
        self.assertTrue(report["archive_preserved"], report)
        self.assertEqual(report["archive_files_removed"], [])
        self.assertEqual(report["archive_files_changed"], [])
        self.assertEqual(report["archive_files_unreadable"], [])
        self.assertEqual(report["archive_files_added_by_app"], [])
        self.assertEqual(report["archive_preservation_failure"], "")

    def test_a_single_removed_archive_fails_the_gate(self):
        (self.scans / "a_result.json").unlink()
        report = archive_roundtrip_ui.inspect_seeded_archives(self.scans, self.source_hashes)
        self.assertFalse(report["archive_preserved"], report)
        self.assertEqual(report["archive_files_removed"], ["a_result.json"])
        self.assertIn("removed=", report["archive_preservation_failure"])

    def test_all_removed_archives_fail_the_gate(self):
        for name in self.ORIGINALS:
            (self.scans / name).unlink()
        report = archive_roundtrip_ui.inspect_seeded_archives(self.scans, self.source_hashes)
        self.assertFalse(report["archive_preserved"], report)
        self.assertEqual(report["archive_files_removed"], ["a.ply", "a_result.json"])

    def test_changed_bytes_fail_the_gate(self):
        (self.scans / "a.ply").write_bytes(b"changed")
        report = archive_roundtrip_ui.inspect_seeded_archives(self.scans, self.source_hashes)
        self.assertFalse(report["archive_preserved"], report)
        self.assertEqual(report["archive_files_changed"], ["a.ply"])
        self.assertIn("changed=", report["archive_preservation_failure"])

    def test_an_unreadable_archive_fails_the_gate(self):
        target = self.scans / "a.ply"
        target.chmod(0)
        if os.access(target, os.R_OK):
            self.skipTest("This process can read a chmod-0 file; the unreadable case cannot be shown")
        report = archive_roundtrip_ui.inspect_seeded_archives(self.scans, self.source_hashes)
        self.assertFalse(report["archive_preserved"], report)
        self.assertEqual(report["archive_files_unreadable"], ["a.ply"])

    def test_a_missing_scans_directory_fails_the_gate(self):
        for path in self.scans.iterdir():
            path.unlink()
        self.scans.rmdir()
        report = archive_roundtrip_ui.inspect_seeded_archives(self.scans, self.source_hashes)
        self.assertFalse(report["archive_preserved"], report)
        self.assertEqual(report["archive_files_removed"], ["a.ply", "a_result.json"])

    def test_an_empty_seed_map_proves_nothing(self):
        report = archive_roundtrip_ui.inspect_seeded_archives(self.scans, {})
        self.assertFalse(report["archive_preserved"], report)

    def test_app_created_files_stay_allowed_and_are_reported_separately(self):
        (self.scans / "added.json").write_bytes(b"new")
        report = archive_roundtrip_ui.inspect_seeded_archives(self.scans, self.source_hashes)
        self.assertTrue(report["archive_preserved"], report)
        self.assertEqual(report["archive_files_added_by_app"], ["added.json"])
        self.assertEqual(report["archive_files_removed"], [])

    def test_verify_raises_on_a_removed_archive(self):
        (self.scans / "a.ply").unlink()
        with self.assertRaises(archive_roundtrip_ui.SeededArchiveLost) as caught:
            archive_roundtrip_ui.verify_seeded_archives(self.scans, self.source_hashes)
        self.assertFalse(caught.exception.report["archive_preserved"])
        self.assertEqual(caught.exception.report["archive_files_removed"], ["a.ply"])

    def test_apply_verdict_marks_the_report_failed_on_a_removed_archive(self):
        (self.scans / "a.ply").unlink()
        report = {"result": "passed", "archive_preserved": True}
        with self.assertRaises(archive_roundtrip_ui.SeededArchiveLost):
            archive_roundtrip_ui.apply_preservation_verdict(report, self.scans, self.source_hashes)
        self.assertFalse(report["archive_preserved"], report)
        self.assertEqual(report["result"], "failed", report)
        self.assertEqual(report["archive_files_removed"], ["a.ply"])

    def test_apply_verdict_keeps_a_clean_report_passed(self):
        report = {"result": "passed"}
        archive_roundtrip_ui.apply_preservation_verdict(report, self.scans, self.source_hashes)
        self.assertTrue(report["archive_preserved"], report)
        self.assertEqual(report["result"], "passed", report)

    def test_the_runner_calls_the_checked_gate(self):
        """main 必须调用被测试的这道门禁，不能另走一条旁路 helper。

        用 **AST** 判定，不是文本搜索：把这行字符串写进注释里骗不过去。
        """
        tree = ast.parse(RUNNER_SOURCE)
        main = next(node for node in tree.body
                    if isinstance(node, ast.FunctionDef) and node.name == "main")
        calls = [node for node in ast.walk(main)
                 if isinstance(node, ast.Call)
                 and isinstance(node.func, ast.Name)
                 and node.func.id == "apply_preservation_verdict"]
        self.assertEqual(len(calls), 1, "main 必须且只能调用一次被测门禁")
        self.assertEqual([ast.unparse(argument) for argument in calls[0].args],
                         ["report", "scans", "source_hashes"])

        # 写 result="passed" 的语句必须唯一，并且排在门禁判定之后。
        passed_writes = [node.lineno for node in ast.walk(main)
                         if isinstance(node, ast.Assign)
                         and isinstance(node.value, ast.Constant)
                         and node.value.value == "passed"
                         and any(isinstance(target, ast.Subscript)
                                 and isinstance(target.slice, ast.Constant)
                                 and target.slice.value == "result"
                                 for target in node.targets)]
        self.assertEqual(len(passed_writes), 1, "main 里只能有一处写入 result='passed'")
        self.assertLess(calls[0].lineno, passed_writes[0],
                        "写 result='passed' 必须发生在门禁判定之后")

    def test_the_gates_do_not_rely_on_assert_statements(self):
        """``python -O`` / ``PYTHONOPTIMIZE=1`` 会抹掉 assert，门禁不能靠它。"""
        tree = ast.parse(RUNNER_SOURCE)
        asserts = [node.lineno for node in ast.walk(tree) if isinstance(node, ast.Assert)]
        self.assertEqual(asserts, [], "门禁不能用 assert 表达：优化模式会把它抹掉")

    def test_require_fails_loudly(self):
        with self.assertRaises(AssertionError):
            archive_roundtrip_ui.require(False, "the gate must fail")
        archive_roundtrip_ui.require(True, "the gate must pass")


if __name__ == "__main__":
    unittest.main()
