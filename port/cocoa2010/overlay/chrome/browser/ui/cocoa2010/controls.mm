// Copyright 2010 The Chromium Authors. All rights reserved.
// Copyright 2026 Snowium contributors.
// BSD license; see port/cocoa2010/upstream/LICENSE.
// Tab paths, widths, overlap and field geometry are from Chromium 7.0.517.41.
// Browser/model ownership is supplied by the 124 adapter rather than old C++ APIs.
#import "chrome/browser/ui/cocoa2010/controls.h"
#import <QuartzCore/QuartzCore.h>
#include "chrome/app/chrome_command_ids.h"
#include <algorithm>
#include <cmath>
@implementation Cocoa2010TabData
@end

// Animate only geometry. AppKit's layer-backed NSView animator on 10.6 also
// transitions rendered contents, which adds a fade absent from Chromium 7.
@interface Cocoa2010FrameAnimation : NSAnimation {
  NSView* _view;
  NSRect _from;
  NSRect _to;
}
- (instancetype)initWithView:(NSView*)view target:(NSRect)target;
@end
@implementation Cocoa2010FrameAnimation
- (instancetype)initWithView:(NSView*)view target:(NSRect)target {
  if ((self = [super initWithDuration:.125 animationCurve:NSAnimationEaseInOut])) {
    _view = view; _from = view.frame; _to = target;
    self.animationBlockingMode = NSAnimationNonblocking;
    self.frameRate = 60;
  }
  return self;
}
- (NSArray*)runLoopModesForAnimating {
  return @[NSDefaultRunLoopMode, NSEventTrackingRunLoopMode];
}
- (void)setCurrentProgress:(NSAnimationProgress)progress {
  [super setCurrentProgress:progress];
  if (!_view) return;
  CGFloat t = self.currentValue;
  NSRect frame = NSMakeRect(_from.origin.x + (_to.origin.x-_from.origin.x)*t,
      _from.origin.y + (_to.origin.y-_from.origin.y)*t,
      _from.size.width + (_to.size.width-_from.size.width)*t,
      _from.size.height + (_to.size.height-_from.size.height)*t);
  [CATransaction begin]; [CATransaction setDisableActions:YES];
  _view.frame = frame;
  [CATransaction commit];
}
@end

namespace {
const CGFloat kTabOverlap = 20.0;
const CGFloat kInsetMultiplier = 2.0 / 3.0;
const CGFloat kControlPoint1Multiplier = 1.0 / 3.0;
const CGFloat kControlPoint2Multiplier = 3.0 / 8.0;
const CGFloat kTearDistance = 36.0;
void SetFrameIfChanged(NSView* view, NSRect frame) {
  if (!NSEqualRects(view.frame, frame)) view.frame = frame;
}
// Keep the old explicit hover and position animations. Layer backing is only
// needed to compose above Chromium 124; it must not crossfade tab artwork.
void DisableContentsAnimation(NSView* view) {
  // AppKit's layer delegate consults the view's animation dictionary before
  // CALayer.actions. Suppress its defaults as well as Core Animation's defaults.
  view.animations = @{@"frame":NSNull.null, @"frameOrigin":NSNull.null,
                      @"frameSize":NSNull.null, @"alphaValue":NSNull.null};
  CALayer* layer = view.layer;
  if (!layer) return;
  NSMutableDictionary* actions = [layer.actions mutableCopy] ?: [[NSMutableDictionary alloc] init];
  for (NSString* key in @[@"contents", @"opacity", @"position", @"bounds",
                          @"sublayers", @"onOrderIn", @"onOrderOut"])
    [actions setObject:NSNull.null forKey:key];
  layer.actions = actions;
  [layer removeAllAnimations];
}
NSComparisonResult CompareSubviewOrder(id first, id second, void* context) {
  NSArray* order = (__bridge NSArray*)context;
  NSUInteger a = [order indexOfObjectIdenticalTo:first];
  NSUInteger b = [order indexOfObjectIdenticalTo:second];
  return a < b ? NSOrderedAscending : a > b ? NSOrderedDescending : NSOrderedSame;
}
void InvalidateAppearance(NSView* view) {
  // A parent's redraw does not invalidate its children's cached CA contents.
  view.needsDisplay = YES;
  for (NSView* child in view.subviews) InvalidateAppearance(child);
}
NSImage* Image(NSString* directory, NSString* name) {
  static NSMutableDictionary* images = [[NSMutableDictionary alloc] init];
  NSString* path = [directory stringByAppendingPathComponent:name];
  NSImage* image = images[path];
  if (!image) { image = [[NSImage alloc] initWithContentsOfFile:path]; if (image) images[path] = image; }
  return image;
}
// Google Toolbox for Mac, copyright 2009 Google Inc., Apache 2.0.
// Original Lab luminance treatment used by BrowserThemeProvider::GetNSGradient.
NSColor* AdjustLuminance(NSColor* color, CGFloat change) {
  CGFloat white[3] = {.95047, 1, 1.08883}, black[3] = {0, 0, 0}, range[4] = {-127, 127, -127, 127};
  CGColorSpaceRef cg = CGColorSpaceCreateLab(white, black, range);
  NSColorSpace* lab = [[NSColorSpace alloc] initWithCGColorSpace:cg]; CGColorSpaceRelease(cg);
  CGFloat values[4]; [[color colorUsingColorSpace:lab] getComponents:values];
  values[0] *= 1 + change;
  return [NSColor colorWithColorSpace:lab components:values count:4];
}
NSGradient* ToolbarGradient(BOOL active) {
  // BrowserThemeProvider cached these gradients in Chromium 7. The port uses
  // its default theme, so active/inactive gradients can be retained directly.
  static NSGradient* gradients[2];
  NSUInteger index = active ? 1 : 0;
  if (gradients[index]) return gradients[index];
  NSColor* base = [NSColor colorWithCalibratedWhite:.2 alpha:1];
  NSColor* white = [NSColor whiteColor];
  NSArray* colors = @[[AdjustLuminance(base, .25) blendedColorWithFraction:.9 ofColor:white],
    [base blendedColorWithFraction:.8 ofColor:white],
    AdjustLuminance([base blendedColorWithFraction:.7 ofColor:white], -.02),
    AdjustLuminance([base blendedColorWithFraction:.8 ofColor:white], -.01)];
  NSMutableArray* stops = [NSMutableArray array];
  for (NSColor* __strong color in colors) {
    if (!active) {
      CGFloat whitePoint[3] = {.95047, 1, 1.08883}, black[3] = {0, 0, 0}, range[4] = {-127, 127, -127, 127};
      CGColorSpaceRef cg = CGColorSpaceCreateLab(whitePoint, black, range);
      NSColorSpace* lab = [[NSColorSpace alloc] initWithCGColorSpace:cg]; CGColorSpaceRelease(cg);
      CGFloat values[4]; [[color colorUsingColorSpace:lab] getComponents:values];
      values[0] *= 1 + .3 * (1 - values[0] / 100); values[1] *= .3; values[2] *= .3;
      color = [NSColor colorWithColorSpace:lab components:values count:4];
    }
    [stops addObject:color];
  }
  gradients[index] = [[NSGradient alloc] initWithColorsAndLocations:[stops objectAtIndex:0], 0.0,
    [stops objectAtIndex:1], .25, [stops objectAtIndex:2], .5, [stops objectAtIndex:3], .75, nil];
  return gradients[index];
}
}

NSGradient* Cocoa2010ToolbarGradient(BOOL active) { return ToolbarGradient(active); }

// The modern content host otherwise blocks the portion of the native strip
// overlapping its content rectangle. The standalone preview has no such host.
@interface NSView (Cocoa2010WindowMoveRegions)
- (void)setWindowDragTopInset:(CGFloat)inset;
@end

