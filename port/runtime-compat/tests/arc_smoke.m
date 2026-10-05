#import "fixtures.h"
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <dispatch/dispatch.h>
#include <string.h>
#define EXCLUDE_STUB_PROTOTYPES 1
#import "../src/PLWeakCompatibilityStubs.h"

#define CHECK(expression) do { \
  if (!(expression)) { \
    fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #expression); \
    abort(); \
  } \
} while (0)

@interface SnowPropertyOwner : NSObject
@property(atomic, strong) id strongValue;
@property(nonatomic, copy) NSString *copiedValue;
@property(nonatomic, weak) id weakValue;
@property(nonatomic) NSInteger counter;
@end
@implementation SnowPropertyOwner
@end
@interface SnowObserver : NSObject
@property(nonatomic) NSInteger notifications;
@end
@implementation SnowObserver
- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)object
                       change:(NSDictionary *)change context:(void *)context {
  self.notifications++;
}
@end

static void properties(void) {
  SnowPropertyOwner *owner = [SnowPropertyOwner new];
  int before = snow_deallocated;
  @autoreleasepool {
    SnowTracked *object = [SnowTracked new];
    owner.strongValue = object;
    owner.weakValue = object;
    NSMutableString *value = [NSMutableString stringWithString:@"original"];
    owner.copiedValue = value;
    [value appendString:@" modified"];
    CHECK([owner.copiedValue isEqualToString:@"original"]);
  }
  @autoreleasepool {
    CHECK(owner.strongValue == owner.weakValue && owner.weakValue != nil);
  }
  @autoreleasepool { owner.strongValue = nil; }
  CHECK(owner.weakValue == nil && snow_deallocated == before + 1);
  puts("PASS synthesized atomic strong, nonatomic weak/copy properties");
}

/* Diagnostic, separate from the supported-runtime regression: changing isa
 * after registration may bypass the weak library's deallocation hook. Inspect
 * slot bytes without ever dereferencing a potentially stale object pointer.
 */
static int kvo_probe(BOOL observe_first) {
  __weak id weak;
  @autoreleasepool {
    SnowObserver *observer = [SnowObserver new];
    SnowPropertyOwner *object = [SnowPropertyOwner new];
    if (!observe_first) weak = object;
    [object addObserver:observer forKeyPath:@"counter" options:0 context:NULL];
    if (observe_first) weak = object;
    object.counter++;
    CHECK(observer.notifications == 1);
    [object removeObserver:observer forKeyPath:@"counter"];
  }
  void *bits = NULL;
  memcpy(&bits, (void *)&weak, sizeof(bits));
  printf("%s KVO %s weak registration and observation removal\n",
         bits == NULL ? "PASS" : "UNSUPPORTED", observe_first ? "before" : "after");
  return bits != NULL;
}

static int cf_probe(void) {
  __weak id weak;
  @autoreleasepool {
    CFMutableStringRef string = CFStringCreateMutable(NULL, 0);
    CFStringAppend(string, CFSTR("Snowium CF lifetime probe"));
    weak = (__bridge id)string;
    CFRelease(string);
  }
  void *bits = NULL;
  memcpy(&bits, (void *)&weak, sizeof(bits));
  printf("%s weak reference to toll-free bridged CF object released via CFRelease\n",
         bits == NULL ? "PASS" : "UNSUPPORTED");
  return bits != NULL;
}

static void basic(void) {
  int before = snow_deallocated;
  __weak SnowTracked *weak = nil;
  @autoreleasepool {
    SnowTracked *object = [SnowTracked new];
    weak = object;
    CHECK(weak == object);
    __weak id copy = weak;
    CHECK(copy == object);
    object = nil;
  }
  CHECK(weak == nil);
  CHECK(snow_deallocated == before + 1);
  puts("PASS ARC strong, pool, weak initialization/copy, zeroing");
}

static void custom(void) {
  int before = snow_custom_deallocated;
  __weak id weakA, weakB, weakC;
  @autoreleasepool {
    id a = [SnowCustomRetain new];
    id b = [SnowCustomChild new];
    id c = [SnowBlockedRelease new];
    weakA = a; weakB = b; weakC = c;
    CHECK(weakA == a && weakB == b && weakC == c);
    @autoreleasepool { NSArray *array = @[a, b, c]; CHECK([array count] == 3); }
  }
  CHECK(weakA == nil && weakB == nil && weakC == nil);
  CHECK(snow_custom_deallocated == before + 3);
  puts("PASS independent retain/release implementation and 3-level inheritance");
}

