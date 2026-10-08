// Copyright (c) 2009-2010 The Chromium Authors. All rights reserved.
// Copyright 2026 Snowium contributors. BSD license.
// Ported from BookmarkBarController, BookmarkBarToolbarView, BookmarkBarView,
// BookmarkButtonCell and the flat-button path of GradientButtonCell.
#import "chrome/browser/ui/cocoa2010/bookmark_bar.h"
#import "chrome/browser/ui/cocoa2010/controls.h"
#include <algorithm>
#include <memory>
#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/bookmarks/bookmark_model_factory.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_navigator.h"
#include "chrome/browser/ui/browser_navigator_params.h"
#include "chrome/browser/ui/bookmarks/bookmark_context_menu_controller.h"
#include "components/bookmarks/browser/base_bookmark_model_observer.h"
#include "components/bookmarks/browser/bookmark_model.h"
#include "components/bookmarks/browser/bookmark_node.h"
#include "components/bookmarks/browser/bookmark_utils.h"
#include "ui/base/cocoa/cocoa_base_utils.h"
#import "ui/base/cocoa/menu_controller.h"
#include "ui/gfx/image/image.h"
#include "ui/gfx/native_widget_types.h"

namespace {
class BookmarkObserver;
constexpr CGFloat kDefaultBookmarkWidth = 150;
constexpr CGFloat kBookmarkHorizontalPadding = 1;
constexpr CGFloat kBookmarkVerticalPadding = 2;
constexpr CGFloat kBookmarkButtonHeight = 28;
NSString* const kBookmarkDragType = @"org.snowium.cocoa2010.bookmark-node";
}

