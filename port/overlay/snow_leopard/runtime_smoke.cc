// Snowium: exercise the actual Chromium 124 bundled C++ runtime on Darwin 10.
#include <any>
#include <optional>
#include <variant>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <future>
#include <map>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>
namespace {
std::atomic<int> destructed{0};
struct Local { int value = 17; ~Local() { ++destructed; } };
thread_local Local local;
void Check(bool ok, const char* what) {
  if (!ok) { std::fprintf(stderr, "FAIL %s\n", what); std::abort(); }
  std::printf("PASS %s\n", what);
}
}
int main() {
  auto start = std::chrono::steady_clock::now();
  std::vector<std::thread> workers;
  std::atomic<int> isolated{0};
  for (int n=0;n<8;n++) workers.emplace_back([n,&isolated] {
    if(local.value==17)++isolated;
    local.value=n;
    std::this_thread::sleep_for(std::chrono::milliseconds(2));
    if(local.value==n)++isolated;
  });
  for(auto& thread:workers)thread.join();
  Check(isolated==16,"C++ thread-local isolation");
  Check(destructed==8,"C++ thread-local destructors");
  Check(std::chrono::steady_clock::now()>start,"monotonic clock");
  Check(std::async(std::launch::async,[]{return 42;}).get()==42,"future and condition variable");
  bool caught=false;
  try {throw std::runtime_error("snow");}catch(const std::runtime_error& e){caught=std::string(e.what())=="snow";}
  Check(caught,"C++ exception and unwind");
  std::map<std::string,int> values{{"snow",124}};
  Check(values.at("snow")==124,"bundled libc++ containers");
  Check(std::any_cast<int>(std::any(124))==124, "bundled std::any");
  std::optional<int> absent;
  caught=false;
  try { (void)absent.value(); } catch (const std::bad_optional_access&) {caught=true;}
  Check(caught, "bundled std::optional exception");
  std::variant<int,std::string> variant=124;
  caught=false;
  try { (void)std::get<std::string>(variant); } catch (const std::bad_variant_access&) {caught=true;}
  Check(caught && std::get<int>(variant)==124, "bundled std::variant exception");
  return 0;
}
