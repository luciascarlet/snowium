#!/usr/bin/env python3
import urllib.request,re,tarfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
packages={'libffi':'3.4.8_0','libedit':'20251016-3.1_0','libxml2':'2.15.3_0','ncurses':'6.6_0','zlib':'1.3.2_0','zstd':'1.5.7_0','libiconv':'','xz':'','icu':'78'}
for name,version in packages.items():
 url=f'https://packages.macports.org/{name}/'
 html=urllib.request.urlopen(url).read().decode()
 names=sorted(set(re.findall(r'href="([^"]+\.tbz2)"',html)))
 candidates=[n for n in names if n.startswith(name+'-'+version) and '.darwin_23.' in n and 'arm64' in n]
 if not candidates:raise SystemExit(f'No matching package for {name}: {names[:2]}')
 filename=candidates[-1];dest=root/'downloads'/filename
 if not dest.exists():urllib.request.urlretrieve(url+filename,dest)
 print(filename,flush=True)
 out=root/'toolchain/host-dependencies'/name
 if not out.exists():
  with tarfile.open(dest) as tf:tf.extractall(out)
