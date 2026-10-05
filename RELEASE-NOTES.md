Fixes the **CSS custom-property style-cache renderer crash** on Intel OS X 10.6.8. This is the pass40 build of Snowium, based on Chromium Legacy 124.0.6367.207.1, and includes the previous Lucida Grande font fallback fix.

Registered custom properties with universal syntax can be reparsed into separate token-data objects representing equal computed values. The previous identity comparison incorrectly marked cached and recalculated styles as different and triggered assertions in `style_resolver.cc`. The fix compares resolved values by content only when parser context and animation-taint match. Unresolved declarations and different values remain distinct; the style assertions remain enabled.

The old renderer crash was reproduced on lucia.red and a reduced custom-property/animation/SVG fixture. The repaired build passed the 30-second fixture test, including dynamically changed values and inherited widths, and a 45-second website observation. Native Screen Sharing testing covered homepage rendering, Works navigation, scrolling and context menus.

Download the ZIP, extract it, and double-click `Chromium.app`. You can replace the previous app in `/Applications` after quitting it. The profile remains `~/Library/Application Support/Snowium124`; existing profiles need not be removed. No special launch flags or replacement system libraries are required.

**Remaining limits:** rendering uses software paths and performance can be slow. ChatGPT's login form rendered, but cold JavaScript compilation still caused minutes-long stalls, Page Unresponsive and temporary blank content. Full authentication and extended browsing stability remain unverified. This is based on Chromium 124, not a current Chromium security update.

The ZIP includes dependency credits and runtime licenses. Checksums and a file manifest accompany it. The release app matches all 159 physical files of the tested target bundle. Source and release CI verify integrity, not a clean rebuild or native Snow Leopard UI behavior.
