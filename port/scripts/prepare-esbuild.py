#!/usr/bin/env python3
"""Install the pinned Mac build-host esbuild from its retained CIPD archive."""
import hashlib
import json
from pathlib import Path
import zipfile

root = Path(__file__).resolve().parents[1]
record = json.loads((root / 'references/esbuild-host-tool.json').read_text())
archive = root / 'downloads/esbuild-0.14.13.chromium.2-mac-arm64.zip'
if hashlib.sha256(archive.read_bytes()).hexdigest() != record['archive_sha256']:
    raise SystemExit('esbuild archive hash differs from the recorded pinned input')
target = root / 'chromium-124.0.6367.207/third_party/devtools-frontend/src/third_party/esbuild/esbuild'
with zipfile.ZipFile(archive) as package:
    binary = package.read('esbuild')
if hashlib.sha256(binary).hexdigest() != record['binary_sha256']:
    raise SystemExit('esbuild binary hash differs from the recorded pinned input')
if not target.exists() or target.read_bytes() != binary:
    if target.exists():
        target.chmod(0o755)
    target.write_bytes(binary)
target.chmod(0o755)
print(target)
