#import "snow_leopard/cocoa_compat.h"
#import <objc/runtime.h>
#include <stdlib.h>

#if defined(SNOW_LEOPARD_PORT)

#if __has_feature(objc_arc)
#error "Build the Snow Leopard Cocoa compatibility layer without ARC."
#endif

namespace {

Method FindMethodWithoutInitializing(Class cls, SEL selector) {
  // On Darwin 10, class_getInstanceMethod may send +resolveInstanceMethod:
  // and initialize NSView/NSUserDefaults. Registration needs metadata only.
  for (Class current = cls; current; current = class_getSuperclass(current)) {
    unsigned int count = 0;
    Method* methods = class_copyMethodList(current, &count);
    Method found = nullptr;
    for (unsigned int i = 0; i < count; ++i) {
      if (method_getName(methods[i]) == selector) {
        found = methods[i];
        break;
      }
    }
    free(methods);
    if (found)
      return found;
  }
  return nullptr;
}

void AddMissing(Class target, Class provider, SEL selector) {
  // Checking inherited methods also matters: class_addMethod alone would
  // override an inherited OS implementation on a later operating system.
  if (FindMethodWithoutInitializing(target, selector))
    return;
  Method method = FindMethodWithoutInitializing(provider, selector);
  if (method)
    class_addMethod(target, selector, method_getImplementation(method),
                    method_getTypeEncoding(method));
}

void AddNamed(Class target, Class provider, const char* name) {
  AddMissing(target, provider, sel_registerName(name));
}

// AppKit presentation options are process-wide. Keep them hidden until the
// last fullscreen window exits, regardless of the windows' exit order.
NSUInteger fullscreen_window_count = 0;
NSApplicationPresentationOptions windowed_presentation_options =
    NSApplicationPresentationDefault;

}  // namespace

BOOL SnowiumEnterFullscreen(NSWindow* window, SnowiumFullscreenState* state) {
  if (!window || !state)
    return NO;
  if (state->active)
    return YES;
  NSScreen* screen = [window screen] ?: [NSScreen mainScreen];
  if (!screen)
    return NO;

  state->windowed_frame = [window frame];
  state->windowed_style = [window styleMask];
  state->windowed_movable = [window isMovable];
  NSApplicationPresentationOptions previous_options = [NSApp presentationOptions];
  @try {
    if (fullscreen_window_count == 0) {
      NSApplicationPresentationOptions fullscreen_options =
          (previous_options & ~(NSApplicationPresentationAutoHideDock |
                                NSApplicationPresentationAutoHideMenuBar)) |
          NSApplicationPresentationHideDock | NSApplicationPresentationHideMenuBar;
      [NSApp setPresentationOptions:fullscreen_options];
    }
    [window setMovable:NO];
    [window setStyleMask:NSWindowStyleMaskBorderless];
    [window setFrame:[screen frame] display:YES];
    if ([window isMovable] ||
        !NSEqualRects([window frame], [screen frame]) ||
        [window styleMask] != NSWindowStyleMaskBorderless) {
      [window setMovable:state->windowed_movable];
      [window setStyleMask:state->windowed_style];
      [window setFrame:state->windowed_frame display:YES];
      [NSApp setPresentationOptions:previous_options];
      return NO;
    }
    [window makeKeyAndOrderFront:nil];
  } @catch (NSException* exception) {
    [window setMovable:state->windowed_movable];
    [window setStyleMask:state->windowed_style];
    [window setFrame:state->windowed_frame display:YES];
    [NSApp setPresentationOptions:previous_options];
    return NO;
  }
  if (fullscreen_window_count == 0)
    windowed_presentation_options = previous_options;
  ++fullscreen_window_count;
  state->active = true;
  return YES;
}

BOOL SnowiumExitFullscreen(NSWindow* window, SnowiumFullscreenState* state) {
  if (!window || !state)
    return NO;
  if (!state->active)
    return YES;
  NSRect fullscreen_frame = [window frame];
  NSApplicationPresentationOptions fullscreen_options = [NSApp presentationOptions];
  BOOL restored = NO;
  @try {
    [window setMovable:state->windowed_movable];
    [window setStyleMask:state->windowed_style];
    if (fullscreen_window_count == 1)
      [NSApp setPresentationOptions:windowed_presentation_options];
    [window setFrame:state->windowed_frame display:YES];
    restored = [window isMovable] == state->windowed_movable &&
               [window styleMask] == state->windowed_style &&
               NSEqualRects([window frame], state->windowed_frame);
  } @catch (NSException* exception) {
    restored = NO;
  }
  if (!restored) {
    @try {
      [NSApp setPresentationOptions:fullscreen_options];
      [window setMovable:NO];
      [window setStyleMask:NSWindowStyleMaskBorderless];
      [window setFrame:fullscreen_frame display:YES];
    } @catch (NSException* exception) {
      // The closing-window path still releases presentation state below.
    }
    return NO;
  }
  --fullscreen_window_count;
  state->active = false;
  return YES;
}

