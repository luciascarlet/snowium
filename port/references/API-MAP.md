# Chromium Legacy 124: Snow Leopard API map

This map reuses the working Chromium 60 source port without changing it. Paths
below are relative to the workspace; `old/` means
`source-port/chromium-60.0.3112.113/`. The 60 port's successful native checks are
evidence for the implementation strategy, not proof that the 124 integration
already works.

## Start with the observed boundaries

`evidence/missing-imports.tsv` contains **474 absent imports: 116 non-weak and
358 weak** from the original Chromium Legacy 124 framework on 10.6.8. The last
column is the import's weak flag. These counts exclude `dyld_stub_binder`, which
`tools/probe.c` deliberately skips. Missing optional APIs must remain guarded;
they do not each need a replacement. The import list cannot reveal missing
Objective-C selectors, kernel-operation incompatibility, or inlined ABI
assumptions.

The previous 124 binary experiment reached three such additional boundaries:

- Thirty inlined reads assumed Lion's pthread TSD layout. Snow Leopard's array
  is at displacement `0x60`, not zero. Replace source fast paths with the public
  pthread API rather than copying binary edits.
- Ipcz fileport conversion failed even though the functions resolve. A kernel
  operation existing in an exported wrapper does not establish support.
- A later modified-binary SIGSYS occurred near a code-page boundary. Its signing
  check failed, but causality was not established. The new source work does not
  require revisiting or repairing that binary's signing.

## Runtime and platform replacements

