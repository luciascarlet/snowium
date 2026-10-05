// Actual Chromium 124 LaunchProcess + authenticated Mach task-port rendezvous.
#include <poll.h>
#include <errno.h>
#include <limits.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#include "base/at_exit.h"
#include "base/command_line.h"
#include "base/files/scoped_file.h"
#include "base/mac/mach_port_rendezvous.h"
#include "base/process/launch.h"
#include "base/process/process.h"
#include "base/threading/platform_thread.h"
#include "base/time/time.h"

bool Require(bool ok, const char* label) {
  printf("%s %s\n", ok ? "PASS" : "FAIL", label);
  return ok;
}

int main(int argc, char** argv) {
  setbuf(stdout, nullptr);
  base::AtExitManager at_exit;
  base::CommandLine::Init(argc, argv);
  if (argc > 1 && strcmp(argv[1], "--rendezvous-child") == 0) {
    if (argc != 4) return 1;
    int same_fd = atoi(argv[2]), unrelated_fd = atoi(argv[3]);
    if (!Require(fcntl(same_fd, F_GETFD) >= 0 &&
                     !(fcntl(same_fd, F_GETFD) & FD_CLOEXEC),
                 "same-FD CLOEXEC mapping survives exec")) return 1;
    if (!Require(fcntl(unrelated_fd, F_GETFD) == -1 && errno == EBADF,
                 "unrelated parent descriptor is closed in child")) return 1;
    if (!Require(getpgrp() == getpid(), "child process group option is preserved")) return 1;
    char directory[1024];
    if (!Require(getcwd(directory, sizeof(directory)) && strcmp(directory, "/private/tmp") == 0,
                 "working directory is applied in child")) return 1;
    if (!Require(getenv("SNOWIUM_MODERN_LAUNCH_PROBE") &&
                     strcmp(getenv("SNOWIUM_MODERN_LAUNCH_PROBE"), "child-only") == 0,
                 "child receives the requested environment overlay")) return 1;
    auto* client = base::MachPortRendezvousClient::GetInstance();
    if (!Require(client && client->GetPortCount() == 0,
                 "actual Chromium child exchanges task right with zero incoming ports")) return 1;
    char byte;
    return write(3, "x", 1) == 1 && read(3, &byte, 1) == 1 ? 0 : 1;
  }
  int fds[2];
  if (!Require(socketpair(AF_UNIX, SOCK_STREAM, 0, fds) == 0,
               "create child synchronization socket")) return 1;
  base::ScopedFD local(fds[0]), remote(fds[1]);
  base::ScopedFD same_fd(fcntl(local.get(), F_DUPFD, 64));
  base::ScopedFD unrelated_fd(fcntl(local.get(), F_DUPFD, 200));
  if (!Require(same_fd.is_valid() && unrelated_fd.is_valid() &&
                   fcntl(same_fd.get(), F_SETFD, FD_CLOEXEC) == 0,
               "prepare identity mapping and unrelated high descriptor")) return 1;
  char executable[PATH_MAX], parent_directory[PATH_MAX];
  if (!realpath(argv[0], executable) || !getcwd(parent_directory, sizeof(parent_directory))) return 1;
  const char* existing_value = getenv("SNOWIUM_MODERN_LAUNCH_PROBE");
  std::string parent_value = existing_value ? existing_value : "";
  base::CommandLine command{base::FilePath(executable)};
  command.AppendSwitch("rendezvous-child");
  command.AppendArg(std::to_string(same_fd.get()));
  command.AppendArg(std::to_string(unrelated_fd.get()));
  base::LaunchOptions options;
  options.rendezvous_task_port = true;
  options.new_process_group = true;
  options.environment["SNOWIUM_MODERN_LAUNCH_PROBE"] = "child-only";
  options.current_directory = base::FilePath("/private/tmp");
  options.fds_to_remap.emplace_back(same_fd.get(), same_fd.get());
  options.fds_to_remap.emplace_back(remote.get(), 3);
  base::Process process = base::LaunchProcess(command, options);
  remote.reset();
  if (!Require(process.IsValid(), "actual Chromium LaunchProcess starts registered child")) return 1;
  pollfd poll_fd{local.get(), POLLIN, 0};
  char byte;
  char after_directory[PATH_MAX];
  const char* after_value = getenv("SNOWIUM_MODERN_LAUNCH_PROBE");
  if (!Require(getcwd(after_directory, sizeof(after_directory)) &&
                   strcmp(after_directory, parent_directory) == 0 &&
                   parent_value == (after_value ? after_value : "") &&
                   fcntl(unrelated_fd.get(), F_GETFD) >= 0 &&
                   (fcntl(same_fd.get(), F_GETFD) & FD_CLOEXEC),
               "parent directory, environment and descriptor flags remain unchanged")) return 1;
  bool ready = poll(&poll_fd, 1, 10000) == 1 && read(local.get(), &byte, 1) == 1;
  bool ok = Require(ready, "child finishes Mach startup before higher level IPC");
  auto* provider = base::MachPortRendezvousServer::GetInstance();
  mach_port_t task = provider->TaskForHandle(process.Handle());
  pid_t task_pid = -1;
  ok &= Require(task != MACH_PORT_NULL && pid_for_task(task, &task_pid) == KERN_SUCCESS &&
                    task_pid == process.Pid(),
                "browser provider returns the authenticated child's task right");
  if (ready) write(local.get(), "x", 1);
  int exit_code = -1;
  bool exited = process.WaitForExitWithTimeout(base::Seconds(5), &exit_code);
  ok &= Require(exited && exit_code == 0, "child exits cleanly");
  if (!exited) process.Terminate(1, true);
  for (int i = 0; i < 100 && provider->TaskForHandle(process.Handle()); ++i)
    base::PlatformThread::Sleep(base::Milliseconds(10));
  ok &= Require(provider->TaskForHandle(process.Handle()) == MACH_PORT_NULL,
                "process-exit watcher removes the task port enrollment");
  base::CommandLine missing(base::FilePath("/nonexistent/Snowium-owned-exec-test"));
  ok &= Require(!base::LaunchProcess(missing, base::LaunchOptions()).IsValid(),
                "failed exec is reported as launch failure");
  return ok ? 0 : 1;
}
