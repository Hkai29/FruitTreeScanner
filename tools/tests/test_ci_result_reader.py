"""Reader selection must rely on retained schema evidence, not Xcode names."""

import copy
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock


spec = importlib.util.spec_from_file_location(
    "ci_result_reader", Path(__file__).resolve().parents[1] / "ci_result_reader.py")
reader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reader)


SCHEMA = {"schemas": {
    "Summary": {"type": "object", "required": ["runtimeWarnings"], "properties": {
        "runtimeWarnings": {"type": "array", "items": {"$ref": "#/schemas/Issue"}}}},
    "Issue": {"type": "object", "required": ["message"], "properties": {"message": {"type": "string"}}},
}}


class CIResultReaderTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="result-reader-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.compiler = str(self.root / "Xcode_16.4.app/Contents/Developer")
        self.capable = str(self.root / "Xcode_26.3.app/Contents/Developer")
        self.calls = []

    def fake_command(self, outcomes):
        def command(run, name, argv, log, stderr=None, developer_dir=None):
            self.calls.append({"name": name, "argv": argv, "developer_dir": developer_dir,
                               "parent_developer_dir": os.environ.get("DEVELOPER_DIR")})
            status, stdout, errors = outcomes[developer_dir]
            (run / log).write_text(stdout if isinstance(stdout, str) else json.dumps(stdout))
            (run / stderr).write_text(errors)
            return status
        return command

    def read_manifest(self, run=None):
        return json.loads(((run or self.root) / "reader-selection.json").read_text())

    def test_automatic_selection_probes_compiler_then_chooses_capable_reader(self):
        old_schema = copy.deepcopy(SCHEMA)
        old_schema["schemas"]["Summary"]["required"] = []
        outcomes = {self.compiler: (0, old_schema, "old reader diagnostic"), self.capable: (0, SCHEMA, "")}
        with mock.patch.dict(os.environ, {"DEVELOPER_DIR": self.compiler}):
            selected = reader.select_reader(self.root, self.compiler, None, False,
                                            self.fake_command(outcomes), candidates=[self.capable])
            self.assertEqual(os.environ["DEVELOPER_DIR"], self.compiler)
        self.assertEqual(selected["developer_dir"], self.capable)
        self.assertEqual(selected["manifest"], self.read_manifest())
        self.assertEqual([call["developer_dir"] for call in self.calls], [self.compiler, self.capable])
        self.assertEqual({call["parent_developer_dir"] for call in self.calls}, {self.compiler})
        self.assertTrue(all(call["argv"] == ["xcrun", "xcresulttool", "get", "test-results", "summary", "--schema"]
                            for call in self.calls))
        first, second = selected["manifest"]["probes"]
        self.assertEqual(first["exit_code"], 0)
        self.assertFalse(first["supported"])
        self.assertIn("not required", first["rejection_reason"])
        self.assertEqual((self.root / first["stderr"]).read_text(), "old reader diagnostic")
        self.assertEqual(json.loads((self.root / first["stdout"]).read_text()), old_schema)
        self.assertTrue(second["supported"])

    def test_capable_compiler_is_preferred_and_duplicate_directories_are_skipped(self):
        old = {self.compiler: (3, "", "old reader unsupported"), self.capable: (0, SCHEMA, "")}
        outcome = reader.select_reader(self.root, self.compiler, None, False, self.fake_command(old),
                                       candidates=[self.compiler + "/", self.capable, self.capable + "/"])
        self.assertEqual(outcome["developer_dir"], self.capable)
        self.assertEqual(len(self.calls), 2)
        run = self.root / "compiler-first"
        run.mkdir()
        first = reader.select_reader(run, self.compiler, None, False,
            self.fake_command({self.compiler: (0, SCHEMA, "")}), candidates=[self.capable])
        self.assertEqual(first["developer_dir"], self.compiler)
        self.assertEqual(len(first["manifest"]["probes"]), 1)

    def test_explicit_old_or_failed_reader_never_tries_the_alternative(self):
        for index, outcome in enumerate(((0, {"schemas": {}}, ""), (72, "", "reader unavailable"))):
            with self.subTest(outcome=outcome):
                run = self.root / str(index)
                run.mkdir()
                self.calls.clear()
                with self.assertRaisesRegex(ValueError, "Explicit result reader"):
                    reader.select_reader(run, self.compiler, self.compiler, True,
                        self.fake_command({self.compiler: outcome, self.capable: (0, SCHEMA, "")}),
                        candidates=[self.capable])
                self.assertEqual([call["developer_dir"] for call in self.calls], [self.compiler])
                manifest = self.read_manifest(run)
                self.assertEqual(manifest["status"], "failed")
                self.assertIsNone(manifest["developer_dir"])
                self.assertEqual(manifest["probes"][0]["exit_code"], outcome[0])

    def test_explicit_empty_override_is_not_automatic_discovery(self):
        with self.assertRaisesRegex(ValueError, "Explicit FTS_XCRESULT_DEVELOPER_DIR"):
            reader.select_reader(self.root, self.compiler, "", True,
                                 self.fake_command({}), candidates=[self.capable])
        self.assertEqual(self.calls, [])
        self.assertEqual(self.read_manifest()["status"], "failed")

    def test_automatic_selection_without_capable_tool_fails_with_all_evidence(self):
        failures = {self.compiler: (64, "", "unknown option --schema"), self.capable: (0, "{", "")}
        with self.assertRaisesRegex(ValueError, "No installed result reader"):
            reader.select_reader(self.root, self.compiler, None, False,
                                 self.fake_command(failures), candidates=[self.capable])
        manifest = self.read_manifest()
        self.assertEqual(manifest["status"], "failed")
        self.assertEqual([item["exit_code"] for item in manifest["probes"]], [64, 0])
        self.assertTrue(all(item["rejection_reason"] for item in manifest["probes"]))
        self.assertEqual((self.root / manifest["probes"][1]["stdout"]).read_text(), "{")

    def test_schema_rejects_missing_fields_wrong_types_and_unknown_references(self):
        mutations = (
            (lambda d: d["schemas"]["Summary"]["properties"].pop("runtimeWarnings"), "runtimeWarnings"),
            (lambda d: d["schemas"]["Summary"].update(required="runtimeWarnings"), "not required"),
            (lambda d: d["schemas"]["Summary"]["properties"]["runtimeWarnings"].update(type="object"), "array"),
            (lambda d: d["schemas"]["Summary"]["properties"]["runtimeWarnings"].update(items={"$ref": "#/schemas/Other"}), "reference Issue"),
            (lambda d: d["schemas"]["Issue"].update(required=[]), "message is not required"),
            (lambda d: d["schemas"]["Issue"]["properties"]["message"].update(type="integer"), "required string"),
            (lambda d: d["schemas"].pop("Issue"), "invalid schema object: Issue"),
            (lambda d: d["schemas"]["Summary"].update(type="array"), "Summary must be an object"),
        )
        path = self.root / "schema.json"
        for mutate, message in mutations:
            with self.subTest(message=message):
                document = copy.deepcopy(SCHEMA)
                mutate(document)
                path.write_text(json.dumps(document))
                with self.assertRaisesRegex(ValueError, message):
                    reader.require_warning_schema(path)

    def test_selection_evidence_cannot_be_overwritten(self):
        command = self.fake_command({self.compiler: (0, SCHEMA, "")})
        reader.select_reader(self.root, self.compiler, None, False, command, candidates=[])
        before = (self.root / "reader-selection.json").read_bytes()
        with self.assertRaisesRegex(ValueError, "already exists"):
            reader.select_reader(self.root, self.compiler, None, False, command, candidates=[])
        self.assertEqual(len(self.calls), 1)
        self.assertEqual((self.root / "reader-selection.json").read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
