// Copyright 2010 The Chromium Authors. Copyright 2026 Snowium contributors.
// BSD license. Port of BookmarkBarController/View and BookmarkButtonCell.
#pragma once
#import <Cocoa/Cocoa.h>
class Browser;
@interface Cocoa2010BookmarkBarController : NSObject
- (instancetype)initWithBrowser:(Browser*)browser window:(NSWindow*)window resources:(NSString*)resources;
- (void)layoutWithScreenRect:(NSRect)rect;
- (void)invalidate;
@end
