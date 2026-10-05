Fixes a browser crash while drawing tab titles on **Intel OS X 10.6.8**. This is the pass39 build of Snowium, based on Chromium Legacy 124.0.6367.207.1.

Snow Leopard's CoreText font fallback can return Lucida Grande, including for Helvetica and Arial. The previous build incorrectly rejected this named system font and aborted in `PlatformFontMac`/`GetFallbackFonts`. The fix accepts and retains the native font on Snow Leopard while preserving fallback ordering, glyph coverage, size and traits. The restriction remains on other platforms; other diagnostic checks remain enabled.

The actual gfx font regression reproduced the crash before the fix and passed afterward on 10.6.8. A missing-glyph tab-title browser fixture crashed the old build after 13.61 seconds; the repaired build remained alive for the 30-second test and rendered its window. The release app matches the tested/deployed bundle.

Download the ZIP, extract it, and double-click `Chromium.app`. You may move it to `/Applications`. The profile remains `~/Library/Application Support/Snowium124`; existing profiles need not be removed. No special launch flags or replacement system libraries are required.

Rendering still uses software paths and performance can be slow. Separate CSS custom-property renderer assertions remain unresolved, and extended browsing stability is not established. This is a compatibility preview based on Chromium 124, not a current Chromium security update.

The ZIP includes dependency credits and runtime licenses; checksums and a file manifest accompany it. Source CI and release CI verify integrity, not a clean rebuild or native Snow Leopard UI behavior.
