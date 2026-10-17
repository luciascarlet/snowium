# Publish the one-off release

This directory is the source repository. `release-assets/` contains the prebuilt browser assets and is excluded from Git. No full Chromium build tree, SDK or compiler needs to be uploaded or retained for GitHub to host these files.

1. Use the existing `luciascarlet/snowium` repository and its `origin` remote.
2. Commit and push the source files from this directory. Add its GitHub URL as `origin`. Do not force-push over an existing repository.
3. Create and push tag `v124.0.6367.207-sl.5` for that source commit.
4. In GitHub's Releases page choose that tag, mark the release as a prerelease, and attach **all three** files from `release-assets/v124.0.6367.207-sl.5/`: the ZIP, its `.manifest.json` and `SHA256SUMS`. Use `RELEASE-NOTES.md` for the description. Save a draft, review it, then publish.

Alternatively, after the repository and tag are pushed, GitHub CLI can create the draft:

```sh
gh release create v124.0.6367.207-sl.5 \
  release-assets/v124.0.6367.207-sl.5/*.zip \
  release-assets/v124.0.6367.207-sl.5/*.manifest.json \
  release-assets/v124.0.6367.207-sl.5/SHA256SUMS \
  --verify-tag --draft --prerelease \
  --title 'Snowium 124 for Snow Leopard — performance build' \
  --notes-file RELEASE-NOTES.md
```

Creating a draft does not make it a public download. Publish it after review. Publishing triggers the hosted release check, which downloads the assets, verifies checksums and checks every app file and symlink against the manifest. The source workflow checks patches/hashes and script syntax on pushes and pull requests. These jobs verify integrity; neither rebuilds Chromium nor tests the Snow Leopard UI.

Keep a backup of this repository and `release-assets/` before removing the old build inputs. No cleanup is performed by these scripts.
