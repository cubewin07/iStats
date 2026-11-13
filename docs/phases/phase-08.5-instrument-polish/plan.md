# Phase 8.5 — Instrument 2: Chart Engine v3, Synchronized Motion & Popover Polish — Plan

**Status:** Docs on disk, not closed (see [`docs/progress.md`](../../progress.md))  
**ADR:** [`docs/architecture/adr/0010-time-domain-chart-engine-and-synchronized-panel-motion.md`](../../architecture/adr/0010-time-domain-chart-engine-and-synchronized-panel-motion.md)  
**Spec files:** [`requirements.md`](./requirements.md) · [`design.md`](./design.md) · [`tasks.md`](./tasks.md)

---

## 1. Why Phase 8.5 Exists

Phase 8 replaced `NSPopover` with `MetricPanel` and delivered the initial "Instrument" design language. However, a deep code audit of `LiveChart`, `HistoryPage`, `PanelScaffold`, `PanelController`, `Downsampler`, `MetricsStore`, and all 8 category panels exposed **13 concrete animation defects (A1–A13)**, **14 shell, telemetry, and panel correctness bugs (B1–B14)**, and **10 visual/structural weaknesses** that kept the popovers feeling half-done:

### 1.1 The 13 Animation Root Causes
| ID | Symptom | Root Cause in Phase 8 Code |
|----|---------|----------------------------|
| **A1** | Line snaps backward by 1 step periodically | `LiveChart` computed glide via `elapsed.truncatingRemainder(dividingBy: interval)`. A sample arriving even 20 ms late wrapped `glide` from `1.0 → 0.0` before the new sample arrived. |
| **A2** | Rightmost end of the trace wobbles vertically | The last sample's Y was interpolated from the previous value every frame (`prevY + glide * (rawY - prevY)`), causing Fritsch–Carlson spline tangents on the last 2–3 segments to bend continuously. |
| **A3** | Horizontal jolt on every sample arrival | Step width switched from `plotWidth / (n - 2)` when `glide > 0` to `plotWidth / (n - 1)` when `glide == 0`. |
| **A4** | Entire chart snaps taller or flatter | `computeMaxBound` (`max * 1.15`) had zero easing or hold hysteresis; when a peak exited the window, every point rescaled in 1 frame. |
| **A5** | Trace stretches sideways for the first 60 s | X positions were index-based (`i * dx`) rather than timestamp-based, so horizontal scale changed on every sample until the buffer filled. |
| **A6** | 5m / 15m History curve "boils" every second | `Downsampler` bucketed by array index (`0..<count`). Each new 1 Hz sample shifted all 120 bucket boundaries by 1 index, reshuffling peaks across the entire curve. |
| **A7** | Trace jumps sideways when hover begins | Hover switched from the gliding `TimelineView` to a static `Canvas` with `glideFraction: 0`, shifting the curve by up to `1 dx`. |
| **A8** | Perpetual 60 fps radar-ping pulse | The head dot drew an infinite 60 fps expanding ring, looking busy and burning CPU inside a CPU monitor. |
| **A9** | Thermal / Fan history is a flat line near the top | Hardcoded `0.0` Y-axis floor compressed 45–60 °C readings into the top 25% of the plot. |
| **A10** | Switching to History clips and snaps | `matchedGeometryEffect` (0.32 s spring) fought an async `DispatchQueue.main.async` `NSPanel.setFrame` (0.16 s easeInOut). |
| **A11** | Hard cut when switching categories | `MetricPanel.setSwiftUIContent` destroyed and recreated `PanelBackgroundView` and `NSHostingView` on every switch. |
| **A12** | Slot-machine decimal numerals | `LiveNumber` triggered `.numericText` rolling on every 1 s tick even for 0.1 sub-unit jitter. |
| **A13** | Process rows teleport on rank change | `TopConsumersModule` had no reorder transition and used variable-width SF Mono formatting. |

### 1.2 Shell, Telemetry & Panel Correctness Bugs (B1–B14)

In addition to `A1–A13`, the follow-up audit (see [`docs/handoffs/08.5-amendment-plan.md`](../../handoffs/08.5-amendment-plan.md)) identified 14 correctness bugs across shell lifecycle, chart state, and panel plumbing:

