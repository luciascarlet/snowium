#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <future>
#include <mutex>
#include <pthread.h>
#include <thread>
#include <vector>

namespace {
std::atomic<int> destroyed_root{0}, destroyed_child{0}, destroyed_guard{0};
std::atomic<int> failures{0};
int traces[32][3] = {};
int positions[32] = {};
thread_local int index = -1;
void Record(int value) {
  if (index < 0 || index >= 32 || positions[index] >= 3) {
    ++failures;
    return;
  }
  traces[index][positions[index]++] = value;
}
struct alignas(64) Guard {
  unsigned long value = 0x1122334455667788UL;
  ~Guard() { Record(3); value = 0; ++destroyed_guard; }
};
thread_local Guard guard;
struct Child {
  int value = 93;
  ~Child() {
    if (value != 93 || guard.value != 0x1122334455667788UL)
      ++failures;
    Record(2);
    ++destroyed_child;
  }
};
Child& GetChild() { static thread_local Child child; return child; }
struct Root {
  int value = 71;
  ~Root() {
    if (value != 71 || guard.value != 0x1122334455667788UL)
      ++failures;
    Record(1);
    if (GetChild().value != 93)
      ++failures;
    ++destroyed_root;
  }
};
thread_local Root root;
void Touch(int slot) {
  index = slot;
  if (guard.value != 0x1122334455667788UL ||
      reinterpret_cast<uintptr_t>(&guard) % 64 != 0 || root.value != 71)
    ++failures;
}
void* PthreadWorker(void* arg) {
  Touch(static_cast<int>(reinterpret_cast<intptr_t>(arg)));
  pthread_exit(NULL);
}
std::atomic<int> completed_marker{0};
struct Marker {
  int used = 0;
  ~Marker() {
    // Expose premature notification even on a fast target: readiness may not
    // become visible while a thread_local destructor is still running.
    std::this_thread::sleep_for(std::chrono::milliseconds(40));
    completed_marker.fetch_add(1, std::memory_order_release);
  }
};
Marker& GetMarker() { static thread_local Marker marker; return marker; }
void Check(bool ok, const char* label) {
  std::printf("%s %s\n", ok ? "PASS" : "FAIL", label);
  std::fflush(stdout);
  if (!ok)
    std::exit(1);
}
}

int main() {
  std::vector<std::thread> threads;
  for (int i = 0; i < 16; ++i)
    threads.emplace_back([i] { Touch(i); });
  for (auto& thread : threads)
    thread.join();
  pthread_t raw[16];
  for (int i = 0; i < 16; ++i)
    Check(pthread_create(&raw[i], NULL, PthreadWorker,
                         reinterpret_cast<void*>(static_cast<intptr_t>(i + 16))) == 0,
          "pthread creation");
  for (auto& thread : raw)
    Check(pthread_join(thread, NULL) == 0, "pthread_exit and join");
  bool order = true;
  for (int i = 0; i < 32; ++i)
    order = order && positions[i] == 3 && traces[i][0] == 1 &&
            traces[i][1] == 2 && traces[i][2] == 3;
  std::printf("Destructor counts root=%d child=%d guard=%d failures=%d\n",
              int(destroyed_root), int(destroyed_child), int(destroyed_guard), int(failures));
  Check(destroyed_root == 32 && destroyed_child == 32 && destroyed_guard == 32 &&
            failures == 0 && order,
        "TLS alignment, lifetime, and new TLS initialized inside destructors");

  std::mutex mutex;
  std::condition_variable cv;
  bool ready = false;
  std::thread notify_thread([&] {
    GetMarker().used = 1;
    std::unique_lock<std::mutex> lock(mutex);
    ready = true;
    std::notify_all_at_thread_exit(cv, std::move(lock));
  });
  {
    std::unique_lock<std::mutex> lock(mutex);
    cv.wait(lock, [&] { return ready; });
    Check(completed_marker.load(std::memory_order_acquire) == 1,
          "notify_all_at_thread_exit follows TLS destructors");
  }
  notify_thread.join();

  std::promise<int> promise;
  auto future = promise.get_future();
  std::thread future_thread([&] {
    GetMarker().used = 1;
    promise.set_value_at_thread_exit(124);
  });
  Check(future.get() == 124 && completed_marker.load(std::memory_order_acquire) == 2,
        "future readiness at thread exit follows TLS destructors");
  future_thread.join();
  return 0;
}
