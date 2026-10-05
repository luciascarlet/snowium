#!/usr/bin/env python3
"""Prepare current renderer SBPL without substituting runtime probe parameters."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
source = root / 'chromium-124.0.6367.207/sandbox/policy/mac'
output = root / 'tests/policy-renderer-ipc.sb'
output.write_text((source / 'common.sb').read_text() + '\n' +
                  (source / 'renderer.sb').read_text())
print(output)
