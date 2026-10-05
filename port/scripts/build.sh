#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
src="$root/chromium-124.0.6367.207"
python3 "$root/scripts/sync_overlay.py"
python3 "$root/scripts/prepare-link-stubs.py"
python3 "$root/scripts/prepare-esbuild.py"
# GN loads the entire root BUILD file; a :target suffix does not limit it.
# The complete Chromium root is required for the default chrome target.
root_target=${SNOWIUM_GN_ROOT_TARGET:-//:default}
"$root/toolchain/gn/gn" gen "$src/out/SnowLeopard" --root="$src" --root-target="$root_target"
if [ "$#" -eq 0 ]; then
  set -- runtime_smoke seatbelt_smoke foundation_smoke font_smoke d8 content_shell chrome
fi
exec "$root/toolchain/bin/ninja" -C "$src/out/SnowLeopard" -j"${SNOWIUM_JOBS:-12}" -k"${SNOWIUM_KEEP_GOING:-1}" "$@"
