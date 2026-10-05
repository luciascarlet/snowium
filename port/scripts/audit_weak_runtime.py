#!/usr/bin/env python3
"""Read-only inventory of PLWeak runtime providers in one browser bundle.

Each executable is a separate process. All bundled shared images are treated
as potentially co-loaded in that process, including optional graphics backends.
This deliberately conservative check does not assume a particular dlopen order.
"""
import argparse
import json
import pathlib
import struct
import sys

CPU_X86_64 = 0x01000007
MH_EXECUTE, MH_DYLIB, MH_BUNDLE = 2, 6, 8
MARKERS = (b"release_PLWeakCompatibility_swizzled\0",
           b"dealloc_PLWeakCompatibility_swizzled\0")


def inspect(path):
    """Return the x86_64 image type and provider markers, even after stripping."""
    with path.open("rb") as f:
        header = f.read(32)
        if len(header) < 32:
            return None
        offset, size = 0, path.stat().st_size
        if header[:4] in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"):
            fat64 = header[:4] == b"\xca\xfe\xba\xbf"
            count = struct.unpack_from(">I", header, 4)[0]
            if count > 64:
                return None
            f.seek(8)
            for _ in range(count):
                entry = f.read(32 if fat64 else 20)
                if len(entry) != (32 if fat64 else 20):
                    return None
                cpu = struct.unpack_from(">I", entry)[0]
                if cpu == CPU_X86_64:
                    offset, size = struct.unpack_from(">QQ" if fat64 else ">II", entry, 8)
                    break
            else:
                return None
            f.seek(offset)
            header = f.read(32)
        if header[:4] != b"\xcf\xfa\xed\xfe":
            return None
        cpu, _, kind = struct.unpack_from("<III", header, 4)
        if cpu != CPU_X86_64 or kind not in (MH_EXECUTE, MH_DYLIB, MH_BUNDLE):
            return None
        if offset + size > path.stat().st_size:
            raise ValueError("truncated Mach-O: " + str(path))
        f.seek(offset)
        data = f.read(size)
    markers = [marker.decode().rstrip("\0") for marker in MARKERS if marker in data]
    if len(markers) == 1:
        raise ValueError("incomplete PLWeak signature: " + str(path))
    return {"path": str(path), "kind": kind, "weak_provider": len(markers) == 2,
            "provider_markers": markers}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=pathlib.Path,
                        help="Inventory all x86_64 executables and shared images recursively.")
    parser.add_argument("--executable", type=pathlib.Path, action="append", default=[])
    parser.add_argument("--library", type=pathlib.Path, action="append", default=[])
    parser.add_argument("--allow-no-provider", action="store_true",
                        help="Permit pure C/C++ or MRC groups; browser bundles normally require one.")
    args = parser.parse_args()
    if args.bundle and (args.executable or args.library):
        parser.error("Use either --bundle or explicit --executable/--library inputs.")
    if not args.bundle and not args.executable:
        parser.error("Supply --bundle or at least one --executable.")
    if args.bundle and not args.bundle.is_dir():
        parser.error("--bundle must be an existing directory.")
    paths = (args.bundle.rglob("*") if args.bundle else args.executable + args.library)
    images, seen = [], set()
    for path in paths:
        if args.bundle and not path.is_file():
            continue
        path = path.resolve(strict=True)
        if path in seen:
            continue
        seen.add(path)
        image = inspect(path)
        if image:
            images.append(image)
        elif not args.bundle:
            raise ValueError("explicit input is not an x86_64 executable/shared image: " + str(path))
    executables = [i for i in images if i["kind"] == MH_EXECUTE]
    libraries = [i for i in images if i["kind"] != MH_EXECUTE]
    processes = []
    for executable in executables:
        providers = [i["path"] for i in [executable] + libraries if i["weak_provider"]]
        valid = len(providers) == 1 or (args.allow_no_provider and not providers)
        processes.append({"executable": executable["path"], "providers": providers,
                          "provider_count": len(providers), "pass": valid})
    result = {"pass": bool(processes) and all(p["pass"] for p in processes),
              "basis": "PLWeak release/dealloc selector signatures in each x86_64 slice",
              "scope": "each executable plus all supplied/bundled shared images",
              "images": images, "processes": processes}
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["pass"] else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, struct.error) as error:
        print("FAIL weak-runtime audit: " + str(error), file=sys.stderr)
        sys.exit(2)
