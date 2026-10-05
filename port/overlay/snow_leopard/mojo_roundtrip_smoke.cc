// Actual Chromium 124 parent/child Mojo graph, Mach shared buffers and FD relay.
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <string>
#include <utility>
#include <vector>

#include "base/apple/foundation_util.h"
#include "base/at_exit.h"
#include "base/command_line.h"
#include "base/files/file_util.h"
#include "base/files/scoped_file.h"
#include "base/files/scoped_temp_dir.h"
#include "base/mac/mach_port_rendezvous.h"
#include "base/memory/writable_shared_memory_region.h"
#include "base/process/launch.h"
#include "base/process/process.h"
#include "base/threading/platform_thread.h"
#include "base/threading/thread.h"
#include "base/time/time.h"
#include "mojo/core/embedder/configuration.h"
#include "mojo/core/embedder/embedder.h"
#include "mojo/core/embedder/scoped_ipc_support.h"
#include "mojo/public/cpp/platform/platform_channel.h"
#include "mojo/public/cpp/system/buffer.h"
#include "mojo/public/cpp/system/invitation.h"
#include "mojo/public/cpp/system/message_pipe.h"
#include "mojo/public/cpp/system/platform_handle.h"
#include "sandbox/mac/seatbelt_exec.h"

namespace {
// Optional --renderer-profile=/absolute/path/to/policy-renderer-ipc.sb uses
// the real SeatbeltExec policy pipe. The child applies the policy before any
// rendezvous, Mojo initialization, or thread creation, as helper main does.
constexpr unsigned kRounds = 16;
constexpr size_t kBufferSize = 4096;
constexpr uint64_t kParentValue = 0x534c313234000000ULL;
constexpr uint64_t kChildValue = 0x4348494c44000000ULL;
constexpr char kFileContents[] = "Chromium 124 Snow Leopard mixed-handle relay";

bool Require(bool ok, const char* label) {
  printf("%s [%s] %s\n", ok ? "PASS" : "FAIL",
         base::CommandLine::ForCurrentProcess()->HasSwitch("mojo-child")
             ? "child" : "parent", label);
  return ok;
}

bool Read(mojo::MessagePipeHandle pipe, std::vector<uint8_t>* bytes,
          std::vector<mojo::ScopedHandle>* handles) {
  const auto deadline = base::TimeTicks::Now() + base::Seconds(15);
  while (base::TimeTicks::Now() < deadline) {
    MojoResult rv = mojo::ReadMessageRaw(pipe, bytes, handles,
                                        MOJO_READ_MESSAGE_FLAG_NONE);
    if (rv == MOJO_RESULT_OK) return true;
    if (rv != MOJO_RESULT_SHOULD_WAIT) {
      printf("FAIL read result %d\n", rv);
      return false;
    }
    base::PlatformThread::Sleep(base::Milliseconds(5));
  }
  return Require(false, "message received before deadline");
}

bool Write(mojo::MessagePipeHandle pipe, unsigned sequence,
           std::vector<mojo::ScopedHandle>* handles) {
  std::vector<MojoHandle> raw;
  for (const auto& handle : *handles) raw.push_back(handle.get().value());
  MojoResult rv = mojo::WriteMessageRaw(pipe, &sequence, sizeof(sequence),
      raw.data(), raw.size(), MOJO_WRITE_MESSAGE_FLAG_NONE);
  if (rv != MOJO_RESULT_OK) {
    printf("FAIL write result %d\n", rv);
    return false;
  }
  for (auto& handle : *handles) (void)handle.release();
  handles->clear();
  return true;
}

bool CheckFD(mojo::ScopedHandle* handle) {
  auto platform = mojo::UnwrapPlatformHandle(std::move(*handle));
  if (!platform.is_fd()) return false;
  char bytes[sizeof(kFileContents)] = {};
  bool ok = pread(platform.GetFD().get(), bytes, sizeof(bytes), 0) == sizeof(bytes) &&
            memcmp(bytes, kFileContents, sizeof(bytes)) == 0;
  *handle = mojo::WrapPlatformHandle(std::move(platform));
  return ok && handle->is_valid();
}

bool CheckBuffers(std::vector<mojo::ScopedHandle>* handles,
                  uint64_t expected, bool update) {
  for (size_t index : {1U, 2U, 4U}) {
    mojo::SharedBufferHandle buffer((*handles)[index].get().value());
    auto mapping = buffer.Map(kBufferSize);
    if (!mapping || static_cast<uint64_t*>(mapping.get())[index] != expected)
      return false;
    if (update)
      static_cast<uint64_t*>(mapping.get())[index] =
          kChildValue | (expected & 0xffff);
  }
  return true;
}

bool RoundtripChild(mojo::MessagePipeHandle pipe) {
  for (unsigned sequence = 0; sequence < kRounds; ++sequence) {
    std::vector<uint8_t> bytes;
    std::vector<mojo::ScopedHandle> handles;
    unsigned incoming = ~0U;
    if (!Read(pipe, &bytes, &handles) || bytes.size() != sizeof(incoming))
      return false;
    memcpy(&incoming, bytes.data(), sizeof(incoming));
    if (!Require(incoming == sequence && handles.size() == 5 &&
                     CheckFD(&handles[0]) && CheckFD(&handles[3]) &&
                     CheckBuffers(&handles, kParentValue | sequence, true),
                 "receive ordered FD/Mach/Mach/FD attachments and map shared memory"))
      return false;
    if (!Write(pipe, sequence, &handles)) return false;
  }
  std::vector<uint8_t> bytes;
  std::vector<mojo::ScopedHandle> handles;
  return Require(Read(pipe, &bytes, &handles) && handles.empty(),
                 "parent confirms receipt before child exits");
}

bool RoundtripParent(mojo::MessagePipeHandle pipe) {
  char name[] = "/tmp/snowium124-mojo-XXXXXX";
  base::ScopedFD file(mkstemp(name));
  if (!file.is_valid()) return false;
  unlink(name);
  if (write(file.get(), kFileContents, sizeof(kFileContents)) != sizeof(kFileContents))
    return false;
  for (unsigned sequence = 0; sequence < kRounds; ++sequence) {
    // Unlike Create(), this region retains writable-to-read-only conversion
    // semantics. It must serialize as one Mach handle even over Unix sockets.
    auto writable = base::WritableSharedMemoryRegion::Create(kBufferSize);
    auto writable_mapping = writable.Map();
    if (!Require(writable.IsValid() && writable_mapping.IsValid(),
                 "create convertible writable shared memory")) return false;
    static_cast<uint64_t*>(writable_mapping.memory())[4] = kParentValue | sequence;
    auto writable_handle = mojo::WrapWritableSharedMemoryRegion(std::move(writable));
    if (!Require(writable_handle.is_valid(), "wrap writable region as one Mach handle"))
      return false;
    auto buffer = mojo::SharedBufferHandle::Create(kBufferSize);
    if (!buffer.is_valid()) return Require(false, "create Mojo shared buffer");
    auto mapping = buffer->Map(kBufferSize);
    if (!mapping) return false;
    auto* values = static_cast<uint64_t*>(mapping.get());
    values[1] = values[2] = kParentValue | sequence;
    std::vector<mojo::ScopedHandle> handles;
    handles.push_back(mojo::WrapPlatformHandle(mojo::PlatformHandle(base::ScopedFD(dup(file.get())))));
    for (int i = 0; i < 2; ++i) {
      auto clone = buffer->Clone(mojo::SharedBufferHandle::AccessMode::READ_WRITE);
      if (!clone.is_valid()) return false;
      handles.emplace_back(mojo::Handle(clone.release().value()));
    }
    handles.push_back(mojo::WrapPlatformHandle(mojo::PlatformHandle(base::ScopedFD(dup(file.get())))));
    handles.emplace_back(mojo::Handle(writable_handle.release().value()));
    if (!Write(pipe, sequence, &handles)) return false;
    std::vector<uint8_t> bytes;
    unsigned incoming = ~0U;
    if (!Read(pipe, &bytes, &handles) || bytes.size() != sizeof(incoming)) return false;
    memcpy(&incoming, bytes.data(), sizeof(incoming));
    if (!Require(incoming == sequence && handles.size() == 5 &&
                     CheckFD(&handles[0]) && CheckFD(&handles[3]) &&
                     CheckBuffers(&handles, kChildValue | sequence, false) &&
                     values[1] == (kChildValue | sequence) &&
                     values[2] == (kChildValue | sequence) &&
                     static_cast<uint64_t*>(writable_mapping.memory())[4] ==
                         (kChildValue | sequence),
                 "broker receives child Mach rights and FDs with shared writes intact"))
      return false;
  }
  std::vector<mojo::ScopedHandle> none;
  return Write(pipe, kRounds, &none);
}
}  // namespace

