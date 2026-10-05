#!/usr/bin/env python3
"""Cheap, host-independent checks of the exported source repository."""
import ast
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    manifest = json.loads((ROOT / 'source-manifest.json').read_text())
    for name, expected in manifest['files'].items():
        actual = hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
        if actual != expected:
            raise SystemExit('Source manifest mismatch: ' + name)
    for pin in json.loads((ROOT / 'port/references/legacy-124-pins.json').read_text()):
        data = (ROOT / 'port/references' / pin['patch']).read_bytes()
        if hashlib.sha256(data).hexdigest() != pin['patch_sha256']:
            raise SystemExit('Legacy patch mismatch: ' + pin['patch'])
    for base in ('ci', 'port'):
        for path in (ROOT / base).rglob('*.py'):
            ast.parse(path.read_text(), filename=str(path))
        for path in (ROOT / base).rglob('*.sh'):
            subprocess.run(['bash', '-n', str(path)], check=True)
    print('Source hashes, pinned patches, Python and shell syntax passed.')


if __name__ == '__main__':
    main()
