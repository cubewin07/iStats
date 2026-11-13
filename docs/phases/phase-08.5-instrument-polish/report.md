# Phase 8.5 — Instrument 2 Polish — Completion Report

**Status:** Completed & Validated  
**Branch:** `feature/popover-and-widget-redesign`  
**Reference ADR:** [`ADR 0010`](../../architecture/adr/0010-time-domain-chart-engine-and-synchronized-panel-motion.md) (amended 2026-11-13 per [`08.5-amendment-plan.md`](../../handoffs/08.5-amendment-plan.md))

---

## 1. Executive Summary

Phase 8.5 ("Instrument 2") eliminated all **13 chart/shell animation defects (A1–A13)** and **14 shell, telemetry, and panel correctness bugs (B1–B14)** across the Instrument panel host, chart engine, component kit, and all 8 category panels:

1. **Shell Lifecycle & Sizing (`8.5.6a`):** Replaced per-switch hosting teardown and asynchronous `fittingSize` loops with a persistent `NSHostingView<AnyView>` (`sizingOptions = []`), synchronous `PanelContentHeightKey` preference reporting, `NSHostingController.sizeThatFits(in:)` pre-open sizing, a single `ScrollView` across all tabs, a `transitionGeneration` close/show race guard with status-item hit-test exclusion, and a visible pinned-panel guard.
2. **Time-Domain Chart Engine v3 & History v3 (`8.5.1`–`8.5.5`):** Replaced modulo-remainder index gliding and index-based downsampling with wall-clock timestamp coordinates (`ChartPoint`, `DualChartPoint`, `ChartTimeline`), nice-number Y-axis scaling with asymmetric `3.0 s` hysteresis (`ChartScale`, `ChartScaleState`), immutable wall-clock `BucketPoint` envelopes (`Downsampler.alignedBuckets` at `2.5 s` / `7.5 s`), independent mirrored half-scales, dark-mode underlay bloom, Stocks-style `ChartScrubState` header scrub readouts, and timestamp-pinned History stat-cell scrubbing.
3. **Header v2 & Instrument Kit v2 (`8.5.6b`–`8.5.7`):** Upgraded the panel header with an `18×18 pt` tinted category badge, text `PageSwitcher` (`Now · Details · History`), inline `InlineStatusChip` (`● Elevated`, `▲ Warning`, `◆ Critical`), integrated `Section` cards, non-copyable-by-default hairline `MetricRow`s, unified `SegmentedControl` and `FilterChip` primitives, `LiveNumber` `2.0 s` decimal cadence throttling, animated `TopConsumersModule` rank transitions with `ProcessIconCache` miss caching, WCAG AA secondary series hues, and deletion of dead `PanelHostView` (391 lines).
4. **8-Panel Instrument 2 Polish (`8.5.8a`–`8.5.8h`):** Rebuilt all 8 panels around timestamped scalar queries (`timedScalarHistory` / `timedDualScalarHistory`), per-sample glance memoisation, `≤ 3` Kit v2 `Section`s per page, honest telemetry instruments (CPU P/E cluster columns + Load Average dot plot + 2-col core grid; Memory 5-segment `SplitCapsule` + 3-step Pressure Pill replacing synthetic `ArcGauge`; GPU `RingStack` tabular legend + consolidated VRAM/architecture; Temperature unified Spectrum + Ranked Groups + collapsible Details; Fan `FanRPMRangeBar` + real hardware Details table; Network/Disk independent-scale mirrored `84 pt` hero charts; Power watts-only scalar chart + calm wattage-scaled `PowerFlowView`).
5. **Gallery Harness & Verification (`8.5.9`):** Synced `PopoverTab.supportedTabs(for: .fan)` to `[.overview, .detail, .history]`, added `#if DEBUG` `InstrumentGalleryPreview` with synthetic `Steady` / `10× Spike` / `+60 ms` jitter / `15 s` sleep-gap driver, and verified all CPU, accessibility, and appearance budgets.

