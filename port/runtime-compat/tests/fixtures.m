#import "fixtures.h"
#include <libkern/OSAtomic.h>

volatile int32_t snow_deallocated;
volatile int32_t snow_custom_deallocated;
pthread_mutex_t snow_release_mutex = PTHREAD_MUTEX_INITIALIZER;
pthread_cond_t snow_release_condition = PTHREAD_COND_INITIALIZER;
int snow_release_started, snow_release_continue, snow_release_block;

@implementation SnowTracked
- (void)dealloc { OSAtomicIncrement32Barrier(&snow_deallocated); [super dealloc]; }
@end

/* Deliberately bypass NSObject's -retain/-release. This is an important case
 * which the original experimental NSObject-only shim could not support.
 */
@implementation SnowCustomRetain
- (id)init { self = [super init]; if (self) _references = 1; return self; }
- (id)retain { OSAtomicIncrement32Barrier(&_references); return self; }
- (oneway void)release {
  if (OSAtomicDecrement32Barrier(&_references) == 0) [self dealloc];
}
- (NSUInteger)retainCount { return _references; }
- (void)dealloc {
  OSAtomicIncrement32Barrier(&snow_custom_deallocated);
  [super dealloc];
}
@end
@implementation SnowCustomChild
- (id)retain { return [super retain]; }
- (oneway void)release { [super release]; }
- (void)dealloc { [super dealloc]; }
@end
@implementation SnowBlockedRelease
- (oneway void)release {
  pthread_mutex_lock(&snow_release_mutex);
  if (snow_release_block) {
    snow_release_started = 1;
    pthread_cond_broadcast(&snow_release_condition);
    while (!snow_release_continue)
      pthread_cond_wait(&snow_release_condition, &snow_release_mutex);
  }
  pthread_mutex_unlock(&snow_release_mutex);
  [super release];
}
- (void)dealloc { [super dealloc]; }
@end
void snow_mrc_release(void *object) { [(id)object release]; }
void snow_mrc_retain(void *object) { [(id)object retain]; }

extern id objc_storeWeak(id *slot, id value);
extern void objc_destroyWeak(id *slot);
struct StoreArgs { id *slot; id object; };
static void *store_thread(void *context) {
  struct StoreArgs *args = context;
  for (int i = 0; i < 128; ++i) objc_storeWeak(args->slot, args->object);
  return NULL;
}
BOOL snow_store_race(void) {
  for (int round = 0; round < 1000; ++round) {
    id slot = nil;
    id a = [SnowTracked new], b = [SnowCustomChild new];
    struct StoreArgs args_a = {&slot, a}, args_b = {&slot, b};
    pthread_t thread_a, thread_b;
    if (pthread_create(&thread_a, NULL, store_thread, &args_a) ||
        pthread_create(&thread_b, NULL, store_thread, &args_b)) abort();
    pthread_join(thread_a, NULL); pthread_join(thread_b, NULL);
    objc_destroyWeak(&slot);
    // The destroyed slot no longer belongs to the runtime. A stale address
    // registration would overwrite this sentinel when either object dies.
    slot = (id)(uintptr_t)0x12345;
    [a release]; [b release];
    if (slot != (id)(uintptr_t)0x12345) return NO;
  }
  return YES;
}
