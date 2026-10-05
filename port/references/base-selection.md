# Chromium Legacy 124 base selection

Verified 2026-10-04 against primary GitHub source, release metadata, and the project's build wiki.

Use **Chromium Legacy 124.0.6367.207.1**, pinned at `647f7a9e3fd71ac45324676d3bb19b159e2d1629`. Its stock Chromium base is `a9001a6e39fbaa559510ca866052950457dd4e6b` (124.0.6367.207). The release is the latest stable, while 127.0.6494.0 is the later canary. The project documents basic stable testing on Lion through Mojave.

121.0.6167.160.1 (`5385c7ab0d695a0071176a7ea7083c179459d76f`) is **not a separate special Lion edition**: the `.stable.lion` suffix is the historical tag convention. Both live branches are named `master.lion` and `stable.lion`; the latter points at 124. Comparison of 121 and 124 build configuration shows both require the same broad modern SDK, ARC, bundled libc++, and modern toolchain strategy. No inspected source evidence justifies accepting an older browser engine merely for a presumed Lion compatibility advantage. This is a brief selection assessment, not proof that 124 is easier than every earlier 100-series release.

The main source patch `chromium-legacy-lion.patch` was fetched using GitHub's raw compare diff for the exact base and head. It contains **474 file diffs** (29,563 lines). The associated JSON compare response lists only 300 files because of GitHub's API limit; do not derive the patch from that truncated list. The diff has no binary-file placeholders. SHA-256 values and exact dependency pins are in `legacy-124-pins.json`.

Apply the other `*-lion.patch` files in the corresponding dependency source directory after extracting the stock complete 124 source archive. Skia, ANGLE, Dawn, WebRTC, libc++, BoringSSL, and Vulkan Memory Allocator comparisons all have the exact 124 DEPS pin as their merge base. The WebRTC pin includes the maintainer's May 25 merge correction after the May 16 Chromium release.

**SwiftShader exception:** its `stable.lion` branch is stale from October 2022. Do not replace the 124 dependency with that checkout. Its small compatibility diff only removes the `__sincosf_stret` symbol registration from `src/Reactor/LLVMJIT.cpp`; apply/adapt that single change to the 124-pinned source, or omit the unused backend if the Snow Leopard build excludes it.

The official build wiki's general script follows canary dependency branches, so it should not be run verbatim for this stable reproduction. Its recommended build strategy uses custom libc++, `use_lld=false`, `use_thin_lto=false`, `chrome_pgo_phase=0`, no NaCl, modern SDK 14+, and Clang 18+. The two GameController SDK property edits replace `strong` dispatch queue properties with `assign` for old deployment targets. Prefer any SDK edits in a private copied SDK; do not mutate the global Xcode SDK. The wiki's deployment target is 10.7; the Snow Leopard source port must establish its own 10.6 runtime support before claiming compatibility.

Sources:

- https://github.com/blueboxd/chromium-legacy/releases/tag/stable
- https://github.com/blueboxd/chromium-legacy/tree/stable.lion
- https://github.com/blueboxd/chromium-legacy/releases/tag/121.0.6167.160.1-stable.lion
- https://github.com/blueboxd/chromium-legacy/wiki/Building
- https://github.com/blueboxd/chromium-legacy/compare/a9001a6e39fbaa559510ca866052950457dd4e6b...647f7a9e3fd71ac45324676d3bb19b159e2d1629
- Dependency compare URLs are reconstructible from `legacy-124-pins.json`; original compare/head metadata are saved beside it.
