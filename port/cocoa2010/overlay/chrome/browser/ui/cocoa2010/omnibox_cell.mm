// Copyright (c) 2010 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "chrome/browser/ui/cocoa2010/controls.h"

namespace {

NSBezierPath* RectPathWithInset(NSInteger roundedFlags,
                                const NSRect frame,
                                const CGFloat inset,
                                const CGFloat outerRadius) {
  NSRect insetFrame = NSInsetRect(frame, inset, inset);

  if (outerRadius > 0.0) {
    CGFloat leftRadius = outerRadius - inset;

    return [NSBezierPath bezierPathWithRoundedRect:insetFrame
                                         xRadius:leftRadius yRadius:leftRadius];
  } else {
    return [NSBezierPath bezierPathWithRect:insetFrame];
  }
}

// Similar to |NSRectFill()|, additionally sets |color| as the fill
// color.  |outerRadius| greater than 0.0 uses rounded corners, with
// inset backed out of the radius.
void FillRectWithInset(NSInteger roundedFlags,
                       const NSRect frame,
                       const CGFloat inset,
                       const CGFloat outerRadius,
                       NSColor* color) {
  NSBezierPath* path =
      RectPathWithInset(roundedFlags, frame, inset, outerRadius);
  [color setFill];
  [path fill];
}

// Similar to |NSFrameRectWithWidth()|, additionally sets |color| as
// the stroke color (as opposed to the fill color).  |outerRadius|
// greater than 0.0 uses rounded corners, with inset backed out of the
// radius.
void FrameRectWithInset(NSInteger roundedFlags,
                        const NSRect frame,
                        const CGFloat inset,
                        const CGFloat outerRadius,
                        const CGFloat lineWidth,
                        NSColor* color) {
  const CGFloat finalInset = inset + (lineWidth / 2.0);
  NSBezierPath* path =
      RectPathWithInset(roundedFlags, frame, finalInset, outerRadius);
  [color setStroke];
  [path setLineWidth:lineWidth];
  [path stroke];
}

// TODO(shess): Maybe we need a |cocoa_util.h|?
class ScopedSaveGraphicsState {
 public:
  ScopedSaveGraphicsState()
      : context_([NSGraphicsContext currentContext]) {
    [context_ saveGraphicsState];
  }
  explicit ScopedSaveGraphicsState(NSGraphicsContext* context)
      : context_(context) {
    [context_ saveGraphicsState];
  }
  ~ScopedSaveGraphicsState() {
    [context_ restoreGraphicsState];
  }

private:
  NSGraphicsContext* context_;
};

}  // namespace

@implementation Cocoa2010StyledTextFieldCell

- (CGFloat)baselineAdjust {
  return 0.0;
}

- (CGFloat)cornerRadius {
  return 0.0;
}

- (NSInteger)roundedFlags {
  return 0;
}

- (BOOL)shouldDrawBezel {
  return NO;
}

// Returns the same value as textCursorFrameForFrame, but does not call it
// directly to avoid potential infinite loops.
- (NSRect)textFrameForFrame:(NSRect)cellFrame {
  return NSInsetRect(cellFrame, 0, [self baselineAdjust]);
}

// Returns the same value as textFrameForFrame, but does not call it directly to
// avoid potential infinite loops.
- (NSRect)textCursorFrameForFrame:(NSRect)cellFrame {
  return NSInsetRect(cellFrame, 0, [self baselineAdjust]);
}

// Override to show the I-beam cursor only in the area given by
// |textCursorFrameForFrame:|.
- (void)resetCursorRect:(NSRect)cellFrame inView:(NSView *)controlView {
  [super resetCursorRect:[self textCursorFrameForFrame:cellFrame]
                  inView:controlView];
}

// For NSTextFieldCell this is the area within the borders.  For our
// purposes, we count the info decorations as being part of the
// border.
- (NSRect)drawingRectForBounds:(NSRect)theRect {
  return [super drawingRectForBounds:[self textFrameForFrame:theRect]];
}

// TODO(shess): This code is manually drawing the cell's border area,
// but otherwise the cell assumes -setBordered:YES for purposes of
// calculating things like the editing area.  This is probably
// incorrect.  I know that this affects -drawingRectForBounds:.
- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView*)controlView {
  NSCAssert([controlView isFlipped], @"Flipped omnibox field required");
  NSInteger roundedFlags = [self roundedFlags];

  // TODO(shess): This inset is also reflected by |kFieldVisualInset|
  // in autocomplete_popup_view_mac.mm.
  const NSRect frame = NSInsetRect(cellFrame, 0, 1);
  const CGFloat radius = [self cornerRadius];

  // The original default-theme path, adapted from BrowserThemeProvider to
  // native colors. Custom extension themes are intentionally not substituted.
  BOOL active = [[controlView window] isMainWindow];
  NSColor* strokeColor = [NSColor colorWithCalibratedWhite:0.0
                                                   alpha:active ? 0.3 : 0.2];
  FrameRectWithInset(roundedFlags, frame, 0.0, radius, 1.0, strokeColor);

  // Fill interior with background color.
  FillRectWithInset(roundedFlags, frame, 1.0, radius, [self backgroundColor]);

  // Draw the shadow.  For the rounded-rect case, the shadow needs to
  // slightly turn in at the corners.  |shadowFrame| is at the same
  // midline as the inner border line on the top and left, but at the
  // outer border line on the bottom and right.  The clipping change
  // will clip the bottom and right edges (and corner).
  {
    ScopedSaveGraphicsState state;
    [RectPathWithInset(roundedFlags, frame, 1.0, radius) addClip];
    const NSRect shadowFrame = NSOffsetRect(frame, 0.5, 0.5);
    NSColor* shadowShade = [NSColor colorWithCalibratedWhite:0.0 alpha:0.05];
    FrameRectWithInset(roundedFlags, shadowFrame, 0.5, radius - 0.5,
                       1.0, shadowShade);
  }

  // Draw optional bezel below bottom stroke.
  if ([self shouldDrawBezel]) {

    [[NSColor colorWithCalibratedWhite:1.0 alpha:0.5] set];
    NSRect bezelRect = NSMakeRect(cellFrame.origin.x,
                                  NSMaxY(cellFrame) - 0.5,
                                  NSWidth(cellFrame),
                                  1.0);
    bezelRect = NSInsetRect(bezelRect, radius - 0.5, 0.0);
    NSRectFill(bezelRect);
  }

  // Draw the focus ring if needed.
  if ([self showsFirstResponder]) {
    NSColor* color =
        [[NSColor keyboardFocusIndicatorColor] colorWithAlphaComponent:0.5];
    FrameRectWithInset(roundedFlags, frame, 0.0, radius, 2.0, color);
  }

  [self drawInteriorWithFrame:cellFrame inView:controlView];
}