### Reordered Rollout Note (ADR 0010 Amendment)

Per the 2026-11-13 amendment to [`ADR 0010`](../../architecture/adr/0010-time-domain-chart-engine-and-synchronized-panel-motion.md) and [`08.5-amendment-plan.md`](../../handoffs/08.5-amendment-plan.md), the originally planned `8.5.1 → 8.5.6` order was reordered by splitting `8.5.6` into `8.5.6a` and `8.5.6b` so shell lifecycle and sizing fixes landed **first**:

- **Stage 0 (`8.5.0`):** ADR 0010, Phase 8.5 spec package, and `B1–B14` / `8.5.6a` amendment.
- **Stage 1 (`8.5.6a`):** Shell lifecycle & sizing (`B1–B6`, `A10`, `A11`) — zero chart-engine dependencies.
- **Stage 2 (`8.5.1`–`8.5.5`):** Pure chart math v3, timestamped scalar series (`B8`, `B9`), `LiveChart` v3 (`B7`), `ChartScrubState` + crosshair v2 (`B11` ring), and `HistoryPage` v3 (`B10`).
- **Stage 3 (`8.5.6b` & `8.5.7`):** Header v2, text `PageSwitcher`, inline status chip, and Kit v2 (`A12`, `A13`, `B11` row copyability, `B12`, `B14`).
- **Stage 4 (`8.5.8a`–`8.5.8h`):** Per-panel Instrument 2 polish across CPU, Memory, GPU, Temperature, Fan (`B13`), Network, Disk, and Power.
- **Stage 5 (`8.5.9`):** `InstrumentGalleryPreview`, `PopoverConfig` sync, CPU/accessibility/appearance verification, and this completion report.

---

## 2. Animation Root-Cause Resolution Matrix (A1–A13)

