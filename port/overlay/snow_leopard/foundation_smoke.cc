// Native regression checks against the actual Chromium 124/V8 platform code.
#include <mach/mach.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>

#include "base/apple/scoped_mach_port.h"
#include "base/at_exit.h"
#include "base/threading/thread_local_storage.h"
#include "base/memory/read_only_shared_memory_region.h"
#include "base/memory/writable_shared_memory_region.h"
#include "partition_alloc/page_allocator.h"
#include "partition_alloc/partition_tls.h"
#include "v8/src/base/platform/platform.h"
#include "v8/src/base/page-allocator.h"
#include <utility>

namespace {
namespace pa = partition_alloc;
namespace pai = partition_alloc::internal;
using Access = pa::PageAccessibilityConfiguration;
using Disposition = pa::PageAccessibilityDisposition;

bool Require(bool ok, const char* label) {
  printf("%s %s\n", ok ? "PASS" : "FAIL", label);
  return ok;
}

struct ThreadState {
  base::ThreadLocalStorage::Slot base_key;
  pai::PartitionTlsKey partition_key;
  v8::base::Thread::LocalStorageKey v8_key;
};

void* CheckThread(void* value) {
  auto* state = static_cast<ThreadState*>(value);
  int marker = 7;
  if (state->base_key.Get() ||
      pai::PartitionTlsGet(state->partition_key) ||
      v8::base::Thread::GetThreadLocal(state->v8_key))
    return reinterpret_cast<void*>(1);
  state->base_key.Set(&marker);
  pai::PartitionTlsSet(state->partition_key, &marker);
  v8::base::Thread::SetThreadLocal(state->v8_key, &marker);
  bool ok = state->base_key.Get() == &marker &&
            pai::PartitionTlsGet(state->partition_key) == &marker &&
            v8::base::Thread::GetExistingThreadLocal(state->v8_key) == &marker;
  state->base_key.Set(nullptr);
  pai::PartitionTlsSet(state->partition_key, nullptr);
  v8::base::Thread::SetThreadLocal(state->v8_key, nullptr);
  return ok ? nullptr : reinterpret_cast<void*>(1);
}
}  // namespace

int main() {
  setbuf(stdout, nullptr);
  base::AtExitManager at_exit;
  bool ok = true;
  ThreadState state;
  if (!Require(pai::PartitionTlsCreate(&state.partition_key, nullptr),
               "allocate PartitionAlloc TLS key"))
    return 1;
  state.v8_key = v8::base::Thread::CreateThreadLocalKey();
  int parent_marker = 42;
  state.base_key.Set(&parent_marker);
  pai::PartitionTlsSet(state.partition_key, &parent_marker);
  v8::base::Thread::SetThreadLocal(state.v8_key, &parent_marker);
  pthread_t thread;
  void* thread_result = reinterpret_cast<void*>(1);
  bool created = pthread_create(&thread, nullptr, CheckThread, &state) == 0;
  if (created) pthread_join(thread, &thread_result);
  ok &= Require(created && thread_result == nullptr &&
                    state.base_key.Get() == &parent_marker &&
                    pai::PartitionTlsGet(state.partition_key) == &parent_marker &&
                    v8::base::Thread::GetExistingThreadLocal(state.v8_key) ==
                        &parent_marker,
                "base, PartitionAlloc and V8 TLS isolate parent and child values");
  pthread_key_delete(state.partition_key);
  v8::base::Thread::DeleteThreadLocalKey(state.v8_key);

  constexpr size_t size = 65536;
  uintptr_t pages = pa::AllocPages(size, size, Access(Access::kInaccessible));
  bool pages_ok = pages != 0;
  if (pages) {
    for (int cycle = 0; cycle < 64; ++cycle) {
      pa::DecommitSystemPages(pages, size, Disposition::kRequireUpdate);
      pages_ok &= pa::TryRecommitSystemPages(
          pages, size, Access(Access::kReadWrite), Disposition::kRequireUpdate);
      if (!pages_ok) break;
      memset(reinterpret_cast<void*>(pages), cycle + 1, size);
      pages_ok &= reinterpret_cast<unsigned char*>(pages)[size - 1] == cycle + 1;
    }
    pa::FreePages(pages, size);
  }
  ok &= Require(pages_ok, "PartitionAlloc protected discard/recommit cycles");

  v8::base::PageAllocator v8_allocator;
  auto* v8_pages = v8_allocator.AllocatePages(nullptr, size, size,
                                v8::PageAllocator::kNoAccess);
  bool v8_ok = v8_pages != nullptr;
  if (v8_pages) {
    for (int cycle = 0; cycle < 64; ++cycle) {
      v8_ok &= v8_allocator.RecommitPages(v8_pages, size,
                                 v8::PageAllocator::kReadWrite);
      if (!v8_ok) break;
      memset(v8_pages, cycle + 1, size);
      v8_ok &= static_cast<unsigned char*>(v8_pages)[size - 1] == cycle + 1;
      v8_ok &= v8_allocator.DecommitPages(v8_pages, size);
      if (!v8_ok) break;
    }
    v8_allocator.FreePages(v8_pages, size);
  }
  ok &= Require(v8_ok, "V8 protected page decommit/recommit restores access");

  {
    base::apple::ScopedMachReceiveRight receive;
    bool created_port = base::apple::CreateMachPort(&receive, nullptr, 32);
    mach_port_type_t type = 0;
    bool attributes = mach_port_type(mach_task_self(), receive.get(), &type) ==
                      KERN_SUCCESS;
    ok &= Require(created_port && attributes &&
                      (type & MACH_PORT_TYPE_RECEIVE) &&
                      !(type & MACH_PORT_TYPE_SEND),
                  "receive-only Mach creation owns no unwanted send right");
  }
  {
    base::apple::ScopedMachReceiveRight receive;
    base::apple::ScopedMachSendRight send;
    bool created_port = base::apple::CreateMachPort(
        &receive, &send, MACH_PORT_QLIMIT_LARGE);
    mach_port_urefs_t refs = 0;
    mach_port_status_t status{};
    mach_msg_type_number_t count = MACH_PORT_RECEIVE_STATUS_COUNT;
    bool attributes = mach_port_get_attributes(
        mach_task_self(), receive.get(), MACH_PORT_RECEIVE_STATUS,
        reinterpret_cast<mach_port_info_t>(&status), &count) == KERN_SUCCESS;
    bool send_refs = mach_port_get_refs(mach_task_self(), send.get(),
                                        MACH_PORT_RIGHT_SEND, &refs) ==
                     KERN_SUCCESS;
    ok &= Require(created_port && attributes && send_refs && refs == 1 &&
                      status.mps_qlimit == MACH_PORT_QLIMIT_LARGE,
                  "Mach creation preserves requested queue limit and one send right");
  }

  auto writable = base::WritableSharedMemoryRegion::Create(4096);
  auto mapping = writable.Map();
  bool memory_ok = mapping.IsValid();
  if (memory_ok) strcpy(static_cast<char*>(mapping.memory()), "modern-shared-memory");
  auto readonly = base::WritableSharedMemoryRegion::ConvertToReadOnly(
      std::move(writable));
  auto read_mapping = readonly.Map();
  ok &= Require(memory_ok && read_mapping.IsValid() &&
                    strcmp(static_cast<const char*>(read_mapping.memory()),
                           "modern-shared-memory") == 0,
                "Chromium 124 read-only Mach shared-memory mapping");
  return ok ? 0 : 1;
}
