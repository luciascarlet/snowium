#!/usr/bin/env python3
"""Preserve pristine files while developing reproducible Chromium source diffs."""
import difflib
import pathlib
import shutil

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / "chromium-124.0.6367.207"
ORIGINAL = ROOT / "patches/original"


def edit(path, before, after):
    target = SRC / path
    text = target.read_text()
    if before not in text:
        raise ValueError("Expected source not found in " + path)
    original = ORIGINAL / path
    if not original.exists():
        original.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(target, original)
    target.write_text(text.replace(before, after))


def save_patch():
    changes = []
    for original in sorted(ORIGINAL.rglob("*")):
        if original.is_file() and original.name != ".DS_Store":
            path = original.relative_to(ORIGINAL).as_posix()
            changes.extend(difflib.unified_diff(
                original.read_text().splitlines(True),
                (SRC / path).read_text().splitlines(True),
                fromfile="a/" + path, tofile="b/" + path))
    (ROOT / "patches/chromium-124-snow-leopard.patch").write_text("".join(changes))


if __name__ == "__main__":
    save_patch()
