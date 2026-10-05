# Snow Leopard ARC source runtime

This directory is separate from the working Chromium 60 port. It provides
source-linkable Objective-C ARC primitives for the Chromium 124 port; it does
not install or replace any system library and does not use binary injection.

## Inputs and build

`src/arc_strong.m` contains the MRC strong-reference/pool wrappers first exercised
in the earlier Snowium work. `src/PLWeakCompatibilityStubs.m` adapts the existing
[PLWeakCompatibility library](https://github.com/plausiblelabs/PLWeakCompatibility)
at commit `1e2b14d85946e39ccddb1cbd5071ee2d69fd563c` (2013-01-13), under its BSD
three-clause license. The unmodified checkout remains in `PLWeakCompatibility/`.
The patched source and its license must travel together.

From the workspace root:

```sh
SNOWIUM_CLANG="$PWD/modern-port/toolchain/clang/bin/clang" \
SNOWIUM_SDK="$PWD/modern-port/MacOSX14.5.sdk" \
SNOWIUM_ARC_BUILD="$PWD/modern-port/runtime-compat/build-clang19-sdk14" \
sh modern-port/runtime-compat/build.sh
```

The script produces `arc-smoke` and `libsnowium_arc.a`. Without overrides it
uses Xcode clang and the untouched 10.6 SDK from `source-port/`. Both compilers
have run the baseline regression successfully on actual Mac OS X 10.6.8. The
final extended regression uses Chromium's pinned Clang 19 and the private
14.5 SDK, still with a real 10.6 deployment target.

For GN integration:

- Compile ARC callers and `PLWeakCompatibilityStubs.m` with
  `-mmacosx-version-min=10.6 -fobjc-arc -Xclang -fobjc-runtime-has-weak`.
  Set the x86_64 target as usual and enable blocks.
- Compile `arc_strong.m` without ARC (`-fno-objc-arc`).
- Link the resulting objects into the process's main code/framework, with
  Foundation and CoreFoundation. Do not pass `-fobjc-arc` to the final compiler
  link command, or explicitly use `-fno-objc-link-runtime`; Xcode no longer ships
  the libarclite archive otherwise requested by that driver flag.
- With the modern SDK, order the link inputs as the ARC archive, then explicit
  `-lobjc`, then frameworks. The 14.5 SDK's CoreFoundation reexports libobjc;
  10.6's CoreFoundation does not. Omitting explicit `-lobjc` binds Objective-C
  cache/message symbols to the wrong image. Putting `-lobjc` before the ARC
  archive instead resolves ARC entry points against the modern SDK runtime,
  which are missing at runtime on 10.6. This ordering is now in the GN target
  configuration and is covered by native ARC, Chromium foundation and Skia runs.
- Hidden definitions are valid only with the single weak-provider constraint
  below. Strong ARC wrappers may be linked into multiple images. Avoid flat
  namespace or any system-wide Objective-C runtime replacement.

## Required process-image constraint

**Exactly one image in a browser process may provide the PLWeak weak runtime.**
Each statically linked copy has its own weak-address map, release mutex and
swizzled-class set, while Objective-C classes and selector aliases are shared by
the whole process. Two copies can overwrite the class hook and leave the other
copy's weak slots pointing at a destroyed object. This is not a supported
configuration. Noncomponent builds retain one weak provider in the browser
framework; main/helper executables must not add another. Other libraries may
use MRC or duplicate the stateless strong ARC wrappers.

`build_cross_image.sh` builds an isolated reproducer. Native evidence on10.6:

- `logs/cross-image-native-before.log`: two independent hidden weak copies
  **fail**; the object deallocates once but the first library's slot stays nonzero.
- `logs/cross-image-native-strong-weak.log`: one weak provider plus another
  library's strong ARC owner **passes**; ownership crosses images, destruction
  occurs exactly once and the weak slot clears.
- `logs/cross-image-native-shared.log`: two weak-using libraries linked to one
  shared runtime **pass** in both registration orders. This is an isolated
  fallback experiment, not a change to browser packaging.

The final bundle must pass the read-only audit before claiming browser startup:

```sh
python3 modern-port/scripts/audit_weak_runtime.py --bundle '/path/to/Content Shell.app'
```

The audit inventories x86_64 executable/shared-image slices, recognizes this
runtime's release/dealloc selector strings even if symbols were stripped, and
conservatively considers all bundled shared libraries potentially co-loaded
with each executable. It requires exactly one provider for each process and
fails if two are present. Symlink aliases are deduplicated. Explicit test groups
may instead supply `--executable ... --library ... --library ...`; all candidate
loaded libraries must be included. `--allow-no-provider` is only for entirely
C/C++/MRC or strong-only test groups, not a browser acceptance shortcut.

`logs/cross-image-audit-negative.json` records rejection of the two-provider
fixture; the shared and strong/weak fixture audits pass. The current actual GN
graphics binaries libEGL, libGLESv2 and libvk_swiftshader contain zero weak
providers (`logs/graphics-weak-provider-audit.json`), so they do not trigger this
failure. Re-audit after linking the final framework and all helpers. This audit
does not establish weak correctness for arbitrary third-party injected images
or the separately documented CFRelease limitation.

## Native evidence and local changes

`logs/arc-native-clang19-sdk14-pass5.log` records the extended native run:

- ARC strong retention, nested autorelease pools, weak initialization/copy and
  zeroing after destruction.
- Synthesized atomic strong and nonatomic weak/copy properties.
- Independent custom reference counting which bypasses NSObject retain/release,
  across three levels of inheritance.
- A heap-copied block capturing weak storage.
- A weak load during a deliberately blocked final release, followed by zeroing.
- 2,000 concurrent double-release/load races, each with deallocation accounting.
- 1,000 concurrent weak-store races (128 stores per thread per round), verifying
  that destroying a weak slot removes every registration before objects die.

The weak-store fix makes unregister/store/register one locked operation. The
weak-copy fix releases its temporary retained target immediately rather than
extending the object's lifetime until the current autorelease pool drains.

The original library failed the case where KVO was installed before the weak
reference and then removed. On Darwin 10, KVO restores the original object's
class, bypassing a deallocation hook installed only on the transient KVO class.
The adapter also hooks that original class. Both orderings now pass in separate
native processes, recorded in `logs/arc-native-kvo-before-pass2.log` and
`logs/arc-native-kvo-after-pass2.log`. The tests inspect potentially stale slot
bytes without dereferencing a dead object. This verifies those concrete KVO
class transitions; it is not a claim about all possible isa-swizzling code.

The runtime tests can be repeated in their separate remote directory:

```sh
scp modern-port/runtime-compat/build-clang19-sdk14/arc-smoke \
  admin@keine.local:/Users/admin/Snowium/modern-port/runtime-compat/arc-smoke-clang19-sdk14
ssh admin@keine.local /Users/admin/Snowium/modern-port/runtime-compat/arc-smoke-clang19-sdk14
ssh admin@keine.local '/Users/admin/Snowium/modern-port/runtime-compat/arc-smoke-clang19-sdk14 --kvo-before'
ssh admin@keine.local '/Users/admin/Snowium/modern-port/runtime-compat/arc-smoke-clang19-sdk14 --kvo-after'
```

## Known limit

**A weak reference to a toll-free bridged CoreFoundation object released through
`CFRelease` is not supported.** Its lifetime may bypass Objective-C deallocation
hooks. The native `--cf` probe detects the stale slot and returns nonzero;
`logs/arc-native-cf.log` records this expected failure. Chromium adapters must
avoid weak ownership for those objects (use explicit CF ownership/lifetime
management). The optional MAZeroingWeakRef implementation is not linked: its CF
support depends on invasive private-runtime hooks and has its own concurrency
limitations. Its dynamic opt-in is disabled by default in the patched source.

This is an experimental compatibility runtime with concrete native coverage,
not proof that every Chromium Cocoa object or runtime pattern is supported.
Reentrant weak loads from unusual custom release implementations and arbitrary
third-party isa changes still need call-site review if encountered.
