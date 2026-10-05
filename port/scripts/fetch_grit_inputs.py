#!/usr/bin/env python3
"""Restore literal, omitted source includes from a requested pinned GRIT file."""
import base64
import hashlib
import json
from pathlib import Path
import sys
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
src = root / 'chromium-124.0.6367.207'
revision = 'a9001a6e39fbaa559510ca866052950457dd4e6b'
manifest = root / 'references/restored-source-inputs.json'
records = json.loads(manifest.read_text())
for argument in sys.argv[1:]:
    grd = (src / argument).resolve()
    grd.relative_to(src)
    for include in ET.parse(grd).iter('include'):
        name = include.get('file', '')
        if not name or '$' in name or include.get('use_base_dir') == 'false':
            continue
        target = (grd.parent / name).resolve()
        relative = target.relative_to(src).as_posix()
        if target.exists():
            continue
        if relative.startswith('out/'):
            raise SystemExit('Refusing generated input: ' + relative)
        url = ('https://chromium.googlesource.com/chromium/src/+/' + revision +
               '/' + urllib.parse.quote(relative) + '?format=TEXT')
        data = base64.b64decode(urllib.request.urlopen(url).read(), validate=True)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        records.append(dict(path=relative, revision=revision, url=url,
                            sha256=hashlib.sha256(data).hexdigest()))
        manifest.write_text(json.dumps(records, indent=2) + '\n')
        print('Restored pinned GRIT input:', relative, flush=True)
