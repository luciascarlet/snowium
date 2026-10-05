# Prepared candidate validation — 2026-10-05

- Source manifest and pinned Legacy patch hashes passed. Python parsing and shell syntax passed.
- Both GitHub workflows passed actionlint 1.7.7. They have not yet run on GitHub.
- Release ZIP creation and independent release verification passed: 159 physical app files and five symlinks match the manifest; required credits/notices are present.
- The ZIP was transferred to the actual Snow Leopard 10.6.8 test machine and extracted using its native `/usr/bin/unzip`. All 159 physical file hashes and five symlinks matched, and the main executable retained execute permission. ZIP entries require extraction version 2.0.
- Plain macOS Launch Services launch (`open Chromium.app`, without development flags) started the pass38 executable with only the standard Finder `-psn` argument. Interactive browsing coverage predates this packaging step and is described in the release notes.

Prepared ZIP SHA-256:

```text
23feb631301353d2a17808ec37a1a9ea8e9c8a93de979e45025015c72be4fb0a
```

No GitHub remote, hosted repository or published release was created. No original build inputs or Chromium 60 files were removed.

## Second preview — pass39 font fix, 2026-10-05

- The actual gfx fallback regression aborted before the fix and passed after it on 10.6.8 for Lucida Grande, Helvetica and Arial, including native font identity and derived bold/italic fonts.
- A tab title containing missing glyphs caused pass38 to abort after 13.61 seconds with the reported GetFallbackFonts/PlatformFontMac stack. Pass39 remained alive throughout the 30-second fixture test, loaded the expected page and painted a native window.
- The retained deployment provenance records 159 matching physical files and a passing ARC provider inventory for all nine bundled executables. Release preparation rechecked every local file against that provenance.
- The local rebuilt framework and the installed target framework both match SHA-256 `307cb83473b28ce98fc02396d6eaa3abfbfeef17022999361d7ff6d2068b7486`.
- The release exports the font source fix and enhanced gfx regression. Source/patch checks and independent ZIP verification are run before publication. Native font/browser tests are retained results from the crash-fix work, not new tests performed by hosted CI.
- Separate renderer assertions involving CSS custom properties remain unresolved. The short fixture test does not establish extended browsing stability.