@interface Cocoa2010BackgroundView : NSView
@property(nonatomic) BOOL hideDivider;
@end
@implementation Cocoa2010BackgroundView
- (BOOL)mouseDownCanMoveWindow { return YES; }
- (void)drawRect:(NSRect)dirtyRect {
  [NSGraphicsContext saveGraphicsState];
  // Leave the native frame's rounded upper corners visible.
  CGFloat w = NSWidth(self.bounds), h = NSHeight(self.bounds);
  CGFloat toolbarHeight = self.hideDivider ? 32 : 35;
  NSBezierPath* clip = [NSBezierPath bezierPath];
  [clip moveToPoint:NSMakePoint(0, 0)]; [clip lineToPoint:NSMakePoint(w, 0)];
  [clip lineToPoint:NSMakePoint(w, h - 5)];
  [clip curveToPoint:NSMakePoint(w - 5, h) controlPoint1:NSMakePoint(w, h - 2) controlPoint2:NSMakePoint(w - 2, h)];
  [clip lineToPoint:NSMakePoint(5, h)];
  [clip curveToPoint:NSMakePoint(0, h - 5) controlPoint1:NSMakePoint(2, h) controlPoint2:NSMakePoint(0, h - 2)];
  [clip closePath];
  [clip addClip];
  // Keep the original NSThemeFrame traffic lights outside our compositor
  // layer. Snow Leopard does not refresh their active appearance in CA layers.
  // Intersect this cutout with the rounded clip separately. Appending the
  // reversed rectangle to that path also fills its part outside the curved
  // upper-left corner under the nonzero winding rule.
  NSBezierPath* lightsClip = [NSBezierPath bezierPathWithRect:self.bounds];
  NSBezierPath* lights = [NSBezierPath bezierPathWithRect:NSMakeRect(0, h - 22, 64, 22)];
  [lightsClip appendBezierPath:[lights bezierPathByReversingPath]];
  [lightsClip addClip];
  // AppKit's default textured-window pattern spans the whole window.
  // Backing-layer drawing has a local origin, unlike the original unlayered
  // TabView context. Offset the pattern by this view's window origin.
  [[NSGraphicsContext currentContext] setPatternPhase:
      NSMakePoint(0, -[self convertPoint:NSZeroPoint toView:nil].y)];
  [self.window.backgroundColor set];
  NSRectFill(self.bounds);
  // Original TabStripView bottom border and bezel; the selected tab paints
  // across these two rows to join seamlessly to the toolbar.
  [[NSColor colorWithCalibratedWhite:0 alpha:.2] set];
  NSRectFillUsingOperation(NSMakeRect(0, toolbarHeight + 1, w, 1), NSCompositeSourceOver);
  [[NSColor colorWithCalibratedRed:247.0/255 green:247.0/255 blue:247.0/255 alpha:1] set];
  NSRectFillUsingOperation(NSMakeRect(0, toolbarHeight, w, 1), NSCompositeSourceOver);
  [[NSBezierPath bezierPathWithRect:NSMakeRect(0, 0, w, toolbarHeight)] addClip];
  // BackgroundGradientView's window-relative gradient, spanning 100 points.
  NSGradient* gradient = ToolbarGradient(self.window.isKeyWindow);
  NSPoint start = [self convertPoint:NSMakePoint(0, NSHeight(self.window.frame) - 12) fromView:nil];
  NSPoint end = [self convertPoint:NSMakePoint(0, NSHeight(self.window.frame) - 112) fromView:nil];
  [gradient drawFromPoint:start toPoint:end
                 options:NSGradientDrawsBeforeStartingLocation | NSGradientDrawsAfterEndingLocation];
  CGFloat stroke = (self.window.isKeyWindow ? 103.0 : 123.0) / 255;
  [[NSColor colorWithCalibratedRed:stroke green:stroke blue:stroke alpha:1] set];
  if (!self.hideDivider) NSRectFill(NSMakeRect(0, 0, NSWidth(self.bounds), 1));
  [NSGraphicsContext restoreGraphicsState];
}
@end

@interface Cocoa2010GradientButtonCell : NSButtonCell
@end
@implementation Cocoa2010GradientButtonCell
- (void)drawWithFrame:(NSRect)frame inView:(NSView*)view {
  // Original GradientButtonCell default flat-button treatment: a subtle
  // rounded border and inner highlight when hovering or pressed.
  if (self.isHighlighted || self.showsBorderOnlyWhileMouseInside == NO) {
    NSRect inset = NSInsetRect(frame, 2.5, 2.5);
    NSBezierPath* path = [NSBezierPath bezierPathWithRoundedRect:inset xRadius:3 yRadius:3];
    NSGradient* gradient = [[NSGradient alloc]
        initWithStartingColor:[NSColor colorWithCalibratedWhite:self.isHighlighted ? .64 : 1 alpha:.35]
                  endingColor:[NSColor colorWithCalibratedWhite:self.isHighlighted ? .85 : 1 alpha:.0]];
    [gradient drawInBezierPath:path angle:90];
    [[NSColor colorWithCalibratedWhite:0 alpha:.25] setStroke];
    [path stroke];
  }
  [self drawInteriorWithFrame:frame inView:view];
}
@end

@interface Cocoa2010Button : NSButton
@end
@implementation Cocoa2010Button
+ (Class)cellClass { return [Cocoa2010GradientButtonCell class]; }
- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }
- (void)updateTrackingAreas {
  for (NSTrackingArea* area in [self.trackingAreas copy]) [self removeTrackingArea:area];
  [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.bounds
      options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInActiveApp | NSTrackingInVisibleRect
      owner:self userInfo:nil]];
  [super updateTrackingAreas];
}
- (void)mouseEntered:(NSEvent*)event { ((NSButtonCell*)self.cell).showsBorderOnlyWhileMouseInside = NO; self.needsDisplay = YES; }
- (void)mouseExited:(NSEvent*)event { ((NSButtonCell*)self.cell).showsBorderOnlyWhileMouseInside = YES; self.needsDisplay = YES; }
@end

// Adapted from Chromium 7 HoverCloseButton and MolokoCacao (2008).
// See upstream/third_party/molokocacao/LICENSE for its BSD notice.
// Chromium 7 ImageDecoration::GetDrawRectInFrame/DrawInFrame. Use the
// artwork's natural dimensions; NSButtonCell adds image insets and scaling.
@interface Cocoa2010DecorationButton : NSButton
@end
@implementation Cocoa2010DecorationButton
- (void)drawRect:(NSRect)dirty {
  NSImage* image = self.image;
  if (!image) return;
  CGFloat xInset = std::floor((NSWidth(self.bounds) - image.size.width) / 2);
  CGFloat yInset = std::floor((NSHeight(self.bounds) - image.size.height) / 2);
  [image drawInRect:NSInsetRect(self.bounds, xInset, yInset) fromRect:NSZeroRect
         operation:NSCompositeSourceOver fraction:1 respectFlipped:YES hints:nil];
}
@end

@interface Cocoa2010NewTabButton : Cocoa2010Button
@property(nonatomic, strong) NSImage* normalImage;
@property(nonatomic, strong) NSImage* hoverImage;
@property(nonatomic, strong) NSImage* pressedImage;
@end
@implementation Cocoa2010NewTabButton
- (NSBezierPath*)pathForButton {
  // Chromium 7 NewTabButton's original 40x27-frame click mask.
  static NSBezierPath* path;
  if (!path) {
    path = [NSBezierPath bezierPath];
    [path moveToPoint:NSMakePoint(9, 7)];
    [path lineToPoint:NSMakePoint(26, 7)];
    [path lineToPoint:NSMakePoint(33, 23)];
    [path lineToPoint:NSMakePoint(14, 23)];
    [path closePath];
  }
  return path;
}
- (BOOL)pointIsOverButton:(NSPoint)point {
  return [[self pathForButton] containsPoint:[self convertPoint:point fromView:self.superview]];
}
- (NSView*)hitTest:(NSPoint)point {
  return [self pointIsOverButton:point] ? [super hitTest:point] : nil;
}
- (void)drawRect:(NSRect)dirtyRect {
  NSImage* image = self.cell.isHighlighted ? self.pressedImage :
      (((NSButtonCell*)self.cell).showsBorderOnlyWhileMouseInside ? self.normalImage : self.hoverImage);
  // Chromium 7 uses NSButtonCell's image placement. On 10.6 it aligns the
  // original 30x26 PDF at (5,1) in this 40x27 hit target; arithmetic centering
  // puts it at y=0.5 and filters the one-pixel edges across two rows.
  NSRect imageRect = [self.cell imageRectForBounds:self.bounds];
  [image drawInRect:imageRect fromRect:NSZeroRect operation:NSCompositeSourceOver
      fraction:1 respectFlipped:YES hints:nil];
}
@end

