# Rust 1.78 standard library on Snow Leopard

The Chromium 124 pinned Rust compiler and standard-library sources work on
Mac OS X 10.6.8 when rebuilt with its existing pthread TLS backend and linked to
the MacPorts compatibility library. No Rust standard-library source changes
were necessary for the exercised features.

The pinned compiler reports:

```
rustc 1.78.0-dev (7168c13579a550f2c47f7eea22f5e226a436cd00-1-llvmorg-19-init-2941-ga0b3dbaf chromium)
LLVM version: 19.0.0
```

## Reproduce

From the workspace root, run `sh modern-port/rust-compat/build.sh`. This uses
the already downloaded Chromium Rust toolchain and its vendored crates, without
network access. `prepare.py` makes a private copy of the matching standard
library so Cargo cannot alter the source port's inputs or lock file. No files
from the completed Chromium 60 port are changed.

The important settings are:

- `MACOSX_DEPLOYMENT_TARGET=10.6`: forms the correct LLVM Apple target triple.
- `-Zhas-thread-local=no`: selects Rust std's existing pthread-key TLS and
  destructor implementation, excluding the Lion-only `_tlv_atexit` path.
- `-Ztls-model=emulated`: compiles explicit `#[thread_local]` variables with
  compiler-rt emulated TLS instead of Mach-O TLV descriptors.
- Rebuild std; a prebuilt modern std retains its original OS assumptions.
- Link `libMacportsLegacySupport.a` before the modern SDK's `-lSystem`, so
  `getentropy`, `clock_gettime`, and related imports bind to real backports.
- Explicit compiler TLS needs `libclang_rt.osx.a` for `__emutls_get_address`.
  The standalone Cargo build disables default linker libraries, so this script
  supplies it explicitly. Chromium's C++ link driver handles compiler-rt.

The executable is
`target/x86_64-apple-darwin/release/snowium-rust-smoke`. Run it on the target:

```sh
scp modern-port/rust-compat/target/x86_64-apple-darwin/release/snowium-rust-smoke \
  admin@keine.local:/Users/admin/Snowium/modern-port/rust-compat/rust-smoke
ssh admin@keine.local /Users/admin/Snowium/modern-port/rust-compat/rust-smoke
```

## Native validation

`logs/native-pass4.log` records the native 10.6.8 test:

- Random-seeded HashMap, allocation, and formatting.
- 64 named threads, isolated pthread TLS, explicit emulated compiler TLS, and
  exactly 64 thread-local destructor calls.
- Mutex, condition-variable timed wait, sleep, and monotonic time.
- File write/read/copy, directory enumeration, recursive directory removal.
- A local TCP listener, client connection timeout, and transfer.
- Child process spawning, pipe capture, and exit status.

`logs/native-pass1.log` preserves the failed link-order experiment: placing
`-load_hidden` after the SDK System library left a hard `getentropy` import.
The corrected link selects MacPorts' implementation. TLS and the 10.6 deployment
target alone do not fix newer C library dependencies.

## Chromium GN integration

The source patch adds target-only flags in `build/config/compiler/BUILD.gn` and
the deployment environment in `build/rust/rust_target.gni`. They are gated on
macOS, x64, deployment 10.6, and exclusion of Rust host build toolchains. Native
Apple Silicon build tools keep their usual runtime. Keep `enable_rust=true` and
the existing locally rebuilt std path (`rust_prebuilt_stdlib=false` for target).

These changes were saved through the port's `edit_source.py` helper, preserving
pristine originals and joining the main Chromium 124 patch. The std GN rules
already rebuild the matching Rust source; they need no alternate implementation.

## Remaining limitation

The separate `--backtrace` probe returns `Unsupported` on the target and exits
nonzero, even with std's backtrace feature compiled. No frames were produced by
the old system `_Unwind_Backtrace` path. `logs/native-backtrace.log` records it.
The ordinary regression does not claim Rust stack backtraces work. Chromium's
panic-abort configuration can use the other tested std functionality without
that optional diagnostic feature. This test is not proof of every std API or
every Chromium Rust crate; the actual GN integration still needs its build and
browser-level validation.
