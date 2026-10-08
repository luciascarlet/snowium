// Copyright 2019 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "third_party/blink/renderer/platform/theme/web_theme_engine_mac.h"

#include "third_party/blink/renderer/platform/theme/web_theme_engine_conversions.h"
#include "ui/native_theme/native_theme.h"
#if defined(SNOW_LEOPARD_PORT)
#include "ui/native_theme/aqua_scrollbar.h"
#endif

namespace blink {

namespace {
ui::NativeTheme::ScrollbarExtraParams NativeScrollbarParams(
    const WebThemeEngine::ScrollbarExtraParams& scrollbar_extra) {
  ui::NativeTheme::ScrollbarExtraParams native_scrollbar_extra;
  native_scrollbar_extra.is_hovering = scrollbar_extra.is_hovering;
  native_scrollbar_extra.is_overlay = scrollbar_extra.is_overlay;
  native_scrollbar_extra.scale_from_dip = scrollbar_extra.scale_from_dip;
  native_scrollbar_extra.track_color = scrollbar_extra.track_color;
  native_scrollbar_extra.thumb_color = scrollbar_extra.thumb_color;
#if defined(SNOW_LEOPARD_PORT)
  native_scrollbar_extra.aqua_control_bounds = scrollbar_extra.aqua_control_bounds;
  native_scrollbar_extra.aqua_maximum = scrollbar_extra.aqua_maximum;
  native_scrollbar_extra.aqua_visible_size = scrollbar_extra.aqua_visible_size;
  native_scrollbar_extra.aqua_position = scrollbar_extra.aqua_position;
  native_scrollbar_extra.aqua_active = scrollbar_extra.aqua_active;
  native_scrollbar_extra.aqua_enabled = scrollbar_extra.aqua_enabled;
  native_scrollbar_extra.aqua_has_buttons = scrollbar_extra.aqua_has_buttons;
  native_scrollbar_extra.aqua_thumb_pressed = scrollbar_extra.aqua_thumb_pressed;
#endif
  switch (scrollbar_extra.orientation) {
    case WebThemeEngine::kVerticalOnRight:
      native_scrollbar_extra.orientation =
          ui::NativeTheme::ScrollbarOrientation::kVerticalOnRight;
      break;
    case WebThemeEngine::kVerticalOnLeft:
      native_scrollbar_extra.orientation =
          ui::NativeTheme::ScrollbarOrientation::kVerticalOnLeft;
      break;
    case WebThemeEngine::kHorizontal:
      native_scrollbar_extra.orientation =
          ui::NativeTheme::ScrollbarOrientation::kHorizontal;
      break;
  }

  return native_scrollbar_extra;
}
}  // namespace

#if defined(SNOW_LEOPARD_PORT)
gfx::Rect WebThemeEngineMac::GetAquaScrollbarThumbRect(const ExtraParams& params) {
  return ui::GetAquaScrollbarThumbRect(NativeScrollbarParams(
      absl::get<WebThemeEngine::ScrollbarExtraParams>(params)));
}
#endif


void WebThemeEngineMac::Paint(cc::PaintCanvas* canvas,
                              WebThemeEngine::Part part,
                              WebThemeEngine::State state,
                              const gfx::Rect& rect,
                              const WebThemeEngine::ExtraParams* extra_params,
                              mojom::ColorScheme color_scheme,
                              const ui::ColorProvider* color_provider,
                              const std::optional<SkColor>& accent_color) {
  if (IsScrollbarPart(part)) {
    PaintMacScrollBarParts(canvas, color_provider, part, state, rect,
                           extra_params, color_scheme);
    return;
  }

  WebThemeEngineDefault::Paint(canvas, part, state, rect, extra_params,
                               color_scheme, color_provider, accent_color);
}

bool WebThemeEngineMac::IsScrollbarPart(WebThemeEngine::Part part) {
  switch (part) {
#if defined(SNOW_LEOPARD_PORT)
    case WebThemeEngine::kPartScrollbarUpArrow:
    case WebThemeEngine::kPartScrollbarDownArrow:
    case WebThemeEngine::kPartScrollbarLeftArrow:
    case WebThemeEngine::kPartScrollbarRightArrow:
#endif
    case WebThemeEngine::kPartScrollbarHorizontalTrack:
    case WebThemeEngine::kPartScrollbarVerticalTrack:
    case WebThemeEngine::kPartScrollbarHorizontalThumb:
    case WebThemeEngine::kPartScrollbarVerticalThumb:
    case WebThemeEngine::kPartScrollbarCorner:
      return true;
    default:
      return false;
  }
}

void WebThemeEngineMac::PaintMacScrollBarParts(
    cc::PaintCanvas* canvas,
    const ui::ColorProvider* color_provider,
    WebThemeEngine::Part part,
    WebThemeEngine::State state,
    const gfx::Rect& rect,
    const WebThemeEngine::ExtraParams* extra_params,
    mojom::ColorScheme color_scheme) {
  ui::NativeTheme::ScrollbarExtraParams native_scrollbar_extra;
  const WebThemeEngine::ScrollbarExtraParams& scrollbar_extra =
      absl::get<WebThemeEngine::ScrollbarExtraParams>(*extra_params);
  native_scrollbar_extra = NativeScrollbarParams(scrollbar_extra);

  ui::NativeTheme::GetInstanceForNativeUi()->Paint(
      canvas, color_provider, NativeThemePart(part), NativeThemeState(state),
      rect, ui::NativeTheme::ExtraParams(native_scrollbar_extra),
      NativeColorScheme(color_scheme));
}

}  // namespace blink