| ID | Bug | Where |
|----|-----|-------|
| **B1** | Clicking a different widget while a panel is open makes the panel vanish. The local mouse-down monitor starts `close()` (0.12 s fade), mouse-up calls `show()`, which reuses the still-visible fading panel and skips the fade-in; the close teardown then `orderOut`s it while state says "open". | `PanelController.close/show` + monitors |
| **B2** | Window height only updates on first appear and on tab change. Any other height change clips content or leaves a gap: top-processes list filling in, status ribbon appearing, "Show all interfaces", pause toggle. | `PanelScaffold.swift` |
| **B3** | The Now page never scrolls. Content taller than the 560 pt cap is cut off (CPU on many-core Macs, Temperature). | `PanelScaffold.swift` |
| **B4** | Details/History use `ViewThatFits`, which builds the page twice and can flip between plain and scrolling layout while the window animates. | `PanelScaffold.swift` |
| **B5** | First open measures `fittingSize` before layout, then corrects asynchronously — visible height jump on open. | `PanelController.reposition` |
| **B6** | Hover-scrubbing onto a widget whose category is already pinned opens a second, transient panel for it. Keyboard commands hit both, and the transient shows a close button that closes the pinned one. | `PanelController.handleStatusItemHover` |
| **B7** | On a flat series (idle network, steady memory, stopped fan) the chart glides and snaps back every second forever: the glide clock only resets when values *change*. | `LiveChart.swift` |
| **B8** | The hero chart's point count fluctuates 59–61 because the 60 s window is cut relative to the newest sample, so the curve's horizontal scale jitters. Panels also mix two history sources (scalar buffer vs full-sample ring), so 1m and 5m History disagree. | `MetricsStore.scalarHistory`, panel `deriveGlance`s |
| **B9** | The `powerWatts` series stores battery **percent** whenever wattage is missing — watts and percent mixed in one line. | `MetricsStore.swift` |
| **B10** | History range is loaded in `onAppear`, so the page draws 1m then flips to the saved range. Tap-to-scrub on a stat cell freezes the chart on a fixed index that drifts as samples arrive. | `HistoryPage.swift` |
| **B11** | Every row hover-highlights and is click-to-copy by default, including labels like "Read-only (ADR 0004)". Crosshair dots use a hardcoded white ring (wrong in Light mode). | `MetricRow.swift`, `LiveChart.swift` |
| **B12** | Process icons for non-app processes are looked up on the main thread on every render (misses are never cached). | `TopConsumersModule.swift` |
| **B13** | Fan "Details" renders the same page as "Now". Memory shows a fabricated 25/65/95 gauge (also tracked in `8.5.8b`). | `FanPanel.swift`, `MemoryPanel.swift` |
| **B14** | Each panel re-derives its glance (history copy, filter, downsample, insight) on every coordinator publish; `PanelHostView` is dead code that does it three times. | `*Panel.deriveGlance`, `PanelFactory.swift` |

### 1.3 Locked Architectural Decisions (ADR 0010, as amended)
1. **Mirrored Charts (Network, Disk):** **Independent scales per half**, each with its own top/bottom ceiling label (`↓ 12 MB/s`, `↑ 800 KB/s`) so upload/write activity is never flattened by asymmetric download/read peaks.
2. **Page Switcher:** **Text segmented control (`Now · Details · History`)** with a sliding glass puck (`matchedGeometryEffect`), replacing the 3 cryptic icons.
3. **Dark-Mode Line Glow:** **Subtle dark-mode underlay bloom** (`5 pt` stroke at `16%` opacity with `3 pt` blur underneath the crisp `1.75 pt` stroke, dark appearance only).
4. **Reordered Rollout Strategy (ADR 0010 Amendment):** **Shell correctness lands first**, followed by the chart engine and Instrument 2 polish in granular per-task commits:
   - **Stage 1 (`8.5.6a`):** Shell lifecycle & sizing (`B1–B6`, `A10`, `A11`) — zero chart-engine dependencies; lands first before `8.5.1`.
   - **Stage 2 (`8.5.1–8.5.5`):** Time-Domain Chart Engine v3 & History v3 (`A1–A9`, `B7–B10`).
   - **Stage 3 (`8.5.6b` & `8.5.7`):** Header v2, text `PageSwitcher`, inline status chip, and Kit v2 (`A12–A13`, `B11–B12`, `B14`).
   - **Stage 4 (`8.5.8a–8.5.8h`):** Per-panel Instrument 2 polish pass (`B13` included).
   - **Stage 5 (`8.5.9`):** `InstrumentGalleryPreview`, performance/accessibility verification, and `report.md`.

