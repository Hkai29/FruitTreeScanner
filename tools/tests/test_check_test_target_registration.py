import importlib.util
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parents[2]
TOOLS = Path(__file__).resolve().parents[1]
sys_path = str(TOOLS)

import sys
if sys_path not in sys.path:
    sys.path.insert(0, sys_path)

spec = importlib.util.spec_from_file_location(
    "check_test_target_registration", TOOLS / "check_test_target_registration.py")
registration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(registration)


def parse(project_path):
    return json.loads(subprocess.check_output(
        ["plutil", "-convert", "json", "-o", "-", str(project_path)], text=True))


class RegistrationCheckTests(unittest.TestCase):
    """注册检查本身必须有反例覆盖：漏判一个文件就不能算通过。

    反例不是靠手工编造，而是**真的动一份 pbxproj 副本**：
    把某个已注册文件从 Sources 阶段摘掉，再看检查能不能拒绝。
    """

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="registration-check-test-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.project = self.root / "FruitTreeScanner.xcodeproj" / "project.pbxproj"
        self.project.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(REPOSITORY / "FruitTreeScanner.xcodeproj" / "project.pbxproj",
                     self.project)
        self.sources = self.root / "FruitTreeScannerUITests"
        self.sources.mkdir()
        for path in sorted((REPOSITORY / "FruitTreeScannerUITests").glob("*.swift")):
            shutil.copy2(path, self.sources / path.name)

    def _check(self):
        return registration.check(self.project, "FruitTreeScannerUITests",
                                  "FruitTreeScannerUITests", "FruitTreeScannerUITests")

    def _drop_from_sources(self, file_name):
        """Remove a file's build file from the UITests Sources phase."""
        project = parse(self.project)
        objects = project["objects"]
        build_file_ids = [
            key for key, value in objects.items()
            if value.get("isa") == "PBXBuildFile"
            and objects.get(value.get("fileRef"), {}).get("path") == file_name
        ]
        self.assertEqual(len(build_file_ids), 1, file_name)
        for phase in objects.values():
            if phase.get("isa") != "PBXSourcesBuildPhase":
                continue
            files = phase.get("files", [])
            if any(f in files for f in build_file_ids):
                phase["files"] = [f for f in files if f not in build_file_ids]
        result = subprocess.run(
            ["plutil", "-convert", "binary1", "-o", "-", "-"],
            input=json.dumps(project).encode(), capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        # plutil cannot write OpenStep back, so write the JSON form the
        # checker can still parse: the checker reads via plutil, which
        # accepts JSON input files too.
        self.project.write_text(json.dumps(project))

    def _drop_from_group(self, file_name):
        project = parse(self.project)
        objects = project["objects"]
        reference_ids = [
            key for key, value in objects.items()
            if value.get("isa") == "PBXFileReference" and value.get("path") == file_name
        ]
        self.assertEqual(len(reference_ids), 1, file_name)
        for group in objects.values():
            if group.get("isa") != "PBXGroup":
                continue
            if group.get("path") != "FruitTreeScannerUITests":
                continue
            group["children"] = [c for c in group.get("children", [])
                                 if c not in reference_ids]
        self.project.write_text(json.dumps(project))

    def test_the_real_project_registers_every_ui_test_file(self):
        ok, findings = self._check()
        self.assertTrue(ok, findings)

    def test_the_real_project_has_no_orphan_ui_test_sources(self):
        """当前仓库里每个 UI 测试源文件都必须真的接进 target。"""
        project = parse(REPOSITORY / "FruitTreeScanner.xcodeproj" / "project.pbxproj")
        registered = registration.registered_files(
            project, "FruitTreeScannerUITests", "FruitTreeScannerUITests")
        for path in sorted((REPOSITORY / "FruitTreeScannerUITests").glob("*.swift")):
            entry = registered.get(path.name)
            self.assertIsNotNone(entry, path.name)
            self.assertTrue(entry["in_sources"], path.name)
            self.assertTrue(entry["in_group"], path.name)

    def test_rejects_a_file_dropped_from_the_sources_phase(self):
        self._drop_from_sources("VarietyConfirmationTests.swift")
        ok, findings = self._check()
        self.assertFalse(ok, "a file outside Sources must be rejected")
        self.assertEqual([f["file"] for f in findings], ["VarietyConfirmationTests.swift"])
        self.assertIn("Sources", findings[0]["reason"])

    def test_rejects_a_file_dropped_from_the_group(self):
        self._drop_from_group("BatchExportRecoveryTests.swift")
        ok, findings = self._check()
        self.assertFalse(ok, "a file outside the group must be rejected")
        self.assertEqual([f["file"] for f in findings], ["BatchExportRecoveryTests.swift"])
        self.assertIn("group", findings[0]["reason"])

    def test_rejects_a_file_with_no_reference_at_all(self):
        (self.sources / "GhostUITests.swift").write_text("import XCTest\n")
        ok, findings = self._check()
        self.assertFalse(ok, "a file with no reference must be rejected")
        self.assertEqual([f["file"] for f in findings], ["GhostUITests.swift"])

    def test_a_registered_file_is_not_reported(self):
        ok, findings = self._check()
        self.assertEqual(findings, [])


if __name__ == "__main__":
    unittest.main()
