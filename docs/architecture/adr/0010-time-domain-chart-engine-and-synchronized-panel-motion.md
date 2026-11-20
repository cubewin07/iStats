# ADR 0010: Time-Domain Chart Engine v3, Synchronized Panel Motion, and Instrument 2 Polish

- **Status:** Accepted
- **Date:** 2026-11-08
- **Phase:** Phase 8.5 (`phase-08.5-instrument-polish`)
- **Refines:** [ADR 0009](0009-instrument-design-language-and-glass-panels.md) (§4–6: chart rendering, motion system, and signature panel ergonomics)
- **Preserves:** [ADR 0001](0001-language-and-ui-stack.md), [ADR 0002](0002-threading-and-scheduling-model.md), [ADR 0004](0004-privilege-and-fan-control.md), [ADR 0006](0006-telemetry-privacy-no-persistence.md)

---

## Context

Phase 8 delivered the `MetricPanel` glass shell, `PanelScaffold`, `LiveChart`, and 8 signature category panels under ADR 0009. While structurally sound, audit of the shipped implementation revealed fundamental mathematical and architectural flaws in how charts animate, how extended history is downsampled, and how panel window geometry synchronizes with SwiftUI layout transitions:

1. **Sample-Index Glide Artifacts (`LiveChart`):**
   - Glide phase was computed via `elapsed.truncatingRemainder(dividingBy: sampleIntervalSeconds)`. Any background sample arriving even 15–30 ms late caused the remainder to wrap past `1.0 → 0.0` before the new sample arrived, snapping the entire trace backward by one horizontal step (`dx`).
   - Vertical interpolation of the newest point (`prevY + glide * (rawY - prevY)`) forced Fritsch–Carlson monotone cubic spline tangents to recompute every frame, causing the rightmost 2–3 curve segments to visibly wobble up and down.
   - Step width switched between `plotWidth / (n - 2)` while gliding and `plotWidth / (n - 1)` when static (`glide == 0` or on hover), producing a 1-step horizontal jump on every sample boundary and whenever scrubbing began.
   - Index-based X coordinates (`i * dx`) stretched the trace horizontally during the first 60 seconds until the ring buffer filled.
2. **Un-eased Y-Axis Autoscaling & Zero Floor:**
   - `LiveChartMath.computeMaxBound` recomputed `observedMax * 1.15` instantaneously per sample. When a transient spike exited the window, the entire trace rescaled vertically in a single frame.
   - A hardcoded `0.0` floor compressed narrow-band metrics (such as 45–65 °C CPU temperature or idle fan RPM) into a flat line near the top of the plot.
   - Mirrored charts (Network, Disk) shared a single `combinedMax`, flattening upload or write traffic into an invisible 1 px line whenever download or read traffic was an order of magnitude higher.
3. **Index-Bucket Downsampling "Boiling" (`Downsampler`):**
   - Extended history (5m / 15m) bucketed samples by array index (`0..<count`). Every new 1 Hz sample shifted all 120 bucket boundaries by one element, causing peaks to jump across buckets and making the entire 5m/15m curve boil every second.
4. **Desynchronized Window Morphing & Hard Category Cuts (`PanelController` / `MetricPanel`):**
   - `matchedGeometryEffect` between the 72 pt hero chart and 140 pt History chart ran a 0.32 s SwiftUI spring concurrently with an asynchronous `DispatchQueue.main.async` `NSPanel.setFrame` using a 0.16 s `easeInEaseOut` curve—causing content to snap and clip before the window caught up.
   - `MetricPanel.setSwiftUIContent` tore down and recreated both `PanelBackgroundView` and `NSHostingView` on every category switch.
5. **Visual & Ergonomic Friction ("Half-Done" Polish):**
   - A perpetual 60 fps radar-pulse ring on the chart head wasted CPU cycles and added visual noise.
   - Hover scrubbing drew a floating tooltip pill over the curve, occluding the inspected data point.
   - Memory's `ArcGauge` rendered synthetic hardcoded values (`25 / 65 / 95`) for a 3-state enum (`.normal`, `.warning`, `.critical`), violating the real-telemetry-only ethos.
   - Every module used an identical external uppercase eyebrow + grey box pattern, three competing chip styles coexisted in `HistoryPage`, and `LiveNumber` rolled fractional digits every second like a slot machine.