@interface Cocoa2010CloseButton : Cocoa2010Button
@end
@implementation Cocoa2010CloseButton
- (void)drawRect:(NSRect)rect {
  NSPoint center = NSMakePoint(NSMidX(self.bounds), NSMidY(self.bounds));
  BOOL hover = !((NSButtonCell*)self.cell).showsBorderOnlyWhileMouseInside;
  BOOL pressed = self.cell.isHighlighted;
  if (hover || pressed) {
    NSBezierPath* circle = [NSBezierPath bezierPath];
    [circle appendBezierPathWithArcWithCenter:center radius:.415 * NSWidth(self.bounds)
                                 startAngle:0 endAngle:365];
    [[NSColor colorWithCalibratedWhite:pressed ? .396 : .565 alpha:1] set];
    [circle fill];
  }
  NSBezierPath* cross = [NSBezierPath bezierPath];
  [cross appendBezierPathWithRect:NSMakeRect(3.5, 7, 9, 2)];
  [cross appendBezierPathWithRect:NSMakeRect(7, 3.5, 2, 9)];
  NSPoint pathCenter = NSMakePoint(NSMidX(cross.bounds), NSMidY(cross.bounds));
  NSAffineTransform* transform = [NSAffineTransform transform];
  [transform translateXBy:center.x yBy:center.y]; [transform rotateByDegrees:45];
  [transform translateXBy:-pathCenter.x yBy:-pathCenter.y]; [cross transformUsingAffineTransform:transform];
  [[NSColor whiteColor] set]; [cross fill];
  NSShadow* shadow = [[NSShadow alloc] init];
  shadow.shadowColor = [NSColor colorWithCalibratedWhite:.15 alpha:hover || pressed ? .1 : .75];
  shadow.shadowOffset = NSZeroSize; shadow.shadowBlurRadius = 2.5;
  // Original fillWithInnerShadow algorithm, retained without category symbols.
  [NSGraphicsContext saveGraphicsState];
  NSRect bounds = NSInsetRect(cross.bounds, -2.5, -2.5);
  shadow.shadowOffset = NSMakeSize(0, bounds.size.height);
  NSAffineTransform* shift = [NSAffineTransform transform];
  [shift translateXBy:0 yBy:NSGraphicsContext.currentContext.isFlipped ? bounds.size.height : -bounds.size.height];
  NSBezierPath* drawingPath = [NSBezierPath bezierPathWithRect:bounds];
  drawingPath.windingRule = NSEvenOddWindingRule;
  [drawingPath appendBezierPath:cross]; [drawingPath transformUsingAffineTransform:shift];
  [cross addClip]; [shadow set]; [[NSColor blackColor] set]; [drawingPath fill];
  [NSGraphicsContext restoreGraphicsState];
}
@end

