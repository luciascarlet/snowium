// Copyright (c) 2010 The Chromium Authors. All rights reserved.
// Copyright 2026 Snowium contributors.
// BSD license; see port/cocoa2010/upstream/LICENSE.
// Port of Chromium 7 autocomplete_popup_view_mac.mm. The native matrix, cell
// drawing, hover/drag tracking, text classifications and popup geometry are
// retained; model ownership and commands use Chromium 124's omnibox model.

#import <Cocoa/Cocoa.h>
#include <algorithm>
#include <cmath>
#include <vector>

#include "base/command_line.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/cocoa2010/browser_adapter.h"
#include "chrome/browser/ui/cocoa2010/omnibox_popup.h"
#include "components/omnibox/browser/actions/omnibox_action.h"
#include "components/omnibox/browser/autocomplete_match.h"
#include "components/omnibox/browser/omnibox_controller.h"
#include "components/omnibox/browser/omnibox_edit_model.h"
#include "components/omnibox/browser/omnibox_popup_view.h"
#include "ui/accessibility/ax_node_data.h"
#include "ui/base/cocoa/cocoa_base_utils.h"

namespace {
constexpr CGFloat kPopupAlpha = 240.0 / 255.0;
constexpr CGFloat kPopupRoundingRadius = 3.5;
constexpr CGFloat kPopupFieldGap = 2.0;
constexpr CGFloat kTextXOffset = 27.0;
constexpr CGFloat kImageXOffset = 4.0;
constexpr CGFloat kCellHeightAdjust = 6.0;
constexpr CGFloat kMaxContentsFraction = 0.7;

NSColor* BackgroundColor() {
  return [NSColor.controlBackgroundColor colorWithAlphaComponent:kPopupAlpha];
}
NSColor* SelectedBackgroundColor() {
  return [NSColor.selectedControlColor colorWithAlphaComponent:kPopupAlpha];
}
NSColor* HoveredBackgroundColor() {
  return [NSColor.controlHighlightColor colorWithAlphaComponent:kPopupAlpha];
}

NSMutableAttributedString* DecorateMatchedString(
    const std::u16string& text,
    const ACMatchClassifications& classifications,
    NSColor* color, NSFont* font) {
  NSMutableAttributedString* result = [[NSMutableAttributedString alloc]
      initWithString:base::SysUTF16ToNSString(text)
      attributes:@{NSFontAttributeName:font, NSForegroundColorAttributeName:color}];
  for (size_t i = 0; i < classifications.size(); ++i) {
    size_t start = std::min(classifications[i].offset, text.size());
    size_t end = i + 1 < classifications.size()
        ? std::min(classifications[i + 1].offset, text.size()) : text.size();
    if (end <= start) continue;
    NSRange range = NSMakeRange(start, end - start);
    if (classifications[i].style & ACMatchClassification::URL)
      [result addAttribute:NSForegroundColorAttributeName
          value:[NSColor colorWithCalibratedRed:0 green:0.55 blue:0 alpha:1]
          range:range];
    if (classifications[i].style & ACMatchClassification::MATCH)
      [result addAttribute:NSFontAttributeName
          value:[NSFontManager.sharedFontManager convertFont:font toHaveTrait:NSBoldFontMask]
          range:range];
  }
  return result;
}

// The original elider used gfx::ElideText; retain native attributed runs while
// measuring the actual font, and avoid splitting UTF-16 composed characters.
void ElideString(NSMutableAttributedString* text, CGFloat width) {
  if (text.size.width <= width) return;
  NSMutableAttributedString* best = [[NSMutableAttributedString alloc] init];
  NSInteger low = 0, high = text.length;
  while (low <= high) {
    NSInteger middle = low + (high - low) / 2;
    NSUInteger cut = middle < static_cast<NSInteger>(text.length)
        ? [text.string rangeOfComposedCharacterSequenceAtIndex:middle].location : text.length;
    NSMutableAttributedString* trial = [[text attributedSubstringFromRange:NSMakeRange(0, cut)] mutableCopy];
    NSDictionary* attributes = text.length
        ? [text attributesAtIndex:cut ? cut - 1 : 0 effectiveRange:NULL] : nil;
    [trial appendAttributedString:[[NSAttributedString alloc] initWithString:@"…" attributes:attributes]];
    if (trial.size.width <= width) {
      best = trial;
      low = middle + 1;
    } else high = middle - 1;
  }
  [text setAttributedString:best];
}

NSAttributedString* MatchText(const AutocompleteMatch& match, NSFont* font,
                              CGFloat width) {
  NSMutableAttributedString* result = DecorateMatchedString(
      match.contents, match.contents_class, NSColor.blackColor, font);
  if (!match.description.empty()) {
    ElideString(result, std::max<CGFloat>(0, width - kTextXOffset) * kMaxContentsFraction);
    [result appendAttributedString:[[NSAttributedString alloc] initWithString:@" – "
        attributes:@{NSFontAttributeName:font, NSForegroundColorAttributeName:NSColor.blackColor}]];
    [result appendAttributedString:DecorateMatchedString(
        match.description, match.description_class, NSColor.darkGrayColor, font)];
  }
  NSMutableParagraphStyle* style = [[NSMutableParagraphStyle alloc] init];
  style.lineBreakMode = NSLineBreakByTruncatingTail;
  style.tighteningFactorForTruncation = 0;
  [result addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, result.length)];
  return result;
}

