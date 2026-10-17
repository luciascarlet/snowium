// Copyright 2026 Snowium contributors. BSD license.
// Adapters from the actual Cocoa controls to Chromium 124 browser models.
#import "chrome/browser/ui/cocoa2010/browser_adapter.h"
#import "chrome/browser/ui/cocoa2010/controls.h"
#import "chrome/browser/ui/cocoa2010/bookmark_bar.h"
#include "chrome/browser/ui/views/bookmarks/bookmark_bar_view.h"
#include <memory>
#include <algorithm>
#include <cmath>
#include "base/command_line.h"
#include "base/functional/callback_helpers.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/app/chrome_command_ids.h"
#include "chrome/grit/generated_resources.h"
#include "ui/base/l10n/l10n_util.h"
#include "ui/base/l10n/l10n_util_mac.h"
#include "chrome/browser/bookmarks/bookmark_model_factory.h"
#include "chrome/browser/autocomplete/chrome_autocomplete_scheme_classifier.h"
#include "components/omnibox/browser/autocomplete_input.h"
#include "chrome/browser/favicon/favicon_utils.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/common/pref_names.h"
#include "components/prefs/pref_service.h"
#include "chrome/browser/ssl/security_state_tab_helper.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_commands.h"
#include "chrome/browser/ui/browser_window.h"
#include "chrome/browser/ui/toolbar/app_menu_model.h"
#import "ui/base/cocoa/menu_controller.h"
#import "ui/base/accelerators/platform_accelerator_cocoa.h"
#include "ui/base/models/button_menu_item_model.h"
#include "chrome/browser/ui/page_info/page_info_dialog.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model_observer.h"
#include "chrome/browser/ui/views/frame/browser_view.h"
#include "chrome/browser/ui/views/location_bar/location_bar_view.h"
#include "chrome/browser/ui/views/tabs/tab_strip.h"
#include "ui/base/ui_base_types.h"
#include "chrome/browser/ui/views/omnibox/omnibox_view_views.h"
#include "components/bookmarks/browser/bookmark_model.h"
#include "components/omnibox/browser/omnibox_edit_model.h"
#include "components/omnibox/browser/autocomplete_match.h"
#include "components/security_state/core/security_state.h"
#include "content/public/browser/web_contents.h"
#include "ui/gfx/image/image.h"
#include "ui/gfx/range/range.h"
#include "ui/views/widget/widget.h"

namespace {
bool HasEnabledMenuItems(ui::MenuModel* model) {
  for (size_t i = 0; i < model->GetItemCount(); ++i) {
    if (!model->IsVisibleAt(i) || model->GetTypeAt(i) == ui::MenuModel::TYPE_SEPARATOR) continue;
    if (model->GetTypeAt(i) == ui::MenuModel::TYPE_SUBMENU) {
      if (HasEnabledMenuItems(model->GetSubmenuModelAt(i))) return true;
    } else if (model->IsEnabledAt(i)) return true;
  }
  return false;
}
}