@interface Cocoa2010TabView () {
  NSTimeInterval _hoverStart;
  NSPoint _hoverPoint;
  NSTimeInterval _hoverHoldEnd;
  BOOL _hoverInside;
  BOOL _invalidated;
  NSUInteger _animationFrame;
}
- (BOOL)needsHoverAnimation;
- (void)redisplayHover;
- (void)animateHover;
@end
@implementation Cocoa2010TabView
- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    _closeButton = [[Cocoa2010CloseButton alloc] initWithFrame:NSMakeRect(0, 5, 16, 16)];
    _closeButton.bordered = NO; _closeButton.imagePosition = NSImageOnly;
    _closeButton.imageScaling = NSImageScaleProportionallyDown;
    _closeButton.title = @"";
    ((NSButtonCell*)_closeButton.cell).showsBorderOnlyWhileMouseInside = YES;
    _closeButton.target = self;
    _closeButton.action = @selector(close:);

    [self addSubview:_closeButton];
  }
  return self;
}
- (void)dealloc { [NSObject cancelPreviousPerformRequestsWithTarget:self]; }
- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (void)setData:(Cocoa2010TabData*)data {
  BOOL loadingChanged = !_data || _data.loading != data.loading;
  BOOL changed = !_data || _data.selected != data.selected || _data.pinned != data.pinned ||
                 _data.loading != data.loading || _data.waiting != data.waiting ||
                 ![_data.title isEqualToString:data.title] || _data.icon != data.icon;
  _data = data;
  self.toolTip = data.title;
  self.closeButton.hidden = data.pinned || (!data.selected && NSWidth(self.bounds) < 64);
  SetFrameIfChanged(self.closeButton, NSMakeRect(NSWidth(self.bounds) - 29, 5, 16, 16));
  if (loadingChanged) {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(advanceThrobber) object:nil];
    _animationFrame = 0;
    if (data.loading) [self performSelector:@selector(advanceThrobber) withObject:nil afterDelay:.03];
  }
  if (changed) self.needsDisplay = YES;
}
// Chromium 7 ThrobberFilmstripDelegate: square frames across the image, 30ms.
- (void)advanceThrobber {
  if (!self.data.loading || !self.window) return;
  ++_animationFrame;
  [self setNeedsDisplayInRect:NSMakeRect(18, 5, 16, 16)];
  [self performSelector:@selector(advanceThrobber) withObject:nil afterDelay:.03];
}
- (void)setFrame:(NSRect)frame {
  [super setFrame:frame];
  SetFrameIfChanged(self.closeButton, NSMakeRect(NSWidth(frame) - 29, 5, 16, 16));
  self.closeButton.hidden = self.data.pinned || (!self.data.selected && NSWidth(frame) < 64);
}
// TabView::adjustGlowValue's original show/hold/hide timing. A shared strip
// timer advances every fading tab together, without a drifting delayed chain.
- (void)redisplayHover {
  if (self.data.selected) return;
  // Invalidate the existing AppKit backing layer directly. On 10.6 marking
  // this translucent NSView dirty also repaints NSThemeFrame underneath it,
  // synchronizing the window backing store on every glow frame. The layer's
  // AppKit delegate still calls the original drawRect:, with transparent tab
  // edges composited above the unchanged frame and toolbar.
  if (self.layer) [self.layer setNeedsDisplay];
  else self.needsDisplay = YES;
}
- (BOOL)needsHoverAnimation {
  return !self.dragging && self.window &&
      (_hoverInside ? self.hoverAlpha < 1 : self.hoverAlpha > 0);
}
- (void)animateHover {
  if (self.dragging) return;
  NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
  NSTimeInterval elapsed = now - _hoverStart; _hoverStart = now;
  if (_hoverInside) self.hoverAlpha = MIN(self.hoverAlpha + elapsed/.2, 1);
  else if (now >= _hoverHoldEnd) self.hoverAlpha = MAX(self.hoverAlpha - elapsed/.4, 0);
  [self redisplayHover];
}
- (void)mouseEntered:(NSEvent*)event {
  if (event) _hoverPoint = [self convertPoint:event.locationInWindow fromView:nil];
  _hoverStart = [NSDate timeIntervalSinceReferenceDate]; _hoverInside = YES;
  [self animateHover];
}
- (void)mouseMoved:(NSEvent*)event {
  NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
  if (NSEqualPoints(_hoverPoint, point)) return;
  _hoverPoint = point;
  [self redisplayHover];
}
- (void)mouseExited:(NSEvent*)event {
  _hoverStart = [NSDate timeIntervalSinceReferenceDate]; _hoverHoldEnd = _hoverStart + .02; _hoverInside = NO;
  [self animateHover];
}
- (NSView*)hitTest:(NSPoint)point {
  NSPoint local = [self convertPoint:point fromView:self.superview];
  if (!self.closeButton.hidden && NSPointInRect(local, self.closeButton.frame)) return self.closeButton;
  return NSPointInRect(point, NSInsetRect(self.frame, NSHeight(self.frame) / 3, 0)) ? self : nil;
}
- (void)close:(id)sender { [self.browserDelegate closeTab:self.data.identity]; }
- (void)rightMouseDown:(NSEvent*)event {
  [self.browserDelegate showContextMenuForTab:self.data.identity
      atScreenPoint:[self.window convertBaseToScreen:event.locationInWindow]];
}
- (void)otherMouseUp:(NSEvent*)event { if (event.buttonNumber == 2) [self close:nil]; }
- (void)mouseDown:(NSEvent*)event {
  __attribute__((objc_precise_lifetime)) Cocoa2010TabView* keepAlive = self;
  (void)keepAlive;
  id<Cocoa2010BrowserDelegate> delegate = self.browserDelegate;
  uintptr_t identity = self.data.identity;
  // Chromium 7 selects and raises the tab before capturing its drag frame.
  // Setting dragging first would suppress the selection's stacking update.
  [delegate activateTab:identity];
  self.dragging = YES;
  Cocoa2010WindowController* dragController = self.stripController;
  NSPoint start = [self.window convertBaseToScreen:event.locationInWindow];
  NSRect original = self.frame;
  BOOL dragged = NO;
  // Present the new stacking order before the nested loop waits for mouse up.
  [self.window displayIfNeeded];
  [CATransaction flush];
  for (;;) {
    NSEvent* next = [self.window nextEventMatchingMask:NSLeftMouseDraggedMask | NSLeftMouseUpMask
        untilDate:[NSDate distantFuture] inMode:NSEventTrackingRunLoopMode dequeue:YES];
    if (!next) break;
    NSPoint current = [self.window convertBaseToScreen:next.locationInWindow];
    CGFloat dx = current.x - start.x, dy = current.y - start.y;
    if (!dragged && std::hypot(dx, dy) > 4) {
      dragged = YES;
      [dragController beginDraggingTab:self];
    }
    if (next.type == NSLeftMouseUp) {
      if (dragged) {
        if (fabs(dy) < kTearDistance) {
          NSRect rect = original; rect.origin.x += dx;
          [dragController updateDraggingTab:self frame:rect];
        }
        [delegate dropTab:identity atScreenPoint:current];
      }
      break;
    }
    if (dragged && fabs(dy) < kTearDistance) {
      NSRect rect = original; rect.origin.x += dx;
      [dragController updateDraggingTab:self frame:rect];
    }
  }
  self.dragging = NO;
  [dragController endDraggingTab];
  [[NSNotificationCenter defaultCenter] postNotificationName:@"Cocoa2010DragEnded" object:self.window];
}
- (void)drawRect:(NSRect)dirtyRect {
  NSBezierPath* path = [self bezierPathForRect:self.bounds];
  BOOL selected = self.data.selected;
  [NSGraphicsContext saveGraphicsState];
  [[NSGraphicsContext currentContext] setPatternPhase:
      NSMakePoint(0, -[self convertPoint:NSZeroPoint toView:nil].y)];
  [path addClip];
  if (selected) {
    NSPoint start = [self convertPoint:NSMakePoint(0, NSHeight(self.window.frame) - 12) fromView:nil];
    NSPoint end = [self convertPoint:NSMakePoint(0, NSHeight(self.window.frame) - 112) fromView:nil];
    [ToolbarGradient(self.window.isKeyWindow) drawFromPoint:start toPoint:end
        options:NSGradientDrawsBeforeStartingLocation | NSGradientDrawsAfterEndingLocation];
  } else {
    [[self.window backgroundColor] set]; [path fill];
    [[NSColor colorWithCalibratedWhite:1 alpha:.3] set]; [path fill];
    // Chromium 7 TabView's selected-background overlay and cursor-following
    // radial glow, with its original alpha and radius calculations.
    if (self.hoverAlpha > 0) {
      [NSGraphicsContext saveGraphicsState];
      CGContextRef context = (CGContextRef)NSGraphicsContext.currentContext.graphicsPort;
      CGContextBeginTransparencyLayer(context, nullptr);
      CGContextSetAlpha(context, .5 * self.hoverAlpha);
      NSPoint start = [self convertPoint:NSMakePoint(0, NSHeight(self.window.frame) - 12) fromView:nil];
      NSPoint end = [self convertPoint:NSMakePoint(0, NSHeight(self.window.frame) - 112) fromView:nil];
      [ToolbarGradient(self.window.isKeyWindow) drawFromPoint:start toPoint:end
          options:NSGradientDrawsBeforeStartingLocation | NSGradientDrawsAfterEndingLocation];
      NSGradient* glow = [[NSGradient alloc] initWithStartingColor:
          [NSColor colorWithCalibratedWhite:1 alpha:self.hoverAlpha]
          endingColor:[NSColor colorWithCalibratedWhite:1 alpha:0]];
      NSPoint point = _hoverPoint; point.y = NSHeight(self.bounds);
      [glow drawFromCenter:point radius:0 toCenter:point radius:NSWidth(self.bounds)/3
          options:NSGradientDrawsBeforeStartingLocation];
      [glow drawInBezierPath:path relativeCenterPosition:_hoverPoint];
      CGContextEndTransparencyLayer(context);
      [NSGraphicsContext restoreGraphicsState];
    }
  }
  // The original TabView clips both inner highlight strokes to the tab
  // silhouette. Letting a translated stroke escape the clip leaves a spur
  // where the curve meets the tabstrip's horizontal border.
  if (selected) {
    NSBezierPath* highlight = [path copy];
    highlight.lineWidth = 1;
    NSAffineTransform* transform = [NSAffineTransform transform];
    [transform translateXBy:1 yBy:-1]; [highlight transformUsingAffineTransform:transform];
    [[NSColor colorWithCalibratedRed:247.0/255 green:247.0/255 blue:247.0/255 alpha:1] setStroke]; [highlight stroke];
    transform = [NSAffineTransform transform];
    [transform translateXBy:-2 yBy:0]; [highlight transformUsingAffineTransform:transform];
    [highlight stroke];
  }
  [NSGraphicsContext restoreGraphicsState];
  path.lineWidth = 1;
  [[NSColor colorWithDeviceWhite:0 alpha:selected && (self.window.isKeyWindow || self.window.isMainWindow) ? .3 : .2] setStroke];
  [path stroke];
  if (!selected) {
    [NSGraphicsContext saveGraphicsState]; [path addClip];
    [[NSColor colorWithDeviceWhite:0 alpha:.2] set];
    NSRectFillUsingOperation(NSMakeRect(0, 1, NSWidth(self.bounds), 1), NSCompositeSourceOver);
    [[NSColor colorWithCalibratedRed:247.0/255 green:247.0/255 blue:247.0/255 alpha:1] set];
    NSRectFillUsingOperation(NSMakeRect(0, 0, NSWidth(self.bounds), 1), NSCompositeSourceOver);
    [NSGraphicsContext restoreGraphicsState];
  }
  if (self.data.loading && self.throbberImage.size.height > 0) {
    CGFloat size = self.throbberImage.size.height;
    NSUInteger frames = MAX(1, (NSUInteger)(self.throbberImage.size.width / size));
    [self.throbberImage drawInRect:NSMakeRect(18, 5, 16, 16)
        fromRect:NSMakeRect((_animationFrame % frames) * size, 0, size, size)
        operation:NSCompositeSourceOver fraction:1];
  }
  if (!self.data.loading && self.data.icon)
    [self.data.icon drawInRect:NSMakeRect(18, 5, 16, 16) fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1];
  if (!self.data.pinned && NSWidth(self.bounds) >= 80) {
    NSFont* font = [NSFont fontWithName:@"Lucida Grande" size:11] ?: [NSFont systemFontOfSize:11];
    NSMutableParagraphStyle* paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.lineBreakMode = NSLineBreakByTruncatingTail;
    NSDictionary* attributes = @{NSFontAttributeName:font, NSForegroundColorAttributeName:[NSColor blackColor],
                                 NSParagraphStyleAttributeName:paragraph};
    CGFloat textWidth = NSWidth(self.bounds) - (self.closeButton.hidden ? 49 : 63);
    [self.data.title drawInRect:NSMakeRect(36, 6, MAX(0, textWidth - 2), 14) withAttributes:attributes];
  }
}

- (NSBezierPath*)bezierPathForRect:(NSRect)rect {
  // Outset by 0.5 in order to draw on pixels rather than on borders (which
  // would cause blurry pixels). Subtract 1px of height to compensate, otherwise
  // clipping will occur.
  rect = NSInsetRect(rect, -0.5, -0.5);
  rect.size.height -= 1.0;

  NSPoint bottomLeft = NSMakePoint(NSMinX(rect), NSMinY(rect) + 2);
  NSPoint bottomRight = NSMakePoint(NSMaxX(rect), NSMinY(rect) + 2);
  NSPoint topRight =
      NSMakePoint(NSMaxX(rect) - kInsetMultiplier * NSHeight(rect),
                  NSMaxY(rect));
  NSPoint topLeft =
      NSMakePoint(NSMinX(rect)  + kInsetMultiplier * NSHeight(rect),
                  NSMaxY(rect));

  CGFloat baseControlPointOutset = NSHeight(rect) * kControlPoint1Multiplier;
  CGFloat bottomControlPointInset = NSHeight(rect) * kControlPoint2Multiplier;

  // Outset many of these values by 1 to cause the fill to bleed outside the
  // clip area.
  NSBezierPath* path = [NSBezierPath bezierPath];
  [path moveToPoint:NSMakePoint(bottomLeft.x - 1, bottomLeft.y - 2)];
  [path lineToPoint:NSMakePoint(bottomLeft.x - 1, bottomLeft.y)];
  [path lineToPoint:bottomLeft];
  [path curveToPoint:topLeft
       controlPoint1:NSMakePoint(bottomLeft.x + baseControlPointOutset,
                                 bottomLeft.y)
       controlPoint2:NSMakePoint(topLeft.x - bottomControlPointInset,
                                 topLeft.y)];
  [path lineToPoint:topRight];
  [path curveToPoint:bottomRight
       controlPoint1:NSMakePoint(topRight.x + bottomControlPointInset,
                                 topRight.y)
       controlPoint2:NSMakePoint(bottomRight.x - baseControlPointOutset,
                                 bottomRight.y)];
  [path lineToPoint:NSMakePoint(bottomRight.x + 1, bottomRight.y)];
  [path lineToPoint:NSMakePoint(bottomRight.x + 1, bottomRight.y - 2)];
  return path;
}

