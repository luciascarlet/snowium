// Copyright 2026 Snowium contributors. BSD license.
#pragma once

#include <memory>

class Browser;
class OmniboxController;
class OmniboxPopupView;
class OmniboxView;

namespace cocoa2010 {
// Returns null for windows using the current Views UI. The native field is
// resolved lazily, after BrowserView finishes installing the Cocoa controls.
std::unique_ptr<OmniboxPopupView> CreateOmniboxPopup(
    OmniboxView* view, OmniboxController* controller, Browser* browser);
}
