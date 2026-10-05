// Runs the actual Chromium 124 ChannelPosix with mixed Mach and FD attachments.
#include <errno.h>
#include <fcntl.h>
#include <mach/mach.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "base/at_exit.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/run_loop.h"
#include "base/task/single_thread_task_executor.h"
#include "base/task/single_thread_task_runner.h"
#include "base/time/time.h"
#include "mojo/core/channel.h"
#include "mojo/core/connection_params.h"
#include "mojo/public/cpp/platform/platform_channel.h"
#include "snow_leopard/mach_port_relay.h"

namespace {
constexpr uint32_t kMessageCount = 32;
struct Payload { uint32_t sequence; char text[28]; };

class Receiver : public mojo::core::Channel::Delegate {
 public:
  explicit Receiver(base::RunLoop& loop) : loop_(loop) {}
  void OnChannelMessage(const void* data, size_t size,
                        std::vector<mojo::PlatformHandle> handles) override {
    if (size != sizeof(Payload) || handles.size() != 4) return Fail();
    const auto& payload = *static_cast<const Payload*>(data);
    if (payload.sequence != received_ || strcmp(payload.text, "mixed-124-wire")) return Fail();
    for (size_t i = 0; i < handles.size(); ++i) {
      if (i == 0 || i == 3) {
        char bytes[4];
        if (!handles[i].is_fd() || pread(handles[i].GetFD().get(), bytes, 4, 0) != 4 ||
            memcmp(bytes, "file", 4)) return Fail();
      } else {
        if (!handles[i].is_mach_name()) return Fail();
        base::apple::ScopedMachReceiveRight intermediate(handles[i].GetMachName());
        mach_port_t right = MACH_PORT_NULL;
        if (snow_leopard::ReceiveIntermediateMachPort(intermediate.get(), &right) != KERN_SUCCESS)
          return Fail();
        base::apple::ScopedMachSendRight memory(right);
        vm_address_t address = 0;
        if (vm_map(mach_task_self(), &address, getpagesize(), 0, VM_FLAGS_ANYWHERE,
                   memory.get(), 0, FALSE, VM_PROT_READ, VM_PROT_READ,
                   VM_INHERIT_NONE) != KERN_SUCCESS) return Fail();
        bool correct = strcmp(reinterpret_cast<const char*>(address), "mach-memory") == 0;
        vm_deallocate(mach_task_self(), address, getpagesize());
        if (!correct) return Fail();
      }
    }
    if (++received_ == kMessageCount) {
      // Give ChannelPosix's Darwin HANDLES_SENT_ACK exchange time to drain.
      base::SingleThreadTaskRunner::GetCurrentDefault()->PostDelayedTask(
          FROM_HERE, loop_.QuitClosure(), base::Milliseconds(50));
    }
  }
  void OnChannelError(mojo::core::Channel::Error) override {
    if (!finished_) Fail();
  }
  void Fail() { failed_ = true; loop_.Quit(); }
  bool passed() const { return !failed_ && received_ == kMessageCount; }
  void Finish() { finished_ = true; }
 private:
  base::RunLoop& loop_;
  uint32_t received_ = 0;
  bool failed_ = false;
  bool finished_ = false;
};

bool Require(bool ok, const char* text) {
  printf("%s %s\n", ok ? "PASS" : "FAIL", text);
  return ok;
}
}  // namespace

int main() {
  setbuf(stdout, nullptr);
  base::AtExitManager at_exit;
  base::SingleThreadTaskExecutor executor(base::MessagePumpType::IO);
  base::RunLoop loop;
  Receiver receiver(loop);
  mojo::PlatformChannel endpoints;
  using Channel = mojo::core::Channel;
  auto sender = Channel::Create(&receiver,
      mojo::core::ConnectionParams(endpoints.TakeLocalEndpoint()),
      Channel::HandlePolicy::kAcceptHandles, executor.task_runner());
  auto destination = Channel::Create(&receiver,
      mojo::core::ConnectionParams(endpoints.TakeRemoteEndpoint()),
      Channel::HandlePolicy::kAcceptHandles, executor.task_runner());
  sender->Start();
  destination->Start();

  char path[] = "/tmp/snowium-modern-channel-XXXXXX";
  base::ScopedFD file(mkstemp(path));
  if (!Require(file.is_valid(), "create owned POSIX attachment")) return 1;
  unlink(path);
  if (!Require(write(file.get(), "file", 4) == 4, "prepare file data")) return 1;
  memory_object_size_t size = getpagesize();
  mach_port_t memory = MACH_PORT_NULL;
  if (!Require(mach_make_memory_entry_64(mach_task_self(), &size, 0,
      MAP_MEM_NAMED_CREATE | VM_PROT_READ | VM_PROT_WRITE, &memory,
      MACH_PORT_NULL) == KERN_SUCCESS, "create Mach attachment")) return 1;
  base::apple::ScopedMachSendRight owned_memory(memory);
  vm_address_t address = 0;
  if (!Require(vm_map(mach_task_self(), &address, size, 0, VM_FLAGS_ANYWHERE,
      memory, 0, FALSE, VM_PROT_READ | VM_PROT_WRITE, VM_PROT_READ | VM_PROT_WRITE,
      VM_INHERIT_NONE) == KERN_SUCCESS, "map attachment contents")) return 1;
  strcpy(reinterpret_cast<char*>(address), "mach-memory");

  std::vector<int> sent_fds;
  for (uint32_t sequence = 0; sequence < kMessageCount; ++sequence) {
    auto message = Channel::Message::CreateMessage(sizeof(Payload), 4);
    auto* payload = static_cast<Payload*>(message->mutable_payload());
    *payload = {};
    payload->sequence = sequence;
    strcpy(payload->text, "mixed-124-wire");
    std::vector<mojo::PlatformHandle> handles;
    for (int i = 0; i < 4; ++i) {
      if (i == 0 || i == 3) {
        int fd = dup(file.get());
        if (fd < 0) return 1;
        sent_fds.push_back(fd);
        handles.emplace_back(base::ScopedFD(fd));
      } else {
        mach_port_name_t name;
        if (snow_leopard::CreateIntermediateMachPort(mach_task_self(), memory, &name) != KERN_SUCCESS)
          return 1;
        handles.push_back(mojo::PlatformHandle::FromMachName(name));
      }
    }
    message->SetHandles(std::move(handles));
    sender->Write(std::move(message));
  }
  executor.task_runner()->PostDelayedTask(FROM_HERE, loop.QuitClosure(), base::Seconds(10));
  loop.Run();
  bool ok = Require(receiver.passed(), "32 actual Mojo messages preserve mixed handle order, bytes and memory");
  bool closed = true;
  for (int fd : sent_fds) closed &= fcntl(fd, F_GETFD) == -1 && errno == EBADF;
  ok &= Require(closed, "Darwin FD acknowledgments release all sender descriptors");
  receiver.Finish();
  sender->ShutDown();
  destination->ShutDown();
  base::RunLoop().RunUntilIdle();
  vm_deallocate(mach_task_self(), address, size);
  return ok ? 0 : 1;
}
