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