NSImage* ImageForMatch(const AutocompleteMatch& match, OmniboxEditModel* model) {
  NSString* name = @"omnibox_http.pdf";
  if (model->IsStarredMatch(match)) name = @"omnibox_star.pdf";
  else if (match.type == AutocompleteMatchType::HISTORY_URL ||
           match.type == AutocompleteMatchType::HISTORY_TITLE ||
           match.type == AutocompleteMatchType::HISTORY_BODY ||
           match.type == AutocompleteMatchType::HISTORY_KEYWORD ||
           match.type == AutocompleteMatchType::SEARCH_HISTORY)
    name = @"omnibox_history.pdf";
  else if (AutocompleteMatch::IsSearchType(match.type)) name = @"omnibox_search.pdf";
  NSString* path = [[[NSBundle.mainBundle resourcePath]
      stringByAppendingPathComponent:@"Cocoa2010"] stringByAppendingPathComponent:name];
  static NSMutableDictionary* images = [NSMutableDictionary dictionary];
  NSImage* image = [images objectForKey:path];
  if (!image) {
    image = [[NSImage alloc] initWithContentsOfFile:path];
    if (image) [images setObject:image forKey:path];
  }
  return image;
}

class NativeOmniboxPopup;
struct PopupRow {
  size_t match;
  bool header;
};
}

@interface Cocoa2010AutocompleteButtonCell : NSButtonCell
@property(nonatomic) CGFloat textWidth;
@end

@interface Cocoa2010AutocompleteMatrix : NSMatrix
@property(nonatomic) NativeOmniboxPopup* popupView;
- (instancetype)initWithPopupView:(NativeOmniboxPopup*)popup;
- (void)highlightRowAt:(NSInteger)row;
- (NSInteger)highlightedRow;
@end

@interface Cocoa2010PopupAction : NSObject
@property(nonatomic) NativeOmniboxPopup* popupView;
@property(nonatomic) size_t match;
@property(nonatomic) OmniboxPopupSelection::LineState state;
@property(nonatomic) size_t actionIndex;
@property(nonatomic, strong) NSButton* button;
- (void)activate:(id)sender;
- (void)parentClosed:(NSNotification*)notification;
- (void)parentMoved:(NSNotification*)notification;
@end

namespace {
class NativeOmniboxPopup final : public OmniboxPopupView {
 public:
  NativeOmniboxPopup(OmniboxView* view, OmniboxController* controller)
      : OmniboxPopupView(controller), view_(view) {
    model()->set_popup_view(this);
  }
  ~NativeOmniboxPopup() override {
    Close();
    model()->set_popup_view(nullptr);
  }
  bool IsOpen() const override { return popup_.visible; }
  void InvalidateLine(size_t line) override {
    if (matrix_) matrix_.needsDisplay = YES;
  }
  void OnSelectionChanged(OmniboxPopupSelection, OmniboxPopupSelection) override {
    SyncSelection();
  }
  void ProvideButtonFocusHint(size_t line) override { SyncSelection(); }
  void OnMatchIconUpdated(size_t match) override { InvalidateLine(match); }
  void OnDragCanceled() override { [matrix_ highlightRowAt:-1]; }
  void GetPopupAccessibleNodeData(ui::AXNodeData* data) override {
    data->role = ax::mojom::Role::kListBox;
  }
  void AddPopupAccessibleNodeData(ui::AXNodeData* data) override {
    data->SetHasPopup(ax::mojom::HasPopup::kListbox);
    if (IsOpen()) data->AddState(ax::mojom::State::kExpanded);
    else data->AddState(ax::mojom::State::kCollapsed);
  }
  std::u16string GetAccessibleButtonTextForResult(size_t line) override {
    auto selection = model()->GetPopupSelection();
    if (line >= Result().size()) return {};
    const auto& match = Result().match_at(line);
    if (selection.state == OmniboxPopupSelection::FOCUSED_BUTTON_ACTION &&
        selection.action_index < match.actions.size())
      return match.actions[selection.action_index]->GetLabelStrings().accessibility_hint;
    return {};
  }
  void SetSuggestionGroupVisibility(size_t, bool) override { UpdatePopupAppearance(); }