| ID | Defect | Resolution | Task & Primary Files |
|----|--------|------------|----------------------|
| **A1** | Line snaps backward on late sample arrival | Replaced `truncatingRemainder` modulo phase with `ChartTimeline` one-sample delayed cursor (`targetEdge = min(now - sampleInterval, latestTimestamp)`) advancing monotonically at `1.0 s/s` (snapping only on `> 3 * sampleInterval` wake gaps). | `8.5.1`, `8.5.3` — [`LiveChartMath.swift`](../../../Sources/iStatsCore/LiveChartMath.swift), [`LiveChart.swift`](../../../iStats/UI/Instrument/LiveChart.swift) |
| **A2** | Rightmost trace end wobbles vertically | Eliminated per-frame `prevY + glide * (rawY - prevY)` interpolation; samples enter off-screen to the right and glide into view along a fixed Fritsch–Carlson spline (`ChartTimeline.valueAtEdge`). | `8.5.1`, `8.5.3` — [`LiveChartMath.swift`](../../../Sources/iStatsCore/LiveChartMath.swift), [`LiveChart.swift`](../../../iStats/UI/Instrument/LiveChart.swift) |
| **A3** | Horizontal jolt on sample arrival | Removed `n - 2` vs `n - 1` step-width switching; all points project via uniform time-domain equation `width * (1 - (edge - t) / window)`. | `8.5.1`, `8.5.3` — [`LiveChartMath.swift`](../../../Sources/iStatsCore/LiveChartMath.swift), [`LiveChart.swift`](../../../iStats/UI/Instrument/LiveChart.swift) |
| **A4** | Entire chart snaps taller or flatter in 1 frame | Added `ChartScale.niceCeiling` (`{1, 2, 2.5, 5} × 10^k` with `1.10` headroom) and `ChartScaleState` (`0.35 s` critically damped upward spring, `3.0 s` hold `< 70%` before `0.60 s` ease-out contraction). | `8.5.1`, `8.5.3` — [`LiveChartMath.swift`](../../../Sources/iStatsCore/LiveChartMath.swift), [`LiveChart.swift`](../../../iStats/UI/Instrument/LiveChart.swift) |
| **A5** | Trace stretches sideways during first 60 s | Timestamp-projected X coordinates occupy only their elapsed trailing fraction `(edge - t) / window` without horizontal stretching on partial buffers. | `8.5.1`, `8.5.3` — [`LiveChartMath.swift`](../../../Sources/iStatsCore/LiveChartMath.swift), [`LiveChart.swift`](../../../iStats/UI/Instrument/LiveChart.swift) |
| **A6** | 5m / 15m History curve "boils" every second | Added `Downsampler.alignedBuckets` grouping by fixed epoch `Int(floor(timestamp / bucketWidth))` (`2.5 s` for 5m, `7.5 s` for 15m) with `(min, max, mean)` `BucketPoint`s so closed historical buckets never shift. | `8.5.1`, `8.5.2`, `8.5.5` — [`Downsampler.swift`](../../../Sources/iStatsCore/Downsampler.swift), [`MetricsStore.swift`](../../../Sources/iStatsCore/MetricsStore.swift), [`HistoryPage.swift`](../../../iStats/UI/Panels/HistoryPage.swift) |
| **A7** | Trace jumps sideways when hover begins | Hover freezes `ChartTimeline.edge` at `frozenEdge` without switching renderers or resetting glide, then eases back over `250 ms` on hover exit. | `8.5.1`, `8.5.3` — [`LiveChartMath.swift`](../../../Sources/iStatsCore/LiveChartMath.swift), [`LiveChart.swift`](../../../iStats/UI/Instrument/LiveChart.swift) |
| **A8** | Perpetual 60 fps radar-ping pulse on head dot | Removed the looping 60 fps ring animation; replaced with a calm `6 pt` solid bead and `2 pt` `Instrument.Surface.panel` cutout halo. | `8.5.3` — [`LiveChart.swift`](../../../iStats/UI/Instrument/LiveChart.swift) |
| **A9** | Thermal / Fan history flattens near top | Added `ChartScale.domainFloor` (`max(20°C, floor((visibleMin - 5) / 10) * 10)` for Thermal; `minRPM` for Fan) wired through `LiveChartMode.domainFloor`. | `8.5.1`, `8.5.3`, `8.5.8d`, `8.5.8e` — [`LiveChartMath.swift`](../../../Sources/iStatsCore/LiveChartMath.swift), [`TemperaturePanel.swift`](../../../iStats/UI/Panels/TemperaturePanel.swift), [`FanPanel.swift`](../../../iStats/UI/Panels/FanPanel.swift) |
| **A10** | Switching to History clips and snaps | Removed cross-view `matchedGeometryEffect` between hero and History charts; unified height updates through `PanelContentHeightKey` + `PanelController.setContentHeight` (`0.32 s` curve matching `Motion.snappy`). | `8.5.6a`, `8.5.5` — [`PanelScaffold.swift`](../../../iStats/UI/Panels/PanelScaffold.swift), [`PanelController.swift`](../../../iStats/App/PanelController.swift), [`HistoryPage.swift`](../../../iStats/UI/Panels/HistoryPage.swift) |
| **A11** | Hard cut when switching categories | Reused single persistent `PanelBackgroundView` and `NSHostingView<AnyView>` (`sizingOptions = []`) in `MetricPanel`, swapping `rootView` in place and clearing to `EmptyView()` on close. | `8.5.6a` — [`MetricPanel.swift`](../../../iStats/App/MetricPanel.swift) |
| **A12** | Slot-machine decimal numerals | Added `LiveNumberCadenceGate` in `LiveNumber`, throttling fractional updates to a `2.0 s` minimum cadence unless delta `>= 1.0` display unit. | `8.5.7` — [`LiveNumber.swift`](../../../iStats/UI/Instrument/LiveNumber.swift) |
| **A13** | Process rows teleport on rank change | Keyed `TopConsumersModule` rows with `.animation(motionPolicy == .frozen ? nil : Motion.smooth, value: processes.map(\.pid))` and tabular `Instrument.Typography.value` digits. | `8.5.7` — [`TopConsumersModule.swift`](../../../iStats/UI/Instrument/Kit/TopConsumersModule.swift) |

