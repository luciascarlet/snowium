#!/usr/bin/env python3
"""Create a private, unmodified std source copy and offline vendor mapping."""
from pathlib import Path
import shutil

here = Path(__file__).resolve().parent
port = here.parent
source = port / "chromium-124.0.6367.207/third_party/rust-toolchain/lib/rustlib/src/rust"
copy = here / "rust-src"
copy.mkdir(exist_ok=True)
if not (copy / "library").exists():
    shutil.copytree(source / "library", copy / "library")
if not (copy / "Cargo.lock").exists():
    shutil.copy2(source / "Cargo.lock", copy / "Cargo.lock")
(here / ".cargo").mkdir(exist_ok=True)
(here / ".cargo/config.toml").write_text(
    '[source.crates-io]\nreplace-with = "vendored"\n'
    '[source.vendored]\ndirectory = "' + str(source / "vendor") + '"\n'
)