  void Close() {
    [NSNotificationCenter.defaultCenter removeObserver:observer_];
    observer_.popupView = nullptr;
    observer_ = nil;
    for (Cocoa2010PopupAction* action in actions_) action.popupView = nullptr;
    actions_ = nil;
    matrix_.popupView = nullptr;
    [popup_.parentWindow removeChildWindow:popup_];
    [popup_ orderOut:nil];
    // NSWindow normally releases itself on close. This C++ object owns it.
    popup_.releasedWhenClosed = NO;
    [popup_ close];
    matrix_ = nil;
    popup_ = nil;
    rows_.clear();
  }

  void PositionPopup() {
    NSTextField* field = cocoa2010::OmniboxFieldForView(view_);
    if (!popup_ || !field.window) return;
    NSRect frame = [field convertRect:NSInsetRect(field.bounds, 0, 1) toView:nil];
    frame.origin = [field.window convertBaseToScreen:frame.origin];
    CGFloat width = (NSWidth(frame) - 2) / popup_.userSpaceScaleFactor;
    if (std::abs(width - matrix_.cellSize.width) > 0.1) {
      UpdatePopupAppearance();
      return;
    }
    frame.size.height = rows_.size() * matrix_.cellSize.height * popup_.userSpaceScaleFactor;
    frame.origin.y -= frame.size.height + 1 + kPopupFieldGap * popup_.userSpaceScaleFactor;
    frame = NSInsetRect(frame, 1, 0);
    // Native AppKit drawing and window shadow; no Views/IOSurface compositor.
    // Snap asynchronous updates to avoid animating outdated row hit regions.
    [popup_ setFrame:frame display:YES];
    if (!IsOpen()) [field.window addChildWindow:popup_ ordered:NSWindowAbove];
    [popup_ orderFront:nil];
  }