@class Cocoa2010BookmarkBarView;
@interface Cocoa2010BookmarkButtonCell : NSButtonCell
@property(nonatomic) CGFloat hoverAlpha;
@property(nonatomic) BOOL mouseInside;
- (void)setBookmarkCellText:(NSString*)title image:(NSImage*)image;
@end
@implementation Cocoa2010BookmarkButtonCell
// BookmarkButtonCell::configureBookmarkButtonCell, with its original native
// image/text layout, control size, small font and tail truncation.
- (instancetype)initTextCell:(NSString*)string {
  if ((self = [super initTextCell:string])) {
    [self setButtonType:NSMomentaryPushInButton];
    [self setBezelStyle:NSShadowlessSquareBezelStyle];
    [self setShowsBorderOnlyWhileMouseInside:YES];
    [self setAlignment:NSLeftTextAlignment];
    [self setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [self setWraps:NO];
    [self setLineBreakMode:NSLineBreakByTruncatingTail];
  }
  return self;
}
- (NSSize)cellSizeForBounds:(NSRect)rect {
  NSSize size = [super cellSizeForBounds:rect];
  if (self.title.length) size.width += 2;
  size.height += 4;
  return size;
}
- (void)setBookmarkCellText:(NSString*)title image:(NSImage*)image {
  title = [title stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
  title = [title stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
  if (title.length) { self.imagePosition = NSImageLeft; self.controlSize = NSSmallControlSize; }
  else { self.controlSize = NSMiniControlSize; self.imagePosition = NSImageOnly; }
  self.image = image; self.title = title ?: @"";
}
// GradientButtonCell::getDrawParamsForFrame and the default flat-button
// drawBorderAndFill path. Obsolete extension-theme plumbing is replaced by
// the native default colors; NSButtonCell still owns image/title drawing.
- (void)drawWithFrame:(NSRect)frame inView:(NSView*)view {
  NSRect innerFrame = NSInsetRect(frame, 2, 1);
  if (self.isHighlighted || self.mouseInside || self.showsFirstResponder) {
    NSBezierPath* path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(frame, 1.5, 1.5)
                                                     xRadius:3.5 yRadius:3.5];
    CGFloat alpha = self.showsFirstResponder ? 1 : self.hoverAlpha;
    // Flat bookmark cells have the original limited click feedback tag.
    if (!self.isHighlighted) alpha *= .6;
    // gradientForHoverAlpha:isThemed: from the original default-theme path.
    NSGradient* gradient = [[NSGradient alloc] initWithColorsAndLocations:
        [NSColor colorWithCalibratedWhite:1 alpha:.2 + .35 * alpha], alpha * .33,
        [NSColor colorWithCalibratedWhite:1 - .15 * alpha alpha:.333 * alpha], 1.0, nil];
    [NSGraphicsContext saveGraphicsState]; [path addClip];
    if (!self.isHighlighted) {
      path.lineWidth = 2;
      [[NSColor colorWithCalibratedWhite:1 alpha:.2 * alpha] setStroke]; [path stroke];
      NSAffineTransform* transform = [NSAffineTransform transform];
      [transform translateXBy:1 yBy:1];
      NSBezierPath* highlight = [path copy]; [highlight transformUsingAffineTransform:transform];
      [[NSColor colorWithCalibratedWhite:1 alpha:.2] setStroke]; [highlight stroke];
    }
    [gradient drawInBezierPath:path angle:90];
    [NSGraphicsContext restoreGraphicsState];
    path.lineWidth = 1;
    [[NSColor colorWithCalibratedWhite:0 alpha:self.isHighlighted ? .3 : .2] setStroke];
    [path stroke];
  }
  [self drawInteriorWithFrame:innerFrame inView:view];
}
@end

@interface Cocoa2010BookmarkBarController () {
 @public
  Browser* _browser;
  bookmarks::BookmarkModel* _model;
  NSWindow* __unsafe_unretained _window;
  Cocoa2010BookmarkBarView* _view;
  NSMutableDictionary<NSNumber*, NSButton*>* _buttons;
  NSMutableArray<NSButton*>* _visibleButtons;
  NSButton* _other;
  NSButton* _overflow;
  NSImage* _folderImage;
  NSImage* _defaultImage;
  NSMenu* _trackingMenu;
  std::unique_ptr<BookmarkObserver> _observer;
  BOOL _valid;
  BOOL _dirty;
  NSInteger _displayedButtonCount;
}
- (void)refresh;
- (NSButton*)buttonForNode:(const bookmarks::BookmarkNode*)node;
- (void)modelChanged;
- (void)openBookmark:(id)sender;
- (void)showContextForNode:(NSNumber*)identity event:(NSEvent*)event;
- (NSInteger)indexForDragToPoint:(NSPoint)point;
- (BOOL)performBookmarkDrop:(id<NSDraggingInfo>)info;
@end

@interface Cocoa2010BookmarkButton : NSButton {
  NSTimeInterval _lastHoverUpdate;
}
@property(nonatomic, unsafe_unretained) Cocoa2010BookmarkBarController* controller;
@end
@implementation Cocoa2010BookmarkButton
+ (Class)cellClass { return Cocoa2010BookmarkButtonCell.class; }
- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (void)updateTrackingAreas {
  for (NSTrackingArea* area in [self.trackingAreas copy]) [self removeTrackingArea:area];
  [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.bounds
      options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInActiveApp | NSTrackingInVisibleRect
      owner:self userInfo:nil]];
  [super updateTrackingAreas];
}
// GradientButtonCell's original linear .2s/.4s hover pulse. The original
// flat-cell draw path hides the outgoing pulse as soon as the mouse leaves.
- (void)mouseEntered:(NSEvent*)event {
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(performOnePulseStep) object:nil];
  Cocoa2010BookmarkButtonCell* cell = (Cocoa2010BookmarkButtonCell*)self.cell;
  cell.mouseInside = YES; cell.hoverAlpha = 0;
  _lastHoverUpdate = [NSDate timeIntervalSinceReferenceDate];
  [self performOnePulseStep];
}
- (void)mouseExited:(NSEvent*)event {
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(performOnePulseStep) object:nil];
  Cocoa2010BookmarkButtonCell* cell = (Cocoa2010BookmarkButtonCell*)self.cell;
  cell.mouseInside = NO; cell.hoverAlpha = 1;
  _lastHoverUpdate = [NSDate timeIntervalSinceReferenceDate];
  [self performOnePulseStep];
}
- (void)performOnePulseStep {
  Cocoa2010BookmarkButtonCell* cell = (Cocoa2010BookmarkButtonCell*)self.cell;
  NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
  CGFloat opacity = cell.hoverAlpha + (now-_lastHoverUpdate) / (cell.mouseInside ? .2 : -.4);
  _lastHoverUpdate = now; cell.hoverAlpha = std::clamp(opacity, CGFloat(0), CGFloat(1));
  self.needsDisplay = YES;
  if ((cell.mouseInside ? opacity < 1 : opacity > 0) && self.window)
    [self performSelector:_cmd withObject:nil afterDelay:.02];
}
- (void)viewWillMoveToWindow:(NSWindow*)window {
  if (!window) [NSObject cancelPreviousPerformRequestsWithTarget:self];
  [super viewWillMoveToWindow:window];
}
- (void)rightMouseDown:(NSEvent*)event {
  [self.controller showContextForNode:self.cell.representedObject event:event];
}
- (void)mouseDown:(NSEvent*)event {
  if (event.modifierFlags & NSControlKeyMask) { [self rightMouseDown:event]; return; }
  // BookmarkButton's first-drag threshold; the current model supplies IDs
  // rather than the original raw BookmarkNode pasteboard pointers.
  __attribute__((objc_precise_lifetime)) Cocoa2010BookmarkButton* keepAlive = self;
  __attribute__((objc_precise_lifetime)) Cocoa2010BookmarkBarController* controller = self.controller;
  (void)keepAlive;
  self.cell.highlighted = YES; self.needsDisplay = YES;
  for (;;) {
    NSEvent* next = [self.window nextEventMatchingMask:NSLeftMouseDraggedMask | NSLeftMouseUpMask
        untilDate:NSDate.distantFuture inMode:NSEventTrackingRunLoopMode dequeue:YES];
    if (!next) break;
    if (next.type == NSLeftMouseUp) {
      self.cell.highlighted = NO; self.needsDisplay = YES;
      NSPoint point = [self convertPoint:next.locationInWindow fromView:nil];
      if (NSPointInRect(point, self.bounds)) [self sendAction:self.action to:self.target];
      break;
    }
    CGFloat dx = next.locationInWindow.x - event.locationInWindow.x;
    CGFloat dy = next.locationInWindow.y - event.locationInWindow.y;
    if (dx*dx + dy*dy > 25 && self != controller->_other && self != controller->_overflow) {
      NSPasteboard* pasteboard = [NSPasteboard pasteboardWithName:NSDragPboard];
      [pasteboard declareTypes:@[kBookmarkDragType] owner:nil];
      [pasteboard setString:[self.cell.representedObject stringValue] forType:kBookmarkDragType];
      NSImage* image = [[NSImage alloc] initWithSize:self.bounds.size];
      [image lockFocus]; [self.cell drawWithFrame:self.bounds inView:self]; [image unlockFocus];
      [self dragImage:image at:NSZeroPoint offset:NSZeroSize event:next pasteboard:pasteboard source:self slideBack:YES];
      break;
    }
  }
  self.cell.highlighted = NO; self.needsDisplay = YES;
}
- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)local { return local ? NSDragOperationMove : NSDragOperationNone; }
@end

