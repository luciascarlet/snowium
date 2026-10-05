// Source-linked Darwin 10 replacements for later libSystem entry points.
#ifndef SNOW_LEOPARD_SYSTEM_COMPAT_H_
#define SNOW_LEOPARD_SYSTEM_COMPAT_H_

#include <mach-o/loader.h>

#ifdef __cplusplus
extern "C" {
#endif
unsigned char* getsectiondata(const struct mach_header_64* header,
                             const char* segment_name,
                             const char* section_name,
                             unsigned long* size);
unsigned char* getsegmentdata(const struct mach_header_64* header,
                             const char* segment_name,
                             unsigned long* size);
void abort_report_np(const char* format, ...)
    __attribute__((noreturn, format(printf, 1, 2)));
#ifdef __cplusplus
}
#endif
#endif
