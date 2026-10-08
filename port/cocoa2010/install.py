#!/usr/bin/env python3
"""Apply the Cocoa 2010 UI to the provisioned, Snow Leopard-patched 124 source."""
import argparse
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    args = parser.parse_args()
    source = args.source.resolve()
    version = (source / 'chrome/VERSION').read_text()
    if 'MAJOR=124' not in version or 'BUILD=6367' not in version or 'PATCH=207' not in version:
        parser.error('Expected Chromium 124.0.6367.207 with the Legacy and Snow Leopard patches applied.')
    patch = ROOT / 'chromium-124-cocoa2010.patch'
    command = ['patch', '-p1', '-i', str(patch)]
    forward = subprocess.run(command + ['--dry-run', '--forward'], cwd=source, capture_output=True, text=True)
    if forward.returncode == 0:
        subprocess.run(command + ['--forward'], cwd=source, check=True)
    else:
        reverse = subprocess.run(command + ['--dry-run', '--reverse'], cwd=source, capture_output=True, text=True)
        if reverse.returncode:
            raise SystemExit('UI patch neither applies cleanly nor is wholly applied. Preserving this tree.\n' + forward.stdout)
        print('Cocoa 2010 patch already applied.')
    for path in (ROOT / 'overlay').rglob('*'):
        if path.is_file():
            dest = source / path.relative_to(ROOT / 'overlay')
            dest.parent.mkdir(parents=True, exist_ok=True)
            if not dest.exists() or dest.read_bytes() != path.read_bytes():
                shutil.copy2(path, dest)
    print('Cocoa 2010 sources and original assets installed; build chrome with the existing port toolchain.')

if __name__ == '__main__':
    main()
