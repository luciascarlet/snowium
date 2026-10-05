#!/bin/sh
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
python3 "$here/prepare.py"
port=$(CDPATH= cd -- "$here/.." && pwd)
toolchain="$port/chromium-124.0.6367.207/third_party/rust-toolchain"
export RUSTC="$toolchain/bin/rustc"
export RUSTDOC="$toolchain/bin/rustdoc"
export __CARGO_TESTS_ONLY_SRC_ROOT="$here/rust-src"
export MACOSX_DEPLOYMENT_TARGET=10.6
export CARGO_HOME="$here/cargo-home"
export CARGO_TARGET_X86_64_APPLE_DARWIN_LINKER="$port/toolchain/clang/bin/clang"
export SDKROOT="$port/MacOSX14.5.sdk"
export RUSTFLAGS="-Zhas-thread-local=no -Ztls-model=emulated -Ctarget-cpu=core2 -Clink-arg=-arch -Clink-arg=x86_64 -Clink-arg=-mmacosx-version-min=10.6 -Lnative=$port/runtime -lstatic=MacportsLegacySupport -Lnative=$port/toolchain/clang/lib/clang/19/lib/darwin -lstatic=clang_rt.osx"
cd "$here"
exec "$toolchain/bin/cargo" build --offline --release --target x86_64-apple-darwin \
  -Zbuild-std=std,panic_abort -Zbuild-std-features=compiler-builtins-mem,backtrace,panic-unwind