  void UpdatePopupAppearance() override {
    NSTextField* field = cocoa2010::OmniboxFieldForView(view_);
    if (!field.window || Result().empty() || cocoa2010::OmniboxIsComposing(view_)) {
      Close();
      return;
    }
    if (!popup_) {
      popup_ = [[NSWindow alloc] initWithContentRect:NSZeroRect
          styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:YES];
      popup_.releasedWhenClosed = NO;
      popup_.movableByWindowBackground = NO;
      popup_.opaque = NO;
      popup_.backgroundColor = NSColor.clearColor;
      popup_.hasShadow = YES;
      popup_.level = NSNormalWindowLevel;
      matrix_ = [[Cocoa2010AutocompleteMatrix alloc] initWithPopupView:this];
      popup_.contentView = matrix_;
      observer_ = [[Cocoa2010PopupAction alloc] init];
      observer_.popupView = this;
      for (NSString* name in @[NSWindowWillCloseNotification, NSWindowDidMoveNotification,
                              NSWindowDidResizeNotification])
        [NSNotificationCenter.defaultCenter addObserver:observer_
            selector:[name isEqualToString:NSWindowWillCloseNotification] ? @selector(parentClosed:) : @selector(parentMoved:)
            name:name object:field.window];
    }
    rows_.clear();
    std::u16string previous_header;
    for (size_t i = 0; i < Result().size(); ++i) {
      const auto& match = Result().match_at(i);
      std::u16string header = match.suggestion_group_id.has_value()
          ? Result().GetHeaderForSuggestionGroup(match.suggestion_group_id.value()) : u"";
      if (!header.empty() && header != previous_header) rows_.push_back({i, true});
      previous_header = header;
      if (controller()->IsSuggestionHidden(match) ||
          (match.suggestion_group_id.has_value() &&
           controller()->IsSuggestionGroupHidden(match.suggestion_group_id.value()))) continue;
      rows_.push_back({i, false});
    }
    if (rows_.empty()) { Close(); return; }
    for (Cocoa2010PopupAction* action in actions_) action.popupView = nullptr;
    for (NSView* button in [matrix_.subviews copy]) [button removeFromSuperview];
    actions_ = [NSMutableArray array];
    [matrix_ renewRows:rows_.size() columns:1];
    NSFont* font = [NSFont fontWithName:field.font.fontName size:field.font.pointSize - 1];
    if (!font) font = [NSFont systemFontOfSize:12];
    CGFloat width = std::max<CGFloat>(1, NSWidth([field convertRect:field.bounds toView:nil]) - 2);
    for (size_t i = 0; i < rows_.size(); ++i) {
      auto row = rows_[i];
      const auto& match = Result().match_at(row.match);
      Cocoa2010AutocompleteButtonCell* cell = [matrix_ cellAtRow:i column:0];
      cell.font = font;
      cell.image = row.header ? nil : ImageForMatch(match, model());
      cell.attributedTitle = row.header ? [[NSAttributedString alloc]
          initWithString:base::SysUTF16ToNSString(Result().GetHeaderForSuggestionGroup(match.suggestion_group_id.value()))
          attributes:@{NSFontAttributeName:font, NSForegroundColorAttributeName:NSColor.darkGrayColor}]
          : MatchText(match, font, width);
      cell.textWidth = width;
    }
    CGFloat height = [[matrix_ cellAtRow:0 column:0] cellSize].height + kCellHeightAdjust;
    matrix_.cellSize = NSMakeSize(width, height);
    // Newer optional controls use compact native buttons in the same row.
    for (size_t i = 0; i < rows_.size(); ++i) {
      auto row = rows_[i];
      const auto& match = Result().match_at(row.match);
      CGFloat right = width - 4;
      auto add_button = [&](NSString* title, OmniboxPopupSelection::LineState state, size_t index) {
        CGFloat button_width = std::min<CGFloat>(160, std::max<CGFloat>(20,
            [title sizeWithAttributes:@{NSFontAttributeName:font}].width + 12));
        if (right - button_width < width * 0.6) return;
        Cocoa2010PopupAction* action = [[Cocoa2010PopupAction alloc] init];
        action.popupView = this; action.match = row.match; action.state = state; action.actionIndex = index;
        NSButton* button = [[NSButton alloc] initWithFrame:NSMakeRect(right - button_width,
            i * height + 2, button_width, height - 4)];
        button.font = font; button.title = title; button.bezelStyle = NSSmallSquareBezelStyle;
        button.target = action; button.action = @selector(activate:); button.focusRingType = NSFocusRingTypeExterior;
        action.button = button;
        [matrix_ addSubview:button]; [actions_ addObject:action];
        right -= button_width + 4;
      };
      if (row.header) {
        add_button(controller()->IsSuggestionGroupHidden(match.suggestion_group_id.value()) ? @"▸" : @"▾",
                   OmniboxPopupSelection::FOCUSED_BUTTON_HEADER, 0);
      } else {
        if (model()->IsPopupControlPresentOnMatch(OmniboxPopupSelection(row.match,
            OmniboxPopupSelection::FOCUSED_BUTTON_REMOVE_SUGGESTION)))
          add_button(@"×", OmniboxPopupSelection::FOCUSED_BUTTON_REMOVE_SUGGESTION, 0);
        for (size_t j = match.actions.size(); j > 0; --j)
          add_button(base::SysUTF16ToNSString(match.actions[j - 1]->GetLabelStrings().hint),
                     OmniboxPopupSelection::FOCUSED_BUTTON_ACTION, j - 1);
      }
      Cocoa2010AutocompleteButtonCell* cell = [matrix_ cellAtRow:i column:0];
      cell.textWidth = right;
      if (!row.header) cell.attributedTitle = MatchText(match, font, right);
    }
    SyncSelection();
    matrix_.needsDisplay = YES;
    PositionPopup();
    [popup_ displayIfNeeded];
    [popup_ invalidateShadow];
  }

