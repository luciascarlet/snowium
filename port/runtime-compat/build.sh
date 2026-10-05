#!/bin/sh
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
sdk=${SNOWIUM_SDK:-"$here/../../source-port/MacOSX10.6.sdk"}
build=${SNOWIUM_ARC_BUILD:-"$here/build"}
mkdir -p "$build"
# Compile-only ARC flags avoid the removed libarclite linker dependency.
cc() {
  if [ -n "${SNOWIUM_CLANG:-}" ]; then
    "$SNOWIUM_CLANG" -target x86_64-apple-macosx10.6 -isysroot "$sdk" -fblocks "$@"
  else
    xcrun clang -target x86_64-apple-macosx10.6 -isysroot "$sdk" -fblocks "$@"
  fi
}
cc -fno-objc-arc -c "$here/src/arc_strong.m" -o "$build/strong.o"
cc -fobjc-arc -Xclang -fobjc-runtime-has-weak -include dispatch/dispatch.h \
   -c "$here/src/PLWeakCompatibilityStubs.m" -o "$build/weak.o"
cc -fno-objc-arc -c "$here/tests/fixtures.m" -o "$build/fixtures.o"
cc -fobjc-arc -Xclang -fobjc-runtime-has-weak \
   -c "$here/tests/arc_smoke.m" -o "$build/arc_smoke.o"
cc "$build/strong.o" "$build/weak.o" "$build/fixtures.o" \
   "$build/arc_smoke.o" -framework Foundation -framework CoreFoundation \
   -o "$build/arc-smoke"
libtool -static "$build/strong.o" "$build/weak.o" -o "$build/libsnowium_arc.a"
