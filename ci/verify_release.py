#!/usr/bin/env python3
"""Verify downloadable release assets on a host without macOS tooling."""
import argparse
import hashlib
import json
from pathlib import Path
import stat
import zipfile


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('directory', type=Path)
    a = p.parse_args()
    sums = (a.directory / 'SHA256SUMS').read_text().splitlines()
    checked = set()
    for line in sums:
        expected, name = line.split('  ', 1)
        if Path(name).name != name or name in checked:
            p.error('Invalid/duplicate asset name in SHA256SUMS')
        path = a.directory / name
        with path.open('rb') as f:
            h = hashlib.sha256()
            for chunk in iter(lambda: f.read(1024 * 1024), b''):
                h.update(chunk)
        if h.hexdigest() != expected:
            p.error('Checksum mismatch: ' + name)
        checked.add(name)
    archives = list(a.directory.glob('*.zip'))
    records = list(a.directory.glob('*.manifest.json'))
    if len(archives) != 1 or len(records) != 1 or checked != {archives[0].name, records[0].name}:
        p.error('Expected one app ZIP and one manifest, both checksummed')
    m = json.loads(records[0].read_text())
    with archives[0].open('rb') as f:
        h = hashlib.sha256()
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    if h.hexdigest() != m['archive_sha256'] or archives[0].stat().st_size != m['archive_bytes']:
        p.error('Archive differs from manifest')
    prefix = archives[0].stem + '/Chromium.app/'
    with zipfile.ZipFile(archives[0]) as z:
        if len(z.namelist()) != len(set(z.namelist())):
            p.error('Duplicate ZIP entries')
        for entry in z.infolist():
            if entry.filename.startswith('/') or '..' in Path(entry.filename).parts:
                p.error('Unsafe ZIP path')
        actual = {x.filename[len(prefix):] for x in z.infolist() if x.filename.startswith(prefix) and not x.is_dir()}
        if actual != set(m['bundle_files']) | set(m['bundle_symlinks']):
            p.error('ZIP app inventory differs from manifest')
        for path, expected in m['bundle_files'].items():
            if hashlib.sha256(z.read(prefix + path)).hexdigest() != expected:
                p.error('Bundle file mismatch: ' + path)
        for path, target in m['bundle_symlinks'].items():
            entry = z.getinfo(prefix + path)
            if not stat.S_ISLNK(entry.external_attr >> 16) or z.read(entry).decode() != target:
                p.error('Bundle symlink mismatch: ' + path)
        for name in ('about_credits.html', 'NOTICE.md', 'licenses/CHROMIUM', 'licenses/PLWeakCompatibility', 'licenses/LLVM', 'licenses/MacPorts-LegacySupport'):
            z.getinfo(archives[0].stem + '/' + name)
    print('Release checksums, app inventory, symlinks and notices passed.')


if __name__ == '__main__':
    main()
