#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string>
#include <sys/wait.h>
#include <unistd.h>
#include "sandbox/mac/seatbelt.h"
#include "sandbox/mac/seatbelt_extension.h"
#include "sandbox/mac/seatbelt_extension_token.h"

int CheckPath(const char* suffix) {
  std::string stem = "/private/tmp/snowium124-seatbelt-" + std::to_string(getpid());
  std::string allowed = stem + suffix;
  std::string denied = stem + "-denied";
  for (const auto& path : {allowed, denied}) {
    int fd = open(path.c_str(), O_WRONLY | O_CREAT | O_EXCL, 0600);
    if (fd < 0) return 1;
    close(fd);
  }
  // HFS+ normalizes Unicode names. Match the kernel's canonical file path.
  char canonical[4096];
  int canonical_fd = open(allowed.c_str(), O_RDONLY);
  if (canonical_fd < 0 || fcntl(canonical_fd, F_GETPATH, canonical) != 0) return 6;
  close(canonical_fd);
  allowed.assign(canonical);
  pid_t child = fork();
  if (child == 0) {
    const char* params[] = {"PATH", allowed.c_str(), nullptr};
    std::string error;
    const char* profile = "(version 1)\n(deny default)\n"
        "(allow file-read*)\n(allow file-write* (literal (param \"PATH\")))\n";
    if (!sandbox::Seatbelt::InitWithParams(profile, 0, params, &error)) {
      fprintf(stderr, "sandbox_init: %s\n", error.c_str());
      _exit(2);
    }
    int good = open(allowed.c_str(), O_WRONLY | O_TRUNC);
    bool wrote = good >= 0 && write(good, "OK", 2) == 2;
    if (!wrote) fprintf(stderr, "allowed write errno=%d path=%s\n", errno, allowed.c_str());
    if (good >= 0) close(good);
    int bad = open(denied.c_str(), O_WRONLY | O_TRUNC);
    bool blocked = bad < 0 && (errno == EACCES || errno == EPERM);
    if (bad >= 0) close(bad);
    _exit(!wrote ? 4 : !blocked ? 5 : 0);
  }
  int status = 0;
  bool waited = child > 0 && waitpid(child, &status, 0) == child;
  unlink(allowed.c_str());
  unlink(denied.c_str());
  if (!waited || !WIFEXITED(status) || WEXITSTATUS(status))
    printf("child wait=%d status=%d\n", waited, status);
  bool ok = waited && WIFEXITED(status) && WEXITSTATUS(status) == 0;
  printf("%s sandbox parameters preserve quoted Unicode paths and deny other writes\n",
         ok ? "PASS" : "FAIL");
  printf("suffix: %s\n", suffix);
  return ok ? 0 : 1;
}

int main() {
  int failures = 0;
  auto issued = sandbox::SeatbeltExtension::Issue(
      sandbox::SeatbeltExtension::FILE_READ, "/private/tmp");
  auto fake = sandbox::SeatbeltExtension::FromToken(
      sandbox::SeatbeltExtensionToken::CreateForTesting("untrusted-token"));
  bool extension_denied = !issued && fake && !fake->Consume();
  if (fake) fake->Revoke();
  printf("%s unsupported extension tokens never grant access\n",
         extension_denied ? "PASS" : "FAIL");
  failures += !extension_denied;
  for (const char* suffix : {"-ascii", "-quote\"", "-backslash\\", "-unicodeé", "-astral🐈", "-\"\\é (allow file-write*)"})
    failures += CheckPath(suffix);
  return failures ? 1 : 0;
}
