// Copyright 2026 Snowium contributors. BSD license.
#pragma once
#include "ui/gfx/geometry/rect.h"
class BrowserView;
class Browser;
class OmniboxView;
#ifdef __OBJC__
@class NSWindow;
@class NSTextField;
#endif
namespace cocoa2010 {
bool EnabledByFlag();
bool Enabled(const BrowserView* view);
#ifdef __OBJC__
void Install(BrowserView* view, NSWindow* window);
NSTextField* OmniboxFieldForView(const OmniboxView* view);
#endif
void Uninstall(BrowserView* view);
void Layout(BrowserView* view);
void Update(BrowserView* view);
void FocusLocation(BrowserView* view);
void ShowMenu(BrowserView* view);
int TabStripHeight();
int ContentTopInset(BrowserView* view);
gfx::Rect OmniboxBounds(const Browser* browser);
gfx::Rect OmniboxBoundsForView(const OmniboxView* view);
bool OmniboxHasFocus(const OmniboxView* view);
bool OmniboxIsComposing(const OmniboxView* view);
void OmniboxTextChanged(const OmniboxView* view);
}
