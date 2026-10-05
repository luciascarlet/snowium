#!/bin/bash
set -euo pipefail
TLS_ROOT=$(cd "$(dirname "$0")" && pwd)
PORT_ROOT=$(cd "$TLS_ROOT/.." && pwd)
mkdir -p "$TLS_ROOT/build"
"$PORT_ROOT/toolchain/snow-clang/bin/clang" \
  -arch x86_64 -mmacosx-version-min=10.6 \
  -isysroot "$PORT_ROOT/MacOSX14.5.sdk" -DSNOW_LEOPARD_PORT=1 \
  -I "$TLS_ROOT/references" -O2 -fvisibility=hidden \
  -c "$TLS_ROOT/src/emutls.c" -o "$TLS_ROOT/build/emutls.o"
"$PORT_ROOT/toolchain/clang/bin/llvm-ar" rcs \
  "$TLS_ROOT/build/libsnowium_emutls.a" "$TLS_ROOT/build/emutls.o"