  bool SelectRow(NSInteger row) {
    if (row < 0 || static_cast<size_t>(row) >= rows_.size()) return false;
    auto entry = rows_[row];
    model()->SetPopupSelection(OmniboxPopupSelection(entry.match, entry.header
        ? OmniboxPopupSelection::FOCUSED_BUTTON_HEADER : OmniboxPopupSelection::NORMAL));
    return true;
  }
  void OpenRow(NSInteger row, bool background) {
    if (row < 0 || static_cast<size_t>(row) >= rows_.size()) return;
    auto entry = rows_[row];
    OpenControl(entry.match, entry.header ? OmniboxPopupSelection::FOCUSED_BUTTON_HEADER
                                        : OmniboxPopupSelection::NORMAL, 0, background);
  }
  void OpenControl(size_t match, OmniboxPopupSelection::LineState state,
                   size_t index, bool background = false) {
    if (match >= Result().size()) return;
    // OpenSelection owns current navigation, actions and deletion. It may
    // synchronously close this popup; do not access cells after this call.
    model()->OpenSelection(OmniboxPopupSelection(match, state, index), base::TimeTicks::Now(),
        background ? WindowOpenDisposition::NEW_BACKGROUND_TAB
                   : ui::WindowOpenDispositionFromNSEvent(NSApp.currentEvent));
  }

 private:
  const AutocompleteResult& Result() const { return controller()->autocomplete_controller()->result(); }
  void SyncSelection() {
    if (!matrix_) return;
    auto selection = model()->GetPopupSelection();
    [matrix_ deselectAllCells];
    for (size_t i = 0; i < rows_.size(); ++i)
      if (rows_[i].match == selection.line &&
          rows_[i].header == (selection.state == OmniboxPopupSelection::FOCUSED_BUTTON_HEADER))
        [matrix_ selectCellAtRow:i column:0];
    for (Cocoa2010PopupAction* action in actions_) {
      action.button.showsBorderOnlyWhileMouseInside = NO;
      [action.button highlight:action.match == selection.line && action.state == selection.state &&
                               action.actionIndex == selection.action_index];
    }
    matrix_.needsDisplay = YES;
  }
  OmniboxView* view_;  // owns this popup
  NSWindow* __strong popup_ = nil;
  Cocoa2010AutocompleteMatrix* __strong matrix_ = nil;
  Cocoa2010PopupAction* __strong observer_ = nil;
  NSMutableArray<Cocoa2010PopupAction*>* __strong actions_ = nil;
  std::vector<PopupRow> rows_;
};
}

@implementation Cocoa2010PopupAction
@synthesize popupView = _popupView, match = _match, state = _state, actionIndex = _actionIndex, button = _button;
- (void)activate:(id)sender {
  if (_popupView) _popupView->OpenControl(_match, _state, _actionIndex);
}
- (void)parentClosed:(NSNotification*)notification { if (_popupView) _popupView->Close(); }
- (void)parentMoved:(NSNotification*)notification { if (_popupView) _popupView->PositionPopup(); }
@end

@implementation Cocoa2010AutocompleteButtonCell
@synthesize textWidth = _textWidth;
- (instancetype)init {
  if ((self = [super init])) {
    self.imagePosition = NSImageLeft;
    self.bordered = NO;
    [self setButtonType:NSRadioButton];
    self.highlightsBy = NSNoCellMask;
  }
  return self;
}
- (NSColor*)backgroundColor {
  return self.state == NSOnState ? SelectedBackgroundColor()
      : self.highlighted ? HoveredBackgroundColor() : BackgroundColor();
}
- (void)drawInteriorWithFrame:(NSRect)frame inView:(NSView*)view {
  [[self backgroundColor] set];
  NSRectFill(frame);
  if (self.image) {
    NSRect imageRect = frame;
    imageRect.size = self.image.size;
    imageRect.origin.y += std::floor((NSHeight(frame) - NSHeight(imageRect)) / 2);
    imageRect.origin.x += kImageXOffset;
    [self.image drawInRect:imageRect fromRect:NSZeroRect operation:NSCompositeSourceOver
                 fraction:1 respectFlipped:YES hints:nil];
  }
  if (self.attributedTitle.length) {
    NSRect titleRect = frame;
    titleRect.size.width = std::max<CGFloat>(0, std::min(NSWidth(frame), self.textWidth) - kTextXOffset);
    titleRect.origin.x += kTextXOffset;
    [self drawTitle:self.attributedTitle withFrame:titleRect inView:view];
  }
}
@end

