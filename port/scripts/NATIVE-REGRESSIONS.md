# Native Chromium124 regression runner

`run_native_probes.py` stages the eight actual GN-built executables from
`modern-port/chromium-124.0.6367.207/out/SnowLeopard` and runs them on
`admin@keine.local`. It never builds, relinks, signs, changes system settings, or
uses the separate Chromium60 port. Run the normal build first; the runner checks
what the recorded executable hashes do, not whether every current source edit
was rebuilt.

Read-only preflight (does not connect or write files):

```sh
python3 modern-port/scripts/run_native_probes.py --dry-run
```

Run all probes, or select specific probes after relevant changes:

```sh
python3 modern-port/scripts/run_native_probes.py
python3 modern-port/scripts/run_native_probes.py --only net_https_smoke
python3 modern-port/scripts/run_native_probes.py --only mojo_channel_smoke,mojo_roundtrip_smoke
```

Each run has a unique, non-overwritten directory:

- Remote: `/Users/admin/Snowium/modern-port/native-regressions/<run-id>/<probe>/`
- Local: `modern-port/logs/native-regressions/<run-id>/`

The runner copies only the selected GN probe binaries, `icudtl.dat` for HTTPS,
and the assembled renderer policy when the optional sandbox case is requested. The font probe embeds its font fixture; its resulting PNG is copied
back. Local `inputs/` preserves the exact tested binary snapshots. `provenance.json`
records SHA256 hashes, source/overlay/compatibility-library snapshots, GN args,
remote OS/CPU, executable arguments, exit codes, durations, assertion criteria,
logs, and the PNG. Remote log files also remain in each owned probe directory.
No existing remote browser or profile is touched.

A pass requires exit status **zero**, every expected `PASS` assertion, and no
`FAIL` assertion or timeout. Repeated cases are counted: six sandbox filenames,
16 child receives and 16 parent replies. Nonzero exits always fail, even if a
partial transcript contains `PASS`. The sandbox denial, failed process launch,
and rejected certificate are negative cases checked *inside* their probes;
the successful probe still exits zero. Expected certificate and failed-exec
`ERROR` diagnostics are retained instead of being mistaken for harness failure.
All probes run even if an earlier one fails; the runner exits 1 if any fails,
or 2 for setup/preflight errors. Signing failures are reported without repair.

The Python2.6-compatible watchdog in `native_probe_remote.py` is sent over SSH
stdin. It bounds each executable, including setup/shutdown, and stops only its
own process and verified descendants running the same exact executable path.
It does not kill by process name. SSH also has a transport timeout.

## Coverage

| Probe | Native assertions |
| --- | --- |
| `runtime_smoke` | C++ TLS/destructors, clocks, futures, exceptions/unwind, containers, any/optional/variant |
| `seatbelt_smoke` | Parameter escaping for six paths, allowed/denied writes, unsupported extensions never grant access |
| `foundation_smoke` | Actual PartitionAlloc/V8 TLS and memory protection, Mach rights, read-only shared memory |
| `font_smoke` | Actual Skia system/pattern color conversion, three system fonts, embedded rotated TrueType, PNG output |
| `mach_rendezvous_smoke` | Actual child launch, FD/cwd/env/process-group behavior, authenticated task enrollment/exchange, cleanup, failed exec |
| `mojo_channel_smoke` | 32 mixed FD/Mach messages with preserved order/data and sender FD acknowledgments |
| `mojo_roundtrip_smoke` | Actual two-process Mojo invitation and 16 bidirectional FD/Mach/shared-memory round trips, including convertible writable regions |
| `net_https_smoke` | Verified HTTPS200 with nonempty body, rejected invalid certificate with no response body |

HTTPS defaults to `https://example.com/` and `https://expired.badssl.com/`.
`--valid-url` and `--invalid-url` can select other explicit test endpoints.
Internet/DNS reachability, remote clock, and endpoint certificates affect this
probe. It uses real certificate verification without ignore flags or trust-store
changes. The default URLRequestContextBuilder has no AIA fetcher, so this probe
does not establish fetching of missing intermediates. Positive and negative
requests each have a 30-second application timeout and an 80-second outer bound.

This runner covers existing native integration probes. It does not establish
full browser startup, renderer sandbox behavior on real pages, GPU/video/audio,
printing, downloads, client certificates, or visual UI correctness. V8's separate
`tests/d8_smoke.js`, ARC concurrency/KVO, Rust standard-library, and standalone
security/system tests retain their existing dedicated evidence. The experimental
weak runtime still does not support weak references to toll-free CF objects
released directly through `CFRelease`.


## Renderer sandbox IPC case

After rebuilding `mojo_roundtrip_smoke` with its `//sandbox/mac:seatbelt`
dependency, run both the original unsandboxed baseline and an additional fully
sandboxed child case:

```sh
python3 modern-port/scripts/run_native_probes.py --only mojo_roundtrip_smoke --renderer-sandbox --dry-run
python3 modern-port/scripts/run_native_probes.py --only mojo_roundtrip_smoke --renderer-sandbox
```

The extra result is named `mojo_roundtrip_renderer_sandbox`. It reuses the same
GN executable, concatenates the current `common.sb` and `renderer.sb`, records
source and assembled-policy hashes, and stages the profile in that case's own
remote directory. The child receives runtime parameters through the actual
SeatbeltExec pipe and applies the sandbox before Mach/Mojo/thread startup. A
passing result requires the denied unrelated write, authenticated task exchange,
invitation acceptance, all 16 mixed shared-memory/FD round trips, and clean exit.
An older GN executable without this mode fails the required assertions even if
it otherwise exits successfully.

For a standalone invocation, `prepare_mojo_sandbox_profile.py` writes the raw
`modern-port/tests/policy-renderer-ipc.sb`; pass its remote absolute path as
`mojo_roundtrip_smoke --renderer-profile=/absolute/path/policy-renderer-ipc.sb`.
The retained passing private GN-object link is documented in
`../logs/mojo-roundtrip-sandbox-provenance.json`. It validates this IPC boundary,
not full renderer framework loading or a working browser.
