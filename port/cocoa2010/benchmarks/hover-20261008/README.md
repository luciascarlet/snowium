# Tab hover measurements on Snow Leopard

Measured on the actual OS X 10.6.8 Mac on 2026-10-08. The baseline already contains pass26's single hover owner, which the user confirmed fixes overlapping input. The selected tab displays X; the two unselected tabs are Settings and New Tab. Native Screen Sharing pointer movements cross those two unselected tabs at roughly 0.8-second intervals. No page input or navigation is used for the measurement.

| Measurement | Before: median / p95 | After: median / p95 |
| --- | --- | --- |
| Mouse-event delivery | 1.50 / 2.16 ms | 1.44 / 2.03 ms |
| Hover timer interval | 53.78 / 82.26 ms | 16.67 / 17.09 ms |
| Redraw request to `drawRect:` | 14.97 / 15.90 ms | 0.40 / 3.63 ms |
| Time inside `drawRect:` | 2.85 / 3.95 ms | 1.75 / 3.46 ms |
| Consecutive redraw spacing | 51.97 / 83.35 ms | 16.67 / 17.36 ms |

The baseline records seven real pointer moves and 96 paints. The final run records 18 moves and 714 paints, including a longer repeat during native sampling. All logged backing-layer animation keys are empty; the delay was not an implicit contents crossfade. These are application redraw measurements, not hardware presentation timestamps or a numerical comparison with Chromium 7.

A shared 60 Hz repeating timer alone reduced the median interval to about 33 ms. A 35-second native sample, including 12 tab crossings, then showed repeated `NSGrayFrame drawRect:` / `_CGSSynchronizeWindowBackingStore` and `CAViewEndDraw` waits. Invalidating the existing AppKit tab backing layer directly removed those stacks from the next active sample; AppKit still invokes the original `drawRect:` implementation. The default active/inactive toolbar gradients are now cached as they were in Chromium 7. Stationary synthetic tracking updates do not repaint unchanged glow positions, and selected tabs do not redraw an invisible hover overlay.

The original 200 ms rise, 20 ms hold, 400 ms decay, cursor-following gradient, tab silhouette, and single hit-tested hover owner remain. No layer replacement, synchronous window display/flush, new compositor thread, or separate hover artwork was added. The timer stops when the fades finish and is invalidated when its window controller closes; removed tabs are removed from its animation set.

Temporary probes logged uptime, tab identity, alpha/event timestamp, elapsed time, and layer animation keys at timer, move, and draw boundaries. They are absent from the clean pass30 source and deployed build. [before.csv](before.csv), [after.csv](after.csv), and [results.json](results.json) retain the numerical evidence. Tick/redraw spacing statistics omit immediate entry/exit adjustments below 5 ms and idle gaps above 200 ms; p95 uses the nearest-rank definition. Event delivery omits synthetic timestamp-zero moves.

The final table uses settled-page runs. The first seven pass29 movements during session restoration had mouse-event delivery of 30.2 ms median / 41.9 ms maximum, with GPU startup stalls also logged. This change does not eliminate delays caused by browser startup or other work blocking the main thread. Subjective smoothness and equivalence to Chromium 7 still need user acceptance. Screen Sharing drag validation was inconclusive: a test detached the Settings tab rather than establishing a reliable in-strip reorder. Full drag parity is not claimed by these measurements.
