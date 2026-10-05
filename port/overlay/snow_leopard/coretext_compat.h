#ifndef SNOW_LEOPARD_CORETEXT_COMPAT_H_
#define SNOW_LEOPARD_CORETEXT_COMPAT_H_

#include <ApplicationServices/ApplicationServices.h>
#include <CoreText/CoreText.h>

// Source-level versions of the two Lion entry points used by Skia. Keep the
// native implementation on later systems; the older path retains CG's glyph
// hinting and the caller's text-space transform rather than drawing outlines.
static inline void SnowiumCTFontDrawGlyphs(CTFontRef font,
                                         const CGGlyph* glyphs,
                                         const CGPoint* positions,
                                         size_t count,
                                         CGContextRef context) {
  if (__builtin_available(macOS 10.7, *)) {
    CTFontDrawGlyphs(font, glyphs, positions, count, context);
    return;
  }
  CGFontRef graphics_font = CTFontCopyGraphicsFont(font, NULL);
  if (!graphics_font)
    return;
  CGContextSaveGState(context);
  CGContextSetFont(context, graphics_font);
  CGContextSetFontSize(context, CTFontGetSize(font));
  CGContextShowGlyphsAtPositions(context, glyphs, positions, count);
  CGContextRestoreGState(context);
  CGFontRelease(graphics_font);
}

static inline CTFontDescriptorRef SnowiumCTFontCreateDescriptorFromData(
    CFDataRef data) {
  if (__builtin_available(macOS 10.7, *))
    return CTFontManagerCreateFontDescriptorFromData(data);
  CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
  if (!provider)
    return NULL;
  CGFontRef graphics_font = CGFontCreateWithDataProvider(provider);
  CGDataProviderRelease(provider);
  if (!graphics_font)
    return NULL;
  CTFontRef font = CTFontCreateWithGraphicsFont(graphics_font, 0, NULL, NULL);
  CGFontRelease(graphics_font);
  if (!font)
    return NULL;
  CTFontDescriptorRef descriptor = CTFontCopyFontDescriptor(font);
  CFRelease(font);
  return descriptor;
}

#endif  // SNOW_LEOPARD_CORETEXT_COMPAT_H_
