// Copyright 2026 Snowium contributors. BSD license.
#pragma once
#include "ui/native_theme/native_theme.h"

namespace ui {
// Record Snow Leopard's actual HITheme scrollbar artwork into Chromium's
// display list. Explicit CSS scrollbar colors retain the existing paint path.
gfx::Rect GetAquaScrollbarThumbRect(const NativeTheme::ScrollbarExtraParams& extra);

bool PaintAquaScrollbar(cc::PaintCanvas* canvas, NativeTheme::Part part,
                        NativeTheme::State state, const gfx::Rect& rect,
                        const NativeTheme::ScrollbarExtraParams& extra);
}