// Use Chromium's native menu bridge for the current model. The two button
// rows become ordinary AppKit submenus, retaining their current commands.
@interface Cocoa2010MenuButtonTarget : NSObject <NSUserInterfaceValidations>
@property(nonatomic) ui::ButtonMenuItemModel* model;
@property(nonatomic) size_t index;
- (void)activate:(id)sender;
@end
@implementation Cocoa2010MenuButtonTarget
- (void)activate:(id)sender { self.model->ActivatedAt(self.index); }
- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
  return self.model->IsEnabledAt(self.index);
}
@end
@interface Cocoa2010MenuBridge : NSObject <MenuControllerCocoaDelegate>
@property(nonatomic, strong) NSMutableArray* buttonTargets;
@end
@implementation Cocoa2010MenuBridge
- (instancetype)init { if ((self = [super init])) _buttonTargets = [NSMutableArray array]; return self; }
- (void)controllerWillAddMenu:(NSMenu*)menu fromModel:(ui::MenuModel*)model {}
- (void)controllerWillAddItem:(NSMenuItem*)item fromModel:(ui::MenuModel*)model atIndex:(size_t)index {
  ui::Accelerator accelerator;
  if (model->GetAcceleratorAt(index, &accelerator)) {
    KeyEquivalentAndModifierMask* key = ui::GetKeyEquivalentAndModifierMaskFromAccelerator(accelerator);
    item.keyEquivalent = key.keyEquivalent; item.keyEquivalentModifierMask = key.modifierMask;
  }
  if (model->GetTypeAt(index) == ui::MenuModel::TYPE_SUBMENU) {
    // These group IDs are not executable browser commands on Mac. Leaf
    // commands still use the model's current policy and enabled state.
    item.enabled = HasEnabledMenuItems(model->GetSubmenuModelAt(index));
  }
  if (model->GetTypeAt(index) != ui::MenuModel::TYPE_BUTTON_ITEM) return;
  ui::ButtonMenuItemModel* buttons = model->GetButtonMenuItemAt(index);
  if (!item.title.length) item.title = l10n_util::FixUpWindowsStyleLabel(buttons->label());
  NSMenu* submenu = [[NSMenu alloc] initWithTitle:item.title];
  for (size_t i = 0; i < buttons->GetItemCount(); ++i) {
    if (buttons->GetTypeAt(i) == ui::ButtonMenuItemModel::TYPE_SPACE) continue;
    NSString* title = l10n_util::FixUpWindowsStyleLabel(buttons->GetLabelAt(i));
    switch (buttons->GetCommandIdAt(i)) {
      case IDC_ZOOM_MINUS: title = l10n_util::FixUpWindowsStyleLabel(l10n_util::GetStringUTF16(IDS_ZOOM_MINUS)); break;
      case IDC_ZOOM_PLUS: title = l10n_util::FixUpWindowsStyleLabel(l10n_util::GetStringUTF16(IDS_ZOOM_PLUS)); break;
      case IDC_FULLSCREEN: title = l10n_util::FixUpWindowsStyleLabel(l10n_util::GetStringUTF16(IDS_FULLSCREEN)); break;
      default: break;
    }
    if (!title.length) {
      switch (buttons->GetCommandIdAt(i)) {
        case IDC_ZOOM_MINUS: title = @"Zoom Out"; break;
        case IDC_ZOOM_PLUS: title = @"Zoom In"; break;
        case IDC_FULLSCREEN: title = @"Full Screen"; break;
        default: continue;
      }
    }
    NSMenuItem* button = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
    if (buttons->GetTypeAt(i) == ui::ButtonMenuItemModel::TYPE_BUTTON) {
      Cocoa2010MenuButtonTarget* target = [[Cocoa2010MenuButtonTarget alloc] init];
      target.model = buttons; target.index = i; [self.buttonTargets addObject:target];
      button.target = target; button.action = @selector(activate:);
      if (buttons->GetAcceleratorAt(i, &accelerator)) {
        KeyEquivalentAndModifierMask* key = ui::GetKeyEquivalentAndModifierMaskFromAccelerator(accelerator);
        button.keyEquivalent = key.keyEquivalent; button.keyEquivalentModifierMask = key.modifierMask;
      }
    } else button.enabled = NO;
    [submenu addItem:button];
  }
  item.submenu = submenu;
  item.enabled = YES;
}
@end

@class Cocoa2010BrowserAdapter;
namespace {
class TabObserver : public TabStripModelObserver {
 public:
  TabObserver(BrowserView* view, Cocoa2010BrowserAdapter* adapter);
  ~TabObserver() override;
  void OnTabStripModelChanged(TabStripModel*, const TabStripModelChange&,
                             const TabStripSelectionChange&) override;
  void TabChangedAt(content::WebContents*, int, TabChangeType) override;
 private:
  BrowserView* view_;
  Cocoa2010BrowserAdapter* __unsafe_unretained adapter_;
};
NSMutableDictionary<NSValue*, Cocoa2010BrowserAdapter*>* Sessions() {
  static NSMutableDictionary* sessions = [[NSMutableDictionary alloc] init];
  return sessions;
}
NSValue* Key(const BrowserView* view) { return [NSValue valueWithPointer:view]; }
OmniboxViewViews* Omnibox(BrowserView* view) {
  auto* bar = view->GetLocationBarView();
  return bar ? bar->omnibox_view() : nullptr;
}
}

