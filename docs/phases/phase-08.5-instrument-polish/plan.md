# Phase 8.5 — Instrument 2: Chart Engine v3, Synchronized Motion & Popover Polish — Plan

**Status:** Docs on disk, not closed (see [`docs/progress.md`](../../progress.md))  
**ADR:** [`docs/architecture/adr/0010-time-domain-chart-engine-and-synchronized-panel-motion.md`](../../architecture/adr/0010-time-domain-chart-engine-and-synchronized-panel-motion.md)  
**Spec files:** [`requirements.md`](./requirements.md) · [`design.md`](./design.md) · [`tasks.md`](./tasks.md)

---

## 1. Why Phase 8.5 Exists

Phase 8 replaced `NSPopover` with `MetricPanel` and delivered the initial "Instrument" design language. However, a deep code audit of `LiveChart`, `HistoryPage`, `PanelScaffold`, `PanelController`, `Downsampler`, and all 8 category panels exposed **13 concrete animation defects (A1–A13)** and **10 visual/structural weaknesses** that kept the popovers feeling half-done:

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

### 1.2 Locked Architectural Decisions (ADR 0010)
1. **Mirrored Charts (Network, Disk):** **Independent scales per half**, each with its own top/bottom ceiling label (`↓ 12 MB/s`, `↑ 800 KB/s`) so upload/write activity is never flattened by asymmetric download/read peaks.
2. **Page Switcher:** **Text segmented control (`Now · Details · History`)** with a sliding glass puck (`matchedGeometryEffect`), replacing the 3 cryptic icons.
3. **Dark-Mode Line Glow:** **Subtle dark-mode underlay bloom** (`5 pt` stroke at `16%` opacity with `3 pt` blur underneath the crisp `1.75 pt` stroke, dark appearance only).
4. **Rollout Strategy:** **Two-stage execution with granular per-task commits** — Sub-phases 8.5A–8.5B (Tasks `8.5.1–8.5.6`: Chart Engine v3, History v3, Synchronized Shell Motion) land first to eliminate all 13 animation defects, followed by Sub-phases 8.5C–8.5D (Tasks `8.5.7–8.5.9`: Kit v2, Per-Panel Polish Pass, and Live Gallery Verification).

---

## 2. Sub-Phases & Commit Discipline

Every task in Phase 8.5 is self-contained, keeps the build and test suite green, and is committed **separately and meaningfully** (never bundled into a giant commit):

1. **Sub-phase 8.5A — Time-Domain Chart Engine & History v3 (`8.5.0` – `8.5.5`)**
   - `8.5.0`: ADR 0010 & Phase 8.5 specification package.
   - `8.5.1`: Pure math in `iStatsCore` (`ChartTimeline`, `ChartScale` with nice ladder & hysteresis, `Downsampler.alignedBuckets` min/max/mean, domain floors).
   - `8.5.2`: Timestamped series plumbing (`ChartPoint`, `ChartSeries`, `MetricsStore` / `MetricsCoordinator` timestamped queries).
   - `8.5.3`: `LiveChart` v3 (`ChartModel`, `ChartRenderer`, `ScrubController`, independent mirrored scales, dark-mode bloom, calm head bead).
   - `8.5.4`: Stocks-style Glance header scrub readout (`ChartScrubState` environment) & spring-followed crosshair v2.
   - `8.5.5`: `HistoryPage` v3 (time-aligned min–max envelope band + mean line, time axis ticks, hover-revealed AVG/PEAK markers, scrub-aware stats strip).
2. **Sub-phase 8.5B — Synchronized Shell Motion & Kit v2 (`8.5.6` – `8.5.7`)**
   - `8.5.6`: `MetricPanel` persistent hosting view, synchronous `PreferenceKey` height animation matched to `Motion.snappy`, tinted category badge header, text `PageSwitcher`, inline status chip.
   - `8.5.7`: Kit v2 (`Section` card with internal header, hairline table `MetricRow`, unified `SegmentedControl` & `FilterChip`, `LiveNumber` decimal cadence throttle, animated `TopConsumersModule`, secondary series hues in `PaletteContrast`).
3. **Sub-phase 8.5C — Per-Panel Instrument 2 Polish (`8.5.8a` – `8.5.8h`)**
   - `8.5.8a` CPU · `8.5.8b` Memory · `8.5.8c` GPU · `8.5.8d` Thermal · `8.5.8e` Fan · `8.5.8f` Network · `8.5.8g` Disk · `8.5.8h` Power.
4. **Sub-phase 8.5D — Live Preview Gallery & Verification (`8.5.9`)**
   - `8.5.9`: `InstrumentGalleryPreview` with synthetic 1 Hz stream (spikes, late samples, sleep gaps), CPU/energy budget validation, accessibility check, and `report.md`.