---

## 3. Shell, Telemetry & Panel Correctness Resolution Matrix (B1–B14)

| ID | Bug | Resolution | Task & Primary Files |
|----|-----|------------|----------------------|
| **B1** | Switching widgets makes panel vanish | Added `transitionGeneration: UInt64` counter in `PanelController` (cancelling stale close teardown if `show()` bumps generation) and injected `MenuBarController.containsStatusItem(at:)` hit-test closure so dismissal monitors ignore status-item clicks. | `8.5.6a` — [`PanelController.swift`](../../../iStats/App/PanelController.swift), [`MenuBarController.swift`](../../../iStats/App/MenuBarController.swift) |
| **B2** | Dynamic body changes clip or leave gaps | Replaced both `DispatchQueue.main.async { updateFittingHeight }` blocks and `.fittingSize` reads with `PanelContentHeightKey` preference + `PanelStackLayout` forwarding every layout change synchronously to `PanelController.setContentHeight`. | `8.5.6a` — [`PanelScaffold.swift`](../../../iStats/UI/Panels/PanelScaffold.swift), [`MetricPanel.swift`](../../../iStats/App/MetricPanel.swift), [`PanelController.swift`](../../../iStats/App/PanelController.swift) |
| **B3** | Now page never scrolls past 560 pt | Wrapped all three tabs (`Now`, `Details`, `History`) in a single `ScrollView(.vertical, showsIndicators: false)` sized to `min(measuredBodyHeight, maxHeight - chromeHeight)` with `.scrollDisabled(bodyFits)`. | `8.5.6a` — [`PanelScaffold.swift`](../../../iStats/UI/Panels/PanelScaffold.swift) |
| **B4** | `ViewThatFits` builds twice & flips mid-animation | Deleted `ViewThatFits` in favor of the single `ScrollView` + `PanelStackLayout` container so each page body builds once. | `8.5.6a` — [`PanelScaffold.swift`](../../../iStats/UI/Panels/PanelScaffold.swift) |
| **B5** | Visible height jump on first open | `PanelController.show` builds content once and measures `NSHostingController.sizeThatFits(in: CGSize(width: 352, height: 560))` synchronously before ordering the panel front. | `8.5.6a` — [`PanelController.swift`](../../../iStats/App/PanelController.swift) |
| **B6** | Hover onto pinned category opens duplicate transient | `show` and `handleStatusItemHover` close any transient panel and front the existing visible pinned panel for that category (`MenuBarController` also guards `isTransientPanelOpen(for:)`). | `8.5.6a` — [`PanelController.swift`](../../../iStats/App/PanelController.swift), [`MenuBarController.swift`](../../../iStats/App/MenuBarController.swift) |
| **B7** | Flat series twitches/snaps back forever | `ChartTimeline` advances from wall-clock sample timestamps rather than value-change diffs, keeping idle/constant series completely still. | `8.5.1`, `8.5.3` — [`LiveChartMath.swift`](../../../Sources/iStatsCore/LiveChartMath.swift), [`LiveChart.swift`](../../../iStats/UI/Instrument/LiveChart.swift) |
| **B8** | 59–61 point jitter & full-sample ring vs scalar buffer mismatch | `MetricsStore.timedScalarHistory` / `timedDualScalarHistory` cut windows against the requested `referenceDate` instead of newest stored sample; all 8 panels and `HistoryPage` migrated to scalar buffers. | `8.5.2`, `8.5.5`, `8.5.8a–h` — [`MetricsStore.swift`](../../../Sources/iStatsCore/MetricsStore.swift), [`MetricsCoordinator.swift`](../../../iStats/App/MetricsCoordinator.swift), [`HistoryPage.swift`](../../../iStats/UI/Panels/HistoryPage.swift), `*Panel.swift` |
| **B9** | `powerWatts` mixes battery `%` when wattage is `nil` | Split `ScalarSeriesKey.powerChargePercent` (12th scalar key, `172,800` bytes total); `.powerWatts` records only `powerDrawWatts` and `PowerPanel` / `HistoryPage` read watts strictly by default. | `8.5.2`, `8.5.5`, `8.5.8h` — [`MetricsStore.swift`](../../../Sources/iStatsCore/MetricsStore.swift), [`HistoryPage.swift`](../../../iStats/UI/Panels/HistoryPage.swift), [`PowerPanel.swift`](../../../iStats/UI/Panels/PowerPanel.swift) |
| **B10** | History range flashes 1m & stat scrub drifts by index | Initialized `HistoryPage.selectedRange` from `preferences.historyRange(for:)` in `init` and replaced index-based `scrubIndex` with timestamp-anchored `PinnedScrub(timestamp:kind:)`. | `8.5.5` — [`HistoryPage.swift`](../../../iStats/UI/Panels/HistoryPage.swift) |
| **B11** | All rows hover/copyable by default & white Light-mode crosshair ring | Changed `MetricRow.isCopyable` default to `false` (hover highlight + `doc.on.doc` glyph only when copyable); changed crosshair dot cutout ring from hardcoded white to `Instrument.Surface.panel`. | `8.5.4`, `8.5.7` — [`MetricRow.swift`](../../../iStats/UI/Instrument/Kit/MetricRow.swift), [`LiveChart.swift`](../../../iStats/UI/Instrument/LiveChart.swift) |
| **B12** | Uncached non-app process icon lookups on main thread | Added bounded `.miss` negative caching to `ProcessIconCache` so non-app processes never re-query `NSRunningApplication(processIdentifier:)` on subsequent renders. | `8.5.7` — [`TopConsumersModule.swift`](../../../iStats/UI/Instrument/Kit/TopConsumersModule.swift) |
| **B13** | Fan Details duplicates Now & Memory shows synthetic `25/65/95` `ArcGauge` | Removed synthetic `ArcGauge` in `MemoryPanel` (replaced by 3-step Pressure Pill + 5-part `SplitCapsule`); added real per-fan hardware bounds table in `FanPanel` Details and synced `PopoverTab.supportedTabs(for: .fan)` to `[.overview, .detail, .history]`. | `8.5.8b`, `8.5.8e`, `8.5.9` — [`MemoryPanel.swift`](../../../iStats/UI/Panels/MemoryPanel.swift), [`FanPanel.swift`](../../../iStats/UI/Panels/FanPanel.swift), [`PopoverConfig.swift`](../../../Sources/iStatsCore/PopoverConfig.swift) |
| **B14** | Dead `PanelHostView` & redundant per-publish glance re-derivation | Deleted unused `PanelHostView` (391 lines) from `PanelFactory.swift`; added per-sample-timestamp glance/state memoisation (`DerivedStateCache` / `DerivedMemo` / `MemoCache` / `DerivedCache`) across all 8 category panels. | `8.5.7`, `8.5.8a–h` — [`PanelFactory.swift`](../../../iStats/UI/Panels/PanelFactory.swift), `*Panel.swift` |

