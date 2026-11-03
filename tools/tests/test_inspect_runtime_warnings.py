"""Forensic regressions using actual SQLite result-shape fixtures, without Xcode."""

import hashlib
import importlib.util
from contextlib import closing
from pathlib import Path
import sqlite3
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location("inspect_runtime_warnings", Path(__file__).resolve().parents[1] / "inspect_runtime_warnings.py")
inspector = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(inspector)


class RuntimeWarningEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="fruit-runtime-evidence-")
        self.addCleanup(self.temporary.cleanup)
        self.bundle = Path(self.temporary.name) / "result with ? and #.xcresult"
        self.bundle.mkdir()
        self.database = self.bundle / "database.sqlite3"
        with closing(sqlite3.connect(self.database)) as c, c:
            c.executescript("""
                CREATE TABLE TestIssues(issueType TEXT, compactDescription TEXT, timestamp REAL, testCaseRun_fk INTEGER, sourceCodeContext_fk INTEGER);
                CREATE TABLE TestCaseRuns(testCase_fk INTEGER);
                CREATE TABLE TestCases(identifier TEXT, identifierURL TEXT);
                CREATE TABLE SourceCodeContexts(location_fk INTEGER);
                CREATE TABLE SourceCodeFrames(context_fk INTEGER, orderInContainer INTEGER, address TEXT, symbolInfo_fk INTEGER);
                CREATE TABLE SourceCodeSymbolInfos(symbolName TEXT, imageName TEXT, location_fk INTEGER);
                CREATE TABLE SourceCodeLocations(filePath TEXT, lineNumber INTEGER);
                INSERT INTO TestCases VALUES('A/testFirst()', 'test://A/testFirst');
                INSERT INTO TestCases VALUES('B/testSecond()', 'test://B/testSecond');
                INSERT INTO TestCaseRuns VALUES(1);
                INSERT INTO TestCaseRuns VALUES(2);
                INSERT INTO SourceCodeContexts VALUES(NULL);
                INSERT INTO SourceCodeFrames VALUES(1, 1, '4295000004', NULL);
                INSERT INTO SourceCodeFrames VALUES(1, 0, '4295000000', NULL);
                INSERT INTO TestIssues VALUES('Runtime Warning', 'QoS warning', 1234.5, 1, 1);
            """)
        self.summary = {"runtimeWarnings": [{"message": "QoS warning"}]}

    def test_unsymbolicated_addresses_remain_an_ordered_stack_without_false_cause(self):
        result = inspector.inspect(self.bundle, self.summary)
        self.assertEqual(result["warning_count"], 1)
        self.assertEqual(result["raw_frame_count"], 2)
        self.assertEqual(result["warnings_without_frames"], 0)
        warning = result["warnings"][0]
        self.assertEqual(warning["test_identifier"], "A/testFirst()")
        self.assertEqual(warning["stack_status"], "frames_available")
        self.assertEqual(warning["symbolicated_frame_count"], 0)
        self.assertEqual([frame["address"] for frame in warning["frames"]], ['4295000000', '4295000004'])
        self.assertIn("do not establish its root cause", result["interpretation"])

    def test_duplicate_messages_keep_distinct_test_bindings_and_missing_context(self):
        with closing(sqlite3.connect(self.database)) as c, c:
            c.execute("INSERT INTO TestIssues VALUES('Runtime Warning', 'QoS warning', 1234.6, 2, NULL)")
        self.summary["runtimeWarnings"].append({"message": "QoS warning"})
        result = inspector.inspect(self.bundle, self.summary)
        self.assertEqual(result["warning_count"], 2)
        self.assertEqual(result["warnings_without_frames"], 1)
        self.assertEqual([w["test_identifier"] for w in result["warnings"]], ['A/testFirst()', 'B/testSecond()'])
        self.assertEqual(result["warnings"][1]["stack_status"], "no_context")

    def test_frame_symbols_and_source_locations_are_retained_when_available(self):
        with closing(sqlite3.connect(self.database)) as c, c:
            c.execute("INSERT INTO SourceCodeLocations VALUES('/source/test.swift', 42)")
            c.execute("INSERT INTO SourceCodeSymbolInfos VALUES('readAX', 'TestHost', 1)")
            c.execute("UPDATE SourceCodeFrames SET symbolInfo_fk=1 WHERE orderInContainer=0")
        warning = inspector.inspect(self.bundle, self.summary)["warnings"][0]
        self.assertEqual(warning["symbolicated_frame_count"], 1)
        self.assertEqual(warning["frames"][0]["file_path"], '/source/test.swift')
        self.assertEqual(warning["frames"][0]["line"], 42)
        self.assertIsNone(warning["frames"][1]["symbol"])

    def test_summary_count_or_message_mismatch_is_not_silent_success(self):
        for warnings in [[], [{"message": "another warning"}], [{"message": "QoS warning"}] * 2]:
            with self.subTest(warnings=warnings), self.assertRaisesRegex(inspector.EvidenceError, "differ"):
                inspector.inspect(self.bundle, {"runtimeWarnings": warnings})

    def test_missing_database_and_unknown_schema_fail_without_creating_evidence(self):
        missing = self.bundle / "missing"
        with self.assertRaisesRegex(inspector.EvidenceError, "unavailable"):
            inspector.inspect(missing, self.summary)
        self.assertFalse(missing.exists())
        with closing(sqlite3.connect(self.database)) as c, c:
            c.execute("ALTER TABLE SourceCodeFrames RENAME COLUMN address TO unsupportedAddress")
        with self.assertRaisesRegex(inspector.EvidenceError, "database/schema"):
            inspector.inspect(self.bundle, self.summary)

    def test_missing_referenced_context_is_not_reported_as_no_stack(self):
        with closing(sqlite3.connect(self.database)) as c, c:
            c.execute("UPDATE TestIssues SET sourceCodeContext_fk=999")
        with self.assertRaisesRegex(inspector.EvidenceError, "Missing context"):
            inspector.inspect(self.bundle, self.summary)

    def test_nonnull_dangling_test_binding_is_not_reported_as_unbound_warning(self):
        for statement in ["UPDATE TestIssues SET testCaseRun_fk=999", "UPDATE TestCaseRuns SET testCase_fk=999"]:
            with self.subTest(statement=statement):
                with closing(sqlite3.connect(self.database)) as c, c:
                    c.execute("UPDATE TestIssues SET testCaseRun_fk=1")
                    c.execute("UPDATE TestCaseRuns SET testCase_fk=1")
                    c.execute(statement)
                with self.assertRaisesRegex(inspector.EvidenceError, "test binding"):
                    inspector.inspect(self.bundle, self.summary)

    def test_nonnull_dangling_symbol_or_source_is_not_reported_as_unsymbolicated(self):
        with closing(sqlite3.connect(self.database)) as c, c:
            c.execute("INSERT INTO SourceCodeLocations VALUES('/source/test.swift', 42)")
            c.execute("INSERT INTO SourceCodeSymbolInfos VALUES('readAX', 'TestHost', 1)")
        for statement in [
            "UPDATE SourceCodeFrames SET symbolInfo_fk=999 WHERE orderInContainer=0",
            "UPDATE SourceCodeContexts SET location_fk=999",
            "UPDATE SourceCodeSymbolInfos SET location_fk=999",
        ]:
            with self.subTest(statement=statement):
                with closing(sqlite3.connect(self.database)) as c, c:
                    c.execute("UPDATE SourceCodeFrames SET symbolInfo_fk=1 WHERE orderInContainer=0")
                    c.execute("UPDATE SourceCodeContexts SET location_fk=1")
                    c.execute("UPDATE SourceCodeSymbolInfos SET location_fk=1")
                    c.execute(statement)
                with self.assertRaisesRegex(inspector.EvidenceError, "source reference"):
                    inspector.inspect(self.bundle, self.summary)

    def test_zero_warning_result_is_distinct_from_missing_warning_evidence(self):
        with closing(sqlite3.connect(self.database)) as c, c:
            c.execute("DELETE FROM TestIssues")
        self.assertEqual(inspector.inspect(self.bundle, {"runtimeWarnings": []})["warning_count"], 0)
        for payload in [{}, {"runtimeWarnings": None}, {"runtimeWarnings": [{}]}]:
            with self.subTest(payload=payload), self.assertRaises(inspector.EvidenceError):
                inspector.inspect(self.bundle, payload)

    def test_inspection_is_read_only_including_paths_with_uri_special_characters(self):
        before = hashlib.sha256(self.database.read_bytes()).hexdigest()
        files = sorted(p.name for p in self.bundle.iterdir())
        inspector.inspect(self.bundle, self.summary)
        self.assertEqual(hashlib.sha256(self.database.read_bytes()).hexdigest(), before)
        self.assertEqual(sorted(p.name for p in self.bundle.iterdir()), files)


if __name__ == "__main__":
    unittest.main()