@end

@interface Cocoa2010WindowController () {
  NSWindow* __unsafe_unretained _window;
  id<Cocoa2010BrowserDelegate> __unsafe_unretained _delegate;
  NSString* _resources;
  Cocoa2010BackgroundView* _rootView;
  NSView* _tabStripView;
  NSTrackingArea* _tabTrackingArea;
  Cocoa2010TabView* _hoveredTab;
  NSTimer* _hoverTimer;
  NSMutableSet<Cocoa2010TabView*>* _hoverAnimatingTabs;
  NSMutableDictionary<NSValue*, Cocoa2010FrameAnimation*>* _frameAnimations;
  Cocoa2010AutocompleteField* _field;
  NSMutableDictionary<NSNumber*, Cocoa2010TabView*>* _views;
  NSArray<Cocoa2010TabData*>* _tabs;
  Cocoa2010Button* _back;
  Cocoa2010Button* _forward;
  Cocoa2010Button* _reload;
  Cocoa2010Button* _home;
  Cocoa2010Button* _tools;
  NSButton* _star;
  NSButton* _location;
  NSButton* _newTab;
  NSArray<NSButton*>* _windowButtons;
  NSString* _url;
  NSString* _locationIcon;
  BOOL _editing;
  BOOL _syncing;
  BOOL _valid;
  CGFloat _rapidWidth;
  NSMutableDictionary<NSNumber*, NSValue*>* _targetFrames;
  Cocoa2010TabView* __unsafe_unretained _draggedTab;
  NSMutableDictionary<NSNumber*, NSValue*>* _dragTargetFrames;
  NSInteger _dragInsertionIndex;
}
@end
@implementation Cocoa2010WindowController
@synthesize rootView = _rootView, field = _field, editing = _editing;
- (Cocoa2010Button*)button:(NSString*)name command:(NSInteger)command tooltip:(NSString*)tooltip {
  Cocoa2010Button* button = [[Cocoa2010Button alloc] initWithFrame:NSMakeRect(0, 3, 29, 29)];
  button.cell = [[Cocoa2010GradientButtonCell alloc] initTextCell:@""];
  button.imagePosition = NSImageOnly; button.imageScaling = NSImageScaleProportionallyDown;
  button.title = @""; button.image = Image(_resources, name); button.bordered = NO;
  ((NSButtonCell*)button.cell).showsBorderOnlyWhileMouseInside = YES;
  button.tag = command; button.target = self; button.action = @selector(command:); button.toolTip = tooltip;
 [_rootView addSubview:button];
  return button;
}
- (instancetype)initWithWindow:(NSWindow*)window delegate:(id<Cocoa2010BrowserDelegate>)delegate resources:(NSString*)resources {
  if ((self = [super init])) {
    _valid = YES; _window = window; _delegate = delegate; _resources = resources;
    _views = [[NSMutableDictionary alloc] init];
    _hoverAnimatingTabs = [[NSMutableSet alloc] init];
    _targetFrames = [[NSMutableDictionary alloc] init];
    _frameAnimations = [[NSMutableDictionary alloc] init];
    _tabs = @[];
    _rootView = [[Cocoa2010BackgroundView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(window.frame), cocoa2010::kChromeHeight)];
    _rootView.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    // Chromium 124's content host is layer-backed. A non-layer-backed sibling
    // is painted underneath its compositor on 10.6, even in NSView front order.
    _rootView.wantsLayer = YES;
    // The original tab-strip clips a new tab while it rises from below its
    // lower edge; keep that separate from the toolbar beneath it.
    _tabStripView = [[NSView alloc] initWithFrame:NSMakeRect(0, 35, NSWidth(window.frame), 36)];
    _tabStripView.wantsLayer = YES;
    [_rootView addSubview:_tabStripView];
    // Chromium 7 TabStripController owns one tracking area and dispatches to
    // the hit-tested tab. Individual rectangular areas overlap adjacent tabs.
    _tabTrackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved |
                NSTrackingActiveInActiveApp | NSTrackingInVisibleRect
        owner:self userInfo:nil];
    [_tabStripView addTrackingArea:_tabTrackingArea];
    // TabWindowController attaches top chrome to the frame view, overlapping
    // the native title bar. Retain that arrangement on 10.6 as well as modern macOS.
    [[window.contentView superview] addSubview:_rootView];
    _back = [self button:@"back_Template.pdf" command:IDC_BACK tooltip:@"Back"];
    _forward = [self button:@"forward_Template.pdf" command:IDC_FORWARD tooltip:@"Forward"];
    _reload = [self button:@"reload_Template.pdf" command:IDC_RELOAD tooltip:@"Reload"];
    _home = [self button:@"home_Template.pdf" command:IDC_HOME tooltip:@"Home"];
    _tools = [self button:@"tools_Template.pdf" command:IDC_SHOW_APP_MENU tooltip:@"Customize and control Chromium"];
    _field = [[Cocoa2010AutocompleteField alloc] initWithFrame:NSZeroRect];
    _field.cell = [[Cocoa2010AutocompleteCell alloc] initTextCell:@""];
    _field.delegate = self;
    _field.font = [NSFont fontWithName:@"Lucida Grande" size:13] ?: [NSFont systemFontOfSize:13];
    _field.backgroundColor = [NSColor whiteColor]; _field.textColor = [NSColor blackColor];
    _field.allowsEditingTextAttributes = YES;
    // Toolbar.xib archives a bezeled NSTextFieldCell. Its native text insets
    // still apply even though StyledTextFieldCell draws the border itself.
    _field.editable = YES; _field.selectable = YES; _field.bezeled = YES;
    _field.cell.scrollable = YES; _field.cell.wraps = NO; _field.focusRingType = NSFocusRingTypeNone;

    [_rootView addSubview:_field];
    _star = [[Cocoa2010DecorationButton alloc] initWithFrame:NSZeroRect];
    _star.imagePosition = NSImageOnly; _star.imageScaling = NSImageScaleProportionallyDown;
    _star.title = @""; _star.bordered = NO; _star.image = Image(resources, @"star.pdf");
    _star.target = self; _star.tag = IDC_BOOKMARK_THIS_TAB; _star.action = @selector(command:);
    _star.toolTip = @"Bookmark this page"; [_rootView addSubview:_star];
    _location = [[Cocoa2010DecorationButton alloc] initWithFrame:NSZeroRect];
    _location.imagePosition = NSImageOnly; _location.imageScaling = NSImageScaleProportionallyDown;
    _location.title = @""; _location.bordered = NO; _location.image = Image(resources, @"omnibox_http.pdf");
    _location.target = self; _location.action = @selector(pageInfo:); _location.toolTip = @"Site information";
 [_rootView addSubview:_location];
    Cocoa2010NewTabButton* newTab = [[Cocoa2010NewTabButton alloc] initWithFrame:NSZeroRect];
    newTab.normalImage = Image(resources, @"newtab.pdf");
    newTab.hoverImage = Image(resources, @"newtab_h.pdf");
    newTab.pressedImage = Image(resources, @"newtab_p.pdf");
    ((NSButtonCell*)newTab.cell).showsBorderOnlyWhileMouseInside = YES;
    _newTab = newTab;
    _newTab.imagePosition = NSImageOnly; _newTab.imageScaling = NSImageScaleNone;
    _newTab.title = @""; _newTab.image = Image(resources, @"newtab.pdf"); _newTab.bordered = NO;
    _newTab.target = self; _newTab.tag = IDC_NEW_TAB; _newTab.action = @selector(command:);
    _newTab.toolTip = @"New tab"; [_tabStripView addSubview:_newTab];
    // Preserve AppKit's live traffic lights at the historical positions.
    NSMutableArray* buttons = [NSMutableArray array];
    NSWindowButton types[] = {NSWindowCloseButton, NSWindowMiniaturizeButton, NSWindowZoomButton};
    for (int i = 0; i < 3; ++i) {
      NSButton* button = [window standardWindowButton:types[i]];
      button.hidden = NO;
      // Keep AppKit's target/action. On 10.6 performZoom: and its siblings
      // simulate the standard button click; making that the button's action
      // recursively clicks the same button instead of operating the window.
      button.wantsLayer = NO;
      [[window.contentView superview] addSubview:button]; [buttons addObject:button];
    }
    _windowButtons = buttons;
    [window setAutorecalculatesContentBorderThickness:NO forEdge:NSMaxYEdge];
    [window setContentBorderThickness:24 forEdge:NSMaxYEdge];
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    for (NSString* name in @[NSWindowDidResizeNotification, NSWindowDidBecomeKeyNotification,
                            NSWindowDidResignKeyNotification, NSWindowDidBecomeMainNotification,
                            NSWindowDidResignMainNotification, @"Cocoa2010DragEnded"])
      [center addObserver:self selector:@selector(windowChanged:) name:name object:window];
    for (NSString* name in @[NSApplicationDidBecomeActiveNotification, NSApplicationDidResignActiveNotification])
      [center addObserver:self selector:@selector(windowChanged:) name:name object:NSApp];
    [center addObserver:self selector:@selector(selectionChanged:) name:NSTextViewDidChangeSelectionNotification object:nil];
    [self layout];
  }
  return self;
}
- (void)selectionChanged:(NSNotification*)notification {
  if (!_valid || !_editing || _syncing || notification.object != _field.currentEditor) return;
  [_delegate omniboxSelectionChanged:((NSTextView*)notification.object).selectedRange];
}
- (NSString*)omniboxCopyText:(NSString*)text offset:(NSUInteger)offset { return [_delegate omniboxCopyText:text offset:offset]; }
- (NSString*)omniboxPasteText:(NSString*)text { return [_delegate omniboxPasteText:text]; }
- (void)invalidate {
  if (!_valid) return;
  _valid = NO;
  for (Cocoa2010FrameAnimation* animation in _frameAnimations.allValues) [animation stopAnimation];
  [_frameAnimations removeAllObjects];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [_tabStripView removeTrackingArea:_tabTrackingArea];
  _tabTrackingArea = nil; _hoveredTab = nil;
  [_hoverTimer invalidate]; _hoverTimer = nil;
  [_hoverAnimatingTabs removeAllObjects];
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
  _field.delegate = nil;
  for (Cocoa2010TabView* view in _views.allValues) { view.browserDelegate = nil; [NSObject cancelPreviousPerformRequestsWithTarget:view]; }
  if ([_window.contentView respondsToSelector:@selector(setWindowDragTopInset:)])
    [_window.contentView setWindowDragTopInset:0];
  [_rootView removeFromSuperview];
  // NSThemeFrame keeps references to its standard buttons on 10.6. Detaching
  // and releasing them while the frame is still pending display leaves those
  // references dangling in _resetDragMargins during window close.
  _delegate = nil; _window = nil;
}
- (void)dealloc { [self invalidate]; }
- (void)queueHoverAnimation:(Cocoa2010TabView*)tab {
  if (![tab needsHoverAnimation]) return;
  [_hoverAnimatingTabs addObject:tab];
  if (_hoverTimer) return;
  // Keep a fixed cadence and coalesce all dirty tabs into one AppKit display
  // pass. Separate performSelector chains slipped to 50-90ms on Snow Leopard.
  _hoverTimer = [NSTimer timerWithTimeInterval:1.0/60 target:self
      selector:@selector(advanceHover:) userInfo:nil repeats:YES];
  [NSRunLoop.mainRunLoop addTimer:_hoverTimer forMode:NSDefaultRunLoopMode];
  [NSRunLoop.mainRunLoop addTimer:_hoverTimer forMode:NSEventTrackingRunLoopMode];
}
- (void)advanceHover:(NSTimer*)timer {
  for (Cocoa2010TabView* tab in [_hoverAnimatingTabs copy]) {
    if ([tab needsHoverAnimation]) [tab animateHover];
    if (![tab needsHoverAnimation]) [_hoverAnimatingTabs removeObject:tab];
  }
  if (!_hoverAnimatingTabs.count) { [_hoverTimer invalidate]; _hoverTimer = nil; }
}
- (void)mouseMoved:(NSEvent*)event {
  if (!_valid || _draggedTab) return;
  NSPoint point = [_tabStripView.superview convertPoint:event.locationInWindow fromView:nil];
  NSView* target = [_tabStripView hitTest:point];
  Cocoa2010TabView* tab = nil;
  for (NSView* view = target; view && view != _tabStripView; view = view.superview) {
    if ([view isKindOfClass:[Cocoa2010TabView class]]) { tab = (Cocoa2010TabView*)view; break; }
  }
  if (_hoveredTab != tab) {
    [_hoveredTab mouseExited:nil];
    [self queueHoverAnimation:_hoveredTab];
    _hoveredTab = tab;
    [tab mouseEntered:event];
    [self queueHoverAnimation:tab];
  }
  [tab mouseMoved:event];
}
- (void)mouseEntered:(NSEvent*)event {
  if (event.trackingArea == _tabTrackingArea) [self mouseMoved:event];
}
- (void)mouseExited:(NSEvent*)event {
  if (event.trackingArea != _tabTrackingArea) return;
  [_hoveredTab mouseExited:nil];
  [self queueHoverAnimation:_hoveredTab]; _hoveredTab = nil;
}
- (void)tabTrackingAreasChanged:(NSNotification*)notification {
  if (!_valid || !NSApp.isActive || _draggedTab) return;
  // As in TabStripController::tabUpdateTracking, re-hit-test after tabs move
  // beneath a stationary cursor rather than leaving the old owner hovered.
  NSPoint location = [_window mouseLocationOutsideOfEventStream];
  NSEvent* event = [NSEvent mouseEventWithType:NSMouseMoved location:location
      modifierFlags:0 timestamp:0 windowNumber:_window.windowNumber context:nil
      eventNumber:0 clickCount:0 pressure:0];
  [self mouseMoved:event];
}
- (void)windowChanged:(NSNotification*)notification {
  if (!_valid) return;
  [self layout];
  // Repaint every tab and control on window/app activation, including tabs
  // whose title, favicon and selection have not otherwise changed.
  InvalidateAppearance(_rootView);
}
- (void)layout {
  if (!_valid) return;
  // The modern bridge clears the window background and titlebar border during
  // initialization. Restore the historical native textured-window treatment.
  if ([_window contentBorderThicknessForEdge:NSMaxYEdge] != 24)
    [_window setContentBorderThickness:24 forEdge:NSMaxYEdge];
  NSView* frameView = [_window.contentView superview];
  CGFloat width = NSWidth(frameView.bounds), height = NSHeight(frameView.bounds);
  // BookmarkBarController::toolbarHeightCompression returns the original 3pt
  // overlap while its attached bar is showing.
  CGFloat chromeHeight = cocoa2010::kChromeHeight - (_rootView.hideDivider ? 3 : 0);
  NSRect headerFrame = NSMakeRect(0, height - chromeHeight, width, chromeHeight);
  if (!NSEqualRects(_rootView.frame, headerFrame)) _rootView.frame = headerFrame;
  if (_rootView.superview != frameView ||
      [frameView.subviews indexOfObjectIdenticalTo:_rootView] <
      [frameView.subviews indexOfObjectIdenticalTo:_window.contentView]) {
    [_rootView removeFromSuperview];
    [frameView addSubview:_rootView positioned:NSWindowAbove relativeTo:_window.contentView];
  }
  CGFloat x = 8;
  for (NSButton* button in _windowButtons) {
    NSRect frame = button.frame; frame.origin = NSMakePoint(x, height - NSHeight(frame) - 6);
    SetFrameIfChanged(button, frame); x = NSMaxX(frame) + 7;
    if ([frameView.subviews indexOfObjectIdenticalTo:button] <
        [frameView.subviews indexOfObjectIdenticalTo:_rootView]) {
      [button removeFromSuperview];
      [frameView addSubview:button positioned:NSWindowAbove relativeTo:_rootView];
    }
  }
  // Positions from the original Toolbar.xib (35 high, field 27 high).
  SetFrameIfChanged(_back, NSMakeRect(3, 3, 29, 29)); SetFrameIfChanged(_forward, NSMakeRect(31, 3, 29, 29));
  SetFrameIfChanged(_reload, NSMakeRect(59, 3, 29, 29)); SetFrameIfChanged(_home, NSMakeRect(87, 3, 29, 29));
  SetFrameIfChanged(_tools, NSMakeRect(width - 32, 3, 29, 29));
  CGFloat fieldX = _home.hidden ? 91 : 119;
  SetFrameIfChanged(_field, NSMakeRect(fieldX, 4, MAX(100, width - fieldX - 35), 27));
  SetFrameIfChanged(_location, NSMakeRect(NSMinX(_field.frame) + 5, NSMinY(_field.frame), _location.image.size.width, NSHeight(_field.frame)));
  SetFrameIfChanged(_star, NSMakeRect(NSMaxX(_field.frame) - 5 - _star.image.size.width, NSMinY(_field.frame), _star.image.size.width, NSHeight(_field.frame)));
  SetFrameIfChanged(_tabStripView, NSMakeRect(0, _rootView.hideDivider ? 32 : 35, width, 36));
  if ([_window.contentView respondsToSelector:@selector(setWindowDragTopInset:)]) {
    NSRect strip = [_tabStripView convertRect:_tabStripView.bounds toView:_window.contentView];
    [_window.contentView setWindowDragTopInset:
        MAX(0, NSMaxY(_window.contentView.bounds) - NSMinY(strip))];
  }
  DisableContentsAnimation(_rootView); DisableContentsAnimation(_tabStripView); DisableContentsAnimation(_newTab);
  [self layoutTabs:NO];
}
- (void)setFrame:(NSRect)frame forView:(NSView*)view animate:(BOOL)animate {
  NSValue* key = [NSValue valueWithPointer:(__bridge const void*)view];
  Cocoa2010FrameAnimation* old = [_frameAnimations objectForKey:key];
  [old stopAnimation]; [_frameAnimations removeObjectForKey:key];
  DisableContentsAnimation(view);
  if (animate && _window.isVisible && !NSEqualRects(view.frame, frame)) {
    Cocoa2010FrameAnimation* animation = [[Cocoa2010FrameAnimation alloc] initWithView:view target:frame];
    [_frameAnimations setObject:animation forKey:key]; [animation startAnimation];
  } else {
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    view.frame = frame;
    [CATransaction commit];
  }
}
// Adapted from TabStripController's placeholder layout: reserve a gap at the
// dragged tab's left edge and animate the other tabs into their target slots.
- (void)beginDraggingTab:(Cocoa2010TabView*)tab {
  if (!_valid) return;
  for (Cocoa2010FrameAnimation* animation in _frameAnimations.allValues) [animation stopAnimation];
  [_frameAnimations removeAllObjects];
  _draggedTab = tab;
  _dragTargetFrames = [[NSMutableDictionary alloc] init];
  _dragInsertionIndex = 0;
  // On 10.6 raising an attached tab above the final sibling with
  // addSubview:positioned:relativeTo: raises NSRangeException. Sorting
  // changes stacking order while keeping its backing layer attached.
  __attribute__((objc_precise_lifetime)) NSMutableArray* order = [_tabStripView.subviews mutableCopy];
  [order removeObjectIdenticalTo:tab]; [order addObject:tab];
  [_tabStripView sortSubviewsUsingFunction:CompareSubviewOrder context:(__bridge void*)order];
}
- (NSInteger)dragInsertionIndexForTab:(uintptr_t)identity {
  return _draggedTab && _draggedTab.data.identity == identity ? _dragInsertionIndex : -1;
}
- (void)updateDraggingTab:(Cocoa2010TabView*)tab frame:(NSRect)frame {
  if (!_valid || _draggedTab != tab) return;
  NSMutableArray<Cocoa2010TabView*>* others = [NSMutableArray array];
  CGFloat offset = 64;
  NSInteger insertion = 0, pinned = 0;
  BOOL foundGap = NO;
  for (Cocoa2010TabData* data in _tabs) {
    Cocoa2010TabView* other = [_views objectForKey:@(data.identity)];
    if (other == tab) continue;
    [others addObject:other];
    if (data.pinned) ++pinned;
    if (!foundGap && offset + NSWidth(other.frame) / 2 > NSMinX(frame)) foundGap = YES;
    if (!foundGap) ++insertion;
    offset += NSWidth(other.frame) - kTabOverlap;
  }
  insertion = tab.data.pinned ? MIN(insertion, pinned) : MAX(insertion, pinned);
  _dragInsertionIndex = insertion;
  offset = 64;
  for (NSInteger index = 0; index < (NSInteger)others.count; ++index) {
    if (index == insertion) offset += NSWidth(frame) - kTabOverlap;
    Cocoa2010TabView* other = [others objectAtIndex:index];
    NSRect target = NSMakeRect(offset, 0, NSWidth(other.frame), 26);
    NSNumber* key = @(other.data.identity);
    NSValue* previous = [_dragTargetFrames objectForKey:key];
    if (!previous || !NSEqualRects(previous.rectValue, target)) {
      // Only position changes during a drag. Animating frame/bounds on a
      // layer-backed 10.6 view also crossfades its freshly drawn contents.
      DisableContentsAnimation(other);
      [self setFrame:target forView:other animate:YES];
      [_dragTargetFrames setObject:[NSValue valueWithRect:target] forKey:key];
    }
    offset += NSWidth(other.frame) - kTabOverlap;
  }
  [self setFrame:frame forView:tab animate:NO];
  _rootView.needsDisplay = YES;
  // The Chromium run-loop observer is not driven by this AppKit tracking loop.
  // Commit the position and freshly selected artwork before waiting for input.
  [_window displayIfNeeded];
  [CATransaction flush];
}
- (void)endDraggingTab {
  _draggedTab = nil;
  _dragTargetFrames = nil;
  [_targetFrames removeAllObjects];
  [self layoutTabs:YES];
}
- (void)layoutTabs:(BOOL)animate {
  if (!_valid) return;
  for (Cocoa2010TabView* tab in _views.allValues) if (tab.dragging) return;
  CGFloat width = NSWidth(_rootView.bounds), offset = 64;
  NSInteger ordinary = 0, pinned = 0;
  for (Cocoa2010TabData* tab in _tabs) { if (tab.pinned) ++pinned; else ++ordinary; }
  CGFloat available = width - offset - 36 - pinned * (53 - kTabOverlap);
  CGFloat tabWidth = ordinary ? (available + (ordinary - 1) * kTabOverlap) / ordinary : 220;
  tabWidth = MAX(31, MIN(220, tabWidth));
  if (_rapidWidth > 0) tabWidth = MIN(tabWidth, _rapidWidth);
  // Keep the hierarchy stable on title/favicon/loading updates. Removing and
  // reinserting every tab invalidates backing layers and causes drag flicker.
  NSMutableArray* drawOrder = [NSMutableArray array];
  for (Cocoa2010TabData* data in [_tabs reverseObjectEnumerator])
    if (!data.selected) [drawOrder addObject:[_views objectForKey:@(data.identity)]];
  for (Cocoa2010TabData* data in _tabs)
    if (data.selected) [drawOrder addObject:[_views objectForKey:@(data.identity)]];
  [drawOrder addObject:_newTab];
  for (NSView* child in drawOrder)
    if (child.superview != _tabStripView) [_tabStripView addSubview:child];
  // Keep backing layers attached when selection changes the stacking order.
  [_tabStripView sortSubviewsUsingFunction:CompareSubviewOrder context:(__bridge void*)drawOrder];
  for (Cocoa2010TabData* data in _tabs) {
    Cocoa2010TabView* view = [_views objectForKey:@(data.identity)];
    DisableContentsAnimation(view);
    CGFloat w = data.pinned ? 53 : MAX(data.selected ? 46 : 31, tabWidth);
    NSRect frame = NSMakeRect(offset, 0, w, 26);
    NSNumber* key = @(data.identity);
    NSValue* target = [_targetFrames objectForKey:key];
    if (!target || !NSEqualRects(target.rectValue, frame)) {
      if (view.hidden && animate && _window.isVisible)
        [self setFrame:NSOffsetRect(frame, 0, -NSHeight(frame)) forView:view animate:NO];
      view.hidden = NO;
      [self setFrame:frame forView:view animate:animate];
      [_targetFrames setObject:[NSValue valueWithRect:frame] forKey:key];
    }
    view.hidden = offset > width - 20;
    view.closeButton.hidden = data.pinned || (!data.selected && w < 64);
    offset += w - kTabOverlap;
  }
  NSRect buttonFrame = NSMakeRect(MIN(width - 40, offset + 8), 0, 40, 27);
  NSNumber* buttonKey = @0;
  NSValue* buttonTarget = [_targetFrames objectForKey:buttonKey];
  if (!buttonTarget || !NSEqualRects(buttonTarget.rectValue, buttonFrame)) {
    [self setFrame:buttonFrame forView:_newTab animate:animate];
    [_targetFrames setObject:[NSValue valueWithRect:buttonFrame] forKey:buttonKey];
  }
}
- (void)updateTabs:(NSArray<Cocoa2010TabData*>*)tabs animate:(BOOL)animate {
  if (!_valid) return;
  NSMutableSet* keep = [NSMutableSet set];
  BOOL inserted = NO;
  for (Cocoa2010TabData* data in tabs) {
    NSNumber* key = @(data.identity); [keep addObject:key];
    Cocoa2010TabView* view = [_views objectForKey:key];
    if (!view) {
      inserted = YES;
      view = [[Cocoa2010TabView alloc] initWithFrame:NSMakeRect(70, 30, 160, 26)];
      view.browserDelegate = _delegate;
      view.stripController = self;
      view.hidden = YES;
      [[NSNotificationCenter defaultCenter] addObserver:self
          selector:@selector(tabTrackingAreasChanged:)
          name:NSViewDidUpdateTrackingAreasNotification object:view];
      [_views setObject:view forKey:key];
    }
    view.throbberImage = Image(_resources, data.waiting ? @"throbber_waiting.png" : @"throbber.png");
    view.data = data;
  }
  for (NSNumber* key in [_views.allKeys copy]) {
    if (![keep containsObject:key]) {
      Cocoa2010TabView* view = [_views objectForKey:key];
      [[NSNotificationCenter defaultCenter] removeObserver:self
          name:NSViewDidUpdateTrackingAreasNotification object:view];
      if (_hoveredTab == view) { [view mouseExited:nil]; _hoveredTab = nil; }
      [_hoverAnimatingTabs removeObject:view];
      view.browserDelegate = nil; [NSObject cancelPreviousPerformRequestsWithTarget:view];
      NSValue* animationKey = [NSValue valueWithPointer:(__bridge const void*)view];
      [[_frameAnimations objectForKey:animationKey] stopAnimation];
      [_frameAnimations removeObjectForKey:animationKey];
      [_targetFrames removeObjectForKey:key];
      [view removeFromSuperview]; [_views removeObjectForKey:key];
    }
  }
  _tabs = [tabs copy];
  [self layoutTabs:animate || (inserted && _views.count > 1 && _window.isVisible)];
}
- (void)updateURL:(NSString*)url loading:(BOOL)loading starred:(BOOL)starred secure:(BOOL)secure showHome:(BOOL)showHome {
  if (_home.hidden == showHome) { _home.hidden = !showHome; [self layout]; }
  if (!_valid) return;
  _url = [url copy];
  if (!_editing && ![_field.stringValue isEqualToString:url ?: @""]) { _syncing = YES; _field.stringValue = url ?: @""; _syncing = NO; }
  _reload.tag = loading ? IDC_STOP : IDC_RELOAD;
  NSImage* reload = Image(_resources, loading ? @"stop_Template.pdf" : @"reload_Template.pdf");
  if (_reload.image != reload) _reload.image = reload;
  _reload.toolTip = loading ? @"Stop" : @"Reload";
  NSImage* star = Image(_resources, starred ? @"star_lit.pdf" : @"star.pdf");
  if (_star.image != star) _star.image = star;
  if (!_editing) [self updateLocationIcon:secure ? @"omnibox_https_valid.pdf" : @"omnibox_http.pdf"];
  for (NSButton* button in @[_back, _forward, _reload, _home, _star]) button.enabled = [_delegate isCommandEnabled:button.tag];
}
- (void)updateLocationIcon:(NSString*)name {
  if (!_valid || [_locationIcon isEqualToString:name]) return;
  _location.image = Image(_resources, name);
  _locationIcon = [name copy];
}
- (void)focusLocation {
  if (!_valid) return;
  [_window makeFirstResponder:_field];
  [_field selectText:nil];
}
- (NSRect)omniboxScreenRect {
  NSRect rect = [_field convertRect:_field.bounds toView:nil];
  rect.origin = [_window convertBaseToScreen:rect.origin];
  return rect;
}
// Chromium 7 EmphasizeURLComponents updates editor attributes in place,
// preserving native selection, undo and marked-text ownership.
- (void)applyOmniboxAttributes:(NSAttributedString*)text {
  NSTextView* editor = (NSTextView*)_field.currentEditor;
  if (editor) {
    if (editor.hasMarkedText || ![editor.string isEqualToString:text.string]) return;
    _syncing = YES;
    [editor.textStorage beginEditing];
    [text enumerateAttributesInRange:NSMakeRange(0, text.length) options:0
        usingBlock:^(NSDictionary* attributes, NSRange range, BOOL* stop) {
          [editor.textStorage setAttributes:attributes range:range];
        }];
    [editor.textStorage endEditing];
    editor.typingAttributes = @{NSFontAttributeName:_field.font,
                               NSForegroundColorAttributeName:[NSColor blackColor]};
    _syncing = NO;
  } else if ([_field.stringValue isEqualToString:text.string] &&
             ![_field.attributedStringValue isEqualToAttributedString:text]) {
    _field.attributedStringValue = text;
  }
}
- (void)updateEditingText:(NSString*)text selection:(NSRange)selection {
  if (!_editing || _syncing) return;
  NSTextView* editor = (NSTextView*)[_field currentEditor];
  if (editor.hasMarkedText) return;
  _syncing = YES;
  if (![editor.string isEqualToString:text]) [_field setStringValue:text ?: @""];
  selection.location = MIN(selection.location, text.length);
  selection.length = MIN(selection.length, text.length - selection.location);
  [editor setSelectedRange:selection];
  _syncing = NO;
}
- (void)controlTextDidBeginEditing:(NSNotification*)notification {
  if (_editing) return;
  _editing = YES;
  [_delegate omniboxBeganEditing];
  [(NSTextView*)[_field currentEditor] setAllowsUndo:YES];
}
- (void)controlTextDidChange:(NSNotification*)notification {
  if (_syncing) return;
  NSTextView* editor = (NSTextView*)[_field currentEditor];
  [_delegate omniboxChanged:_field.stringValue selection:editor.selectedRange composing:editor.hasMarkedText];
}
- (void)controlTextDidEndEditing:(NSNotification*)notification {
  if (!_valid || !_editing) return;
  _editing = NO;
  [_delegate omniboxEndedEditing];
}
- (BOOL)control:(NSControl*)control textView:(NSTextView*)textView doCommandBySelector:(SEL)selector {
  if (textView.hasMarkedText) return NO;
  // Native NSTextView owns text movement, selection, cut/copy/paste, undo,
  // spelling and composition. Only omnibox-specific commands reach Chromium.
  BOOL handled = [_delegate omniboxCommand:selector];
  if (handled && selector == @selector(insertNewline:)) [_window makeFirstResponder:_window.contentView];
  return handled;
}
- (void)command:(NSButton*)sender {
  if (sender.tag == IDC_SHOW_APP_MENU) [self showToolsMenu];
  else [_delegate executeCommand:sender.tag];
}
- (void)pageInfo:(id)sender { [_delegate showPageInfo]; }
- (void)menuCommand:(NSMenuItem*)sender { [_delegate executeCommand:sender.tag]; }
- (BOOL)validateMenuItem:(NSMenuItem*)item { return [_delegate isCommandEnabled:item.tag]; }
- (void)setBookmarkBarVisible:(BOOL)visible {
  if (_rootView.hideDivider != visible) { _rootView.hideDivider = visible; _rootView.needsDisplay = YES; }
}
- (void)showToolsMenu { [_delegate showApplicationMenuFromView:_tools]; }
@end
