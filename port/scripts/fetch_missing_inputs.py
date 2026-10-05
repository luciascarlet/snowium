#!/usr/bin/env python3
"""Restore graph-required files omitted from the official source release archive.
Only fetch from the pinned Chromium revision/DEPS packages; never generate placeholders.
"""
import base64, hashlib, json, re, subprocess, sys, tarfile, zipfile, urllib.parse, urllib.request
from pathlib import Path
root=Path(__file__).resolve().parents[1]
src=root/'chromium-124.0.6367.207'; out=src/'out/SnowLeopard'
revision='a9001a6e39fbaa559510ca866052950457dd4e6b'
manifest=root/'references/restored-source-inputs.json'
records=json.loads(manifest.read_text()) if manifest.exists() else []
for _ in range(80):
 result=subprocess.run([str(root/'toolchain/bin/ninja'),'-n','-C',str(out),*sys.argv[1:]],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
 missing=re.search(r"ninja: error: '([^']+)', needed by .*missing and no known rule to make it",result.stdout)
 if not missing:
  print('\n'.join(result.stdout.splitlines()[-5:]))
  if 'Regenerating ninja files' in result.stdout and result.returncode == 0:
   raise SystemExit('Dry run stopped at pending GN regeneration; source graph has not been validated.')
  sys.exit(result.returncode)
 target=(out/missing.group(1)).resolve()
 rel=target.relative_to(src).as_posix()
 if rel.startswith('out/') or target.exists(): raise SystemExit('Not a missing source input: '+rel)
 if rel.startswith('third_party/google_toolbox_for_mac/src/'):
  dep_revision='42b12f10cd8342f5cb41a1e3e3a2f13fd9943b0d'
  # The DEPS URL is Chromium's mirror of this exact upstream Git repository.
  assert "'google_toolbox_for_mac_revision': '"+dep_revision+"'" in (src/'DEPS').read_text()
  asset_url='https://codeload.github.com/google/google-toolbox-for-mac/tar.gz/'+dep_revision
  archive=root/'downloads'/('google-toolbox-for-mac-'+dep_revision+'.tar.gz')
  if not archive.exists(): urllib.request.urlretrieve(asset_url,archive)
  restored=0
  with tarfile.open(archive) as bundle:
   for member in bundle.getmembers():
    parts=Path(member.name).parts
    assert not Path(member.name).is_absolute() and '..' not in parts
    if not member.isfile(): continue
    destination=src/'third_party/google_toolbox_for_mac/src'/Path(*parts[1:])
    if destination.exists(): continue
    destination.parent.mkdir(parents=True,exist_ok=True)
    destination.write_bytes(bundle.extractfile(member).read());restored+=1
  records.append(dict(path='third_party/google_toolbox_for_mac/src',url=asset_url,
                      revision=dep_revision,sha256=hashlib.sha256(archive.read_bytes()).hexdigest(),
                      restored_files=restored))
  manifest.write_text(json.dumps(records,indent=2)+'\n')
  print('Restored pinned Google Toolbox repository',dep_revision,restored,'files',flush=True)
  continue
 if rel.startswith('ui/gl/resources/angle-metal/'):
  version='S0FPOVKrgaiqyuR20SSHiPorLgYez29bfwEdKBobUMMC'
  asset_url='https://chrome-infra-packages.appspot.com/dl/chromium/gpu/angle-metal-shader-libraries/+/'+version
  archive=root/'downloads/angle-metal-shader-libraries.zip'
  if not archive.exists(): urllib.request.urlretrieve(asset_url,archive)
  with zipfile.ZipFile(archive) as bundle:
   for member in bundle.namelist():
    assert not Path(member).is_absolute() and '..' not in Path(member).parts
   bundle.extractall(src/'ui/gl/resources/angle-metal')
  records.append(dict(path='ui/gl/resources/angle-metal',url=asset_url,version=version,sha256=hashlib.sha256(archive.read_bytes()).hexdigest()))
  manifest.write_text(json.dumps(records,indent=2)+'\n')
  print('Restored pinned build-resource package',version,flush=True)
  continue
 if rel.startswith('third_party/test_fonts/test_fonts/'):

  sha=(src/'third_party/test_fonts/test_fonts.tar.gz.sha1').read_text().strip()
  archive=root/'downloads/test_fonts.tar.gz'
  asset_url='https://storage.googleapis.com/chromium-fonts/'+sha
  if not archive.exists(): urllib.request.urlretrieve(asset_url,archive)
  assert hashlib.sha1(archive.read_bytes()).hexdigest()==sha
  with tarfile.open(archive) as bundle:
   for member in bundle.getmembers():
    assert not Path(member.name).is_absolute() and '..' not in Path(member.name).parts
   bundle.extractall(src/'third_party/test_fonts')
  records.append(dict(path='third_party/test_fonts/test_fonts',url=asset_url,sha1=sha))
  manifest.write_text(json.dumps(records,indent=2)+'\n')
  print('Restored pinned test-font archive',sha,flush=True)
  continue
 print('Fetching missing input:',rel,flush=True)
 url='https://chromium.googlesource.com/chromium/src/+/'+revision+'/'+urllib.parse.quote(rel)+'?format=TEXT'
 data=base64.b64decode(urllib.request.urlopen(url).read())
 target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
 records.append(dict(path=rel,revision=revision,url=url,sha256=hashlib.sha256(data).hexdigest()))
 manifest.write_text(json.dumps(records,indent=2)+'\n')
 print('Restored pinned source input:',rel,flush=True)
raise SystemExit('Bounded input restoration reached80files; inspect graph before continuing.')