---

## 4. Test Verification & Results

All SwiftPM CLI tests, Xcode app tests, and Release compilation passed after the final Phase 8.5 code edit (`8.5.9`, commit `43ca798`) with zero failures and zero skipped assertions:

| Suite / Build | Command | Result |
|---------------|---------|--------|
| **SwiftPM Full Test Suite** | `swift test --scratch-path /tmp/istats-build-gallery` | **654 passed, 0 failed** (`iStatsCoreTests`: 278/278, `iStatsTests`: 376/376) |
| **Xcode App Test Suite** | `xcodebuild test -scheme iStats -destination 'platform=macOS' -derivedDataPath /tmp/istats-dd-gallery` | **`** TEST SUCCEEDED **`** (`iStatsTests`: 368/368 passed, 0 failed) |
| **SwiftPM Release Build** | `swift build -c release --scratch-path /tmp/istats-build-gallery` | **Build complete** (`0` errors, exit code `0`) |

### New & Expanded Phase 8.5 Test Coverage
- [`DownsamplerTests.swift`](../../../Tests/iStatsCoreTests/DownsamplerTests.swift) (4 tests): Fixed epoch grouping, 5m/15m append immutability, whole-bucket window cutoff, and empty/edge inputs.
- [`LiveChartMathTests.swift`](../../../Tests/iStatsCoreTests/LiveChartMathTests.swift) (19 tests): `ChartTimeline` delayed edge, late-sample monotonicity, wake-from-sleep snap, scrub freeze + 250 ms release ease, `ChartScale` nice ladder, domain floors, and `ChartScaleState` 3.0 s hysteresis.
- [`MetricsStoreTests.swift`](../../../Tests/iStatsCoreTests/MetricsStoreTests.swift) (18 tests): Requested-edge window slicing (`B8`), 12-series footprint (`172,800` bytes `<= 175,000`), pure `.powerWatts` vs `.powerChargePercent` (`B9`), and dual-channel timestamp alignment.
- [`PaletteContrastTests.swift`](../../../Tests/iStatsCoreTests/PaletteContrastTests.swift) & [`PopoverConfigTests.swift`](../../../Tests/iStatsCoreTests/PopoverConfigTests.swift): WCAG AA contrast for secondary series (`cpuEfficiency`, `memoryWired`, `memoryCompressed`, `memoryCached`) and synced `.fan` tabs (`[.overview, .detail, .history]`).
- [`PanelPlacementTests.swift`](../../../Tests/iStatsTests/PanelPlacementTests.swift) (4 tests) & [`PanelControllerLifecycleTests.swift`](../../../Tests/iStatsTests/PanelControllerLifecycleTests.swift) (8 tests): Pre-open `sizeThatFits`, bottom-margin/screen clamping, persistent `NSHostingView` reuse, `EmptyView()` close teardown, close/show race generation guard, pinned-panel hover/show guard, `MenuBarController` status-item hit-test injection, and animated pin/unpin.
- [`PanelScaffoldTests.swift`](../../../Tests/iStatsTests/PanelScaffoldTests.swift) (32 tests): `PanelContentHeightKey` single height channel, single `ScrollView`, `ChartScrubState` header routing, insight caption row below hero chart, tinted badge header, text `PageSwitcher`, and `InlineStatusChip` vs actionable `StatusRibbon`.
- [`InstrumentKitTests.swift`](../../../Tests/iStatsTests/InstrumentKitTests.swift) (8 tests): `Section` / `Module` source compatibility, `MetricRow` `isCopyable = false` default + `0.5 pt` hairlines, `SegmentedControl` & `FilterChip`, `LiveNumberCadenceGate`, `ProcessIconCache` miss caching, and `TopConsumersModule`.
- [`SwiftUIViewsTests.swift`](../../../Tests/iStatsTests/SwiftUIViewsTests.swift): `LiveChart` v3 time-domain/envelope/mirrored/flat-series tests, `HistoryPage` v3 tests (`B8–B10`), all 8 polished panels across `Now`/`Details`/`History` + `FanPanel` `ImageRenderer` bitmap diff (`B13`) + fanless/desktop fallbacks, and `#if DEBUG` `InstrumentGalleryPreview` harness test.