@interface Cocoa2010BookmarkBarView : NSView
@property(nonatomic, unsafe_unretained) Cocoa2010BookmarkBarController* controller;
@property(nonatomic) BOOL dropIndicatorShown;
@property(nonatomic) CGFloat dropIndicatorPosition;
@end
@implementation Cocoa2010BookmarkBarView
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (void)drawRect:(NSRect)dirtyRect {
  // BackgroundGradientView's original window-relative 100pt toolbar gradient.
  // The original bar continues the toolbar fill and owns the lower divider.
  NSPoint start = [self convertPoint:NSMakePoint(0, NSHeight(self.window.frame)-12) fromView:nil];
  NSPoint end = [self convertPoint:NSMakePoint(0, NSHeight(self.window.frame)-112) fromView:nil];
  [Cocoa2010ToolbarGradient(self.window.isKeyWindow) drawFromPoint:start toPoint:end
      options:NSGradientDrawsBeforeStartingLocation | NSGradientDrawsAfterEndingLocation];
  [[NSColor colorWithCalibratedWhite:103.0/255 alpha:1] set];
  NSRectFill(NSMakeRect(0, 0, NSWidth(self.bounds), 1));
  // BookmarkBarView::drawRect's original bookmark-drag drop indicator.
  if (self.dropIndicatorShown) {
    CGFloat x = MAX(self.dropIndicatorPosition - .5, 0);
    [[NSColor colorWithCalibratedWhite:0 alpha:.85] setFill];
    [[NSBezierPath bezierPathWithRect:NSMakeRect(x, 4, 1, NSHeight(self.bounds)-8)] fill];
  }
}
- (void)rightMouseDown:(NSEvent*)event { [self.controller showContextForNode:nil event:event]; }
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)info { return [self draggingUpdated:info]; }
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)info {
  NSPasteboard* board = info.draggingPasteboard;
  if (![board stringForType:kBookmarkDragType] && ![NSURL URLFromPasteboard:board] && ![board stringForType:NSStringPboardType]) return NSDragOperationNone;
  NSPoint point = [self convertPoint:info.draggingLocation fromView:nil];
  NSInteger index = [self.controller indexForDragToPoint:point];
  NSArray* buttons = self.controller->_visibleButtons;
  self.dropIndicatorPosition = index < (NSInteger)buttons.count ?
      NSMinX(((NSButton*)[buttons objectAtIndex:index]).frame)-.5 :
      buttons.count ? NSMaxX(((NSButton*)buttons.lastObject).frame)+.5 : .5;
  self.dropIndicatorShown = YES; self.needsDisplay = YES;
  return info.draggingSource ? NSDragOperationMove : NSDragOperationCopy;
}
- (void)draggingExited:(id<NSDraggingInfo>)info { self.dropIndicatorShown = NO; self.needsDisplay = YES; }
- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)info { return YES; }
- (BOOL)performDragOperation:(id<NSDraggingInfo>)info {
  [self draggingExited:info]; return [self.controller performBookmarkDrop:info];
}
@end

