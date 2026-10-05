#!/usr/bin/env python3
"""Package a complete app, notices and provenance for Snow Leopard users."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    with path.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest() if hasattr(hashlib, 'file_digest') else hashlib.sha256(f.read()).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--app', type=Path, required=True)
    p.add_argument('--credits', type=Path, required=True)
    p.add_argument('--version', required=True)
    p.add_argument('--output', type=Path, default=ROOT / 'dist')
    a = p.parse_args()
    if sys.platform != 'darwin':
        p.error('Packaging uses macOS ditto to preserve the app bundle')
    if not re.fullmatch(r'124\.[A-Za-z0-9.-]+', a.version):
        p.error('Version must start with 124. and contain only letters, digits, dots and hyphens')
    app = a.app.resolve()
    with (app / 'Contents/Info.plist').open('rb') as f:
        info = plistlib.load(f)
    if info.get('CFBundleIdentifier') != 'org.snowium.Chromium124' or info.get('LSMinimumSystemVersion') != '10.6.8':
        p.error('Expected the Snowium124 / 10.6.8 app bundle')
    main_binary = app / 'Contents/MacOS' / info['CFBundleExecutable']
    with main_binary.open('rb') as f:
        magic, cpu = struct.unpack('<II', f.read(8))
    if (magic, cpu) != (0xfeedfacf, 0x01000007):
        p.error('Expected a thin x86_64 Mach-O executable')
    if not a.credits.is_file() or a.credits.stat().st_size < 1000:
        p.error('Generated Chromium credits are required')
    files, links = {}, {}
    for path in sorted(app.rglob('*')):
        name = str(path.relative_to(app))
        if path.is_symlink():
            target = path.readlink()
            if target.is_absolute() or not path.resolve().is_relative_to(app):
                p.error('App symlink escapes its bundle: ' + name)
            links[name] = str(target)
        elif path.is_file():
            files[name] = digest(path)
    revision = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=ROOT, capture_output=True, text=True)
    manifest = {'version': a.version, 'chromium': '124.0.6367.207', 'legacy': '124.0.6367.207.1',
                'architecture': 'x86_64', 'minimum_system': '10.6.8',
                'source_revision': revision.stdout.strip() if revision.returncode == 0 else None,
                'source_patch_sha256': digest(ROOT / 'port/patches/chromium-124-snow-leopard.patch'),
                'native_testing': 'See release notes; packaging does not perform target-machine QA.',
                'bundle_files': files, 'bundle_symlinks': links}
    a.output.mkdir(parents=True, exist_ok=True)
    name = 'Snowium-' + a.version + '-macos10.6-x86_64'
    archive = a.output / (name + '.zip')
    record = a.output / (name + '.manifest.json')
    sums = a.output / 'SHA256SUMS'
    if any(x.exists() for x in (archive, record, sums)):
        p.error('Output already exists; use a new output directory')
    with tempfile.TemporaryDirectory(dir=a.output) as tmp:
        stage = Path(tmp) / name
        stage.mkdir()
        subprocess.run(['/usr/bin/ditto', '--norsrc', str(app), str(stage / 'Chromium.app')], check=True)
        shutil.copytree(ROOT / 'licenses', stage / 'licenses')
        for notice in ('LICENSE', 'NOTICE.md'):
            shutil.copy2(ROOT / notice, stage / notice)
        shutil.copy2(a.credits, stage / 'about_credits.html')
        (stage / 'READ-ME.txt').write_text('Snowium ' + a.version + '\n\nIntel Mac, OS X 10.6.8. Double-click Chromium.app; it may be moved to /Applications.\nKeep the complete app bundle. Profile: ~/Library/Application Support/Snowium124.\nExperimental Chromium 124 port; see the repository and release notes for tested features and limitations.\nLicenses: licenses/, NOTICE.md, about_credits.html and chrome://credits.\n')
        (stage / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        subprocess.run(['/usr/bin/ditto', '-c', '-k', '--norsrc', '--keepParent', str(stage), str(archive.resolve())], check=True)
    # Check every physical file and symlink after compression, not just the ZIP's existence.
    with zipfile.ZipFile(archive) as z:
        prefix = name + '/Chromium.app/'
        for path, expected in files.items():
            if hashlib.sha256(z.read(prefix + path)).hexdigest() != expected:
                raise SystemExit('Packaged file mismatch: ' + path)
        for path, target in links.items():
            entry = z.getinfo(prefix + path)
            if not stat.S_ISLNK(entry.external_attr >> 16) or z.read(entry).decode() != target:
                raise SystemExit('Packaged symlink mismatch: ' + path)
    manifest['archive_sha256'] = digest(archive)
    manifest['archive_bytes'] = archive.stat().st_size
    record.write_text(json.dumps(manifest, indent=2) + '\n')
    sums.write_text(''.join(digest(x) + '  ' + x.name + '\n' for x in (archive, record)))
    print(archive)
    print('Verified', len(files), 'physical files and', len(links), 'symlinks.')


if __name__ == '__main__':
    main()