int main(int argc, char** argv) {
  setbuf(stdout, nullptr);
  alarm(50);  // Bounds setup/accept/shutdown too, including an IPC deadlock.
  auto seatbelt = sandbox::SeatbeltExecServer::CreateFromArguments(
      argv[0], argc, argv);
  if (seatbelt.sandbox_required &&
      (!seatbelt.server || !seatbelt.server->InitializeSandbox())) {
    fprintf(stderr, "FAIL [child] apply renderer policy before IPC startup\n");
    return 1;
  }
  base::AtExitManager at_exit;
  base::CommandLine::Init(argc, argv);
  bool child = base::CommandLine::ForCurrentProcess()->HasSwitch("mojo-child");
  if (child) {
    if (seatbelt.sandbox_required) {
      const auto denied_path = base::CommandLine::ForCurrentProcess()->
          GetSwitchValuePath("denied-write-path");
      errno = 0;
      base::ScopedFD denied(open(denied_path.value().c_str(),
                                 O_WRONLY | O_CREAT | O_EXCL, 0600));
      if (!Require(!denied.is_valid() && (errno == EPERM || errno == EACCES),
                   "renderer policy denies an unrelated filesystem write"))
        return 1;
    }
    auto* rendezvous = base::MachPortRendezvousClient::GetInstance();
    if (!Require(rendezvous && rendezvous->GetPortCount() == 0,
                 "authenticate task port before Mojo initialization")) return 1;
  } else {
    mojo::core::SetMachPortProvider(base::MachPortRendezvousServer::GetInstance());
  }
  mojo::core::Configuration config;
  config.is_broker_process = !child;
  config.disable_ipcz = true;
  mojo::core::Init(config);
  base::Thread io_thread("SnowiumMojoIO");
  base::Thread::Options io_options;
  io_options.message_pump_type = base::MessagePumpType::IO;
  if (!io_thread.StartWithOptions(std::move(io_options))) return 1;
  mojo::core::ScopedIPCSupport ipc(io_thread.task_runner(),
      mojo::core::ScopedIPCSupport::ShutdownPolicy::FAST);
  if (child) {
    auto endpoint = mojo::PlatformChannel::RecoverPassedEndpointFromCommandLine(
        *base::CommandLine::ForCurrentProcess());
    auto invitation = mojo::IncomingInvitation::Accept(std::move(endpoint));
    if (!Require(invitation.is_valid(), "accept actual Mojo invitation")) return 1;
    auto pipe = invitation.ExtractMessagePipe("snowium124");
    return pipe.is_valid() && RoundtripChild(pipe.get()) ? 0 : 1;
  }
  char executable[PATH_MAX];
  if (!realpath(argv[0], executable)) return 1;
  base::CommandLine command{base::FilePath(executable)};
  command.AppendSwitch("mojo-child");
  base::LaunchOptions options;
  options.rendezvous_task_port = true;
  base::ScopedTempDir denied_directory;
  std::unique_ptr<sandbox::SeatbeltExecClient> seatbelt_client;
  sandbox::mac::SandboxPolicy policy;
  const auto profile_path = base::CommandLine::ForCurrentProcess()->
      GetSwitchValuePath("renderer-profile");
  if (!profile_path.empty()) {
    std::string profile;
    if (!Require(base::ReadFileToString(profile_path, &profile) &&
                     denied_directory.CreateUniqueTempDir(),
                 "prepare actual renderer source policy")) return 1;
    auto* source = policy.mutable_source();
    source->set_profile(std::move(profile));
    auto* parameters = source->mutable_params();
    (*parameters)["NETWORK_SERVICE_STORAGE_PATHS_COUNT"] = "0";
    (*parameters)["BROWSER_PID"] = std::to_string(getpid());
    (*parameters)["BUNDLE_ID"] = base::apple::BaseBundleID();
    (*parameters)["HELPER_BUNDLE_ID"] =
        std::string(base::apple::BaseBundleID()) + ".helper";
    (*parameters)["BUNDLE_PATH"] = base::FilePath(executable).DirName().value();
    (*parameters)["EXECUTABLE_PATH"] = executable;
    (*parameters)["USER_HOMEDIR_AS_LITERAL"] = getenv("HOME") ? getenv("HOME") : "/";
    (*parameters)["LOG_FILE_PATH"] = "/dev/null";
    (*parameters)["OS_VERSION"] = "1006";
    (*parameters)["DARWIN_USER_CACHE_DIR"] = "/private/var/tmp";
    (*parameters)["DARWIN_USER_DIR"] = "/private/var/tmp";
    (*parameters)["DARWIN_USER_TEMP_DIR"] = "/private/tmp";
    for (const char* key : {"DISABLE_SANDBOX_DENIAL_LOGGING", "ENABLE_LOGGING",
                           "FILTER_SYSCALLS", "FILTER_SYSCALLS_DEBUG",
                           "DISABLE_METAL_SHADER_CACHE"})
      (*parameters)[key] = "FALSE";
    command.AppendSwitchPath("denied-write-path",
                             denied_directory.GetPath().AppendASCII("denied"));
    seatbelt_client = std::make_unique<sandbox::SeatbeltExecClient>();
    int policy_fd = seatbelt_client->GetReadFD();
    if (policy_fd < 0) return 1;
    options.fds_to_remap.emplace_back(policy_fd, policy_fd);
    command.AppendSwitchASCII(sandbox::switches::kSeatbeltClientName,
                              std::to_string(policy_fd));
  }
  mojo::PlatformChannel channel;
  channel.PrepareToPassRemoteEndpoint(&options, &command);
  auto process = base::LaunchProcess(command, options);
  channel.RemoteProcessLaunchAttempted();
  if (!Require(process.IsValid(), "launch child with inherited Mojo socket and task enrollment")) return 1;
  if (seatbelt_client &&
      !Require(seatbelt_client->SendPolicy(policy),
               "send renderer policy over actual SeatbeltExec pipe")) {
    process.Terminate(1, true);
    return 1;
  }
  mojo::OutgoingInvitation invitation;
  auto pipe = invitation.AttachMessagePipe("snowium124");
  mojo::OutgoingInvitation::Send(std::move(invitation), process.Handle(),
                                 channel.TakeLocalEndpoint());
  bool ok = RoundtripParent(pipe.get());
  pipe.reset();
  int exit_code = -1;
  bool exited = process.WaitForExitWithTimeout(base::Seconds(5), &exit_code);
  ok &= Require(exited && exit_code == 0, "child completes 16 round trips and exits cleanly");
  if (!exited) process.Terminate(1, true);
  return ok ? 0 : 1;
}