@end

@interface Cocoa2010FieldEditor : NSTextView
@property(nonatomic, unsafe_unretained) Cocoa2010AutocompleteField* field;
@end
@implementation Cocoa2010FieldEditor
- (void)setAllowsUndo:(BOOL)allows { [super setAllowsUndo:YES]; }
- (void)copy:(id)sender {
  NSRange selection = self.selectedRange;
  if (!selection.length) return;
  NSString* text = [self.string substringWithRange:selection];
  text = [(Cocoa2010WindowController*)self.field.delegate omniboxCopyText:text offset:selection.location];
  NSPasteboard* board = [NSPasteboard generalPasteboard];
  [board declareTypes:@[NSStringPboardType] owner:nil]; [board setString:text forType:NSStringPboardType];
}
- (void)cut:(id)sender { [self copy:sender]; [self delete:sender]; }
- (void)paste:(id)sender {
  NSString* text = [[NSPasteboard generalPasteboard] stringForType:NSStringPboardType];
  if (!text) return;
  text = [(Cocoa2010WindowController*)self.field.delegate omniboxPasteText:text];
  [self insertText:text];
}
- (BOOL)becomeFirstResponder {
  BOOL result = [super becomeFirstResponder];
  if (result && self.field)
    [(id)self.field.delegate controlTextDidBeginEditing:
        [NSNotification notificationWithName:NSControlTextDidBeginEditingNotification object:self.field]];
  return result;
}
- (BOOL)resignFirstResponder {
  BOOL result = [super resignFirstResponder];
  if (result && self.field)
    [(id)self.field.delegate controlTextDidEndEditing:
        [NSNotification notificationWithName:NSControlTextDidEndEditingNotification object:self.field]];
  return result;
}
// Chromium 7's plain editor treatment: rich text can be displayed but the
// user's font panel and ruler must not change URL editing attributes.
- (void)updateFontPanel {}
- (void)updateRuler {}
@end

@implementation Cocoa2010AutocompleteCell {
  Cocoa2010FieldEditor* _editor;
}
- (NSTextView*)fieldEditorForView:(NSView*)view {
  if (!_editor) {
    _editor = [[Cocoa2010FieldEditor alloc] initWithFrame:NSZeroRect];
    _editor.fieldEditor = YES;
    _editor.richText = NO;
    _editor.allowsUndo = YES;
  }
  _editor.field = (Cocoa2010AutocompleteField*)view;
  return _editor;
}
- (CGFloat)baselineAdjust { return 3.0; }
- (CGFloat)cornerRadius { return 4.0; }
- (BOOL)shouldDrawBezel { return YES; }
- (NSRect)textFrameForFrame:(NSRect)frame {
  // Original single-decoration layout: 5 point outer inset + 19 point PDF.
  // The 3 point inter-decoration pad only applies between multiple icons.
  frame = [super textFrameForFrame:frame];
  frame.origin.x += 24;
  frame.size.width = MAX(0, frame.size.width - 48);
  return frame;
}
- (NSRect)textCursorFrameForFrame:(NSRect)frame {
  return [self textFrameForFrame:frame];
}
@end

@implementation Cocoa2010AutocompleteField
+ (Class)cellClass { return [Cocoa2010AutocompleteCell class]; }
- (BOOL)isFlipped { return YES; }
- (BOOL)isOpaque { return NO; }
// Chromium 7 AutocompleteTextField::mouseDown: selects all on the first
// stationary click. Once installed, NSTextView receives subsequent clicks
// and handles caret placement and drag selection itself.
- (void)mouseDown:(NSEvent*)event {
  [super mouseDown:event];
  NSText* editor = self.currentEditor;
  if (editor && NSApp.currentEvent.type == NSLeftMouseUp && !editor.selectedRange.length)
    [editor selectAll:nil];
}
- (BOOL)becomeFirstResponder {
  BOOL result = [super becomeFirstResponder];
  NSTextView* editor = (NSTextView*)[self currentEditor];
  [editor setAllowsUndo:YES];
  if ([editor respondsToSelector:@selector(setAutomaticQuoteSubstitutionEnabled:)]) {
    [editor setAutomaticQuoteSubstitutionEnabled:NO];
    [editor setAutomaticDashSubstitutionEnabled:NO];
    [editor setAutomaticTextReplacementEnabled:NO];
    [editor setAutomaticSpellingCorrectionEnabled:NO];
  }
  if (result)
    [(id)self.delegate controlTextDidBeginEditing:
        [NSNotification notificationWithName:NSControlTextDidBeginEditingNotification object:self]];
  return result;
}
@end