---

## 5. Performance, Accessibility & Appearance Verification

### 5.1 Measured Performance & CPU Budgets (`PerformancePassTests`, R8.5.6)

| Benchmark | SwiftPM (`swift test`, Debug `-Onone`) | Xcode (`xcodebuild test`, Debug) | Budget |
|-----------|----------------------------------------|----------------------------------|--------|
| **60-Frame `LiveChart` v3 (single + mirrored, `NSBitmapImageRep` + `CGContext`)** | `wall=22.88 ms`, `cpu=22.88 ms`, **`estChartCPU=1.144%`** | `wall=23.27 ms`, `cpu=23.31 ms`, **`estChartCPU=1.165%`** | **`<= 1.5%`** |
| **Single-Panel 1 Hz Total App Refresh (`CPUPanel` + 8 samplers)** | `wall=65.52 ms/s`, `cpu=19.00 ms/s`, **`totalAppCPU=1.900%`** | `wall=59.75 ms/s`, `cpu=18.63 ms/s`, **`totalAppCPU=1.863%`** | **`<= 3.0%`** |
| **8-Sampler Average Pass Duration** | `62.41 ms` | `67.57 ms` | `< 100.0 ms` |

- **Frame-rate throttling:** `LiveChart.frameInterval(isPinnedNonKey:)` throttles `TimelineView` to `30 fps` (`1/30 s`) for pinned non-key HUDs and `60 fps` (`1/60 s`) for key/transient panels, pausing completely under `motionPolicy != .full` or active scrub.
- **Memory footprint:** `MetricsStore` holds 12 scalar series (`900` points each) in `172,800` bytes (`~168.75 KB`), with zero disk/network telemetry (ADR 0006).

