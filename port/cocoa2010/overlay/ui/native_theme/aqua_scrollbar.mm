// Copyright 2026 Snowium contributors. BSD license.
#include "ui/native_theme/aqua_scrollbar.h"
#include <Carbon/Carbon.h>
#include <algorithm>
#include <cmath>
#include "base/trace_event/trace_event.h"
#include "ui/native_theme/native_theme_features.h"
#include "third_party/skia/include/core/SkBitmap.h"
#include "ui/gfx/canvas.h"
#include "ui/gfx/image/image_skia.h"

namespace ui {
namespace {
HIThemeTrackDrawInfo ActualTrackInfo(const NativeTheme::ScrollbarExtraParams& extra) {
  HIThemeTrackDrawInfo info = {};
  const CGFloat scale = extra.scale_from_dip > 0 ? extra.scale_from_dip : 1;
  const auto& bounds = extra.aqua_control_bounds;
  const bool horizontal = extra.orientation == NativeTheme::ScrollbarOrientation::kHorizontal;
  const CGFloat girth = (horizontal ? bounds.height() : bounds.width()) / scale;
  info.kind = girth < 15 ? kThemeSmallScrollBar : kThemeMediumScrollBar;
  info.attributes = kThemeTrackThumbRgnIsNotGhost;
  if (horizontal) info.attributes |= kThemeTrackHorizontal;
  info.bounds = CGRectMake(bounds.x()/scale, bounds.y()/scale,
                           bounds.width()/scale, bounds.height()/scale);
  info.max = std::max(0, extra.aqua_maximum);
  info.value = static_cast<int>(std::clamp(extra.aqua_position, 0.f,
                                          static_cast<float>(info.max)));
  info.trackInfo.scrollbar.viewsize = extra.aqua_visible_size;
  info.trackInfo.scrollbar.pressState = extra.aqua_thumb_pressed ? kThemeThumbPressed : 0;
  info.enableState = !extra.aqua_enabled ? kThemeTrackDisabled :
      extra.aqua_active ? kThemeTrackActive : kThemeTrackInactive;
  if (!extra.aqua_has_buttons) info.enableState = kThemeTrackNothingToScroll;
  return info;
}
}  // namespace

gfx::Rect GetAquaScrollbarThumbRect(const NativeTheme::ScrollbarExtraParams& extra) {
  if (!IsAquaScrollbarEnabled() || extra.aqua_control_bounds.IsEmpty() || !extra.aqua_enabled) return {};
  auto info = ActualTrackInfo(extra);
  info.attributes |= kThemeTrackShowThumb;
  HIShapeRef shape = nullptr;
  HIRect thumb;
  if (HIThemeGetTrackThumbShape(&info, &shape) != noErr || !shape) return {};
  HIShapeGetBounds(shape, &thumb);
  CFRelease(shape);
  if (CGRectIsEmpty(thumb)) return {};
  const CGFloat scale = extra.scale_from_dip > 0 ? extra.scale_from_dip : 1;
  // Retain the full cross-axis width for the track's borders and highlights.
  if (extra.orientation == NativeTheme::ScrollbarOrientation::kHorizontal)
    return gfx::Rect(std::lround(thumb.origin.x*scale), 0,
                     std::lround(thumb.size.width*scale), extra.aqua_control_bounds.height());
  return gfx::Rect(0, std::lround(thumb.origin.y*scale),
                   extra.aqua_control_bounds.width(), std::lround(thumb.size.height*scale));
}

bool PaintAquaScrollbar(cc::PaintCanvas* canvas, NativeTheme::Part part,
                        NativeTheme::State state, const gfx::Rect& rect,
                        const NativeTheme::ScrollbarExtraParams& extra) {
  if (!IsAquaScrollbarEnabled() || extra.is_overlay || extra.thumb_color || extra.track_color) return false;
  const bool thumb = part == NativeTheme::kScrollbarVerticalThumb ||
                     part == NativeTheme::kScrollbarHorizontalThumb;
  const bool track = part == NativeTheme::kScrollbarVerticalTrack ||
                     part == NativeTheme::kScrollbarHorizontalTrack;
  const bool back = part == NativeTheme::kScrollbarUpArrow || part == NativeTheme::kScrollbarLeftArrow;
  const bool forward = part == NativeTheme::kScrollbarDownArrow || part == NativeTheme::kScrollbarRightArrow;
  if (!thumb && !track && !back && !forward) return false;
  // The original WebCore path draws Aqua as one complete HITheme control.
  // Its pattern and rounded ends must not be a separately translated texture.
  if (thumb && !extra.aqua_control_bounds.IsEmpty()) return true;
  TRACE_EVENT0("cc", "Snowium.AquaScrollbar.Paint");
  const bool horizontal = extra.orientation ==
                          NativeTheme::ScrollbarOrientation::kHorizontal;
  const CGFloat scale = extra.scale_from_dip > 0 ? extra.scale_from_dip : 1;
  const CGFloat width = rect.width() / scale;
  const CGFloat height = rect.height() / scale;
  const CGFloat length = horizontal ? width : height;
  const CGFloat girth = horizontal ? height : width;
  if (length <= 0 || girth <= 0) return true;

  SkBitmap bitmap;
  if (!bitmap.tryAllocN32Pixels(rect.width(), rect.height())) return false;
  bitmap.eraseColor(SK_ColorTRANSPARENT);
  CGColorSpaceRef colors = CGColorSpaceCreateDeviceRGB();
  CGContextRef context = CGBitmapContextCreate(bitmap.getPixels(),
      bitmap.width(), bitmap.height(), 8, bitmap.rowBytes(), colors,
      kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
  CGColorSpaceRelease(colors);
  if (!context) return false;
  CGContextTranslateCTM(context, 0, bitmap.height());
  CGContextScaleCTM(context, scale, -scale);

  // Preserve the real control bounds and scroll range. HITheme draws the
  // track, arrows and knob together, as in the original non-overlay WebCore
  // path. Blink owns scrolling, repeat timers and the native hit geometry.
  HIThemeTrackDrawInfo info = {};
  info.kind = girth < 15 ? kThemeSmallScrollBar : kThemeMediumScrollBar;
  info.attributes = kThemeTrackThumbRgnIsNotGhost;
  if (horizontal) info.attributes |= kThemeTrackHorizontal;
  info.enableState = state == NativeTheme::kDisabled ? kThemeTrackDisabled
                                                    : kThemeTrackActive;
  constexpr CGFloat padding = 128;
  info.bounds = thumb ? (horizontal ? CGRectMake(-padding, 0, length + 2 * padding, girth)
                                    : CGRectMake(0, -padding, girth, length + 2 * padding))
                      : CGRectMake(0, 0, width, height);
  info.min = 0; info.max = 256; info.value = 128;
  info.trackInfo.scrollbar.viewsize = length;
  const bool actual_control = !extra.aqua_control_bounds.IsEmpty();
  if (actual_control) {
    info = ActualTrackInfo(extra);
    if (extra.aqua_enabled) info.attributes |= kThemeTrackShowThumb;
  }
  if (state == NativeTheme::kPressed)
    info.trackInfo.scrollbar.pressState = back ? kThemeBottomInsideArrowPressed :
        forward ? kThemeBottomOutsideArrowPressed : kThemeThumbPressed;
  if (thumb) {
    info.attributes |= kThemeTrackShowThumb | kThemeTrackHideTrack;
    if (!actual_control) {
      // Generic Views scrollbars have no full-control snapshot. Preserve their
      // existing crop path; Blink uses exact HITheme geometry above.
      HIShapeRef shape = nullptr;
      HIRect native_thumb;
      if (HIThemeGetTrackThumbShape(&info, &shape) != noErr || !shape) {
        CGContextRelease(context); return false;
      }
      HIShapeGetBounds(shape, &native_thumb);
      CFRelease(shape);
      if (horizontal && native_thumb.size.width > 0) {
        CGContextScaleCTM(context, length / native_thumb.size.width, 1);
        CGContextTranslateCTM(context, -native_thumb.origin.x, 0);
      } else if (!horizontal && native_thumb.size.height > 0) {
        CGContextScaleCTM(context, 1, length / native_thumb.size.height);
        CGContextTranslateCTM(context, 0, -native_thumb.origin.y);
      }
    }
  }
  const OSStatus result = HIThemeDrawTrack(&info, nullptr, context,
                                         kHIThemeOrientationNormal);
  CGContextRelease(context);
  if (result != noErr) return false;
  gfx::Canvas paint_canvas(canvas, 1.f);
  paint_canvas.DrawImageInt(gfx::ImageSkia::CreateFrom1xBitmap(bitmap),
                            rect.x(), rect.y());
  return true;
}
}