| Boundary | Source strategy | Reusable local code / validation |
|---|---|---|
| C/POSIX functions such as `strnlen`, `wcsdup`, `arc4random_buf`, `getentropy`, `clock_gettime`, `os_unfair_lock` | Use the existing MacPorts Legacy Support implementation where semantics match; link its archive privately to avoid global symbol interposition. | `third_party/macports-legacy-support/`, pinned commit `d7744801e5d53b6134443968e96401d5e8ab5900`; `source-port/runtime/libMacportsLegacySupport.a`; `source-port/patches/macports-legacy-support-cxx-linkage.patch`. |
| C++ runtime | Build the version of libc++ used by the modern source, targeting 10.6, with its legacy support fixes. The 60 port's libc++5 binary is not a drop-in library for modern C++20 Chromium. | `old/build/config/compiler/BUILD.gn` demonstrates bundled runtime/rpath and hidden static legacy support; `source-port/runtime/usr/lib` preserves the original 60 package. |
| Compiler `thread_local` / Mach-O TLV | Prefer compiler-emulated TLS with an audited runtime or explicitly implemented TLV support; verify initial values, per-thread isolation and destructor/storage order on 10.6. | Historical `compat/tlv.c`, `compat/tlv.S`, `tools/test_tlv.c`, `tools/test_tlv.S`, `evidence/runtime-tests.log` are a reference and test seed. The assembly's Apple license is `compat/APPLE_LICENSE`. |
| PartitionAlloc direct pthread TLS | In `base/allocator/partition_allocator/src/partition_alloc/partition_tls.h`, select `pthread_getspecific` instead of `FastTlsGet` on 10.6. | Existing 124 `FastTlsGet` hardcodes `movq %%gs:(,%1,8), %0`. 60's `platform_smoke.mm` provides a target pthread-isolation test. |
| V8 direct pthread TLS | Audit `V8_FAST_TLS_SUPPORTED` and `InternalGetExistingThreadLocal` in `v8/src/base/platform/`; prevent Lion-only direct layout assumptions. This is separate from compiler-generated `thread_local`. | 60's `overlay/snow_leopard/engine_smoke.js` and `logs/v8-native-optimization.log` cover execution, not the new TLS implementation. |
| Strong Objective-C ARC entry points | Reuse an ARC compatibility runtime or MRC primitive implementation in a dedicated target. Do not turn the browser's Objective-C sources globally into MRC without fixing ownership. | Historical `compat/runtime.m` contains retain/release/autorelease, pool push/pop and storeStrong equivalents; these allowed native 124 initialization. |
| Zeroing weak Objective-C references | Prefer existing PLWeakCompatibility; inventory actual weak target classes and validate custom retain/release, KVO and thread races. | [PLWeakCompatibility](https://github.com/plausiblelabs/PLWeakCompatibility), BSD-3-Clause, explicitly supports ARC weak references on 10.6. Its basic backend warns about bridged CF objects and KVO. Historical `compat/weak.m` only hooks NSObject and is less complete. |
| `property_copyAttributeValue` | Parse `property_getAttributes` and use `object_getInstanceVariable` where still needed. | `old/base/mac/objc_release_properties.mm`, tested by `overlay/snow_leopard/platform_smoke.mm`. |
| Process launch inheritance / `posix_spawn_file_actions_addinherit_np` | Prefer the Chromium fork/exec path restored for 10.6, with descriptor shuffle and close-on-exec behavior preserved. If the modern code has removed that path, adapt the implementation rather than returning success from an inheritance stub. | `old/base/process/launch_mac.cc`, `launch_posix.cc`; native smoke verifies a close-on-exec pipe remapped to fd7 in the child. |
| `audit_token_to_pid` | Use the older `audit_token_to_au32` decoder. Preserve the kernel audit-token verification. | `old/base/mac/mach_port_broker.mm`. |
| Mach shared-memory maximum protection | Drop unsupported `VM_PROT_IS_MASK`; retain precisely the required maximum read/write permissions. | `old/base/memory/shared_memory_handle_mac.cc`; native writable and read-only handle mapping passes. |
| PartitionAlloc protected-page discard | Use Darwin10 `MADV_FREE` where the modern code uses `MADV_FREE_REUSABLE`, and pair it with correct permission restoration. Preserve the reservation; never substitute unmap. | `old/base/allocator/partition_allocator/page_allocator.cc`; 64 decommit/recommit cycles starting with `PROT_NONE` pass in the native platform test. |
| V8 page reuse | Audit `OS::DiscardSystemPages`, `OS::RecommitPages`, `OS::SetPermissions` together. Modern Darwin code uses `MADV_FREE_REUSE` and returns success without checking unsupported non-EAGAIN errors. | 124 V8 `src/base/platform/platform-posix.cc`; select a 10.6-compatible path and test write/read after protected-page reuse. |
| Mach/bootstrap protocol | Restore 10.6 lookup request layout (no instance UUID); keep the original Mach server transport when XPC is unavailable. | `old/sandbox/mac/os_compatibility.cc`, `launchd_interception_server.cc`, `mach_message_server.cc`, `message_server.h`, `xpc.h`, `pre_exec_delegate.cc`. Layout restored from Chromium49. |
| Modern Ipcz fd transport | Prefer selecting the older Mojo transport in source for the first native integration. Do not fake a valid Mach fileport. Investigate AF_UNIX descriptor passing only if modern Mojo requires a new transport. | Historical `evidence/wrapped_platform_handle.cc` identifies `fileport_makeport/makefd`; `README.md` records the real failure. |

PLWeakCompatibility's optional backend is
[MAZeroingWeakRef](https://github.com/mikeash/MAZeroingWeakRef). It handles more
cases using private CoreFoundation/KVO integration, whose macros and assumptions
require review. [Clang's driver](https://clang.llvm.org/doxygen/Darwin_8cpp_source.html)
still describes the separate libarclite back-deployment mechanism; it is not
proof that a current local Xcode includes a 10.6 runtime.

## Sandbox: reuse the working implementation, preserve its details

`old/sandbox/mac/seatbelt.cc` implements `InitWithParameters` using Snow Leopard's
`sandbox_init`. A local SBPL `param` function maps validated input strings to
values. Its tests are in `source-port/overlay/snow_leopard/seatbelt_smoke.cc`.

The discovered non-obvious requirements are:

- SBPL on Darwin10 wants UTF-8 bytes encoded with `\xHH`. Unicode `\uXXXX`
  escapes do not preserve non-ASCII path bytes. The native tests include quotes,
  backslashes, accented text, astral Unicode and an injection-looking string.
- Lion sandbox extension APIs are absent. Remove extension rules on 10.6 and
  supply the resources the child actually needs through the older profile and
  broker. Do not claim extension consumption succeeded.
- Darwin10 dyld132 has an invalid-free path when resolving `@loader_path` after
  a sandbox-denied `realpath`. The 60 renderer grants **metadata-only** access to
  its bundle and parent directories; this fixed the crash with the sandbox
  active. Preserve the distinction between metadata and content permissions.
- Modern sandbox profile operation names may also postdate10.6. The parameter
  adapter alone is not sufficient; compile and test each process's policy on
  the target before blaming transport or renderer initialization.

The relevant 60 integration is in `old/content/common/sandbox_mac.mm`,
`old/content/renderer/renderer.sb`, and `old/sandbox/mac/BUILD.gn`. The 60 port
actually ran its renderer sandbox and verified that unrelated writes fail.

## Cocoa, fonts and graphics

| Boundary | Reusable implementation and integration note |
|---|---|
| Backing scale / coordinate conversion | `source-port/overlay/snow_leopard/cocoa_compat.h/.mm`: 1x backing, old screen conversion and method installation only where absent. **Its current guard is SDK maximum <10.7. A modern SDK build must change the activation condition to the port build flag/runtime capability, while avoiding duplicate declarations.** |
| Wheel input | Same adapter uses `kCGScrollWheelEventIsContinuous` plus CGEvent pixel delta axes; phase/momentum are zero on10.6. Preserve horizontal as well as vertical input. |
| Scrollbar implementations | `SnowLeopardScrollbarTheme.h/.mm` plus the modifications to `old/third_party/WebKit/Source/platform/scroll/ScrollbarThemeMac.mm` adapt Chromium49 HITheme rendering. Modern Blink geometry/interfaces must be adapted, not the entire old class copied blindly. |
| Fonts / `CTFontDrawGlyphs` | `old/third_party/skia/src/ports/SkFontHost_mac.cpp` uses `CGContextShowGlyphsAtPositions`, preserving CGContext text transformation. The vertical glyph metrics returned by10.6 are unscaled font units, so multiply by font size / units-per-em. |
| Font data descriptor / family matching | Historical `compat/fonts.c` constructs CTFont descriptors via CGDataProvider + CGFont and filters collection descriptors by family. Prefer the already-tested Skia/font source path where applicable. |
| Font cascade | `old/ui/gfx/font_fallback_mac.mm` uses the exported10.6 `CTFontCopyDefaultCascadeList`, with dynamic use of the newer language API when available. |
| NSColor custom space | `old/skia/ext/skia_utils_mac.mm`: convert to device RGB, then use `getComponents:`. On10.6 `NSCustomColorSpace` can throw for `getRed:green:blue:alpha:` even after conversion. Native regression lives in `font_smoke.mm`. |
| System font weight selectors | Use availability/selector checks, not checks for an exact later OS version. Legacy's existing branches may assume all pre10.10 systems still have Lion selectors. |
| Nib loading | `old/ui/base/cocoa/nib_loading.mm`: older `instantiateNibWithOwner:topLevelObjects:`. |
| Drag sessions / NSDraggingItem | The 60 source restores old synchronous `NSDragPboard` / `dragImage` dragging in bookmarks, omnibox and `old/ui/views/cocoa/drag_drop_client_mac.mm`. Views-based124 needs an adapted equivalent in its current drag client. Do not create inert NSDraggingItem classes. |
| Sheets/fullscreen | Older `NSApp beginSheet/endSheet` and Chromium's immersive fullscreen path are available in60. Cocoa traffic-light reparenting in60 is specific to its old tabstrip and must not be assumed necessary for Legacy124's classic title bar. |
| GPU / modern IOSurface and Metal | Retain Legacy's Lion software-rendering policy for10.6. Software compositor selection is source behavior, not a permanent `--disable-gpu` diagnostic flag. |

## Networking, media and optional frameworks

The 60 trust-store work is directly useful: `old/net/cert/internal/trust_store_mac.cc`
uses `SecPolicyGetOID` to preserve policy restrictions, enumerates certificates
when the newer keychain subject query is absent, and compares Chromium's own
RFC5280-normalized names. `SSLPolicyOID()` consistently encodes the binary OID.
Never make the missing normalized-issuer or policy APIs return a nominal success.
Modern Chromium's verifier has changed, so adapt these operations at its actual
system-store boundary. Normal HTTPS and expired-certificate rejection passed in60.

AVFoundation/CoreMedia functions account for a large fraction of the 116 hard
imports. The practical first configuration is software media decoding and ordinary
composition, with camera capture disabled until a real QTKit backend exists.
The60 source changes span `media/BUILD.gn`, `media/base/mac`, `media/gpu`,
`media/capture`, and `ui/accelerated_widget_mac`. The replacement camera factory
is `source-port/overlay/snow_leopard/video_capture_device_factory_mac.cc`.
CoreAudio remains usable; reuse its old device-notification implementation from
`device_monitor_mac.mm` and `old/media/audio/mac/audio_manager_mac.cc`.

Optional WebBluetooth, CIDetector/shape detection, Handoff, native Notification
Center, TouchBar, NSProgress and dictionary hyphenation can report unavailable
in a first configuration. This is feature selection rather than an all-purpose
Apple framework shim. Preserve working native HID/gamepad and old speech/audio
paths where they exist. Modern weak-linked frameworks should not become hard
load dependencies accidentally.

## Reusable evidence harness

Copy/adapt these files into the new port rather than editing the60 copies:

- `source-port/overlay/snow_leopard/platform_smoke.mm`, `font_smoke.mm`,
  `seatbelt_smoke.cc`, `engine_smoke.js`.
- `source-port/tests/browser-smoke.html`, `payload.json`, `serve.py`; the server
  is threaded because Chromium preconnections stalled a single-threaded server.
- `source-port/scripts/check_browser.mjs`, `probe_https.mjs`: CDP fixture/input/
  scroll and separate-tab HTTPS/interstitial checks.
- `window_info.py`, `capture_test_window.py`: capture only the verified own test
  window, never the desktop. New port needs its own title/PID/profile/ports.

First meaningful milestones are native modern-toolchain C++/ARC tests, then
the adapted platform/font/sandbox tests, V8 JIT and WebAssembly, Content Shell
with its renderer sandbox, then full Chromium UI and normal HTTPS validation.
Neither a successful modern build nor a passing60 check substitutes for any of
these target results.

## Implemented 124 foundations and IPC source work

The source tree now contains guarded `SNOW_LEOPARD_PORT` replacements for:

- PartitionAlloc, V8 and base's Apple x86-64 fixed-offset TLS fast paths: use their existing pthread key implementation. Darwin 10 uses a different pthread layout. The base path in `base/threading/thread_local_storage.cc` was found through a native CheckedLockImpl/task-executor crash and verified by the passing Mojo tests.
- PartitionAlloc's `MADV_FREE_REUSABLE`/`MADV_FREE_REUSE` accounting: use `MADV_FREE`; keep explicit protection updates.
- V8 page allocation: omit `MAP_JIT`, use `MADV_FREE`, and actually restore memory protection during recommit.
- `base::apple::CreateMachPort`: one receive allocation, the requested queue limit, and at most one send reference. The Lion patch's duplicate allocation/insertion was not retained in the Snow branch.
- Legacy Mojo channels: AF_UNIX byte transport with SCM_RIGHTS for FDs, typed in-band Mach names, and a browser-owned Mach relay derived from Chromium 60. The modern Mach-only Channel also uses `fileport_makeport`; merely disabling MojoIpcz is insufficient.
- Authenticated task-port bootstrap before Mojo starts: the existing Mach rendezvous request now carries the child's task send right. The server checks its kernel audit PID against the launch registration and `pid_for_task`. Its retained task map is the relay provider. This avoids a dependency loop in 124, whose other task-port provider obtains its first task port over Mojo itself.
- Browser launch glue maps the Mojo socket FD, opts into task-port enrollment, and the child finishes the independent Mach handshake before accepting the Mojo invitation.
- MojoIpcz remains disabled in this Snow build even if a feature/environment setting tries to enable it. Its fileport-based transport has not been ported.

The narrow relay implementation is `overlay/snow_leopard/mach_port_relay.{h,cc}`. The source diff is captured alongside all other agents' source work in `patches/chromium-124-snow-leopard.patch`; it is against the already-applied Chromium Legacy Lion base. Replay scripts `apply_ipc_*.py` record the original edit sequence, but are one-shot source transformations; use the consolidated patch when rebuilding the tree.

### Native kernel evidence

`logs/foundation-kernel-native.log` was produced on the actual 10.6 Mac:

- `fileport_makeport` raises SIGSYS for regular files, both pipe ends, and Unix sockets, despite the exported userspace wrapper.
- `MADV_FREE_REUSABLE` fails on protected memory; `MADV_FREE` succeeds.
- A Mach receive queue limit of 1024 is accepted.
- Read-only Mach memory rejects a writable mapping with `KERN_INVALID_RIGHT`.

`logs/mach-relay-native.log` passes the two-process FD plus shared-memory round trip, including the broker extracting the child's send reference with MOVE_SEND and verifying it is consumed. These are real native kernel operations, not placeholder handles.

`logs/mach-rendezvous-native.log` passes bootstrap registration/lookup, audited child identity, `pid_for_task` verification, rejection of a non-task right, and the zero-port reply needed by the new bootstrap. Temporary named services are unregistered by the test.

### Chromium-native validation targets

The following probes exercise actual Chromium 124 code rather than duplicate implementations; compilation/native execution results must be checked separately:

- `snow_leopard/foundation_smoke`: base/PartitionAlloc/V8 pthread TLS isolation, repeated protected decommit/recommit, Mach right counts/queue size, and read-only shared memory.
- `snow_leopard/mach_rendezvous_smoke`: actual `base::LaunchProcess` plus patched MachPortRendezvous parent/child exchange, task lookup, and exit cleanup.
- `snow_leopard/mojo_channel_smoke`: actual `ChannelPosix` sends 32 messages with FD/Mach/Mach/FD attachments, validates ordering/content/shared memory, and verifies Darwin acknowledgment releases sender FDs.
- `snow_leopard/mojo_roundtrip_smoke`: actual parent/child `OutgoingInvitation` and `IncomingInvitation`, task enrollment before Mojo initialization, and 16 mixed FD/Mach/Mach/FD echoes through NodeController. It validates file contents and child writes in the same shared buffer seen by the parent. Setup and message waits are bounded. Native execution passed; see the actual Mojo validation below.

### Deliberate current limits

This initial relay supports Mach send rights. An attempt to send a Mach receive right through a NodeChannel is rejected, not reinterpreted as a send right. Normal browser channel endpoints now use FDs, and normal Mach shared-memory attachments use send rights.

Only direct children enrolled by the browser's launch path can use the relay. Child-requested additional broker clients are rejected because an arbitrary child-supplied PID is not authorization to extract rights from that task. A future nested-child launch path needs its own authenticated enrollment protocol.

As in the Chromium 60 relay, a child releases ownership of a send reference when it sends its name to the broker. If the broker dies before consuming it, that reference can survive until the child's exit. This is a bounded-lifetime failure-path leak, not permission to access an unrelated task.

The primitive tests alone establish Darwin 10 viability. Subsequent actual Chromium-native validation below proves the direct parent/child NodeController graph and shared-memory/file-descriptor round trip. The renderer-policy IPC test below additionally establishes this transport with the actual renderer policy active; complete browser/UI startup and nested process graphs remain unverified.

### Actual Chromium launch validation

Darwin 10 exports neither `posix_spawn_file_actions_addinherit_np` nor `POSIX_SPAWN_CLOEXEC_DEFAULT`. A native experiment also found that enumerating every numeric descriptor with spawn close actions fails with EBADF on holes (`logs/posix-spawn-native.log`). Enumerating only open descriptors in the parent would race other threads.

`base/process/launch_mac.cc` now has a Snow-only fork/exec backend based on Chromium 60, with all storage prepared before fork, no child heap work or logging, an explicit descriptor map, a CLOEXEC exec-error pipe, child-only cwd/environment changes, and default signal/exception state before exec. Its existing Mach rendezvous launch lock and PID enrollment remain in place.

`logs/rendezvous-private-native.log` records 15 passing checks using the actual Chromium 124 LaunchProcess and rendezvous source, privately compiled with the GN flags and linked to the built Chromium base objects. Checks cover identity-mapped CLOEXEC descriptors, closure of an unrelated high descriptor, process groups, child cwd/environment with parent state unchanged, zero-port authenticated task exchange, exit-watcher task cleanup, and synchronous failed-exec reporting. The executable is `runtime-compat/build-clang19-sdk14/mach_rendezvous_smoke-explicit`; it is a private probe relink, not evidence of a complete browser build.

### Actual Mojo source validation on Snow Leopard

`logs/mojo-channel-private-native.log` passes 32 actual ChannelPosix messages with FD/Mach/Mach/FD attachments and verifies Darwin acknowledgment releases all sender descriptors.

`logs/mojo-roundtrip-private-native.log` passes 16 actual parent/child NodeController round trips. The child authenticates its task port before Mojo initialization, accepts an OutgoingInvitation, maps two handles to one shared buffer, verifies both file attachments, updates shared memory, and echoes the attachments. The broker consumes the child's Mach send references and verifies the shared writes through its original mapping. The final acknowledgment permits a clean child exit. This exercises the source-ported transport through public Mojo APIs, not just relay primitives.

These executables were privately linked from actual Chromium GN objects plus privately compiled changed source, without fake symbols or unresolved imports. Unused net/quiche archives were omitted from the private probe link; the complete browser still needs those archives. Private build helpers are `runtime-compat/build_private_mojo.py` and `runtime-compat/link_private_mojo.py`. The latter explicitly substitutes the corrected base TLS and launch objects before the base archive. All private outputs stay outside the Ninja object tree.

The first run exposed a third fixed-GS-offset TLS path in Chromium base, causing a null pointer in CheckedLockImpl::Acquire during task executor creation. Its Snow branch now uses PlatformThreadLocalStorage::GetTLSValue (pthread_getspecific), preserving the existing slot lifetime/destructor implementation. Both native probes then exited successfully. Bare C++ probe threads emit a few NSAutoreleaseNoPool messages; these are visible in the logs and do not count as browser lifetime/leak validation.

`logs/foundation-tls-private-native.log` additionally passes all seven actual foundation checks, now including base ThreadLocalStorage::Slot alongside PartitionAlloc and V8 TLS. Parent and worker values remain isolated; protected decommit/recommit, Mach queue/reference counts, and read-only shared-memory checks also pass.

### ANGLE patch compatibility correction

The supplied `references/angle-lion.patch` adds a call to `ProgramExecutable::hasAnyDirtyBit()` in `Program::needsSync()`, but the pinned ANGLE revision `c67f290ef0f0433acb766c024d28c6f59f48b909` has neither that method nor a corresponding dirty-state queue. Its `Program::syncState()` only waits optional link tasks. The Snow source diff restores the pinned revision's `!mOptionalLinkTasks.empty()` condition. Uniform setters still call the renderer and send executable-change notifications; uniform-block binding changes still mark Context's uniform buffer and block dirty bits. This corrects a mismatched Legacy patch hunk without suppressing any implemented dirty-state work. The formerly failing `FrameCapture_mock.cpp` compiled with its exact GN flags into a private object (`logs/angle-needs-sync-private-compile.log`, successful empty log); the full ANGLE/browser build is separate validation.

### CoreAudio playback and device monitoring audit

The 124 audio graph retains `media/audio/apple/audio_auhal.cc`, `scoped_audio_unit.cc`, Mac AudioManager/CoreAudio utilities and `audio_device_listener_mac.cc`, with CoreAudio, AudioUnit and AudioToolbox linked. Its device listener already uses the older `AudioObjectAddPropertyListener` / `AudioObjectRemovePropertyListener` C callbacks, not Lion block APIs. Modern enum spellings such as `kAudioObjectPropertyElementMain` remain numeric aliases of old values; the 60-era SDK compile guards around logging-only property enums are unnecessary when compiling against the modern SDK. VoiceProcessingIO is already advertised only on 10.12+, and private AudioDeviceDuck is weak-imported and null-checked. ScreenCaptureKit loopback remains unavailable on Snow; ordinary playback and AUHAL microphone paths remain present.

`tests/coreaudio_native.c` and `logs/coreaudio-native.log` verify on actual 10.6.8: default output and nominal sample-rate queries; default-output, device-list and sample-rate callback listener registration/removal; HAL AudioUnit creation, input/output configuration, Chromium-style stereo Float32 format, render callback installation, initialization, a 300ms silent output stream, and clean stop/uninitialize/dispose. The stream delivered 25 callbacks at 44.1kHz. The probe does not change system volume, default device, global sample rate or global buffer size. It does not establish audible browser playback, microphone capture or actual hotplug event delivery.

A real compatibility difference was confirmed: the AUHAL output `kAudioUnitProperty_AudioChannelLayout` query returns -10877 on this system, whereas output `kAudioUnitProperty_StreamFormat` works. The Lion base already skips channel-layout querying below 10.12, but 124 would then assume stereo. The Snow source now obtains the actual stream channel count and applies the 60-era GuessChannelLayout/discrete fallback, preserving mono and multichannel capability instead of forcing stereo. Only this machine's stereo configuration has native validation. The irrelevant 10.10+ CoreAudio dispatch-interposition workaround is no longer attempted by Snow AudioManager initialization. `audio_manager_mac.cc` compiles with its exact GN flags into a private object (`logs/audio-manager-private-compile.log`); complete Chromium audio service playback remains a later browser integration test.

### IOSurface API boundary

Despite newer SDK availability annotations, the 10.6 SDK declares IOSurfaceCreateMachPort and IOSurfaceLookupFromMachPort available on 10.6, and the native framework exports both. `tests/io_surface_native.c` creates a surface, writes it, makes a Mach port, looks it up, and verifies matching ID, dimensions and contents; all three checks pass in `logs/io-surface-native.log`. The 124 compositor can retain Mach-port IOSurface transport rather than downgrade to global surface IDs. This standalone probe proves the native API/kernel path; actual composited browser frames remain separate validation.

### Renderer sandbox activation and IPC integration

The 124 helper entrypoints (`content/shell/app/shell_main_mac.cc` and
`chrome/app/chrome_exe_main_mac.cc`) apply SeatbeltExec before loading the main
framework. `ChildThreadImpl` performs the Mach rendezvous later, before accepting
its inherited Mojo endpoint. Moving authentication before sandbox activation
would hide the real integration boundary.

`mojo_roundtrip_smoke --renderer-profile=...` now uses actual Chromium
`SeatbeltExecClient`/`SeatbeltExecServer`: the parent sends a source-policy
protobuf through an inherited pipe after launching/enrolling its child. The
child applies `common.sb` + `renderer.sb` before its AtExitManager, CommandLine,
Mach client, Mojo initialization and IO thread. It verifies an unrelated write
is denied, authenticates its task port, accepts the actual invitation, and
completes all 16 FD/Mach/Mach/FD shared-memory round trips with a clean exit.
Native log: `logs/mojo-roundtrip-sandbox-native.log`. Exact source, object,
binary and policy hashes, including matching remote binary/policy hashes:
`logs/mojo-roundtrip-sandbox-provenance.json`.

The runtime parameters use the real browser PID and `base::apple::BaseBundleID`.
The current policy's existing exact `bundle-id.MachPortRendezvousServer.pid`
lookup permission is sufficient. No new permission or transport relaxation was
needed. Anonymous Mach shared buffers and inherited Unix sockets avoid named
POSIX shared-memory setup and fileport syscalls on this path; parent-created
file attachments remain usable after SCM_RIGHTS transfer.

The 60 `sandbox/mac/os_compatibility.cc` 10.6 MIG layout handled its separate
launchd-interception sandbox server. 124's direct system `bootstrap_look_up`
uses Darwin's own serialization and does not need that old interceptor or its
request-struct backport. The existing common policy permits framework/bundle
reads and filesystem metadata, so source inspection found no need to restore
60's pre-sandbox resource warmup for IPC. This probe statically links Chromium:
loading the complete browser framework, fonts, graphics and renderer services
inside the sandbox still requires the forthcoming Content Shell run.

Regenerate a raw current policy with
`scripts/prepare_mojo_sandbox_profile.py`. The native regression runner's optional
`--renderer-sandbox` case builds the policy from current source bytes, records
both source hashes and the assembled profile hash, stages it separately, and
requires every sandbox and repeated IPC assertion. Its default unsandboxed
baseline remains intact; see `scripts/NATIVE-REGRESSIONS.md`.

`tests/io_surface_sandbox_native.c` applies the prepared full renderer policy
before its first IOSurface call. On 10.6 it passes creation, Mach export/lookup,
and ID/geometry/pixel preservation (`logs/io-surface-sandbox-native.log`, hashes
in `logs/io-surface-sandbox-provenance.json`). No broad IOKit allow was added:
the newer user-client filters are absent on this kernel, yet the native
IOSurface operation works. This single-process check does not establish
cross-process compositor rendering.


### Two browser-owned children: ordinary introductions and Mach relay

The nested-client rejection in `NodeController::OnAddBrokerClient` applies when
a non-broker accepts its own new invitation and asks the browser to enroll the
new node. Normal renderer/GPU/utility peers are already browser children:
`RenderProcessHostImpl` uses `ChildProcessLauncher`, while `GpuProcessHost` and
`UtilityProcessHost` use `BrowserChildProcessHostImpl`, which launches through
the same Mac helper. Each receives authenticated task enrollment. Connections
between these existing nodes use `OnRequestIntroduction`/`OnIntroduce`, passing
Unix socket FDs. Child Mach attachments use the browser's `RelayEventMessage`
path; sibling channels do not gain direct access to each other's task ports.

`runtime-compat/mojo_sibling_smoke.cc` tests this actual three-process topology.
The browser launches two children under the current renderer policy, transfers
opposite ends of a message pipe, and supplies one owned seed FD. The children
exchange a handle-free handshake, then 16 ordered FD/Mach/Mach/FD round trips.
Shared buffers are created by the sandboxed sending child; the other child maps,
updates and returns them. Both children deny unrelated writes, authenticate
before Mojo startup, report completion and exit cleanly. All 51 assertions pass:
`logs/mojo-sibling-sandbox-native.log`.

A second private link adds only diagnostic prints to NodeController. Its native
trace observes 2 `OnRequestIntroduction`, 3 `OnIntroduce` (including teardown),
32 sibling `OnRelayEventMessage`, and **zero** `OnAddBrokerClient` calls. It also
passes all 51 assertions (`logs/mojo-sibling-sandbox-trace-native.log`). Exact
source/object/binary/policy hashes and matching remote hashes are recorded in
`logs/mojo-sibling-sandbox-provenance.json`. No production source, GN target or
sandbox permission changed. Browser renderer/GPU-specific services and actual
compositing still require the integrated browser run; the direct sibling Mojo
transport is now covered on Snow Leopard with the renderer policy active.


### Cocoa/framework loading after sandbox activation

A native C-only helper (`tests/load_graphics_after_sandbox.c`) links only
libsandbox and libSystem. It checks dyld's image list to prove Foundation and
AppKit are absent both before and after `sandbox_init`, confirms an unrelated
write is denied, and only then loads the previously built EGL/GLES/SwiftShader
images with `RTLD_NOW`. Their earlier embedded Cocoa shim runs `+load` in this
already-sandboxed process, matching the important helper/framework boundary.

The first run trapped in `__CFXNotificationSendToServer`, reached through
`SnowiumModernCocoaCompatibility +load` → `NSView initialize` → `NSUserDefaults`.
The owned sandbox log identifies the denied exact service
`com.apple.distributed_notifications.2`. Chromium60's historical bootstrap
sandbox test explicitly lists that 10.6 service, while the 124 renderer policy
allowed only its later `com.apple.distributed_notifications@Uv3` name.

The modern source patch now selects `.2` for `os-version < 1007` and retains
`@Uv3` for newer systems. All eight loader assertions then pass, with file-write
denial intact. No DirectoryService or other unrelated denial was allowed.
Native logs/crash/denial evidence: `logs/graphics-load-after-sandbox*`; source,
policy and matching remote library hashes are collected in
`logs/graphics-load-after-sandbox-provenance.json`.

`prepare_dlopen_sandbox_profile.py` regenerates the bound profile directly from
current common+renderer source. The tested libraries are the earlier copies
with duplicate shim classes; those warnings are retained and their hashes match
the original library-load provenance. The newer base-only shim placement and
complete browser framework still require the upcoming integrated build. Cocoa
agent was notified that class messages inside shared shim `+load` eagerly
initialize NSView even in helper processes that do not need it; avoiding those
messages is preferable to adding renderer-only permissions to other profiles.


Follow-up: replacing `+class` messages with `objc_getClass` alone was
insufficient on Darwin10. `class_getInstanceMethod` for missing selectors calls
`_class_resolveMethod`, which still initialized NSView and trapped in the
utility/audio/network policies. The root agent changed target and provider
lookup to `class_copyMethodList` with a superclass walk, preserving inherited
methods and avoiding dynamic resolution. The actual updated GN-compiled shim,
linked as an isolated non-ARC dylib, now loads after sandbox activation under
**renderer, utility, audio and network** policies. Every case proves Cocoa was
absent before/after policy application and an unrelated write remains denied.
Utility/audio/network pass six assertions each; renderer also loads the three
older graphics libraries and passes nine. No additional helper permissions were
needed. All logs, retained failing objects, exact sources and matching remote
shim/policy hashes are listed in `logs/cocoa-metadata-sandbox-provenance.json`.
These are load/registration checks; the next integrated font/native probes must
still validate ordinary shim calls after the source update.


### Integrated Content Shell on Snow Leopard

The pass10 source-built Content Shell runs on the actual 10.6.8 Mac with separate renderer, GPU, network and storage children using SeatbeltExec. The ten page checks and keyboard/click/wheel dispatch pass; `logs/content-shell-pass10-window.png` is a native capture of the verified PID/window/title and shows actual painted content. Public example.com loads with secure TLS 1.3/HTTP200, expired.badssl.com is rejected with ERR_CERT_DATE_INVALID, and the Chromium Legacy GitHub page reaches complete state with 146 HTTP responses and no loading failures. No sandbox or certificate override flags are used. `logs/content-shell-pass10-provenance.json` records matching local/remote hashes for all 30 physical bundle files, source/runtime inputs, native OS and owned process commands. Later full Chrome validation is recorded in the final integration section below.

Integrated startup found that `InitializeMac` initializes NSUserDefaults in every helper, independently of Cocoa shim registration. GPU and utility children trapped in CFPreferences because their policies lacked the exact 10.6 notification service. `common.sb` now permits only `com.apple.distributed_notifications.2` when `os-version < 1007`. Earlier raw-method registration still avoids needless AppKit initialization; the common rule supports a separate, unavoidable preferences startup path. The pass8 GPU/utility crash reports are retained alongside the successful pass10 evidence.

Input focus exposed Lion-only `dismissCorrectionIndicatorForView:` calls. They are now guarded by 10.7 availability. Snow Leopard retains its native unified text checker and immediate quote/dash substitutions using original result ranges plus Chromium's document offset; Lion-only range-adjusted result objects and correction popups are excluded. Its missing system automatic-text-replacement preference accessor returns disabled unless the browser has an explicit setting. The renderer still preserves composition cancellation and normal text input.

The full framework link also identified three callers left behind after optional backend exclusion: VideoToolbox pre-sandbox initialization, AVFoundation camera GPU-buffer selection, and Metal-specific Dawn scheduling. Their callers now match the excluded backends. A nonempty pending Metal flush list is rejected rather than treated as synchronized. The Chrome-only service launcher selects FD mapping from MOJO_USE_APPLE_CHANNEL, matching the platform-channel implementation on 10.6.


### Audio framework providers and strict import lookup

The pass10 Web Audio test exposed a dyld failure for AudioComponentFindNext. Twelve AudioComponent/AudioOutputUnit/AudioUnit imports were bound to modern AudioToolbox, while 10.6 exports them from AudioUnit. `prepare-link-stubs.py` now copies unmodified, hash-checked AudioToolbox/AudioUnit link stubs from the preserved 10.6 SDK into the target-only framework search directory; modern headers remain in use. A modern-header C probe using these exact link stubs binds to AudioUnit and passes all 21 native CoreAudio assertions, including 25 silent render callbacks. Integrated Web Audio subsequently passes in Content Shell pass13 and full Chrome pass25; see the final integration section below.

`tests/probe-imports.c` now uses RTLD_FIRST, supported since 10.5. Its earlier lookup could find an export in an unrelated image, masking the audio-provider mismatch. The strict native audit identifies the twelve audio bindings plus three unavailable strong SecTask signing/entitlement APIs. The latter remain untouched under the user's instruction to skip native signing issues. Missing optional weak imports are reported separately. Evidence: `logs/content-shell-pass10-strict-missing-imports.tsv`, `logs/audio-unit-correct-provider-native.log`, `logs/coreaudio-target-stubs-imports.tsv`, and `logs/coreaudio-target-stubs-native.log`.


### Final full Chrome integration on 10.6.8 — pass25

Full source-built Chromium 124.0.6367.207.1 now runs and visibly paints its modern tab strip, toolbar and page on the actual Snow Leopard Mac. The initial inactive window orders in normally after restart, without a DevTools resize/activation workaround. `logs/chrome-pass25-window.png` is a native single-window capture with verified owner PID, ID and fixture title. All ten page checks and browser-path keyboard/click/wheel dispatch pass. Silent Web Audio has a running 44,100 Hz clock and an AudioWorklet callback; WebGL 1/2 compile/link/draw/read back the expected pixel. HTTPS example.com is secure HTTP200/TLS1.3, expired.badssl.com is rejected, and the Legacy GitHub page completes with 146 responses and no loading failures. No sandbox or certificate bypass flags are used.

The final additional compatibility boundaries are:

| Boundary | 10.6 implementation | Native evidence |
| --- | --- | --- |
| Private CoreText system-font descriptor classification | Keep the existing named-family font derivation; omit unavailable `CTFontDescriptorIsSystemUIFont` | Full Chrome text visibly paints; strict imports no longer include this strong missing API |
| Newer ICC profile extraction | `CGColorSpaceCopyICCProfile` instead of `CGColorSpaceCopyICCData` | Chrome creates and paints its window without the former weak-bind crash |
| Private Services-menu entry classes | Skip only the Chromium filtering swizzle; retain the native AppKit Services menu | Chrome passes the former `_NSServiceEntry` startup trap |
| Simplified kqueue I/O loop | Force the maintained classic loop on the Snow Leopard build; honor immediate work and clamp elapsed timeout | Same-binary classic/simplified comparison: classic serves DevTools and child IPC, simplified timed out child connections; final browser passes without a feature override |
| VM statistics ABI and task power | Request `HOST_VM_INFO64_REV0_COUNT`, zero-initialize counters, omit unavailable file-backed accounting, return zero for unsupported task-power queries | Chrome passes former count assertion and runs metrics without uninitialized results |
| Profile encryption identity | Real native Keychain with service `Snowium124 Safe Storage`, account `Snowium124` | Avoids sharing Chromium60's item; no mock keychain or ACL changes |
| Initial inactive window ordering | Order relative to a main window only if it exists and differs from the new window; otherwise use existing front-order method | Restarted Chrome window appears directly and stays onscreen through checks; original fresh-profile run later hid for an unestablished reason |
| CoreAudio provider mismatch | Unmodified 10.6 AudioToolbox/AudioUnit SDK link stubs, scoped to target linking | Native 21-assertion/25-callback probe plus Content Shell and full Chrome silent Web Audio checks |

`logs/chrome-pass25-provenance.json` records identical hashes for all 159 physical local/remote bundle files, source patch, actual arguments and browser evidence. `logs/chrome-pass25-weak-runtime.json` confirms one PLWeak provider per process for all nine Chrome executables. The final Content Shell bundle also passes the six-executable provider audit; native engine/audio evidence remains attached to its earlier pass13 bundle.

The strict provider audit leaves only three unavailable strong imports, all SecTask signing/entitlement APIs. They remain untouched under the user's explicit instruction to skip native signing issues. Optional weak imports remain listed separately. This establishes the tested browser paths, not complete coverage of every Chrome feature. Metal/hardware video and AVFoundation camera remain unsupported, newer optional services remain gated, and Darwin10 sandbox filtering has the older granularity documented above. Google OAuth/API keys are absent. Extended use, media playback/capture, extensions, downloads and printing still need separate integration coverage.

### Native Screen Sharing follow-up — passes26–33

The pass25 fixture/protocol checks did not establish reliable native browsing. Real Screen Sharing input reproduced disappearing windows, blank page content and an absent resize grip. The retained frame crash report identifies a Lion-only private resize selector. The [interactive record](../logs/interactive-browsing-20261005.md) distinguishes observed results from remaining hypotheses.

| Boundary | Source change | Evidence and limit |
| --- | --- | --- |
| Private frame resize API | Titled windows use Snow Leopard's native NSThemeFrame mouse handling; avoid `_resizeDirectionForMouseLocation:` | Retained pass25 unrecognized-selector crash; pass26 native corner resize did not crash. This does not establish the reported right-click crash's cause. |
| Child-window ordering | Remove the native parent attachment before ordering a popup out; retain the bridge's logical parent for later reattachment | Pass27 traces show popup order-out before main-window disappearance; pass28 example.com navigation stayed visible and painted. Other popup types need coverage. |
| Visible resize affordance | A drawn bottom-right grip tracks native mouse drags and clamps to window size limits | Pass29 grip painted and several grow/shrink drags worked. |
| Missing Seatbelt operations/filters | Guard `iokit-open` and `iokit-get-properties`; select the existing coarse Darwin10 POSIX-shm operation where name filters are unavailable | All seven affected bound source profiles apply via `sandbox_init` on 10.6.8. The old unguarded mirroring rule fails with missing `iokit-open`. This tests compilation, not every helper's functionality or permissions. |
| IOSurface wrapper identity | Explicitly call CALayer `setContentsChanged` after assigning each Snow Leopard surface frame | 1,000 native lookups against a retained first lookup yield different pointers, equal CF objects and identical surface IDs. This supports a reused-buffer invalidation hypothesis; pass33's visible result is unverified. |

Chromium's [upstream display-layer implementation](https://chromium.googlesource.com/experimental/chromium/src/+/refs/tags/83.0.4103.97/ui/accelerated_widget_mac/display_ca_layer_tree.mm) uses pointer equality to choose explicit contents invalidation, as do the local 60 and 124 bases. On the tested 10.6 native API, `CFEqual` succeeds between distinct wrapper pointers for the same buffer. The source change avoids reliance on the setter noticing updated bytes of equal surface objects; the probe does not prove Core Animation's internal caching behavior or establish this as the blank-page cause.

Actual pass29 browsing painted Wikipedia's main page, but searching for “snow leopard” reached a blank article. GitHub's profile also stayed blank, and its page context menu did not open. A New Tab context menu worked in an earlier trial. Pass31 received continuing compositor frames despite a garbled native view. These failures remain open. Native interaction stopped when computer control reported the local Mac was locked. Pass33 is compiled, deployed and hash-recorded; it must be retested through Screen Sharing after unlocking before claiming these issues resolved.

The [morning native retest](../logs/interactive-browsing-20261005-morning.md) reproduced blanking in pass33 during website text entry, so its surface invalidation change is insufficient. Pass34 showed normal-status renderer termination without requested/fast shutdown and with an active view. Pass35 additionally records a renderer self-exit on browser IPC disconnection, but its website text-entry trial was blocked by viewer input errors; that disconnect's relationship to text entry remains to be established. A painted Wikipedia page's context menu worked in one pass34 trial. These diagnostics do not constitute a new repair. Acceleration investigation was cancelled before any acceleration behavior change.

### Writable shared memory over the Darwin10 transport — passes36–38

Disabling MOJO_USE_APPLE_CHANNEL selects the legacy socket transport, but does
not change Apple's shared-memory representation: one Mach right. Mojo's writable
region serialization/wrapping and broker paths incorrectly selected two POSIX
FDs using that transport flag, adding an empty second handle and causing renderer
IPC teardown. shared_buffer_dispatcher.cc, core.cc, broker_host.cc and
broker_posix.cc now select the memory layout using IS_APPLE. Unsupported handles
still close the connection; authenticated Mach relaying and default sandbox
denial remain in force.

Pass36 logs the empty handle before renderer disconnection. Pass37 native
Wikipedia typing/search/article/context-menu/scroll and GitHub profile checks
passed. A fifth convertible writable-memory attachment in mojo_roundtrip_smoke
passes16 bidirectional rounds both normally and inside the actual renderer
sandbox. Pass38 removes temporary tracing and packages this correction. See the
[morning record](../logs/interactive-browsing-20261005-morning.md) and
[regression provenance](../logs/native-regressions/20261005T095148Z-52571/provenance.json).