### 5.2 Accessibility, Appearance & Gallery Verification (`AccessibilityAppearanceTests`)

- **VoiceOver `AXChartDescriptor`:** `testVoiceOverAXChartDescriptorAcrossAll8CategoriesAndModes` verified `AXNumericDataAxisDescriptor` axes, series counts, data points (`20` samples), and `Now / Min / Avg / Max` summaries across all 8 categories (`single`, `stacked`, `mirrored`, `banded`, `envelope`, and `mirroredEnvelope`) plus graceful empty-state `"No data available"` degradation.
- **Increase Contrast (Light & Dark):** `testIncreaseContrastAcrossAll8PolishedPanels` laid out all 8 polished panels across `.overview` and `.detail` under `NSAppearance.Name.accessibilityHighContrastAqua` and `.accessibilityHighContrastDarkAqua` at `352 pt` width (`> 100 pt` height).
- **Differentiate Without Color:** `testDifferentiateWithoutColorAcrossAll8PolishedPanelsAndStatusSymbols` verified distinct glyph + text tokens `[StatusLevel.elevated, .warning, .critical]` → `["● Elevated", "▲ Warning", "◆ Critical"]` via `InlineStatusChip.displayText(for:)` and clean `352 pt` layout of all 8 panels under warning/critical conditions.
- **Reduce Motion & Frozen Policy:** `testReduceMotionAndFrozenMotionAcrossAll8PolishedPanels` verified `MotionPolicy.resolve` and immediate `ChartModel` edge snapping (zero glide lag) plus layout across all 8 panels and all supported tabs under `.reduced` and `.frozen`.
- **Interactive Gallery (`#if DEBUG`):** `InstrumentGalleryPreview` in [`PanelFactory.swift`](../../../iStats/UI/Panels/PanelFactory.swift) exercises all 8 panels under synthetic 1 Hz `Steady` vs `10× Spike` load, `+60 ms` late-sample jitter, `15 s` sleep-gap injection, Light/Dark appearance, `.full`/`.reduced`/`.frozen` `MotionPolicy`, and `Now`/`Details`/`History` tabs.

---

## 6. Files & Commits Summary

Phase 8.5 shipped as granular, per-task atomic commits on `feature/popover-and-widget-redesign` (each verified green before advancing):

