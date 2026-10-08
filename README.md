# Snowium 124

Chromium Legacy 124.0.6367.207.1 ported to **Intel Snow Leopard 10.6.8**. This repository contains the source patch, compatibility sources, native probes and release tooling. Chromium itself and the SDKs remain external build inputs.

The source includes an experimental native Cocoa core UI port from Chromium 7, developed on **cocoa-2010-ui**. The window chrome, tabs, toolbar, bookmarks bar and omnibox field use AppKit controls and adapted historical source. Chromium 124 still supplies the browser models, menu features and renderer. **2010 UI (Experimental)** and **Aqua Scrollbars (Experimental)** are separate opt-in settings in `chrome://flags`; both default to disabled. The old application icon applies to both UI modes. See [the UI port record](port/cocoa2010/README.md) for build instructions, provenance and validation limits. The published pass40 release described below does not include this experiment.

## Run

Download the ZIP from a GitHub Release, extract it, and double-click `Chromium.app`. You can move the app to `/Applications`. No Terminal command, replacement system library, sandbox-disabling option or certificate override is required. Keep the complete app bundle together.

The default profile is `~/Library/Application Support/Snowium124`; its keychain service is `Snowium124 Safe Storage`. It is separate from Chromium 60. Only x86_64 and 10.6.8 have been tested; this is not a PowerPC or 32-bit build.

The current candidate is **pass40**, released as `v124.0.6367.207-sl.3`. It fixes the CSS custom-property style-cache crash while retaining style assertions, and includes the earlier Lucida Grande font fallback fix. The custom-property animation/SVG regression and website tests passed on 10.6.8. Earlier native tests covered Wikipedia search/article navigation, context menus, scrolling, GitHub profile rendering and sandboxed writable-memory round trips.

Rendering uses software paths and performance can be slow. ChatGPT can spend several minutes compiling JavaScript, show Page Unresponsive and temporarily blank its content; full authentication is unverified. Long sessions, downloads, extensions, printing and media have not been comprehensively tested. This is a compatibility preview based on Chromium 124, not a current Chromium security update.

## Source and CI

Read [BUILDING.md](BUILDING.md) for the source/build record. The hosted `Checks` workflow verifies source hashes and Python/shell syntax on pushes and pull requests. The hosted `Verify release assets` workflow verifies downloadable files after a release is published. These are integrity checks, not Chromium builds or target-machine UI tests. No self-hosted Mac runner is needed.

The current app is packaged as a **one-off prebuilt release** in the ignored `release-assets/v124.0.6367.207-sl.3/` directory. See [PUBLISHING.md](PUBLISHING.md) for uploading it and [RELEASE-NOTES.md](RELEASE-NOTES.md) for the release description. Downloads are available from [GitHub Releases](https://github.com/luciascarlet/snowium/releases).

The repository retains the source patch, overlays, pinned Legacy changes and runtime sources. It excludes the large Chromium checkout, SDKs, toolchains and build output. A tested clean-machine rebuild is still future work; the existing release can be hosted independently of that work.

## Credits

Based on [Chromium](https://chromium.googlesource.com/chromium/src/) and [Chromium Legacy](https://github.com/blueboxd/chromium-legacy), with PLWeakCompatibility, LLVM/compiler-rt and MacPorts LegacySupport. See [NOTICE.md](NOTICE.md), `licenses/`, source notices, and the generated `about_credits.html` shipped beside the app in each release. `chrome://credits` provides Chromium's in-app notices.