---

## Decision

We adopt **Instrument 2 (Phase 8.5)** to replace the chart engine, synchronize shell motion, and polish all 8 panels:

### 1. Time-Domain Chart Engine v3 (`ChartTimeline`, `ChartScale`, `LiveChart`)
- **Timestamp-Projected X Coordinates:** Every point is positioned by its wall-clock timestamp `t` relative to a continuous right-edge cursor `edge`:
  $$x = \text{plotWidth} \cdot \left(1 - \frac{\text{edge} - t}{\text{window}}\right)$$
  Partially filled buffers naturally occupy the trailing portion of the window without horizontal stretching.
- **One-Sample Delayed Right Edge (`ChartTimeline`):** The visible right edge trails the newest sample by one interval (`targetEdge = min(now - interval, latestTimestamp)`), advanced by a monotonic velocity follower (`1.0 s/s`, snapping only if behind by `> 3 * interval` after system sleep). New samples arrive off-screen to the right and glide into view along a fixed spline—zero vertical head wobble, zero tangent recomputation per frame, and zero phase-wrap snap when a sample arrives late.
- **Freeze-in-Place Hover Scrub:** Entering hover freezes `edge` at its exact current timestamp; exiting hover eases `edge` back to live over `250 ms`. The curve never jumps under the pointer.
- **Animated Nice-Number Y Scale with Hysteresis (`ChartScale`):**
  - Ceilings snap to a `1 – 2 – 2.5 – 5 × 10^k` nice ladder above `visibleMax * 1.10`.
  - **Upward expansion** triggers immediately with a `0.35 s` critically damped spring.
  - **Downward contraction** requires the target ceiling to remain below `70%` of the current ceiling for a `3.0 s` hold period before easing down over `0.60 s`.
  - **Domain Floors:** Thermal charts floor at `max(20°C, floor((visibleMin - 5) / 10) * 10)`; Fan charts floor at `minRPM`; percentage charts lock to `0...100`.
- **Independent Mirrored Half-Scales:** Mirrored charts (`.mirrored` for Network and Disk) maintain independent `ChartScale` instances for the top (Download / Read) and bottom (Upload / Write) halves, each labeled with its own ceiling (`↓ 12 MB/s`, `↑ 800 KB/s`) in the left axis gutter.
- **Calm Head Bead & Subtle Dark-Mode Bloom:**
  - Replace the looping 60 fps radar pulse with a crisp `6 pt` head bead (`2 pt` surface-colored cutout halo).
  - Increase primary stroke to `1.75 pt` with round joins, paired with a subtle dark-appearance-only underlay bloom (`5 pt` stroke at `16%` opacity, `3 pt` blur) and a cleaner `20% → 0%` vertical area fill over the top `85%` of the plot.

### 2. Time-Aligned Min/Max/Mean Envelope for Extended History (`Downsampler`)
- Extended history (5m / 15m) buckets points by fixed wall-clock epochs:
  $$\text{bucketIndex} = \lfloor t / \Delta t_{\text{bucket}} \rfloor$$
  where $\Delta t_{\text{bucket}} = 2.5\text{ s}$ for 5m and $7.5\text{ s}$ for 15m.
- Historical buckets are immutable as time advances; only the active trailing bucket updates, eliminating curve "boiling".
- Each bucket computes `(min, max, mean)` (`BucketPoint`), rendered as a translucent `min...max` range band (`14%` tint) with a crisp `mean` trace on top. The 1m range remains a raw-sample spline.

### 3. Stocks-Style Header Scrub Readout
- Remove the floating tooltip pill over the chart canvas.
- When scrubbing either the hero `LiveChart` or `HistoryPage`, a shared `ChartScrubState` overrides the Glance header: the display numeral shows the scrubbed value (with channel breakdown for stacked/mirrored charts) and the headline displays relative and wall-clock time (`12s ago · 14:02:31`). Releasing hover springs back to live telemetry.