namespace {
class BookmarkObserver final : public bookmarks::BaseBookmarkModelObserver {
 public:
  explicit BookmarkObserver(Cocoa2010BookmarkBarController* owner) : owner_(owner) {}
  void BookmarkModelChanged() override { [owner_ modelChanged]; }
  void BookmarkModelLoaded(bool) override { [owner_ modelChanged]; }
 private:
  Cocoa2010BookmarkBarController* __unsafe_unretained owner_;
};
class ContextMenuCloser final : public BookmarkContextMenuControllerDelegate {
 public:
  NSMenu* __unsafe_unretained menu = nil;
  void CloseMenu() override { [menu cancelTracking]; }
};
}

@implementation Cocoa2010BookmarkBarController
- (instancetype)initWithBrowser:(Browser*)browser window:(NSWindow*)window resources:(NSString*)resources {
  if ((self = [super init])) {
    _browser = browser; _window = window; _valid = YES; _dirty = YES;
    _model = BookmarkModelFactory::GetForBrowserContext(browser->profile());
    _view = [[Cocoa2010BookmarkBarView alloc] initWithFrame:NSZeroRect]; _view.controller = self;
    _view.wantsLayer = YES; _view.hidden = YES;
    [_view registerForDraggedTypes:@[kBookmarkDragType, NSURLPboardType, NSStringPboardType]];
    _buttons = [[NSMutableDictionary alloc] init]; _visibleButtons = [[NSMutableArray alloc] init];
    _folderImage = [[NSImage alloc] initWithContentsOfFile:[resources stringByAppendingPathComponent:@"bookmark_bar_folder_mac.png"]];
    _defaultImage = [[NSImage alloc] initWithContentsOfFile:[resources stringByAppendingPathComponent:@"omnibox_http.pdf"]];
    // Permanent nodes become available only after the current model loads.
    _overflow = [[Cocoa2010BookmarkButton alloc] initWithFrame:NSZeroRect];
    ((Cocoa2010BookmarkButton*)_overflow).controller = self;
    _overflow.target = self; _overflow.action = @selector(openBookmark:);
    _overflow.cell.representedObject = @(-1);
    ((Cocoa2010BookmarkButtonCell*)_overflow.cell).image = [[NSImage alloc] initWithContentsOfFile:[resources stringByAppendingPathComponent:@"chevron.png"]];
    _overflow.imagePosition = NSImageOnly; _overflow.title = @"";
    _observer = std::make_unique<BookmarkObserver>(self); _model->AddObserver(_observer.get());
    for (NSString* name in @[NSWindowDidBecomeKeyNotification, NSWindowDidResignKeyNotification])
      [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(windowChanged:) name:name object:window];
  }
  return self;
}
- (void)dealloc { [self invalidate]; }
- (void)invalidate {
  if (!_valid) return; _valid = NO;
  [NSObject cancelPreviousPerformRequestsWithTarget:self]; [_trackingMenu cancelTracking];
  [NSNotificationCenter.defaultCenter removeObserver:self];
  if (_observer && _model) _model->RemoveObserver(_observer.get());
  _observer.reset(); [_view unregisterDraggedTypes]; [_view removeFromSuperview];
  _view.controller = nil; _browser = nullptr; _model = nullptr;
}
- (void)windowChanged:(NSNotification*)notification {
  _view.needsDisplay = YES;
  for (NSButton* button in _view.subviews) button.needsDisplay = YES;
}
- (void)modelChanged {
  if (!_valid) return;
  [_trackingMenu cancelTracking]; _dirty = YES;
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refresh) object:nil];
  [self performSelector:@selector(refresh) withObject:nil afterDelay:0];
}
- (NSButton*)buttonForNode:(const bookmarks::BookmarkNode*)node {
  NSNumber* key = @(node->id()); NSButton* button = [_buttons objectForKey:key];
  if (!button) {
    button = [[Cocoa2010BookmarkButton alloc] initWithFrame:NSZeroRect];
    ((Cocoa2010BookmarkButton*)button).controller = self;
    button.target = self; button.action = @selector(openBookmark:);
    button.cell.representedObject = key; button.imageScaling = NSImageScaleProportionallyDown;
    [_buttons setObject:button forKey:key];
  }
  NSImage* image = _folderImage;
  if (node->is_url()) {
    const gfx::Image& favicon = _model->GetFavicon(node);
    image = favicon.IsEmpty() ? _defaultImage : favicon.AsNSImage();
  }
  [(Cocoa2010BookmarkButtonCell*)button.cell setBookmarkCellText:base::SysUTF16ToNSString(node->GetTitle()) image:image];
  button.toolTip = node->is_url() ? base::SysUTF8ToNSString(node->url().spec()) : button.title;
  return button;
}
// Original BookmarkBarController widthForBookmarkButtonCell.
- (CGFloat)widthForBookmarkButtonCell:(NSCell*)cell { return std::min([cell cellSize].width + 2, kDefaultBookmarkWidth); }
// Original frameForBookmarkButtonFromCell:xOffset:, preserving 28pt cell
// height, 1pt horizontal padding and 2pt vertical padding.
- (NSRect)frameForBookmarkButtonFromCell:(NSCell*)cell xOffset:(int*)offset {
  NSRect bounds = _view.bounds; bounds.size.height = kBookmarkButtonHeight;
  NSRect frame = NSInsetRect(bounds, kBookmarkHorizontalPadding, kBookmarkVerticalPadding);
  frame.size.width = [self widthForBookmarkButtonCell:cell];
  frame.origin.x += *offset; *offset = NSMaxX(frame);
  return frame;
}
- (void)layoutWithScreenRect:(NSRect)rect {
  if (!_valid) return;
  _view.hidden = NSIsEmptyRect(rect); if (_view.hidden) return;
  NSView* frameView = _window.contentView.superview;
  rect.origin = [_window convertScreenToBase:rect.origin];
  rect = [frameView convertRect:rect fromView:nil];
  if (!NSEqualRects(_view.frame, rect)) { _view.frame = rect; _dirty = YES; }
  if (_view.superview != frameView) [frameView addSubview:_view positioned:NSWindowAbove relativeTo:_window.contentView];
  [self refresh];
}
- (void)refresh {
  if (!_valid || !_dirty || !_model->loaded()) return;
  _dirty = NO;
  const auto* bar = _model->bookmark_bar_node();
  _other = [self buttonForNode:_model->other_node()];
  int ignored = 0;
  NSRect otherFrame = [self frameForBookmarkButtonFromCell:_other.cell xOffset:&ignored];
  otherFrame.origin.x = NSWidth(_view.bounds)-NSWidth(otherFrame)-kBookmarkHorizontalPadding;
  _other.frame = otherFrame;
  _overflow.frame = NSMakeRect(NSMinX(otherFrame)-24, 2, 22, 24);
  CGFloat maxX = NSMinX(otherFrame)-kBookmarkHorizontalPadding;
  CGFloat totalWidth = 0;
  for (const auto& node : bar->children()) totalWidth += [self widthForBookmarkButtonCell:[self buttonForNode:node.get()].cell] + kBookmarkHorizontalPadding;
  BOOL overflow = totalWidth > maxX;
  if (overflow) maxX = NSMinX(_overflow.frame)-kBookmarkHorizontalPadding;
  NSMutableSet* keep = [NSMutableSet setWithObject:@(_model->other_node()->id())];
  [_visibleButtons removeAllObjects]; int offset = 0;
  for (const auto& node : bar->children()) {
    NSNumber* key = @(node->id()); [keep addObject:key];
    NSButton* button = [self buttonForNode:node.get()];
    NSRect frame = [self frameForBookmarkButtonFromCell:button.cell xOffset:&offset];
    BOOL fits = NSMaxX(frame) < maxX;
    button.hidden = !fits;
    if (fits) { button.frame = frame; [_visibleButtons addObject:button]; if (button.superview != _view) [_view addSubview:button]; }
  }
  for (NSNumber* key in [_buttons.allKeys copy]) if (![keep containsObject:key]) { [[_buttons objectForKey:key] removeFromSuperview]; [_buttons removeObjectForKey:key]; }
  _displayedButtonCount = _visibleButtons.count;
  _overflow.hidden = !overflow;
  if (_other.superview != _view) [_view addSubview:_other];
  if (_overflow.superview != _view) [_view addSubview:_overflow];
  _view.needsDisplay = YES;
}
// Original addNode:toMenu:/addFolderNode:toMenu:, with IDs resolved through
// the current model when activated (safe across sync/model changes).
- (void)addNode:(const bookmarks::BookmarkNode*)node toMenu:(NSMenu*)menu {
  NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:base::SysUTF16ToNSString(node->GetTitle()) action:@selector(openBookmark:) keyEquivalent:@""];
  item.target = self; item.representedObject = @(node->id());
  if (node->is_folder()) {
    item.image = _folderImage; NSMenu* submenu = [[NSMenu alloc] initWithTitle:item.title];
    for (const auto& child : node->children()) [self addNode:child.get() toMenu:submenu];
    item.submenu = submenu;
  } else { const gfx::Image& favicon = _model->GetFavicon(node); item.image = favicon.IsEmpty() ? _defaultImage : favicon.AsNSImage(); }
  [menu addItem:item];
}
- (void)openBookmark:(id)sender {
  if (!_valid) return;
  __attribute__((objc_precise_lifetime)) Cocoa2010BookmarkBarController* keepAlive = self; (void)keepAlive;
  NSNumber* key = [sender isKindOfClass:NSMenuItem.class] ? [sender representedObject] : [[sender cell] representedObject];
  const auto* node = key.longLongValue == -1 ? _model->bookmark_bar_node() : bookmarks::GetBookmarkNodeByID(_model,key.longLongValue);
  if (!node) return;
  if (node->is_url()) {
    NavigateParams params(_browser,node->url(),ui::PAGE_TRANSITION_AUTO_BOOKMARK);
    params.disposition = ui::WindowOpenDispositionFromNSEvent(NSApp.currentEvent); Navigate(&params); return;
  }
  if (![sender isKindOfClass:NSView.class]) return;
  NSMenu* menu = [[NSMenu alloc] initWithTitle:base::SysUTF16ToNSString(node->GetTitle())];
  size_t start = key.longLongValue == -1 ? _displayedButtonCount : 0;
  for (size_t i=start;i<node->children().size();++i) [self addNode:node->children()[i].get() toMenu:menu];
  _trackingMenu = menu;
  [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, 0) inView:sender];
  _trackingMenu = nil;
}
- (void)showContextForNode:(NSNumber*)identity event:(NSEvent*)event {
  if (!_valid) return;
  __attribute__((objc_precise_lifetime)) Cocoa2010BookmarkBarController* keepAlive = self; (void)keepAlive;
  const auto* node = identity ? bookmarks::GetBookmarkNodeByID(_model, identity.longLongValue) : nullptr;
  if (identity && !node) return;
  std::vector<raw_ptr<const bookmarks::BookmarkNode, VectorExperimental>> selection;
  if (node) selection.push_back(node);
  ContextMenuCloser closer;
  BookmarkContextMenuController model(gfx::NativeWindow(_window), &closer, _browser, _browser->profile(),
      BookmarkLaunchLocation::kAttachedBar, node ? node->parent() : _model->bookmark_bar_node(), selection);
  MenuControllerCocoa* controller = [[MenuControllerCocoa alloc] initWithModel:model.menu_model() delegate:nil useWithPopUpButtonCell:NO];
  _trackingMenu = closer.menu = controller.menu;
  [NSMenu popUpContextMenu:controller.menu withEvent:event forView:_view];
  _trackingMenu = nil;
}
// Original indexForDragToPoint: uses the first button midpoint to the right.
- (NSInteger)indexForDragToPoint:(NSPoint)point {
  NSInteger index = 0;
  for (NSButton* button in _visibleButtons) { if (point.x < NSMidX(button.frame)) break; ++index; }
  return index;
}
- (BOOL)performBookmarkDrop:(id<NSDraggingInfo>)info {
  if (!_valid || !_model->loaded()) return NO;
  NSPoint point = [_view convertPoint:info.draggingLocation fromView:nil];
  size_t index = [self indexForDragToPoint:point];
  const auto* parent = _model->bookmark_bar_node();
  for (NSButton* button in _visibleButtons) {
    const auto* candidate = bookmarks::GetBookmarkNodeByID(_model, [button.cell.representedObject longLongValue]);
    if (candidate && candidate->is_folder() && point.x > NSMinX(button.frame)+NSWidth(button.frame)/3 && point.x < NSMaxX(button.frame)-NSWidth(button.frame)/3) {
      parent = candidate; index = candidate->children().size(); break;
    }
  }
  NSString* source = [info.draggingPasteboard stringForType:kBookmarkDragType];
  if (source) {
    const auto* node = bookmarks::GetBookmarkNodeByID(_model, source.longLongValue);
    if (!node) return NO;
    for (const auto* ancestor = parent; ancestor; ancestor = ancestor->parent())
      if (ancestor == node) return NO;
    _model->Move(node,parent,index); return YES;
  }
  NSURL* url = [NSURL URLFromPasteboard:info.draggingPasteboard];
  NSString* value = url.absoluteString ?: [info.draggingPasteboard stringForType:NSStringPboardType];
  GURL address(base::SysNSStringToUTF8(value ?: @""));
  if (!address.is_valid()) return NO;
  _model->AddURL(parent,index,base::SysNSStringToUTF16(value),address,nullptr,std::nullopt,std::nullopt,true);
  return YES;
}
@end
