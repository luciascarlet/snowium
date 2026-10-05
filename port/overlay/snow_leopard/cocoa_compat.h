// Small Cocoa backports for the fixed 1x Snow Leopard display environment.
// Compile cocoa_compat.mm without ARC; its +load must be linked into each process
// that uses Cocoa. Existing operating-system implementations are never replaced.
#ifndef SNOW_LEOPARD_COCOA_COMPAT_H_
#define SNOW_LEOPARD_COCOA_COMPAT_H_

#import <Cocoa/Cocoa.h>

// Literal names remain valid notification names on both old and new systems.
// Snow Leopard never posts these notifications, but passing nil to
// addObserver:name: would accidentally subscribe to every notification.
#define SNOWIUM_BACKING_PROPERTIES_NOTIFICATION \
  @"NSWindowDidChangeBackingPropertiesNotification"
#define SNOWIUM_SCROLLER_STYLE_NOTIFICATION \
  @"NSPreferredScrollerStyleDidChangeNotification"

// NSCustomColorSpace in 10.6 implements getComponents: but raises an exception
// for getRed:green:blue:alpha:, even when its underlying color space is RGB.
// Returns NO for colors that cannot be converted (for example pattern colors).
BOOL SnowiumGetDeviceRGBA(NSColor* color, CGFloat components[4]);

// System background colors on 10.6 can be patterns. Sample their actual Cocoa
// drawing into one pixel when a caller explicitly needs a representative color.
BOOL SnowiumGetSystemColorRGBA(NSColor* color, CGFloat components[4]);

#if defined(SNOW_LEOPARD_PORT)
// State for the pre-Lion borderless-window fullscreen path. The caller owns
// the NSWindow and restores this state before closing it.
struct SnowiumFullscreenState {
  bool active = false;
  NSRect windowed_frame = NSZeroRect;
  NSUInteger windowed_style = 0;
  BOOL windowed_movable = YES;
};

BOOL SnowiumEnterFullscreen(NSWindow* window, SnowiumFullscreenState* state);
BOOL SnowiumExitFullscreen(NSWindow* window, SnowiumFullscreenState* state);
// Release process-wide presentation state even if a closing window can no
// longer accept frame changes.
void SnowiumForgetFullscreen(SnowiumFullscreenState* state);
#endif

#endif  // SNOW_LEOPARD_COCOA_COMPAT_H_
