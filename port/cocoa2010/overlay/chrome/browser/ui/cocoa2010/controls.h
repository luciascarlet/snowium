// Copyright 2010 The Chromium Authors. All rights reserved.
// Copyright 2026 Snowium contributors.
// BSD license; see port/cocoa2010/upstream/LICENSE.
#pragma once
#import <Cocoa/Cocoa.h>

NSGradient* Cocoa2010ToolbarGradient(BOOL active);

// The visual and editing implementation is independent of Chromium models.
// Production and the native preview exercise these same classes.
@interface Cocoa2010TabData : NSObject
@property(nonatomic) uintptr_t identity;
@property(nonatomic, copy) NSString* title;
@property(nonatomic, strong) NSImage* icon;
@property(nonatomic) BOOL selected;
@property(nonatomic) BOOL pinned;
@property(nonatomic) BOOL loading;
@property(nonatomic) BOOL waiting;
@end

@protocol Cocoa2010BrowserDelegate <NSObject>
- (void)executeCommand:(NSInteger)command;
- (BOOL)isCommandEnabled:(NSInteger)command;
- (void)activateTab:(uintptr_t)identity;
- (void)closeTab:(uintptr_t)identity;
- (void)moveTab:(uintptr_t)identity toIndex:(NSInteger)index;
- (void)dropTab:(uintptr_t)identity atScreenPoint:(NSPoint)point;
- (void)showContextMenuForTab:(uintptr_t)identity atScreenPoint:(NSPoint)point;
- (void)omniboxBeganEditing;
- (void)omniboxChanged:(NSString*)text selection:(NSRange)selection composing:(BOOL)composing;
- (void)omniboxEndedEditing;
- (void)omniboxSelectionChanged:(NSRange)selection;
- (NSString*)omniboxCopyText:(NSString*)text offset:(NSUInteger)offset;
- (NSString*)omniboxPasteText:(NSString*)text;
- (BOOL)omniboxCommand:(SEL)selector;
- (void)showPageInfo;
- (void)showApplicationMenuFromView:(NSView*)view;
@end

@interface Cocoa2010StyledTextFieldCell : NSTextFieldCell
- (CGFloat)baselineAdjust;
- (CGFloat)cornerRadius;
- (BOOL)shouldDrawBezel;
- (NSRect)textFrameForFrame:(NSRect)frame;
- (NSRect)textCursorFrameForFrame:(NSRect)frame;
@end

@interface Cocoa2010AutocompleteCell : Cocoa2010StyledTextFieldCell
@end

@interface Cocoa2010AutocompleteField : NSTextField
@end

@class Cocoa2010WindowController;

@interface Cocoa2010TabView : NSView
@property(nonatomic, strong) Cocoa2010TabData* data;
@property(nonatomic, unsafe_unretained) id<Cocoa2010BrowserDelegate> browserDelegate;
@property(nonatomic, strong) NSButton* closeButton;
@property(nonatomic) CGFloat hoverAlpha;
@property(nonatomic) BOOL dragging;
@property(nonatomic, strong) NSImage* throbberImage;
@property(nonatomic, unsafe_unretained) Cocoa2010WindowController* stripController;
- (NSBezierPath*)bezierPathForRect:(NSRect)rect;
@end

@interface Cocoa2010WindowController : NSObject <NSTextFieldDelegate, NSMenuItemValidation>
@property(nonatomic, readonly) Cocoa2010AutocompleteField* field;
@property(nonatomic, readonly) NSView* rootView;
@property(nonatomic, readonly) NSRect omniboxScreenRect;
@property(nonatomic, readonly) BOOL editing;
- (instancetype)initWithWindow:(NSWindow*)window
                      delegate:(id<Cocoa2010BrowserDelegate>)delegate
                     resources:(NSString*)resources;
- (void)updateTabs:(NSArray<Cocoa2010TabData*>*)tabs animate:(BOOL)animate;
- (void)updateURL:(NSString*)url loading:(BOOL)loading starred:(BOOL)starred secure:(BOOL)secure showHome:(BOOL)showHome;
- (void)updateLocationIcon:(NSString*)name;
- (void)applyOmniboxAttributes:(NSAttributedString*)text;
- (void)updateEditingText:(NSString*)text selection:(NSRange)selection;
- (void)focusLocation;
- (void)layout;
- (void)invalidate;
- (void)showToolsMenu;
- (void)setBookmarkBarVisible:(BOOL)visible;
- (void)beginDraggingTab:(Cocoa2010TabView*)tab;
- (void)updateDraggingTab:(Cocoa2010TabView*)tab frame:(NSRect)frame;
- (void)endDraggingTab;
- (NSInteger)dragInsertionIndexForTab:(uintptr_t)identity;
- (NSString*)omniboxCopyText:(NSString*)text offset:(NSUInteger)offset;
- (NSString*)omniboxPasteText:(NSString*)text;
@end

#ifdef __cplusplus
namespace cocoa2010 {
inline constexpr int kTabHeight = 26;
inline constexpr int kToolbarHeight = 35;
inline constexpr int kTabStripHeight = kTabHeight + 10;
inline constexpr int kChromeHeight = kTabStripHeight + kToolbarHeight;
}
#endif
