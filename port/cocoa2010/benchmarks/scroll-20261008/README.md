# Aqua scrollbar scrolling benchmarks — 8 October 2026

The simple page isolates compositor scrolling. Google Fonts reproduces substantial main-thread work while the page keeps scrolling asynchronously. Native painting is inexpensive; the large delay occurs before the main thread receives the compositor's updated scroll position. The complete Aqua control then still needs painting and a commit.

No synchronization optimization is present in the current pass23 build. An earlier forced-main-thread trial was rejected and removed. Aqua refresh lag remains unresolved.

## Target and method

Tests ran on the actual Snow Leopard Mac: MacBookPro6,1, OS X 10.6.8, Core i7 M620 at 2.67 GHz, 8 GiB RAM. Chromium 124.0.6367.207 used the isolated Cocoa 2010 development bundle/profile. This port uses software compositing; a compositor thread still handles asynchronous scrolling. Chromium 7 was the visual reference, not a modern-site performance baseline.

Pass23 adds trace-only scopes for complete native Aqua painting and separate scroll-begin hit-test/repaint reasons. Each current run received 30 native Screen Sharing wheel updates, consuming 1,200 CSS pixels. Resetting, focusing and appearance/load changes happened before recording. DevTools Protocol supplied tracing and process diagnostics, not input or navigation.

The fixture has one 300-pixel-high scroll area with fixed-height rows, `will-change: scroll-position`, and no scroll handlers. Idle mode performs no recurring page work. Busy mode runs a 100 ms synchronous JavaScript task every 500 ms. Aqua and CSS-colored plain scrollbars were tested twice in each mode. Plain uses Chromium's separate compositor thumb path; Aqua preserves the complete HITheme track, knob, arrows and stationary pattern.

Google Fonts was tested twice from the start of the loaded catalog and once farther down into new font rows. These are distinct page states, not three identical repetitions. The farther-down run started at 1,379 CSS pixels and ended at 2,579. Its position chain was checked to exclude scroll anchoring during the measured sequence.

## Current asynchronous scrolling results

Times are milliseconds. Ranges below span per-run statistics, not confidence intervals. “Page” is Chromium's reported input-to-presentation latency for the scroll update. “Main position” is compositor consumption to `NotifyDidScroll` on the renderer main thread, **not final scrollbar pixels**.

| Condition | Runs | Page median | Main position p95 | Main position maximum |
|---|---:|---:|---:|---:|
| Simple, Aqua, idle | 2 | 25.9–30.6 | 0.85–0.99 | 0.92–1.42 |
| Simple, plain, idle | 2 | 26.9–28.9 | 0.89–2.50 | 0.96–9.15 |
| Simple, Aqua, 100 ms stalls | 2 | 27.0–30.6 | 44.0–81.8 | 75.8–98.2 |
| Simple, plain, 100 ms stalls | 2 | 24.7–27.2 | 43.3–57.3 | 76.8–79.8 |
| Google Fonts, start of loaded catalog | 2 | 28.0–35.5 | 96.5–169.3 | 116.6–240.7 |
| Google Fonts, farther into new rows | 1 | 25.2 | 480.5 | 619.8 |

[All eleven per-run distributions](table.md) include page p95, main-position median and native paint times. Percentiles use linear interpolation over 30 samples per current run. Native painting, including allocation and paint recording, took about 0.34–0.38 ms median on the simple page and 0.68–0.69 ms on Google Fonts.

Every simple run had zero scroll-begin repaint and hit-test reasons. Main-position delivery was already fast when main was idle. Under deliberate stalls, the page stayed responsive while that delivery sometimes waited nearly 100 ms. Plain also had delayed main-position notifications, but its thumb can use the latest compositor position.

All Google Fonts runs had zero main-thread repaint reasons. The first needed an initial main-thread hit test (`kNonFastScrollableRegion`, 256); the other two did not. The generic `SCROLL_MAIN_THREAD` frame label includes a gesture initially blocked for a hit test, so that label alone does not establish a per-update rendering dependency.