@interface Cocoa2010BrowserAdapter : NSObject <Cocoa2010BrowserDelegate> {
 @public
  BrowserView* _view;
  Cocoa2010WindowController* _controller;
  Cocoa2010BookmarkBarController* _bookmarks;
  std::unique_ptr<TabObserver> _observer;
  BOOL _nativeChange;
}
- (instancetype)initWithView:(BrowserView*)view window:(NSWindow*)window;
- (void)snapshot:(BOOL)animate;
- (void)invalidate;
- (void)updateLocationIcon;
- (void)styleOmnibox;
@end
@implementation Cocoa2010BrowserAdapter
- (instancetype)initWithView:(BrowserView*)view window:(NSWindow*)window {
  if ((self = [super init])) {
    _view = view;
    NSString* resources = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"Cocoa2010"];
    _controller = [[Cocoa2010WindowController alloc] initWithWindow:window delegate:self resources:resources];
    _bookmarks = [[Cocoa2010BookmarkBarController alloc] initWithBrowser:view->browser() window:window resources:resources];
    _observer = std::make_unique<TabObserver>(view, self);
  }
  return self;
}
- (void)invalidate {
  _observer.reset();
  [_bookmarks invalidate]; _bookmarks = nil;
  [_controller invalidate]; _controller = nil; _view = nullptr;
}
- (void)dealloc { [self invalidate]; }
- (int)indexForIdentity:(uintptr_t)identity {
  if (!_view) return -1;
  auto* model = _view->browser()->tab_strip_model();
  for (int i = 0; i < model->count(); ++i)
    if (reinterpret_cast<uintptr_t>(model->GetWebContentsAt(i)) == identity) return i;
  return -1;
}
- (void)snapshot:(BOOL)animate {
  if (!_view || !_view->toolbar()) return;
  auto* model = _view->browser()->tab_strip_model();
  NSMutableArray* tabs = [NSMutableArray array];
  for (int i = 0; i < model->count(); ++i) {
    content::WebContents* contents = model->GetWebContentsAt(i);
    Cocoa2010TabData* data = [[Cocoa2010TabData alloc] init];
    data.identity = reinterpret_cast<uintptr_t>(contents);
    data.title = base::SysUTF16ToNSString(contents->GetTitle());
    if (!data.title.length) data.title = @"Untitled";
    data.selected = i == model->active_index(); data.pinned = model->IsTabPinned(i);
    data.loading = contents->IsLoading();
    data.waiting = contents->IsWaitingForResponse();
    gfx::Image icon(favicon::TabFaviconFromWebContents(contents));
    if (!icon.IsEmpty()) data.icon = icon.AsNSImage();
    [tabs addObject:data];
  }
  [_controller updateTabs:tabs animate:animate];
  content::WebContents* active = model->GetActiveWebContents();
  auto* omnibox = Omnibox(_view);
  NSString* url = omnibox ? base::SysUTF16ToNSString(omnibox->model()->GetPermanentDisplayText()) : @"";
  auto* bookmarks = BookmarkModelFactory::GetForBrowserContext(_view->browser()->profile());
  auto* security = active ? SecurityStateTabHelper::FromWebContents(active) : nullptr;
  BOOL secure = security && security->GetSecurityLevel() == security_state::SECURE;
  BOOL starred = active && bookmarks && bookmarks->IsBookmarked(active->GetVisibleURL());
  [_controller updateURL:url loading:active && active->IsLoading() starred:starred secure:secure
                showHome:_view->browser()->profile()->GetPrefs()->GetBoolean(prefs::kShowHomeButton)];
  [self updateLocationIcon];
  [self styleOmnibox];
}
- (void)updateLocationIcon {
  auto* omnibox = _view ? Omnibox(_view) : nullptr;
  if (!omnibox) return;
  NSString* icon = @"omnibox_http.pdf";
  if (omnibox->model()->user_input_in_progress() || omnibox->GetText().empty()) {
    const auto match = omnibox->model()->CurrentMatch(nullptr);
    if (AutocompleteMatch::IsSearchType(match.type)) icon = @"omnibox_search.pdf";
    else if (match.type == AutocompleteMatchType::HISTORY_URL ||
             match.type == AutocompleteMatchType::HISTORY_TITLE ||
             match.type == AutocompleteMatchType::HISTORY_BODY)
      icon = @"omnibox_history.pdf";
  } else {
    auto* active = _view->browser()->tab_strip_model()->GetActiveWebContents();
    auto* security = active ? SecurityStateTabHelper::FromWebContents(active) : nullptr;
    if (security) {
      switch (security->GetSecurityLevel()) {
        case security_state::SECURE: icon = @"omnibox_https_valid.pdf"; break;
        case security_state::DANGEROUS: icon = @"omnibox_https_invalid.pdf"; break;
        default: break;
      }
    }
  }
  [_controller updateLocationIcon:icon];
}
// Ported from AutocompleteEditViewMac::ApplyTextAttributes (Chromium 7).
- (void)styleOmnibox {
  auto* view = _view ? Omnibox(_view) : nullptr;
  if (!view) return;
  const std::u16string value = _controller.editing ? view->GetText() : view->model()->GetPermanentDisplayText();
  NSMutableAttributedString* text = [[NSMutableAttributedString alloc]
      initWithString:base::SysUTF16ToNSString(value)];
  NSRange all = NSMakeRange(0, text.length);
  [text addAttribute:NSFontAttributeName value:_controller.field.font range:all];
  [text addAttribute:NSForegroundColorAttributeName value:NSColor.blackColor range:all];
  NSMutableParagraphStyle* paragraph = [[NSMutableParagraphStyle alloc] init];
  NSLayoutManager* layout = [[NSLayoutManager alloc] init];
  layout.usesScreenFonts = YES;
  paragraph.maximumLineHeight = [layout defaultLineHeightForFont:_controller.field.font];
  paragraph.lineBreakMode = NSLineBreakByClipping;
  [text addAttribute:NSParagraphStyleAttributeName value:paragraph range:all];
  url::Component scheme, host;
  AutocompleteInput::ParseForEmphasizeComponents(value,
      ChromeAutocompleteSchemeClassifier(_view->browser()->profile()), &scheme, &host);
  if (view->model()->CurrentTextIsURL() && host.is_nonempty()) {
    [text addAttribute:NSForegroundColorAttributeName value:NSColor.darkGrayColor range:all];
    [text addAttribute:NSForegroundColorAttributeName value:NSColor.blackColor
        range:NSMakeRange(host.begin, host.len)];
  }
  auto* active = _view->browser()->tab_strip_model()->GetActiveWebContents();
  auto* security = active ? SecurityStateTabHelper::FromWebContents(active) : nullptr;
  if (!view->model()->user_input_in_progress() && scheme.is_nonempty() && security) {
    NSRange range = NSMakeRange(scheme.begin, scheme.len);
    if (security->GetSecurityLevel() == security_state::SECURE) {
      [text addAttribute:NSForegroundColorAttributeName value:
          [NSColor colorWithCalibratedRed:7.0/255 green:149.0/255 blue:0 alpha:1] range:range];
    } else if (security->GetSecurityLevel() == security_state::DANGEROUS) {
      [text addAttribute:NSForegroundColorAttributeName value:
          [NSColor colorWithCalibratedRed:162.0/255 green:0 blue:0 alpha:1] range:range];
      [text addAttribute:NSStrikethroughStyleAttributeName value:@(NSUnderlineStyleSingle) range:range];
    }
  }
  [_controller applyOmniboxAttributes:text];
}
- (void)showApplicationMenuFromView:(NSView*)view {
  if (!_view) return;
  __attribute__((objc_precise_lifetime)) Cocoa2010BrowserAdapter* keepAlive = self;
  (void)keepAlive;
  AppMenuModel model(_view, _view->browser());
  model.Init();
  Cocoa2010MenuBridge* bridge = [[Cocoa2010MenuBridge alloc] init];
  MenuControllerCocoa* controller = [[MenuControllerCocoa alloc]
      initWithModel:&model delegate:bridge useWithPopUpButtonCell:NO];
  [controller.menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, 0) inView:view];
}
- (void)executeCommand:(NSInteger)command {
  if (_view && chrome::IsCommandEnabled(_view->browser(), command))
    chrome::ExecuteCommand(_view->browser(), command);
}
- (BOOL)isCommandEnabled:(NSInteger)command {
  return _view && chrome::IsCommandEnabled(_view->browser(), command);
}
- (void)activateTab:(uintptr_t)identity {
  int index = [self indexForIdentity:identity];
  if (index >= 0) _view->browser()->tab_strip_model()->ActivateTabAt(index);
}
- (void)closeTab:(uintptr_t)identity {
  int index = [self indexForIdentity:identity];
  if (index >= 0) _view->browser()->tab_strip_model()->CloseWebContentsAt(index, CLOSE_USER_GESTURE);
}
- (void)moveTab:(uintptr_t)identity toIndex:(NSInteger)index {
  int from = [self indexForIdentity:identity];
  if (from < 0) return;
  auto* model = _view->browser()->tab_strip_model();
  model->MoveWebContentsAt(from, std::clamp<int>(index, 0, model->count() - 1), true);
}
- (void)dropTab:(uintptr_t)identity atScreenPoint:(NSPoint)point {
  int index = [self indexForIdentity:identity];
  if (index < 0) return;
  auto* source = _view->browser()->tab_strip_model();
  BrowserView* source_view = _view;
  // A tear-off transfers the existing WebContents, preserving navigation and
  // renderer state. Validate destination profile; incognito never crosses it.
  for (Cocoa2010BrowserAdapter* other in [Sessions().allValues copy]) {
    if (!other->_view || other->_view->browser()->profile() != _view->browser()->profile()) continue;
    NSView* root = other->_controller.rootView;
    NSPoint local = [root convertPoint:[root.window convertScreenToBase:point] fromView:nil];
    if (!NSPointInRect(local, NSMakeRect(0, 35, NSWidth(root.bounds), 26))) continue;
    auto* destination = other->_view->browser()->tab_strip_model();
    int target = 0;
    // Resolve insertion by actual Cocoa tab bounds, including pinned tabs.
    for (NSView* child in root.subviews) {
      if (![child isKindOfClass:[Cocoa2010TabView class]]) continue;
      Cocoa2010TabView* tab = (Cocoa2010TabView*)child;
      // Count stationary tabs before the pointer. The dragged tab's moving
      // bounds must not determine its own insertion index.
      if (destination == source && tab.data.identity == identity) continue;
      if (local.x >= NSMidX(tab.frame)) ++target;
    }
    if (destination == source) {
      NSInteger placeholder = [_controller dragInsertionIndexForTab:identity];
      if (placeholder >= 0) target = placeholder;
      [self moveTab:identity toIndex:target];
    } else {
      bool pinned = source->IsTabPinned(index);
      auto contents = source->DetachWebContentsAtForInsertion(index);
      destination->InsertWebContentsAt(target, std::move(contents),
          ADD_ACTIVE | (pinned ? ADD_PINNED : 0));
      other->_view->browser()->window()->Activate();
    }
    return;
  }
  if (source->count() == 1) {
    NSWindow* window = _controller.rootView.window;
    NSRect frame = window.frame;
    frame.origin = NSMakePoint(point.x - 100, point.y - NSHeight(frame) + 14);
    [window setFrame:frame display:YES];
    return;
  }
  // Create a normal Chromium Browser so dialogs, command dispatch and profile
  // ownership retain their current implementations in the detached window.
  Browser::CreateParams params(_view->browser()->profile(), true);
  params.initial_bounds = gfx::Rect(point.x - 100,
      NSMaxY(NSScreen.screens.firstObject.frame) - point.y - 14,
      source_view->GetWidget()->GetWindowBoundsInScreen().width(),
      source_view->GetWidget()->GetWindowBoundsInScreen().height());
  Browser* browser = Browser::Create(params);
  bool pinned = source->IsTabPinned(index);
  auto contents = source->DetachWebContentsAtForInsertion(index);
  browser->tab_strip_model()->InsertWebContentsAt(0, std::move(contents),
      ADD_ACTIVE | (pinned ? ADD_PINNED : 0));
  browser->window()->Show();
}
- (void)showContextMenuForTab:(uintptr_t)identity atScreenPoint:(NSPoint)point {
  int index = [self indexForIdentity:identity];
  if (index < 0) return;
  TabStrip* strip = _view->tabstrip();
  strip->ShowContextMenuForTab(strip->tab_at(index),
      gfx::Point(point.x, NSMaxY(NSScreen.screens.firstObject.frame) - point.y),
      ui::MENU_SOURCE_MOUSE);
}
- (void)omniboxBeganEditing {
  auto* view = Omnibox(_view); if (!view) return;
  view->model()->ResetDisplayTexts();
  view->model()->OnSetFocus(false);
  view->model()->SetCaretVisibility(true);
  [self styleOmnibox];
}
- (void)omniboxChanged:(NSString*)text selection:(NSRange)selection composing:(BOOL)composing {
  auto* view = Omnibox(_view); if (!view) return;
  // Keep native IME marked text local until committed. The modern autocomplete
  // pipeline then receives the same UTF-16 text and selection as NSTextView.
  _nativeChange = YES;
  view->SetUserText(base::SysNSStringToUTF16(text), false);
  view->SetSelectedRange(gfx::Range(selection.location, NSMaxRange(selection)));
  if (!composing) static_cast<OmniboxView*>(view)->UpdatePopup();
  _nativeChange = NO;
  if (!composing) cocoa2010::OmniboxTextChanged(view);
}
- (void)omniboxSelectionChanged:(NSRange)selection {
  if (_nativeChange || !_view) return;
  auto* view = Omnibox(_view);
  if (view) view->SetSelectedRange(gfx::Range(selection.location, NSMaxRange(selection)));
}
- (NSString*)omniboxCopyText:(NSString*)text offset:(NSUInteger)offset {
  if (!_view) return text;
  auto* view = Omnibox(_view); if (!view) return text;
  auto value = base::SysNSStringToUTF16(text); GURL url; bool write_url = false;
  view->model()->AdjustTextForCopy(offset, &value, &url, &write_url);
  return base::SysUTF16ToNSString(value);
}
- (NSString*)omniboxPasteText:(NSString*)text {
  if (_view && Omnibox(_view)) Omnibox(_view)->model()->OnPaste();
  return base::SysUTF16ToNSString(OmniboxView::SanitizeTextForPaste(base::SysNSStringToUTF16(text)));
}
- (void)omniboxEndedEditing {
  auto* view = Omnibox(_view); if (!view) return;
  view->model()->OnWillKillFocus(); view->CloseOmniboxPopup(); view->model()->OnKillFocus();
  [self snapshot:NO];
}
- (BOOL)omniboxCommand:(SEL)selector {
  auto* view = Omnibox(_view); if (!view) return NO;
  if (selector == @selector(insertNewline:)) {
    NSEvent* event = NSApp.currentEvent;
    bool alt = (event.modifierFlags & NSAlternateKeyMask) != 0;
    bool command = (event.modifierFlags & NSCommandKeyMask) != 0;
    view->model()->OpenSelection(base::TimeTicks(), command ? WindowOpenDisposition::NEW_FOREGROUND_TAB :
        alt ? WindowOpenDisposition::NEW_BACKGROUND_TAB : WindowOpenDisposition::CURRENT_TAB);
    return YES;
  }
  if (selector == @selector(cancelOperation:)) {
    view->model()->OnEscapeKeyPressed();
    cocoa2010::OmniboxTextChanged(view); return YES;
  }
  if (selector == @selector(moveDown:) || selector == @selector(moveUp:)) {
    view->model()->OnUpOrDownPressed(selector == @selector(moveDown:), false);
    cocoa2010::OmniboxTextChanged(view); return YES;
  }
  return NO;
}
- (void)showPageInfo {
  auto* active = _view->browser()->tab_strip_model()->GetActiveWebContents();
  if (active) ShowPageInfoDialog(active, base::DoNothing());
}
@end