| Commit | Task | Summary |
|--------|------|---------|
| `687a93f` | `8.5.0` | ADR 0010 (`0010-time-domain-chart-engine-and-synchronized-panel-motion.md`) |
| `cd01c6d` | `8.5.0` | Phase 8.5 requirements, design, and plan |
| `3bc9e60`, `4928ee2`, `c9f9a88` | `8.5.0` | Task specs (`8.5.0`–`8.5.9`) and progress registration |
| `125469a`, `be36a03` | `8.5.0` | Amendment for `B1–B14` and split `8.5.6a` shell correctness first |
| `0eef8fb` | `8.5.6a` | Shell lifecycle, `PanelContentHeightKey`, `sizeThatFits`, single `ScrollView`, race/pinned guards (`MetricPanel`, `PanelController`, `PanelScaffold`, `MenuBarController`, `PanelPlacementTests`, `PanelControllerLifecycleTests`) |
| `874df9c` | `8.5.1` | Pure chart math v3 (`ChartPoint`, `DualChartPoint`, `ChartTimeline`, `ChartScale`, `ChartScaleState`, `BucketPoint`, `Downsampler.alignedBuckets`, `DownsamplerTests`, `LiveChartMathTests`) |
| `542865e` | `8.5.2` | Timestamped/bucketed scalar queries & `powerChargePercent` (`MetricsStore`, `MetricsCoordinator`, `MetricsStoreTests`) |
| `c46a31c` | `8.5.3` | `LiveChart` v3 time-domain engine (`ChartModel`, `ChartRenderer`, `ScrubController`, independent mirrored scales, dark bloom, calm head bead) |
| `89c158c` | `8.5.4` | `ChartScrubState` Glance header scrub readout, `ChartScrubAction`, and crosshair v2 |
| `2a9369c` | `8.5.5` | `HistoryPage` v3 (`BucketPoint` envelopes, `init`-loaded range, timestamp-pinned scrub, bottom time axis, Kit v2 controls) |
| `a514386` | `8.5.6b` | Header v2 (`18 pt` badge), text `PageSwitcher`, `InlineStatusChip`, actionable-only `StatusRibbon` |
| `a986196` | `8.5.7` | Instrument Kit v2 (`Section`, hairline `MetricRow`, `SegmentedControl`, `FilterChip`, `LiveNumberCadenceGate`, `ProcessIconCache` miss caching, `PaletteContrast` hues, delete `PanelHostView`, `InstrumentKitTests`) |
| `840a573` | `8.5.8a` | `CPUPanel` & `ClusterStrip` polish (P/E columns, Load Average dot plot, 2-col per-core grid, `B14` memoisation) |
| `d1d9ec8` | `8.5.8b` | `MemoryPanel` polish (3-step Pressure Pill, 5-part `SplitCapsule`, 2-col legend, VM table, remove synthetic `ArcGauge` & duplicate chart) |
| `fa4bd0d` | `8.5.8c` | `GPUPanel` polish (`RingStack` tabular legend, consolidated VRAM/Telemetry, architecture spec table, `B14` memoisation) |
| `9b8f28a` | `8.5.8d` | `TemperaturePanel` polish (banded thermal chart with `domainFloor`, unified Spectrum + Ranked Legend, collapsible Details groups) |
| `3ba905e` | `8.5.8e` | `FanPanel` & `TurbineView` polish (`FanRPMRangeBar`, calm turbine, real hardware Details table fixing `B13`) |
| `72f6015` | `8.5.8f` | `NetworkPanel` polish (`84 pt` independent-scale mirrored chart, Active Link + session totals, Routing & DNS, Details) |
| `d491c19` | `8.5.8g` | `DiskPanel` polish (`84 pt` independent-scale mirrored R/W chart, 2-col storage legend, hairline tables, Mounted Volumes) |
| `19bcc2f` | `8.5.8h` | `PowerPanel` & `PowerFlowView` polish (watts-only scalar chart, calm dash flow, desktop `Meter` card, health & diagnostics tables) |
| `43ca798` | `8.5.9` | `PopoverConfig` Fan Details sync, `#if DEBUG` `InstrumentGalleryPreview`, accessibility/appearance/CPU budget tests |
| *(docs finalization)* | `8.5.9` | Corrected `08.5-8.5.9-summary.md` wording, completed Phase 8.5 `report.md`, and closed Phase 8.5 in `docs/progress.md` |
