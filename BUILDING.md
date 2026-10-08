# Source and build record

The current release is a **prebuilt Cocoa 2010 UI preview on the pass40 base**, not a GitHub CI build. GitHub hosts the download and runs lightweight source/release integrity checks. No self-hosted runner is required.

The working app was built on Apple Silicon with Xcode 27.1, Chromium's pinned host compiler, MacPorts Clang 19.1.7 for x86_64 compilation, modified SDK 14.5 headers, original SDK 10.6 audio link stubs, bundled libc++/libc++abi, PLWeakCompatibility, MacPorts LegacySupport and an emulated-TLS Rust standard library. The app targets Intel OS X 10.6.8.

The current app is optimized: `is_debug=false`, `-O2`, and debug symbol levels are zero. Its “Developer Build” label comes from `is_official_build=false`. Additional `DCHECK` diagnostics remain enabled; PGO and ThinLTO are disabled. Their performance impact has not been measured.

The source export retains the Snow Leopard patch, overlays, runtime sources, build scripts, pinned Chromium Legacy dependency patches and restoration metadata. The Snow Leopard patch applies to stock Chromium 124.0.6367.207 **after** the Legacy patches recorded in `port/references/legacy-124-pins.json`. `port/overlay/` supplies new files. `source-manifest.json` records the hashes of these exported inputs.

This is not a tested clean-machine bootstrap. The toolchain/SDK modifications, custom runtime archives and emulated-TLS Rust standard library currently require a separately prepared environment. Historical runtime READMEs describe the investigation and commands. Retaining this source export allows future work on automated builds without keeping the entire local build tree in Git.

On the original provisioned workspace, the browser was built with:

```sh
SNOWIUM_JOBS=21 modern-port/scripts/build.sh chrome
```

The exported `prepare-link-stubs.py` takes `SNOWIUM_LEGACY_SDK` as the original 10.6 SDK path rather than relying on the adjacent Chromium 60 port. The exported scripts are references for a future provisioned build; hosted CI does not execute them.

## Optional historical UI

After the pinned Legacy and Snow Leopard patches and overlays are applied, `port/cocoa2010/install.py --source /path/to/chromium-124.0.6367.207` installs the optional Cocoa UI and Aqua scrollbar code. Build `chrome` with the existing toolchain. Both runtime flags default to disabled; the Chromium 7 application icon is unconditional. See [the feature record](port/cocoa2010/README.md) for the two independent flags, historical sources and target validation. This experiment has no release package.

## One-off release

`release-assets/` holds the already prepared ZIP, checksums and manifest. This directory is ignored by Git; attach its files as GitHub Release assets. The release ZIP includes all browser files, licenses and generated Chromium dependency credits. Extract and double-click `Chromium.app`.

To regenerate the package on the modern Mac:

```sh
python3 ci/package.py \
  --app /path/to/Snowium/modern-port/chromium-124.0.6367.207/out/SnowLeopard/Chromium.app \
  --credits /path/to/Snowium/modern-port/chromium-124.0.6367.207/out/SnowLeopard/gen/components/resources/about_credits.html \
  --version 124.0.6367.207-sl.4 --output release-assets/v124.0.6367.207-sl.4
```

Use a fresh output directory; packaging refuses to overwrite assets. To upload after creating/pushing a GitHub repository, follow [PUBLISHING.md](PUBLISHING.md). Packaging alone does not publish a release.

## Style regression fixture

`port/tests/style-custom-properties.html` reproduces the registered custom-property/animation/SVG cache mismatch. It checks dynamically changed universal values, unset values and inherited widths while animation frames advance. It reproduced the style assertion before the fix and passed afterward on the target OS.

`port/scripts/probe_style_crash.mjs` is the retained loopback DevTools fixture observer, run with a modern Node providing global `fetch` and `WebSocket`. Set `SNOWIUM_CDP_ENDPOINT` for the isolated test browser and pass the served fixture URL and observation duration. Hosted CI hashes these inputs; it does not execute native renderer tests.
