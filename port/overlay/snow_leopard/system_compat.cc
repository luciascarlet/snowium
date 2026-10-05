// Darwin 10 lacks these mapped Mach-O data and fatal-report exports. These are source
// implementations, linked into the browser instead of modifying libSystem.
#include "system_compat.h"

#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>

static unsigned char* GetMappedMachOData(const struct mach_header_64* header,
                                         const char* segment_name,
                                         const char* section_name,
                                         unsigned long* size) {
  *size = 0;
  if (!header || header->magic != MH_MAGIC_64)
    return nullptr;
  const unsigned char* begin = reinterpret_cast<const unsigned char*>(header + 1);
  const unsigned char* cursor = begin;
  bool have_match = false;
  uint64_t match_address = 0;
  uint64_t match_size = 0;
  uintptr_t preferred_header_address = 0;
  bool have_header_segment = false;
  for (uint32_t i = 0; i < header->ncmds; ++i) {
    size_t offset = static_cast<size_t>(cursor - begin);
    if (offset > header->sizeofcmds ||
        header->sizeofcmds - offset < sizeof(struct load_command))
      return nullptr;
    const struct load_command* command =
        reinterpret_cast<const struct load_command*>(cursor);
    if (command->cmdsize < sizeof(*command) ||
        command->cmdsize > header->sizeofcmds - offset)
      return nullptr;
    if (command->cmd == LC_SEGMENT_64) {
      if (command->cmdsize < sizeof(struct segment_command_64))
        return nullptr;
      const struct segment_command_64* segment =
          reinterpret_cast<const struct segment_command_64*>(cursor);
      if (segment->nsects >
          (command->cmdsize - sizeof(*segment)) / sizeof(struct section_64))
        return nullptr;
      // __PAGEZERO also starts at file offset zero, but has no file contents.
      // Locate the segment that actually contains the mapped Mach-O header.
      if (segment->fileoff == 0 &&
          segment->filesize >= sizeof(*header) + header->sizeofcmds) {
        preferred_header_address = segment->vmaddr;
        have_header_segment = true;
      }
      if (strncmp(segment->segname, segment_name, sizeof(segment->segname)) == 0) {
        if (!section_name) {
          have_match = true;
          match_address = segment->vmaddr;
          match_size = segment->vmsize;
          cursor += command->cmdsize;
          continue;
        }
        const struct section_64* section =
            reinterpret_cast<const struct section_64*>(segment + 1);
        for (uint32_t j = 0; j < segment->nsects; ++j) {
          if (strncmp(section[j].sectname, section_name,
                      sizeof(section[j].sectname)) == 0) {
            have_match = true;
            match_address = section[j].addr;
            match_size = section[j].size;
            break;
          }
        }
      }
    }
    cursor += command->cmdsize;
  }
  if (!have_match || !have_header_segment)
    return nullptr;
  const uintptr_t slide =
      reinterpret_cast<uintptr_t>(header) - preferred_header_address;
  *size = static_cast<unsigned long>(match_size);
  return reinterpret_cast<unsigned char*>(match_address + slide);
}

extern "C" unsigned char* getsectiondata(const struct mach_header_64* header,
                                         const char* segment_name,
                                         const char* section_name,
                                         unsigned long* size) {
  return GetMappedMachOData(header, segment_name, section_name, size);
}

extern "C" unsigned char* getsegmentdata(const struct mach_header_64* header,
                                         const char* segment_name,
                                         unsigned long* size) {
  return GetMappedMachOData(header, segment_name, nullptr, size);
}

extern "C" void abort_report_np(const char* format, ...) {
  va_list arguments;
  va_start(arguments, format);
  vfprintf(stderr, format, arguments);
  va_end(arguments);
  fputc('\n', stderr);
  fflush(stderr);
  abort();
}
