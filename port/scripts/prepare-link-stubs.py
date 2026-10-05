#!/usr/bin/env python3
"""Prepare target-only text link stubs for Snow Leopard framework locations.

CFNetwork's install name follows the measured 10.6 system library ID. Audio
link stubs come from the preserved 10.6 SDK so AudioUnit APIs bind to their
actual old provider rather than modern AudioToolbox reexports. Headers, system
libraries and already-linked binaries are unchanged.
"""
from hashlib import sha256
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "MacOSX14.5.sdk/System/Library/Frameworks/CFNetwork.framework/CFNetwork.tbd"
SOURCE_SHA256 = "1f2dd8acda54c541cdbb4ea1dca86453ec074059a5a7410513f9229fcb8e721c"
ORIGINAL_NAME = "/System/Library/Frameworks/CFNetwork.framework/Versions/A/CFNetwork"
TARGET_NAME = (
    "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/"
    "CFNetwork.framework/Versions/A/CFNetwork"
)

data = SOURCE.read_bytes()
if sha256(data).hexdigest() != SOURCE_SHA256:
    raise SystemExit("Unexpected CFNetwork SDK stub; preserving existing target stub.")
text = data.decode()
old = "install-name:    '" + ORIGINAL_NAME + "'"
new = "install-name:    '" + TARGET_NAME + "'"
if text.count(old) != 1:
    raise SystemExit("Expected exactly one CFNetwork install-name entry.")
result = text.replace(old, new).encode()
destination = ROOT / "link-stubs/CFNetwork.framework/CFNetwork.tbd"
destination.parent.mkdir(parents=True, exist_ok=True)
if not destination.exists() or destination.read_bytes() != result:
    destination.write_bytes(result)
metadata = {
    "source": str(SOURCE.relative_to(ROOT)),
    "source_sha256": SOURCE_SHA256,
    "original_install_name": ORIGINAL_NAME,
    "snow_leopard_install_name": TARGET_NAME,
    "output_sha256": sha256(result).hexdigest(),
    "scope": "x86_64 Snow Leopard linker search path only; SDK headers unchanged",
}
(destination.parent / "provenance.json").write_text(json.dumps(metadata, indent=2) + "\n")
print(destination)

# Modern audio TBDs bind AudioComponent/AudioUnit entry points to AudioToolbox.
# Snow Leopard exports them from AudioUnit. These original SDK files are link
# stubs, not runtime libraries; only the x86_64 target searches this directory.
audio_hashes = {
    "AudioToolbox": "f8cd2d9c4e634bd72e890ef077ed80b74dd09613555f9470199124f184fec148",
    "AudioUnit": "16e920f7267d95ddac7d750126c350b48c437873df4bddb0ddae4cb7ecee3d37",
}
for audio_name, expected_hash in audio_hashes.items():
    audio_source = (Path(os.environ["SNOWIUM_LEGACY_SDK"]) / "System/Library/Frameworks"
                    / (audio_name + ".framework") / audio_name)
    audio_data = audio_source.read_bytes()
    if sha256(audio_data).hexdigest() != expected_hash:
        raise SystemExit("Unexpected 10.6 SDK audio stub: " + str(audio_source))
    audio_destination = ROOT / "link-stubs" / (audio_name + ".framework") / audio_name
    audio_destination.parent.mkdir(parents=True, exist_ok=True)
    if not audio_destination.exists() or audio_destination.read_bytes() != audio_data:
        audio_destination.write_bytes(audio_data)
    (audio_destination.parent / "provenance.json").write_text(json.dumps({
        "source": str(audio_source),
        "source_sha256": expected_hash,
        "output_sha256": sha256(audio_data).hexdigest(),
        "scope": "unmodified original SDK link stub; target-only framework search",
    }, indent=2) + "\n")
    print(audio_destination)
