#!/usr/bin/env python3
"""Configure the isolated Chromium 124 tree without overwriting existing args.

Run after applying the pinned Chromium Legacy patches. --apply-patch applies
our additional source diff (or recognizes an already applied diff).
"""
import argparse
import os
from pathlib import Path
import subprocess
from edit_source import ROOT, SRC

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--apply-patch', action='store_true')
parser.add_argument('--root-target', default=os.environ.get('SNOWIUM_GN_ROOT_TARGET', '//:default'),
                    help='initial GN BUILD directory (default: full Chromium root //:default; '
                         'use //snow_leopard for a reduced initial graph)')
parser.add_argument('--refresh-args', action='store_true',
                    help='explicitly replace args.gn with the documented template')
args = parser.parse_args()
if not (SRC/'chrome/VERSION').is_file():
    parser.error('extract the pinned Chromium 124 source archive first')
if args.apply_patch:
    patch = ROOT/'patches/chromium-124-snow-leopard.patch'
    check = subprocess.run(['patch','--dry-run','--forward','-p1','-i',str(patch)],
                           cwd=SRC, capture_output=True, text=True)
    if check.returncode == 0:
        subprocess.run(['patch','--forward','-p1','-i',str(patch)],cwd=SRC,check=True)
    else:
        reverse = subprocess.run(['patch','--dry-run','--reverse','-p1','-i',str(patch)],
                                 cwd=SRC,capture_output=True,text=True)
        if reverse.returncode:
            raise SystemExit('Patch does not cleanly apply and is not wholly applied. '
                             'Preserving this tree; inspect local changes before continuing.\n'+check.stdout)
        print('Snow Leopard patch is already applied.')
subprocess.run(['python3',str(ROOT/'scripts/sync_overlay.py')],check=True)
subprocess.run(['python3',str(ROOT/'scripts/prepare-link-stubs.py')],check=True)
subprocess.run(['python3',str(ROOT/'scripts/prepare-esbuild.py')],check=True)
out = SRC/'out/SnowLeopard'
out.mkdir(parents=True,exist_ok=True)
if args.refresh_args or not (out/'args.gn').exists():
    template=(ROOT/'references/snow-leopard-args.gn.in').read_text()
    (out/'args.gn').write_text(template.replace('@PORT_ROOT@',str(ROOT)))
subprocess.run([str(ROOT/'toolchain/gn/gn'),'gen',str(out),
                '--root='+str(SRC),'--root-target='+args.root_target],check=True)
