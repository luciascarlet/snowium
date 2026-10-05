#!/usr/bin/env python3
from pathlib import Path
import shutil
r=Path(__file__).resolve().parents[1]
for p in (r/'overlay').rglob('*'):
 if p.is_file():
  dest=r/'chromium-124.0.6367.207'/p.relative_to(r/'overlay')
  dest.parent.mkdir(parents=True,exist_ok=True)
  if not dest.exists() or dest.read_bytes()!=p.read_bytes():shutil.copy2(p,dest)
