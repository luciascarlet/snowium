#!/bin/bash
set -euo pipefail
feature_root=$(cd "$(dirname "$0")" && pwd)
source_root=${1:?Pass the provisioned Chromium 124 source directory}
preview_root=${2:-"$feature_root/../../work/Cocoa2010 Preview.app"}
mkdir -p "$preview_root/Contents/MacOS" "$preview_root/Contents/Resources/Cocoa2010"
xcrun clang++ -std=c++17 -fobjc-arc -Wno-deprecated-declarations \
  -I "$feature_root/overlay" -I "$source_root" -I "$source_root/out/SnowLeopard/gen" \
  "$feature_root/preview.mm" \
  "$feature_root/overlay/chrome/browser/ui/cocoa2010/controls.mm" \
  "$feature_root/overlay/chrome/browser/ui/cocoa2010/omnibox_cell.mm" \
  -framework Cocoa -o "$preview_root/Contents/MacOS/Cocoa2010Preview"
cp "$feature_root/overlay/chrome/browser/ui/cocoa2010/resources/"* "$preview_root/Contents/Resources/Cocoa2010/"
cp "$feature_root/overlay/chrome/browser/ui/cocoa2010/resources/app.icns" "$preview_root/Contents/Resources/"
python3 - "$preview_root" <<'PY'
import plistlib,sys
from pathlib import Path
p=Path(sys.argv[1])/'Contents/Info.plist'
p.write_bytes(plistlib.dumps({'CFBundleExecutable':'Cocoa2010Preview','CFBundleIdentifier':'org.snowium.cocoa2010.preview','CFBundleName':'Cocoa2010 Preview','CFBundlePackageType':'APPL','CFBundleIconFile':'app.icns','NSHighResolutionCapable':True}))
PY
printf 'Preview: %s\n' "$preview_root"
