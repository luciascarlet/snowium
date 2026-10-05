// MRC host owns an object; both independently loaded ARC libraries reference it.
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

static unsigned deallocations;
@interface SnowCrossImageObject : NSObject
@end
@implementation SnowCrossImageObject
- (void)dealloc { ++deallocations; [super dealloc]; }
@end

int main(int argc, char **argv) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  BOOL strong_second = argc == 4 && strcmp(argv[1], "--strong") == 0;
  if (argc != 3 && !strong_second) return 2;
  void *images[2];
  void (*store[2])(void *);
  void *(*slot[2])(void);
  void (*destroy[2])(void);
  for (unsigned i = 0; i < 2; ++i) {
    images[i] = dlopen(argv[i + (strong_second ? 2 : 1)], RTLD_NOW | RTLD_LOCAL);
    if (!images[i]) { fprintf(stderr, "FAIL dlopen: %s\n", dlerror()); return 2; }
    store[i] = dlsym(images[i], "snow_image_store");
    slot[i] = dlsym(images[i], "snow_image_slot");
    destroy[i] = dlsym(images[i], "snow_image_destroy");
    if (!store[i] || !slot[i] || !destroy[i]) return 2;
  }
  id object = [[SnowCrossImageObject alloc] init];
  store[0](object);
  store[1](object);
  BOOL registered = slot[0]() == object && slot[1]() == object;
  [object release];
  if (strong_second) {
    registered = registered && deallocations == 0 && slot[0]() == object;
    destroy[1]();
  }
  BOOL zeroed = !slot[0]() && !slot[1]();
  printf("%s cross-image %s zeroing: registered=%d deallocations=%u slots=%p,%p\n",
         registered && zeroed && deallocations == 1 ? "PASS" : "FAIL",
         strong_second ? "strong/weak" : "weak/weak",
         registered, deallocations, slot[0](), slot[1]());
  // Registered storage lives until process exit. Do not unload code containing
  // class hooks, or message any object through a stale weak pointer.
  destroy[0]();
  destroy[1]();
  [pool drain];
  return registered && zeroed && deallocations == 1 ? 0 : 1;
}
