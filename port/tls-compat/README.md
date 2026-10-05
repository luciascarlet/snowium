# Emulated TLS lifetime on Snow Leopard

The first Chromium 124 bundled-libc++ native probe passed thread-local isolation
but failed to invoke its eight C++ thread-local destructors. LLVM's emutls
pthread-key destructor was freeing the storage containing libc++abi's destructor
list before libc++abi visited that list.

`src/emutls.c` is LLVM compiler-rt at
`a0b3dbaf4b3c01dc7f0a83fce059a26360b58eb2`, matching the pinned Chromium Clang 19
runtime. Its sole local source change adds a `SNOW_LEOPARD_PORT` Darwin path that
defers freeing emulated TLS for two pthread destructor rounds. LLVM already uses
this mechanism on Bionic (one deferred round). The original source and required
headers, with their license, are in `references/`.

There is a separate ordering requirement in libc++: its notification/future
pthread key can run before libc++abi's C++ destructor key. The port edits
`third_party/libc++/src/src/thread.cpp` to drain C++ thread-local destructors before
`__thread_struct_imp` publishes thread-exit notifications or future readiness.
The drain entry point is implemented in
`third_party/libc++abi/src/src/cxa_thread_atexit.cpp`; its existing loop also visits
new thread-local objects first constructed by another thread-local destructor.
Both source edits are guarded by `SNOW_LEOPARD_PORT` and preserve the ordinary
LLVM implementation for other builds.

Build the archive with `./build-runtime.sh`. Link it before the compiler runtime
using `-Wl,-load_hidden,/absolute/path/to/tls-compat/build/libsnowium_emutls.a`.
This statically supplies the actual emutls implementation and avoids interposing
symbols in other processes. Do not overwrite the upstream compiler-rt archive.

`python3 build-tests.py` builds isolated probes from Chromium's generated flags
and already-built libc++ object files, recompiling the two changed C++ runtime
files into this directory. It does not run Ninja or modify its output objects.

Verified on the actual Mac OS X 10.6.8 target:

- Original runtime probe: TLS isolation/destructors, monotonic clock,
  future/condition variable, exceptions/unwind, and containers all pass.
- 16 `std::thread` exits plus 16 explicit `pthread_exit`/join exits: 32 root,
  child, and guard destructors each, in the required root/child/guard order.
- 64-byte TLS alignment and surviving earlier TLS objects during destruction.
- Child TLS first constructed inside a destructor is also destroyed.
- `notify_all_at_thread_exit` and `promise::set_value_at_thread_exit` only become
  observable after a deliberately delayed TLS destructor completes.

Logs are in `logs/runtime-smoke-native.log` and `logs/tls-lifetime-native.log`.
These checks cover the browser's worker-thread lifetime requirements; they are
not a claim of complete language-runtime conformance. LLVM's existing fallback
still documents limitations involving unloading DSOs and the ordering of main
thread TLS versus arbitrary static destructors at process exit.

Relevant existing work inspected:

- [LLVM emutls](https://github.com/llvm/llvm-project/blob/a0b3dbaf4b3c01dc7f0a83fce059a26360b58eb2/compiler-rt/lib/builtins/emutls.c)
- [MacPorts libc++ emutls integration](https://github.com/macports/macports-ports/blob/master/lang/libcxx/files/0005-libcxxabi-add-emutls.patch)
- [MacPorts old-Darwin thread-atexit fallback](https://github.com/macports/macports-ports/blob/master/lang/libcxx/files/0008-libcxxabi-cxa-thread-atexit-no-weak-atexit-impl.patch)
- [MacPorts LLVM 19 emulated TLS support](https://github.com/macports/macports-ports/blob/master/lang/llvm-19/files/0019-10.6-and-less-use-emulated-TLS-before-10.7.patch)

The inspected MacPorts emutls copy also limits its delayed cleanup to Bionic;
the Darwin cleanup delay and explicit libc++ notification ordering are local
port fixes, not preexisting MacPorts guarantees.
