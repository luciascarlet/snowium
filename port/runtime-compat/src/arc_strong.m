/* Snow Leopard implementations of the compiler's strong ARC entry points.
 * Compile this file without ARC. Darwin 10 does not participate in the newer
 * autoreleased-return-value optimization, so ordinary messages are required.
 */
#import <Foundation/Foundation.h>

id objc_retain(id object) { return [object retain]; }
void objc_release(id object) { [object release]; }
id objc_autorelease(id object) { return [object autorelease]; }
id objc_retainAutorelease(id object) { return [[object retain] autorelease]; }
id objc_retainAutoreleaseReturnValue(id object) { return [[object retain] autorelease]; }
id objc_retainAutoreleasedReturnValue(id object) { return [object retain]; }
id objc_autoreleaseReturnValue(id object) { return [object autorelease]; }
id objc_unsafeClaimAutoreleasedReturnValue(id object) { return object; }
id objc_retainBlock(id object) { return [object copy]; }
void objc_storeStrong(id *slot, id object) {
  id old = *slot;
  if (old == object) return;
  [object retain];
  *slot = object;
  [old release];
}
void *objc_autoreleasePoolPush(void) { return [[NSAutoreleasePool alloc] init]; }
void objc_autoreleasePoolPop(void *pool) { [(NSAutoreleasePool *)pool drain]; }
