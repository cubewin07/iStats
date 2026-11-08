# Phase 8.5 — Instrument 2: Chart Engine v3, Synchronized Motion & Popover Polish — Requirements

## Goal of this phase

Eliminate all chart animation artifacts, window-resize desynchronization, and visual/structural monotony across all 8 category panels by introducing a **time-domain chart engine (`LiveChart` v3)**, **time-aligned min/max/mean history envelopes**, **synchronized panel shell motion**, and **honest, cohesive panel layouts**.

---

## Requirement 12: Time-Domain Chart Engine & Synchronized Instrument Polish

**User story:** As a user, I want every live chart, history range, window transition, and signature instrument to move with physical, deterministic fluidity and zero visual jitter, matching the craft of first-party Apple instruments like Stocks and Activity Monitor.

### R8.5.1 Time-Domain Chart Rendering (`LiveChart` v3)
1. Horizontal point placement SHALL be computed from sample wall-clock timestamps relative to a continuous right-edge cursor (`edge`), never from array indices. Partially filled buffers SHALL occupy only their elapsed trailing time fraction without horizontal stretching.
2. Under `MotionPolicy.full`, the visible right edge SHALL trail the latest sample by one sample interval (`targetEdge = min(now - interval, latestTimestamp)`) and advance via a monotonic velocity follower (`1.0 s/s`), so newly sampled points slide into view along a fixed spline without vertical head interpolation, spline tangent wobble, or modulo phase-wrap snap-back on late samples.
3. WHEN the pointer hovers over a chart THEN the right-edge cursor SHALL freeze in place without shifting the curve horizontally, and WHEN hover ends THEN the cursor SHALL ease back to the live trailing edge over `250 ms`.
4. The live head indicator SHALL be a `6 pt` solid dot with a `2 pt` surface-colored cutout halo and SHALL NOT run a continuous looping pulse animation.
5. In Dark Mode, the primary `1.75 pt` stroke SHALL render a subtle underlay bloom (`5 pt` stroke, `16%` opacity, `3 pt` blur). Area fills SHALL fade from `20%` opacity at the line to `0%` at `85%` of plot height, with a `20 pt` leading horizontal fade.

### R8.5.2 Adaptive Y-Axis Scaling & Independent Mirrored Scales (`ChartScale`)
1. Auto-scaled ceilings SHALL snap to a `1 – 2 – 2.5 – 5 × 10^k` nice-number ladder above `visibleMax * 1.10`.
2. Upward scale expansion SHALL animate immediately (`0.35 s` spring). Downward scale contraction SHALL wait until the target ceiling remains below `70%` of the current ceiling for `3.0 s` before easing down (`0.60 s`).
3. Thermal charts SHALL apply a dynamic domain floor `max(20°C, floor((visibleMin - 5) / 10) * 10)`. Fan charts SHALL floor at `minRPM`. Percentage charts SHALL remain fixed at `0...100`.
4. Mirrored charts (`.mirrored` in Network and Disk) SHALL maintain independent `ChartScale` state for top (Download / Read) and bottom (Upload / Write) halves, rendering each ceiling label (`↓ 12 MB/s`, `↑ 800 KB/s`) in the left axis gutter so neither channel is flattened by the other.

### R8.5.3 Time-Aligned Extended History & Header Scrubbing (`HistoryPage` v3)
1. Extended history ranges (`5m` at `2.5 s` buckets, `15m` at `7.5 s` buckets) SHALL bucket samples by fixed wall-clock epochs (`floor(timestamp / bucketWidth)`) so historical buckets never shift when new samples arrive.
2. Each extended bucket SHALL store `(min, max, mean)` and render as a translucent `min...max` envelope band (`14%` tint) overlaid with a `1.75 pt` `mean` curve.
3. Hovering a chart SHALL NOT draw a floating tooltip over the plot; instead, a shared `ChartScrubState` SHALL update the Glance header numeral to the scrubbed value and the headline to the scrubbed relative and wall-clock time (`12s ago · 14:02:31`).
4. Average dashed lines and peak markers in `HistoryPage` SHALL remain hidden by default and reveal when the user hovers the `AVG` or `MAX` cells in the stats strip.

### R8.5.4 Synchronized Shell Motion & Header Ergonomics
1. `MetricPanel` SHALL reuse a single persistent `PanelBackgroundView` and `NSHostingView` across category switches, sliding the window frame horizontally (`0.30 s` spring) and crossfading content (`0.15 s`).
2. `PanelScaffold` SHALL report its content height synchronously via a `PreferenceKey` (with root content top-aligned), and `PanelController` SHALL animate the top-anchored `NSPanel` frame using a timing curve matched to `Motion.snappy` (`0.32 s`), without cross-view `matchedGeometryEffect` between the hero chart and History chart.
3. The panel header SHALL display an `18 pt` tinted category badge, a `13 pt` semibold category title, a text-based `PageSwitcher` (`Now · Details · History`) with a sliding glass puck, and hover-revealed pin/close controls (always visible when pinned).
4. Status alerts (`>= .elevated`) SHALL render as an inline status chip next to the Glance numeral, reserving the full-width `StatusRibbon` for actionable states (`Sampling paused · Resume`).

### R8.5.5 Kit v2 & Honest Signature Instruments
1. `Section` (Module v2) SHALL place its sentence-case title (`11.5 pt` semibold secondary) and trailing accessory inside the top of the card. No panel page SHALL exceed 3 sections.
2. `MetricRow` items inside a section SHALL be separated by `0.5 pt` inset table hairlines, and hover highlights SHALL appear only on interactive or copyable rows (with a subtle copy glyph on hover).
3. `LiveNumber` SHALL roll integer changes and throttle fractional transitions to a `2.0 s` cadence unless the displayed value changes by at least `1` unit.
4. `TopConsumersModule` rows SHALL animate vertical rank changes (`Motion.smooth`) and format values with tabular `Instrument.Typography.value` digits.
5. Synthetic or duplicate instruments SHALL be eliminated:
   - **Memory:** Replace the hardcoded `25 / 65 / 95` `ArcGauge` with a 3-stage Pressure Segmented Indicator (`Normal · Warning · Critical`) and promote the 5-part Composition Capsule + 2-column legend (`swatch · label · bytes · %`) to primary hero; remove the duplicate banded chart on Details.
   - **CPU:** Upgrade P/E Core Map clusters with a dedicated E-core secondary hue and `10×36 pt` bars; replace the text load-average row on Details with a true `1m / 5m / 15m` Load Average Dot Plot against core capacity and a 2-column per-core sparkline grid.
   - **Thermal:** Merge Spectrum and Thermal Groups on Now into one Annotated Thermal Spectrum + Ranked Legend section; make sensor groups collapsible on Details.
   - **Fan:** Replace per-fan `ArcGauge` dials with a Min–Max RPM Range Bar with live marker and target readout.

### R8.5.6 Performance & Invariants
1. With one panel open at 1 s refresh under `MotionPolicy.full`, chart rendering SHALL cost `≤ 1.5%` CPU and total app CPU SHALL stay `≤ 3.0%` on Apple Silicon. Pinned non-key HUDs SHALL throttle chart frame rate to `30 fps`.
2. All core invariants (`AGENTS.md §3`) remain unchanged: zero main-thread OS calls, `.unavailable` degradation, pure `RateMath`, zero disk/network telemetry.