void SnowiumForgetFullscreen(SnowiumFullscreenState* state) {
  if (!state || !state->active)
    return;
  if (--fullscreen_window_count == 0)
    [NSApp setPresentationOptions:windowed_presentation_options];
  state->active = false;
}

BOOL SnowiumGetDeviceRGBA(NSColor* color, CGFloat components[4]) {
  NSColor* rgb = [color colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
  if (!rgb || [rgb numberOfComponents] != 4)
    return NO;
  [rgb getComponents:components];
  return YES;
}

BOOL SnowiumGetSystemColorRGBA(NSColor* color, CGFloat components[4]) {
  if (SnowiumGetDeviceRGBA(color, components))
    return YES;
  if (!color)
    return NO;
  NSBitmapImageRep* bitmap = [[NSBitmapImageRep alloc]
      initWithBitmapDataPlanes:NULL pixelsWide:1 pixelsHigh:1 bitsPerSample:8
      samplesPerPixel:4 hasAlpha:YES isPlanar:NO
      colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:4 bitsPerPixel:32];
  NSGraphicsContext* context = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
  if (!context) {
    [bitmap release];
    return NO;
  }
  [NSGraphicsContext saveGraphicsState];
  [NSGraphicsContext setCurrentContext:context];
  [color setFill];
  NSRectFillUsingOperation(NSMakeRect(0, 0, 1, 1), NSCompositingOperationCopy);
  [NSGraphicsContext restoreGraphicsState];
  BOOL converted = SnowiumGetDeviceRGBA([bitmap colorAtX:0 y:0], components);
  [bitmap release];
  return converted;
}

@interface SnowiumModernCocoaCompatibility : NSObject
@end

@implementation SnowiumModernCocoaCompatibility

+ (void)load {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  Class provider = self;
  // Metadata lookup avoids sending +class, which eagerly runs +initialize.
  // Utility/audio/network helpers need method registration without starting UI
  // defaults or distributed-notification services during framework loading.
  const char* window_methods[] = {"convertRectToScreen:",
                                  "convertRectFromScreen:",
                                  "backingScaleFactor",
                                  "convertRectToBacking:",
                                  "convertRectFromBacking:"};
  for (const char* name : window_methods)
    AddNamed(objc_getClass("NSWindow"), provider, name);

  const char* view_methods[] = {"convertPointToBacking:",
                                "convertPointFromBacking:",
                                "convertSizeToBacking:",
                                "convertSizeFromBacking:",
                                "convertRectToBacking:",
                                "convertRectFromBacking:"};
  for (const char* name : view_methods)
    AddNamed(objc_getClass("NSView"), provider, name);

  const char* screen_methods[] = {"backingScaleFactor", "convertRectToBacking:",
                                  "convertRectFromBacking:"};
  for (const char* name : screen_methods)
    AddNamed(objc_getClass("NSScreen"), provider, name);

  const char* event_methods[] = {"phase", "momentumPhase",
                                 "hasPreciseScrollingDeltas", "scrollingDeltaX",
                                 "scrollingDeltaY", "isDirectionInvertedFromDevice"};
  for (const char* name : event_methods)
    AddNamed(objc_getClass("NSEvent"), provider, name);

  AddNamed(object_getClass(objc_getClass("NSScroller")), provider,
           "preferredScrollerStyle");
  AddNamed(object_getClass(objc_getClass("NSScroller")), provider,
           "scrollerWidthForControlSize:scrollerStyle:");
  AddNamed(object_getClass(objc_getClass("NSColor")), provider,
           "colorWithSRGBRed:green:blue:alpha:");
  AddNamed(objc_getClass("NSArray"), provider, "firstObject");
  AddNamed(objc_getClass("NSArray"), provider, "objectAtIndexedSubscript:");
  AddNamed(objc_getClass("NSMutableArray"), provider, "setObject:atIndexedSubscript:");
  AddNamed(objc_getClass("NSDictionary"), provider, "objectForKeyedSubscript:");
  AddNamed(objc_getClass("NSMutableDictionary"), provider, "setObject:forKeyedSubscript:");
  AddNamed(objc_getClass("NSNib"), provider, "instantiateWithOwner:topLevelObjects:");
  [pool drain];
}

- (NSRect)convertRectToScreen:(NSRect)rect {
  rect.origin = [(NSWindow*)self convertBaseToScreen:rect.origin];
  return rect;
}

- (NSRect)convertRectFromScreen:(NSRect)rect {
  rect.origin = [(NSWindow*)self convertScreenToBase:rect.origin];
  return rect;
}

// Snow Leopard has no Retina backing store. Chromium's ordinary untransformed
// native views use one pixel per point; browser zoom remains a renderer concern.
- (CGFloat)backingScaleFactor { return 1.0; }
- (NSPoint)convertPointToBacking:(NSPoint)point { return point; }
- (NSPoint)convertPointFromBacking:(NSPoint)point { return point; }
- (NSSize)convertSizeToBacking:(NSSize)size { return size; }
- (NSSize)convertSizeFromBacking:(NSSize)size { return size; }
- (NSRect)convertRectToBacking:(NSRect)rect { return rect; }
- (NSRect)convertRectFromBacking:(NSRect)rect { return rect; }

// Lion's gesture phase protocol and natural-scroll preference are absent on
// 10.6. Continuous trackpad wheel events still carry pixel deltas in CGEvent.
- (NSEventPhase)phase { return NSEventPhaseNone; }
- (NSEventPhase)momentumPhase { return NSEventPhaseNone; }
- (BOOL)isDirectionInvertedFromDevice { return NO; }
- (BOOL)hasPreciseScrollingDeltas {
  CGEventRef event = [(NSEvent*)self CGEvent];
  return event && CGEventGetIntegerValueField(
                      event, kCGScrollWheelEventIsContinuous) != 0;
}
- (CGFloat)scrollingDeltaX {
  NSEvent* event = (NSEvent*)self;
  return [event hasPreciseScrollingDeltas]
             ? CGEventGetDoubleValueField([event CGEvent],
                                         kCGScrollWheelEventPointDeltaAxis2)
             : [event deltaX];
}
- (CGFloat)scrollingDeltaY {
  NSEvent* event = (NSEvent*)self;
  return [event hasPreciseScrollingDeltas]
             ? CGEventGetDoubleValueField([event CGEvent],
                                         kCGScrollWheelEventPointDeltaAxis1)
             : [event deltaY];
}

- (NSScrollerStyle)preferredScrollerStyle { return NSScrollerStyleLegacy; }
- (CGFloat)scrollerWidthForControlSize:(NSControlSize)size
                         scrollerStyle:(NSScrollerStyle)style {
  return [NSScroller scrollerWidthForControlSize:size];
}

- (NSColor*)colorWithSRGBRed:(CGFloat)red
                     green:(CGFloat)green
                      blue:(CGFloat)blue
                     alpha:(CGFloat)alpha {
  const CGFloat components[] = {red, green, blue, alpha};
  return [NSColor colorWithColorSpace:[NSColorSpace sRGBColorSpace]
                          components:components
                               count:4];
}

- (id)firstObject {
  NSArray* array = (NSArray*)self;
  return [array count] ? [array objectAtIndex:0] : nil;
}

- (id)objectAtIndexedSubscript:(NSUInteger)index {
  return [(NSArray*)self objectAtIndex:index];
}

- (void)setObject:(id)object atIndexedSubscript:(NSUInteger)index {
  NSMutableArray* array = (NSMutableArray*)self;
  if (index < [array count])
    [array replaceObjectAtIndex:index withObject:object];
  else
    // Inserting at count appends; an index above count or nil object raises
    // the same Foundation exception as native mutable array subscripting.
    [array insertObject:object atIndex:index];
}

- (id)objectForKeyedSubscript:(id)key {
  return [(NSDictionary*)self objectForKey:key];
}

- (void)setObject:(id)object forKeyedSubscript:(id<NSCopying>)key {
  NSMutableDictionary* dictionary = (NSMutableDictionary*)self;
  if (object)
    [dictionary setObject:object forKey:key];
  else
    [dictionary removeObjectForKey:key];
}

- (BOOL)instantiateWithOwner:(id)owner topLevelObjects:(NSArray**)objects {
  return [(NSNib*)self instantiateNibWithOwner:owner topLevelObjects:objects];
}

@end

#endif  // defined(SNOW_LEOPARD_PORT)
