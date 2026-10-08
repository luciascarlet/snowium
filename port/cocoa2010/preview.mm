// Native preview of the same controls compiled into Chromium. BSD license.
#import "chrome/browser/ui/cocoa2010/controls.h"
#include "chrome/app/chrome_command_ids.h"
#include <cstdio>

@interface Preview : NSObject <NSApplicationDelegate, Cocoa2010BrowserDelegate>
@property(nonatomic, strong) NSWindow* window;
@property(nonatomic, strong) Cocoa2010WindowController* controller;
@property(nonatomic, strong) NSMutableArray<Cocoa2010TabData*>* tabs;
@property(nonatomic, copy) NSString* resources;
@property(nonatomic, copy) NSString* input;
@end
@implementation Preview
- (void)applicationDidFinishLaunching:(NSNotification*)notification {
  self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(200, 300, 900, 560)
      styleMask:NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask |
                NSResizableWindowMask | NSTexturedBackgroundWindowMask |
                NSUnifiedTitleAndToolbarWindowMask backing:NSBackingStoreBuffered defer:NO];
  self.window.title = @"Chromium"; self.window.releasedWhenClosed = NO;
  self.controller = [[Cocoa2010WindowController alloc] initWithWindow:self.window delegate:self resources:self.resources];
  self.tabs = [NSMutableArray array];
  for (NSString* title in @[@"Untitled", @"The Chromium Projects", @"Wikipedia"]) {
    Cocoa2010TabData* tab = [[Cocoa2010TabData alloc] init]; tab.identity = self.tabs.count + 1;
    tab.title = title; tab.selected = self.tabs.count == 0; [self.tabs addObject:tab];
  }
  [self.controller updateTabs:self.tabs animate:NO];
  [self.controller updateURL:@"www.google.com" loading:NO starred:NO secure:NO showHome:NO];
  [self.window makeKeyAndOrderFront:nil];
  [NSApp activateIgnoringOtherApps:YES];
  [self performSelector:@selector(capture) withObject:nil afterDelay:1];
}
- (void)capture {
  NSView* view = self.window.contentView.superview;
  NSBitmapImageRep* bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
  [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
  [[bitmap representationUsingType:NSPNGFileType properties:@{}] writeToFile:@"/tmp/snowium-cocoa2010-preview.png" atomically:YES];
}
- (void)focus:(id)sender { [self.controller focusLocation]; }
- (void)executeCommand:(NSInteger)command {
  if (command == IDC_NEW_TAB) {
    for (Cocoa2010TabData* tab in self.tabs) tab.selected = NO;
    Cocoa2010TabData* tab = [[Cocoa2010TabData alloc] init];
    tab.identity = self.tabs.count + 10; tab.title = @"Untitled"; tab.selected = YES; [self.tabs addObject:tab];
    [self.controller updateTabs:self.tabs animate:YES];
  } else if (command == IDC_BOOKMARK_THIS_TAB) {
    [self.controller updateURL:self.input ?: @"www.google.com" loading:NO starred:YES secure:NO showHome:NO];
  }
}
- (BOOL)isCommandEnabled:(NSInteger)command { return command != IDC_FORWARD; }
- (void)activateTab:(uintptr_t)identity {
  for (Cocoa2010TabData* tab in self.tabs) tab.selected = tab.identity == identity;
  [self.controller updateTabs:self.tabs animate:NO];
}
- (void)closeTab:(uintptr_t)identity {
  for (Cocoa2010TabData* tab in [self.tabs copy]) if (tab.identity == identity) [self.tabs removeObject:tab];
  if (self.tabs.count) self.tabs.firstObject.selected = YES;
  [self.controller updateTabs:self.tabs animate:YES];
}
- (void)moveTab:(uintptr_t)identity toIndex:(NSInteger)index {}
- (void)dropTab:(uintptr_t)identity atScreenPoint:(NSPoint)point {}
- (void)showContextMenuForTab:(uintptr_t)identity atScreenPoint:(NSPoint)point {}
- (void)omniboxBeganEditing { printf("FOCUS_BEGIN\n"); fflush(stdout); }
- (void)omniboxChanged:(NSString*)text selection:(NSRange)selection composing:(BOOL)composing {
  self.input = text; printf("EDIT %s selection=%lu,%lu composition=%d\n", text.UTF8String,
      (unsigned long)selection.location, (unsigned long)selection.length, composing); fflush(stdout);
}
- (void)omniboxEndedEditing { printf("FOCUS_END\n"); fflush(stdout); }
- (void)omniboxSelectionChanged:(NSRange)selection {}
- (NSString*)omniboxCopyText:(NSString*)text offset:(NSUInteger)offset { return text; }
- (NSString*)omniboxPasteText:(NSString*)text { return text; }
- (BOOL)omniboxCommand:(SEL)selector {
  if (selector == @selector(insertNewline:)) {
    [self.controller updateURL:self.input ?: @"www.google.com" loading:NO starred:NO secure:NO showHome:NO];
    printf("ACCEPT %s\n", self.input.UTF8String); fflush(stdout); return YES;
  }
  if (selector == @selector(cancelOperation:)) return YES;
  return NO;
}
- (void)showApplicationMenuFromView:(NSView*)view { [self executeCommand:IDC_SHOW_APP_MENU]; }
- (void)showPageInfo {}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)application { return YES; }
@end
int main(int argc, char** argv) {
  @autoreleasepool {
    [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    Preview* preview = [[Preview alloc] init];
    preview.resources = argc > 1 ? [NSString stringWithUTF8String:argv[1]] :
        [[NSBundle mainBundle].resourcePath stringByAppendingPathComponent:@"Cocoa2010"]; [NSApp setDelegate:preview];
    NSMenu* menu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem* app = [[NSMenuItem alloc] initWithTitle:@"Chromium" action:nil keyEquivalent:@""];
    NSMenu* appMenu = [[NSMenu alloc] initWithTitle:@"Chromium"];
    [appMenu addItemWithTitle:@"Quit Chromium" action:@selector(terminate:) keyEquivalent:@"q"];
    app.submenu = appMenu; [menu addItem:app];
    NSMenuItem* edit = [[NSMenuItem alloc] initWithTitle:@"Edit" action:nil keyEquivalent:@""];
    NSMenu* editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    edit.submenu = editMenu; [menu addItem:edit];
    NSMenuItem* location = [[NSMenuItem alloc] initWithTitle:@"Open Location…" action:@selector(focus:) keyEquivalent:@"l"];
    location.target = preview; [menu addItem:location]; [NSApp setMainMenu:menu];
    [NSApp run];
  }
}