@implementation Cocoa2010AutocompleteMatrix
@synthesize popupView = _popupView;
- (instancetype)initWithPopupView:(NativeOmniboxPopup*)popup {
  if ((self = [super initWithFrame:NSZeroRect])) {
    _popupView = popup;
    self.cellClass = Cocoa2010AutocompleteButtonCell.class;
    self.intercellSpacing = NSZeroSize;
    self.drawsBackground = YES;
    self.backgroundColor = BackgroundColor();
    [self renewRows:0 columns:1];
    self.allowsEmptySelection = YES;
    self.mode = NSRadioModeMatrix;
    [self deselectAllCells];
  }
  return self;
}
- (BOOL)acceptsFirstResponder { return NO; }
- (void)updateTrackingAreas {
  for (NSTrackingArea* area in [self.trackingAreas copy]) [self removeTrackingArea:area];
  NSTrackingArea* area = [[NSTrackingArea alloc] initWithRect:self.bounds
      options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved |
              NSTrackingActiveInActiveApp | NSTrackingInVisibleRect
      owner:self userInfo:nil];
  [self addTrackingArea:area];
  [super updateTrackingAreas];
}
- (void)highlightRowAt:(NSInteger)row {
  NSCell* highlight = [self cellAtRow:row column:0];
  for (NSCell* cell in self.cells) cell.highlighted = cell == highlight;
  self.needsDisplay = YES;
}
- (NSInteger)rowForEvent:(NSEvent*)event {
  NSInteger row = -1, column = -1;
  NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
  return [self getRow:&row column:&column forPoint:point] ? row : -1;
}
- (void)highlightRowUnder:(NSEvent*)event { [self highlightRowAt:[self rowForEvent:event]]; }
- (void)mouseEntered:(NSEvent*)event { [self highlightRowUnder:event]; }
- (void)mouseMoved:(NSEvent*)event { [self highlightRowUnder:event]; }
- (void)mouseExited:(NSEvent*)event { [self highlightRowAt:-1]; }
- (void)otherMouseDown:(NSEvent*)event {
  if (event.buttonNumber == 2) [self highlightRowUnder:event];
  [super otherMouseDown:event];
}
- (void)otherMouseDragged:(NSEvent*)event {
  if (event.buttonNumber == 2) [self highlightRowUnder:event];
  [super otherMouseDragged:event];
}
- (void)otherMouseUp:(NSEvent*)event {
  if (event.buttonNumber != 2) { [super otherMouseUp:event]; return; }
  [self highlightRowUnder:event];
  if (_popupView) _popupView->OpenRow(self.highlightedRow, true);
}
- (void)mouseDown:(NSEvent*)event {
  NSCell* selected = self.selectedCell;
  [self highlightRowAt:-1];
  do {
    if (!_popupView) return;
    if (!_popupView->SelectRow([self rowForEvent:event])) [self selectCell:selected];
    event = [self.window nextEventMatchingMask:NSLeftMouseUpMask | NSLeftMouseDraggedMask];
  } while (event.type == NSLeftMouseDragged);
  if (!_popupView) return;
  NSInteger row = [self rowForEvent:event];
  if (!_popupView->SelectRow(row)) [self selectCell:selected];
  else if (_popupView) _popupView->OpenRow(row, false);
}
- (NSInteger)highlightedRow {
  NSArray* cells = self.cells;
  for (NSUInteger i = 0; i < cells.count; ++i) if ([[cells objectAtIndex:i] isHighlighted]) return i;
  return -1;
}
- (BOOL)isOpaque { return NO; }
- (void)drawRect:(NSRect)rect {
  NSBezierPath* path = [NSBezierPath bezierPathWithRoundedRect:self.bounds
      xRadius:kPopupRoundingRadius yRadius:kPopupRoundingRadius];
  [NSGraphicsContext saveGraphicsState];
  [path addClip];
  [super drawRect:rect];
  [NSGraphicsContext restoreGraphicsState];
}
@end

namespace cocoa2010 {
std::unique_ptr<OmniboxPopupView> CreateOmniboxPopup(
    OmniboxView* view, OmniboxController* controller, Browser* browser) {
  if (!EnabledByFlag() || !browser || !browser->is_type_normal()) return nullptr;
  return std::make_unique<NativeOmniboxPopup>(view, controller);
}
}