namespace {
TabObserver::TabObserver(BrowserView* view, Cocoa2010BrowserAdapter* adapter) : view_(view), adapter_(adapter) {
  view_->browser()->tab_strip_model()->AddObserver(this);
}
TabObserver::~TabObserver() { view_->browser()->tab_strip_model()->RemoveObserver(this); }
void TabObserver::OnTabStripModelChanged(TabStripModel*, const TabStripModelChange&, const TabStripSelectionChange&) {
  [adapter_ snapshot:YES];
}
void TabObserver::TabChangedAt(content::WebContents*, int, TabChangeType) { [adapter_ snapshot:NO]; }
Cocoa2010BrowserAdapter* AdapterForOmnibox(const OmniboxView* view) {
  for (Cocoa2010BrowserAdapter* adapter in Sessions().allValues)
    if (adapter->_view && Omnibox(adapter->_view) == view) return adapter;
  return nil;
}
}
namespace cocoa2010 {
bool EnabledByFlag() {
#if defined(SNOW_LEOPARD_PORT)
  const auto* command = base::CommandLine::ForCurrentProcess();
  return command->HasSwitch("enable-cocoa-2010-ui") &&
      !command->HasSwitch("disable-cocoa-2010-ui");
#else
  return false;
#endif
}
bool Enabled(const BrowserView* view) {
  return EnabledByFlag() && view && view->GetIsNormalType();
}
void Install(BrowserView* view, NSWindow* window) {
  if (!Enabled(view) || !window || [Sessions() objectForKey:Key(view)]) return;
  [Sessions() setObject:[[Cocoa2010BrowserAdapter alloc] initWithView:view window:window] forKey:Key(view)];
  if (auto* omnibox = Omnibox(view)) omnibox->SetCursorEnabled(false);
  Update(view);
}
void Uninstall(BrowserView* view) { [[Sessions() objectForKey:Key(view)] invalidate]; [Sessions() removeObjectForKey:Key(view)]; }
void Layout(BrowserView* view) {
  Cocoa2010BrowserAdapter* a = [Sessions() objectForKey:Key(view)]; if (!a) return;
  BookmarkBarView* bar = view->bookmark_bar();
  BOOL visible = bar && bar->GetVisible() && bar->height() > 0;
  [a->_controller setBookmarkBarVisible:visible];
  [a->_controller layout];
  if (visible) {
    gfx::Rect bounds = bar->GetBoundsInScreen();
    CGFloat top = NSMaxY(NSScreen.screens.firstObject.frame);
    [a->_bookmarks layoutWithScreenRect:NSMakeRect(bounds.x(), top-bounds.bottom(), bounds.width(), bounds.height())];
  } else [a->_bookmarks layoutWithScreenRect:NSZeroRect];
}
void Update(BrowserView* view) { [[Sessions() objectForKey:Key(view)] snapshot:NO]; }
void FocusLocation(BrowserView* view) { Cocoa2010BrowserAdapter* a = [Sessions() objectForKey:Key(view)]; if (a) [a->_controller focusLocation]; }
void ShowMenu(BrowserView* view) { Cocoa2010BrowserAdapter* a = [Sessions() objectForKey:Key(view)]; if (a) [a->_controller showToolsMenu]; }
int TabStripHeight() { return kTabStripHeight; }
int ContentTopInset(BrowserView* view) {
  if (!Enabled(view) || !view->GetWidget()) return kChromeHeight;
  NSWindow* window = view->GetWidget()->GetNativeWindow().GetNativeNSWindow();
  if (!window) return kChromeHeight;
  CGFloat titleHeight = NSHeight([window.contentView superview].bounds) - NSHeight(window.contentView.bounds);
  return std::max(0, kChromeHeight - static_cast<int>(std::lround(titleHeight)));
}
gfx::Rect OmniboxBounds(const Browser* browser) {
  auto* view = BrowserView::GetBrowserViewForBrowser(browser);
  Cocoa2010BrowserAdapter* adapter = [Sessions() objectForKey:Key(view)];
  if (!adapter) return {};
  NSRect rect = adapter->_controller.omniboxScreenRect;
  CGFloat screenTop = NSMaxY(NSScreen.screens.firstObject.frame);
  return gfx::Rect(rect.origin.x, screenTop - NSMaxY(rect), rect.size.width, rect.size.height);
}
NSTextField* OmniboxFieldForView(const OmniboxView* view) {
  Cocoa2010BrowserAdapter* adapter = AdapterForOmnibox(view);
  return adapter ? adapter->_controller.field : nil;
}
gfx::Rect OmniboxBoundsForView(const OmniboxView* view) {
  Cocoa2010BrowserAdapter* adapter = AdapterForOmnibox(view);
  return adapter ? OmniboxBounds(adapter->_view->browser()) : gfx::Rect();
}
bool OmniboxHasFocus(const OmniboxView* view) {
  Cocoa2010BrowserAdapter* adapter = AdapterForOmnibox(view);
  return adapter && adapter->_controller.editing;
}
bool OmniboxIsComposing(const OmniboxView* view) {
  Cocoa2010BrowserAdapter* adapter = AdapterForOmnibox(view);
  return adapter && [(NSTextView*)adapter->_controller.field.currentEditor hasMarkedText];
}
void OmniboxTextChanged(const OmniboxView* view) {
  Cocoa2010BrowserAdapter* adapter = AdapterForOmnibox(view);
  if (!adapter || adapter->_nativeChange) return;
  if (!adapter->_controller.editing) {
    // TabStripModel notifies before the omnibox finishes restoring tab state.
    // Publish the settled text as well as changes made by the native editor.
    [adapter snapshot:NO];
    return;
  }
  [adapter updateLocationIcon];
  size_t start = 0, end = 0; view->GetSelectionBounds(&start, &end);
  [adapter->_controller updateEditingText:base::SysUTF16ToNSString(view->GetText())
                               selection:NSMakeRange(std::min(start, end), std::max(start, end) - std::min(start, end))];
  [adapter styleOmnibox];
}
}