### 4. Synchronized Panel Shell & Motion v2
- **Single Persistent Hosting View:** `MetricPanel` retains a single `PanelBackgroundView` and `NSHostingView`, swapping root panel state cleanly on category switches while sliding the window frame horizontally (`0.30 s` spring) and crossfading content (`0.15 s`).
- **Synchronous PreferenceKey Window Sizing:** Drop `matchedGeometryEffect` between the hero chart and History page. SwiftUI reports target content height via a `PreferenceKey`, and `PanelController` animates the top-anchored `NSPanel` frame in the same layout pass using a control-point curve matched to `Motion.snappy` (`0.32 s`).
- **Header & Controls:**
  - Category icon sits in an `18 pt` tinted badge next to a `13 pt` semibold title.
  - `PageSwitcher` uses clear text labels (`Now · Details · History`) inside a sliding glass puck control instead of cryptic icons.
  - Status alerts render as a compact inline pill next to the Glance numeral (`● Elevated`), reserving full-width banners strictly for actionable states (`Sampling paused · Resume`).
- **Cadence-Controlled Numerals & Animated Process Rows:**
  - `LiveNumber` rolls integer values smoothly, while fractional values crossfade and throttle minor sub-unit jitter (`2.0 s` minimum cadence unless delta exceeds `1` display unit).
  - `TopConsumersModule` keys rows by `pid` with `.animation(Motion.smooth, value: processIDs)` so rank changes glide vertically instead of teleporting.

### 5. Kit v2 & Honest Signature Instruments
- **Integrated `Section` Card (Module v2):** Moves the section header inside the top of the card (`11.5 pt` semibold sentence-case title + trailing accessory), capping each page at **at most 3 sections** and using `0.5 pt` inset table hairlines between `MetricRow` items.
- **Unified Controls & Secondary Palette:** Standardize on one `SegmentedControl` and one `FilterChip` primitive. Add explicit secondary-series colors in `PaletteContrast` (e.g., distinct E-core, CPU System, and Memory segment hues) rather than borrowing other categories' tints or stacking alpha opacities.
- **Per-Panel Polish:**
  - **Memory:** Replace the synthetic `25 / 65 / 95` `ArcGauge` with an honest 3-stage **Pressure Segmented Bar (`Normal · Warning · Critical`)** paired with Swap and Compressed callouts, promoting the 5-part Composition Capsule + 2-column legend (`swatch · label · bytes · %`) to primary hero instrument. Remove the duplicate banded chart on Details.
  - **CPU:** Upgrade the Core Map with distinct P/E cluster column groups (`10×36 pt` vertical bars, dedicated E-core hue) and replace the text-only load average row on Details with a true **Load Average Dot Plot** (`1m / 5m / 15m` markers against a core-capacity threshold tick) plus a 2-column per-core sparkline grid.
  - **Thermal:** Merge the redundant Spectrum and Thermal Groups modules on Now into a single **Annotated Thermal Spectrum + Ranked Group Legend** card; make sensor groups collapsible on Details.
  - **Fan:** Replace per-fan `ArcGauge` dials with a **Min–Max RPM Range Bar** with live marker and target readout alongside the RPM-locked turbine.

---

## Options Considered

1. **Patch `LiveChart`'s `truncatingRemainder` Glide Logic in Place:**
   - *Rejected.* Fixing only the modulo wrap still leaves index-based X stretching during buffer fill-up, spline tangent wobble on the rightmost segments, hover snap jumps, and index-bucket boiling in 5m/15m history. Moving to wall-clock timestamp projection with a 1-sample delayed edge solves all five issues with simpler, pure math.
2. **Shared Scale vs. Independent Scales for Mirrored Charts (Network / Disk):**
   - *Chose Independent Scales per Half.* Upload and write rates are routinely 10–50× smaller than download and read rates. A shared scale flattens the lower half into a dead line; independent top/bottom scales with explicit ceiling labels (`↓ 12 MB/s`, `↑ 800 KB/s`) keep both directions expressive and honest.
3. **Icon-Only vs. Text Segmented Page Switcher:**
   - *Chose Text (`Now · Details · History`).* At 352 pt panel width, three short words fit comfortably in the header bar and remove the cognitive overhead of decoding abstract icons (`◐`, category symbol, `◷`).
