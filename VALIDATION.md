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

## Third preview — pass40 style-cache fix

- Retained native records reproduced the previous renderer crashes in `style_resolver.cc:1646` on lucia.red and `style_resolver.cc:2524` in the reduced custom-property fixture. The mismatch involved identical computed values represented by distinct token-data objects.
- With the fix, the 30-second fixture test advanced animation frames and preserved dynamically mutated universal values, unset values and inherited widths with no regression failures. The 45-second website observation passed. Screen Sharing records cover homepage rendering, Works navigation, scrolling and context menus.
- ChatGPT's login form rendered, but cold JavaScript module compilation caused minutes-long stalls, Page Unresponsive and temporary blank content. Full authentication and extended stability remain unverified.
- Release preparation checks all 159 local app files against the retained target deployment provenance. The installed target framework was rechecked against SHA-256 `9fe7701d07c4be2aeb728a821a88e7f3109147af6cd7eb8e1c177a82841a3730`.
- Source export includes the new style fix, regression fixture and observer, plus the updated native font-probe expectations from the prior fix. Native test results come from the crash-fix records; packaging and hosted integrity checks do not perform native UI tests.