---

## 2. Sub-Phases & Commit Discipline

Every task in Phase 8.5 is self-contained, keeps the build and test suite green, and is committed **separately and meaningfully** (never bundled into a giant commit):

1. **Stage 0 & Stage 1 — Specification & Shell Correctness (`8.5.0`, `8.5.6a`)**
   - `8.5.0`: ADR 0010 & Phase 8.5 specification package (amended for `B1–B14` and reordered rollout).
   - `8.5.6a`: Shell lifecycle & sizing (`MetricPanel` persistent hosting view with `sizingOptions = []` and `EmptyView()` close teardown, single `PanelContentHeightKey` preference height channel, `NSHostingController.sizeThatFits(in:)` pre-open measurement, single `ScrollView` across all tabs replacing `ViewThatFits`, transition generation counter + status-item hit-test closure, visible pinned-panel guard, removal of cross-view `matchedGeometryEffect`, animated pin/unpin). Fixes `B1–B6`, `A10`, `A11`.
2. **Stage 2 — Time-Domain Chart Engine & History v3 (`8.5.1` – `8.5.5`)**
   - `8.5.1`: Pure math in `iStatsCore` (`ChartTimeline`, `ChartScale` with nice ladder & hysteresis, `Downsampler.alignedBuckets` min/max/mean, domain floors).
   - `8.5.2`: Timestamped series plumbing (`ChartPoint`, `ChartSeries`, `BucketPoint`, `MetricsStore` / `MetricsCoordinator` timestamped queries cut against requested edge, pure `powerWatts` + `powerChargePercent` key; fixes `B8`, `B9`).
   - `8.5.3`: `LiveChart` v3 (`ChartModel`, `ChartRenderer`, `ScrubController`, timestamp-driven edge follower fixing `B7`, independent mirrored scales, dark-mode bloom, calm head bead).
   - `8.5.4`: Stocks-style Glance header scrub readout (`ChartScrubState` environment) & spring-followed crosshair v2 with surface-colored ring (`B11`).
   - `8.5.5`: `HistoryPage` v3 (time-aligned min–max envelope band + mean line, range loaded in `init`, timestamp-pinned stat-cell scrub fixing `B10`, time axis ticks, hover-revealed AVG/PEAK markers, scrub-aware stats strip).
3. **Stage 3 — Header v2 & Kit v2 (`8.5.6b` – `8.5.7`)**
   - `8.5.6b`: Tinted category badge header, text `PageSwitcher` (`Now · Details · History`), inline status chip, insight line beneath hero chart.
   - `8.5.7`: Kit v2 (`Section` card with internal header, hairline table `MetricRow` with `isCopyable` defaulting to `false` fixing `B11`, unified `SegmentedControl` & `FilterChip`, `LiveNumber` decimal cadence throttle, animated `TopConsumersModule`, `ProcessIconCache` miss caching fixing `B12`, secondary series hues in `PaletteContrast`, delete dead `PanelHostView` and memoize panel glance per sample timestamp fixing `B14`).
4. **Stage 4 — Per-Panel Instrument 2 Polish (`8.5.8a` – `8.5.8h`)**
   - `8.5.8a` CPU · `8.5.8b` Memory · `8.5.8c` GPU · `8.5.8d` Thermal · `8.5.8e` Fan (adds real hardware table Details page fixing `B13`) · `8.5.8f` Network · `8.5.8g` Disk · `8.5.8h` Power.
5. **Stage 5 — Live Preview Gallery & Verification (`8.5.9`)**
   - `8.5.9`: `InstrumentGalleryPreview` with synthetic 1 Hz stream (spikes, late samples, sleep gaps), CPU/energy budget validation, accessibility check, and `report.md`.