4. **Flat Stroke vs. Subtle Dark-Mode Underlay Bloom:**
   - *Chose Subtle Dark-Mode Bloom.* A `5 pt` 16%-opacity blurred underlay beneath the `1.75 pt` stroke gives dark glass panels an authentic optical instrument depth while keeping light mode crisp and un-muddy.

---

## Consequences

- **Butter-Smooth, Deterministic Chart Motion:** Traces scroll at a constant pixel-per-second velocity with zero head wobble, zero late-sample snap-back, smooth spring/hysteresis Y scaling, and stable 5m/15m envelopes.
- **Testable Pure Math in `iStatsCore`:** `ChartTimeline`, `ChartScale`, and `Downsampler.alignedBuckets` are pure value types in `iStatsCore` covered by deterministic unit tests.
- **Lower CPU Overhead While Open:** Removing the perpetual 60 fps radar pulse and pre-projecting model-space points per sample keeps single-panel open CPU overhead well within the `≤ 1.5%` chart / `≤ 3%` total app budget.
- **Incremental, Reviewable Rollout:** Phase 8.5 is structured into logical sub-phases (Shell Correctness → Foundation Math → LiveChart v3 & History v3 → Header v2 & Kit v2 → Per-Panel Polish → Gallery & Verification) so each task commits cleanly and independently.

---

## Amendment (2026-11-13) — Shell Correctness First & B1–B14 Scope Expansion

Following code inspection of the shipped Phase 8 popover path (`docs/handoffs/08.5-amendment-plan.md`), the user accepted two amendments to this ADR:

1. **Scope Expansion (`B1–B14` Included):**
   In addition to the 13 animation defects (`A1–A13`), Phase 8.5 includes 14 correctness bugs (`B1–B14`):
   - **Shell lifecycle & sizing (`B1–B6`):** close/show fade race when switching widgets (`B1`), missing dynamic height updates outside tab switches (`B2`), non-scrolling Now page (`B3`), double-building `ViewThatFits` mid-animation (`B4`), async post-open `fittingSize` height jump (`B5`), and duplicate transient panels created when hovering onto an already-pinned category (`B6`).
   - **Chart & History telemetry (`B7–B10`):** flat-series glide snap-back when glide only resets on value change (`B7`), 59–61 point jitter from cutting windows against the newest sample and mixing scalar vs. full-sample ring sources (`B8`), `powerWatts` storing battery percentage when wattage is missing (`B9`), and `HistoryPage` loading its saved range in `onAppear` plus index-based stat-cell scrub drift (`B10`).
   - **Kit, Caching & Panel correctness (`B11–B14`):** default hover-highlight/copyability on non-copyable `MetricRow`s and hardcoded white crosshair rings in Light mode (`B11`), uncached non-app icon lookups on the main thread (`B12`), duplicate Fan Details page and synthetic Memory `25/65/95` gauge (`B13`), and redundant per-publish glance re-derivation with dead `PanelHostView` (`B14`).

2. **Reordered Rollout (`8.5.6` Split into `8.5.6a` and `8.5.6b`; `8.5.6a` Lands First):**
   The original rollout ordered Chart Engine (`8.5.1–8.5.5`) before Shell Motion (`8.5.6`). Because `B1–B6` have zero chart-engine dependencies and visibly break panel opening, switching, scrolling, and hover behavior today, Task `8.5.6` is split into:
   - **`8.5.6a` (Shell Lifecycle & Sizing):** Fixes `B1–B6`, `A10`, and `A11` (`MetricPanel` persistent hosting view with `sizingOptions = []` and `EmptyView()` close teardown, single `PanelContentHeightKey` preference height channel, `NSHostingController.sizeThatFits(in:)` pre-open sizing, single `ScrollView` across all tabs, close/show transition generation guard + status-item hit-test exclusion, visible pinned-panel guard, removal of cross-view `matchedGeometryEffect`, animated pin/unpin). **Lands first before `8.5.1–8.5.5`.**
   - **`8.5.6b` (Header v2, Text `PageSwitcher` & Inline Status Chip):** Retains its dependency on `8.5.4`, `8.5.5`, and `8.5.6a`, landing in Stage 3 alongside `8.5.7` Kit v2.

