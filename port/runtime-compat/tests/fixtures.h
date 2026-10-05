#import <Foundation/Foundation.h>
#include <pthread.h>

@interface SnowTracked : NSObject
@end
@interface SnowCustomRetain : NSObject {
  volatile int32_t _references;
}
@end
@interface SnowCustomChild : SnowCustomRetain
@end
@interface SnowBlockedRelease : SnowCustomChild
@end

extern volatile int32_t snow_deallocated;
extern volatile int32_t snow_custom_deallocated;
extern pthread_mutex_t snow_release_mutex;
extern pthread_cond_t snow_release_condition;
extern int snow_release_started;
extern int snow_release_continue;
extern int snow_release_block;
void snow_mrc_release(void *object);
void snow_mrc_retain(void *object);
BOOL snow_store_race(void);
