import importlib.util
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('replay_identity', Path(__file__).resolve().parents[1] / 'generate_replay_build_identity.py')
identity = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(identity)


class ReplayBuildIdentityTests(unittest.TestCase):
    def fixture(self, root):
        for relative in ['FruitTreeScanner/Domain/Test.swift', 'FruitTreeScanner.xcodeproj/project.pbxproj',
                         'tools/generate_replay_build_identity.py']:
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('original')

    def test_content_and_path_changes_change_provenance(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            original = identity.build_identity(root)
            source = root / 'FruitTreeScanner/Domain/Test.swift'
            source.write_text('dirty edit')
            changed = identity.build_identity(root)
            self.assertNotEqual(original['sourcesSHA256'], changed['sourcesSHA256'])
            source.rename(source.with_name('Moved.swift'))
            self.assertNotEqual(changed['sourcesSHA256'], identity.build_identity(root)['sourcesSHA256'])

    def test_test_and_build_output_do_not_change_production_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            original = identity.build_identity(root)
            for relative in ['FruitTreeScannerTests/Test.swift', 'DerivedData/Generated.swift']:
                path = root / relative
                path.parent.mkdir(parents=True)
                path.write_text('test or generated')
            self.assertEqual(original, identity.build_identity(root))
            self.assertEqual(set(original), {'schemaVersion', 'sourcesSHA256', 'sourceFileCount'})

    def test_symbolic_link_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            (root / 'FruitTreeScanner/Linked.swift').symlink_to(root / 'tools/generate_replay_build_identity.py')
            with self.assertRaises(ValueError):
                identity.build_identity(root)
