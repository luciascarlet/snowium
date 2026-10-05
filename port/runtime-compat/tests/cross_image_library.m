// Compile this twice; each dylib gets its own -load_hidden ARC archive.
#import <Foundation/Foundation.h>
#include <string.h>

#if SNOW_IMAGE_STRONG
static id slot;
#else
static __weak id slot;
#endif

__attribute__((visibility("default")))
void snow_image_store(void *object) { slot = (__bridge id)object; }

// Inspect raw bytes without retaining or messaging a potentially stale object.
__attribute__((visibility("default")))
void *snow_image_slot(void) {
  void *value = NULL;
  memcpy(&value, (const void *)&slot, sizeof(value));
  return value;
}

__attribute__((visibility("default")))
void snow_image_destroy(void) { slot = nil; }
