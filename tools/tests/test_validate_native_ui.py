import copy
import importlib.util
from pathlib import Path
import unittest


spec = importlib.util.spec_from_file_location("native_ui", Path(__file__).parents[1] / "validate_native_ui.py")
native_ui = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native_ui)


class NativeUIEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.summary = {"result": "Passed", "totalTestCount": 1, "passedTests": 1, "failedTests": 0,
                        "skippedTests": 0, "expectedFailures": 0}
        self.case = {"nodeType": "Test Case", "nodeIdentifier": native_ui.CASE_ID,
                     "nodeIdentifierURL": native_ui.CASE_URL, "result": "Passed"}
        self.tree = {"testNodes": [{"children": [self.case]}]}

    def test_requires_actual_critical_case_in_correct_target(self):
        self.assertTrue(native_ui.evidence_passed(0, self.summary, self.tree))
        self.case["nodeIdentifierURL"] = native_ui.CASE_URL.replace("FruitTreeScannerUITests", "OtherTests")
        self.assertFalse(native_ui.evidence_passed(0, self.summary, self.tree))
        self.case["nodeIdentifierURL"] = native_ui.CASE_URL
        self.case["nodeIdentifier"] = "OtherTests/" + native_ui.METHOD + "()"
        self.assertFalse(native_ui.evidence_passed(0, self.summary, self.tree))

    def test_rejects_failure_even_with_passed_summary(self):
        self.assertFalse(native_ui.evidence_passed(65, self.summary, self.tree))
        self.case["result"] = "Failed"
        self.assertFalse(native_ui.evidence_passed(0, self.summary, self.tree))

    def test_requires_explicit_zero_failure_counts_and_executions(self):
        for key in ("failedTests", "skippedTests", "expectedFailures"):
            for value in (None, True, 1, "0"):
                summary = copy.copy(self.summary)
                summary[key] = value
                self.assertFalse(native_ui.evidence_passed(0, summary, self.tree))
            summary = copy.copy(self.summary)
            del summary[key]
            self.assertFalse(native_ui.evidence_passed(0, summary, self.tree))
        self.summary["passedTests"] = 0
        self.assertFalse(native_ui.evidence_passed(0, self.summary, self.tree))

    def test_requires_complete_execution_count(self):
        self.summary["totalTestCount"] = 2
        self.assertFalse(native_ui.evidence_passed(0, self.summary, self.tree))
        del self.summary["totalTestCount"]
        self.assertFalse(native_ui.evidence_passed(0, self.summary, self.tree))


if __name__ == "__main__":
    unittest.main()