static void block_capture(void) {
  __weak id weak;
  id (^block)(void);
  @autoreleasepool {
    id object = [SnowTracked new];
    weak = object;
    block = [^{ return weak; } copy];
    CHECK(block() == object);
  }
  CHECK(block() == nil);
  block = nil;
  puts("PASS copied block with captured weak storage");
}

struct ReleaseArgs { void *object; };
static void *release_thread(void *ptr) {
  @autoreleasepool { snow_mrc_release(((struct ReleaseArgs *)ptr)->object); }
  return NULL;
}
struct LoadArgs { id __weak *weak; int acquired; int finished; };
static void *load_thread(void *ptr) {
  struct LoadArgs *arg = ptr;
  @autoreleasepool {
    id value = *arg->weak;
    arg->acquired = value != nil;
  }
  pthread_mutex_lock(&snow_release_mutex);
  arg->finished = 1;
  pthread_cond_broadcast(&snow_release_condition);
  pthread_mutex_unlock(&snow_release_mutex);
  return NULL;
}
static void blocked_release(void) {
  __weak id weak;
  void *raw;
  @autoreleasepool {
    id object = [SnowBlockedRelease new];
    weak = object;
    raw = (__bridge_retained void *)object;
  }
  struct ReleaseArgs release_args = {raw};
  struct LoadArgs load_args = {&weak, 0, 0};
  pthread_t release, load;
  snow_release_block = 1;
  CHECK(pthread_create(&release, NULL, release_thread, &release_args) == 0);
  pthread_mutex_lock(&snow_release_mutex);
  while (!snow_release_started)
    pthread_cond_wait(&snow_release_condition, &snow_release_mutex);
  pthread_mutex_unlock(&snow_release_mutex);
  CHECK(pthread_create(&load, NULL, load_thread, &load_args) == 0);
  usleep(20000);
  pthread_mutex_lock(&snow_release_mutex);
  CHECK(!load_args.finished);
  snow_release_continue = 1;
  pthread_cond_broadcast(&snow_release_condition);
  pthread_mutex_unlock(&snow_release_mutex);
  CHECK(pthread_join(release, NULL) == 0);
  CHECK(pthread_join(load, NULL) == 0);
  snow_release_block = 0;
  CHECK(!load_args.acquired && weak == nil);
  puts("PASS weak load waits for custom final release and observes zeroing");
}

static void parallel_release(void) {
  int before = snow_custom_deallocated;
  for (int i = 0; i < 2000; ++i) {
    __weak id weak;
    void *raw;
    @autoreleasepool {
      id object = [SnowCustomChild new];
      weak = object;
      raw = (__bridge_retained void *)object;
    }
    snow_mrc_retain(raw);
    struct ReleaseArgs args = {raw};
    pthread_t a, b;
    CHECK(pthread_create(&a, NULL, release_thread, &args) == 0);
    CHECK(pthread_create(&b, NULL, release_thread, &args) == 0);
    while (1) {
      @autoreleasepool {
        if (weak == nil) break;
      }
      sched_yield();
    }
    CHECK(pthread_join(a, NULL) == 0);
    CHECK(pthread_join(b, NULL) == 0);
    CHECK(weak == nil);
  }
  CHECK(snow_custom_deallocated == before + 2000);
  puts("PASS 2000 concurrent final releases versus retained weak loads");
}

int main(int argc, char **argv) {
  setbuf(stdout, NULL);
  alarm(90);
  @autoreleasepool {
    PLWeakCompatibilitySetMAZWREnabled(NO);
    if (argc > 1 && strcmp(argv[1], "--kvo-before") == 0) return kvo_probe(YES);
    if (argc > 1 && strcmp(argv[1], "--kvo-after") == 0) return kvo_probe(NO);
    if (argc > 1 && strcmp(argv[1], "--cf") == 0) return cf_probe();
    basic(); properties(); custom(); block_capture(); blocked_release(); parallel_release();
    CHECK(snow_store_race());
    puts("PASS 1000 concurrent weak store/destroy races without stale registrations");
  }
  puts("PASS complete ARC runtime regression");
  return 0;
}
