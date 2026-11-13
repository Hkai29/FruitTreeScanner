"""Generate replay provenance from production sources, including dirty edits.

The bundled output contains hashes and a count, never local paths or Git data.
Tests and generated build output are not inputs to the production algorithm.
"""
import argparse
import hashlib
import json
from pathlib import Path


def build_identity(root):
    root = Path(root)
    extensions = {'.swift', '.metal', '.strings', '.plist', '.h', '.m', '.mm'}
    paths = [p for p in (root / 'FruitTreeScanner').rglob('*') if p.suffix in extensions and p.is_file()]
    paths += [root / 'FruitTreeScanner.xcodeproj/project.pbxproj', root / 'tools/generate_replay_build_identity.py']
    entries = []
    for path in sorted(paths, key=lambda p: p.relative_to(root).as_posix()):
        if path.is_symlink() or not path.resolve().is_relative_to(root.resolve()):
            raise ValueError('Replay source identity does not accept symbolic links')
        entries.append(path.relative_to(root).as_posix().encode() + b'\0' + hashlib.sha256(path.read_bytes()).digest())
    digest = hashlib.sha256(b'FruitTreeScanner-replay-sources-v1\0' + b'\n'.join(entries)).hexdigest()
    return {'schemaVersion': 1, 'sourcesSHA256': digest, 'sourceFileCount': len(paths)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    data = (json.dumps(build_identity(args.root), sort_keys=True) + '\n').encode()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if not args.output.exists() or args.output.read_bytes() != data:
        args.output.write_bytes(data)


if __name__ == '__main__':
    main()
