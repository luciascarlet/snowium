First preview of Snowium 124, based on Chromium Legacy 124.0.6367.207.1, for **Intel OS X 10.6.8**.

Download the ZIP, extract it, and double-click `Chromium.app`. You may move the app to `/Applications`. The app includes its compatibility libraries; no system-library replacement or special launch flags are required. Its profile is `~/Library/Application Support/Snowium124`, separate from Chromium 60.

This is the prebuilt **pass38** candidate tested on a MacBookPro6,1 running 10.6.8. Native testing covered Wikipedia search/article navigation, context menus, scrolling and GitHub profile rendering. The corrected writable-memory transport passed regression checks both normally and inside the renderer sandbox. The app now draws a Snow Leopard resize grip.

Rendering uses software paths and performance can be slow. Extended browsing stability, downloads, extensions, printing and media have not been comprehensively tested. This preview is based on Chromium 124; it is not an updated Chromium security release. The originally reported right-click crash was not conclusively traced to the repaired renderer disconnection, although subsequent tested context menus worked.

Checksums and a manifest accompany the ZIP. Chromium dependency credits and supplemental runtime licenses are included. The source repository contains the port changes and pinned Legacy patches. This release was built locally before the GitHub workflows existed; CI verifies source and release integrity and does not rebuild the browser.