During the farther-down sequence, main ran 22 layout events, 11 paint events and 11 tasks longer than 50 ms. Its longest task was 576 ms. Page presentation was 25 ms median while main-position handoff reached 480 ms at p95 and 620 ms maximum. Native painting took 0.69 ms median. This reproduces a substantial delay before Aqua can update while the page continues scrolling.

Compositor scrolling and main-thread rendering coexist. The compositor moves available content while script, font work, layout and painting prepare updated content. Newly rendered elements do not automatically make every scroll update wait for that work. Actual repaint dependencies or cancelling input handlers can require main-thread involvement; the recorded reasons distinguish those cases.

## Earlier forced-main-thread trial

The rejected pass20 trial added a repaint dependency to synchronize Aqua with page scrolling. Three Google Fonts runs had median page latencies of 84.3, 80.9 and 74.8 ms, versus 32.0, 35.9 and 32.9 ms for normal pass22. Their p95 ranges were 124.5–163.7 ms versus 43.6–55.8 ms. The trial is absent from current source.

All six consumed 1,200 pixels from 30 native wheel inputs. One normal and one forced run coalesced input into 29 compositor updates; one normal run has 29 presentation samples. These ordered development trials used different builds and cache/network states. They support rejecting a path that makes page scrolling wait for native painting, but do not give a randomized estimate of its exact cost. `forced-main-summary.json` retains the six runs.

## Limits

- Main-position handoff is a lower bound on current Aqua refresh delay. Painting, committing and presenting the control happen afterward; final scrollbar pixels were not independently timestamped.
- A presentation event can describe a partial update: the page can move while Aqua stays stale. These are browser diagnostics, not measurements of Screen Sharing delivery or the physical display.
- Remote input arrived in short bursts, not a calibrated 60 Hz local-device stream. Trace overhead and input timing affect absolute numbers.
- Manual captures have different idle lead-in/tail lengths. Whole-recording CPU samples cannot establish comparative CPU or energy cost. Renderer child histograms were unavailable from this endpoint.
- Main-thread scopes can nest, so their durations must not be added as independent work. Frame counts can include multiple reporters per frame and are not simple dropped-frame percentages.
- Google Fonts is mutable; warmed rows differ from newly exposed rows. More local-device repetitions would be needed for a regression threshold or a general claim about all sites.

Exploratory captures with no input, incomplete distance, pending startup work or a different fixture were excluded. `simple-plain-busy-1` received only 23 updates/920 pixels and is excluded from the paired results.

## Implication for an asynchronous fix

`ProxyImpl::ScheduledActionSendBeginMainFrame` already batches compositor deltas and posts them to main. Idle delivery is already fast. Increasing its frequency might reduce scheduling delay when main is free, but cannot execute during a running synchronous main-thread task. It also adds compositor work unless bounded.

An independent native scrollbar refresh is the more promising candidate: snapshot immutable control parameters, coalesce to the latest position, allow at most one paint job in flight, and update only the scrollbar resource asynchronously. The compositor must never wait or queue unbounded work. Carbon/HITheme thread safety, resource lifetime, activation/eviction, pixel parity and compositor overhead need validation before integration. This candidate is not implemented or benchmarked.

## Artifacts and reproduction

`paired-summary.json` contains eleven current runs. `runs/*/results.json` retains capture metadata; `artifacts.json` pins raw trace/result hashes. Raw traces remain in the ignored workspace directory `modern-port/benchmarks/cocoa2010-scroll/`, outside Git.

Serve `compositor-scroll.html` to the target, bring its window forward, reset/focus the area, and select load/appearance. Run `node record.mjs RUN_LABEL` with interactive stdin and a localhost port 19227 tunnel to the target's diagnostic port. Send 30 native wheel inputs and press Enter in the recorder after the visible sequence completes. A modern local Node with built-in WebSocket support is required.

Run `python3 analyze.py RUN_DIRECTORY...`. For an externally verified, single monotonically scrolling website area, add `--monotonic-scroll`. The analyzer validates consumed/delivered distance and rejects discontinuous position chains. Do not use that option for mixed scroll areas or anchoring changes.
