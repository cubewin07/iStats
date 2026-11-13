# Phase 8.5 — Instrument 2: Chart Engine v3, Synchronized Motion & Popover Polish — Tasks

**Goal:** Eliminate the 13 animation defects (A1–A13), 14 shell/telemetry/panel correctness bugs (B1–B14), and 10 structural/visual weaknesses across all 8 category panels by fixing shell lifecycle and sizing first (`8.5.6a`), then shipping the time-domain chart engine v3, time-aligned min/max/mean history envelopes, header v2, Kit v2, and Instrument 2 panel polish (see [`plan.md`](./plan.md), [`design.md`](./design.md), [`requirements.md`](./requirements.md)).

**Status tracking:** Do not tick checkboxes here. Update [`docs/progress.md`](../../progress.md) when tasks finish.

**Commit policy:** Every task (`8.5.x`) MUST be committed separately with a clear, meaningful commit message once its tests pass.

---

### Stage 0 & Stage 1 — Specification & Shell Correctness (`8.5.0`, `8.5.6a`)
- [ ] **8.5.0** ADR 0010 time-domain chart engine v3, synchronized panel motion, and Phase 8.5 specification package (amended for B1–B14 and reordered rollout)
  - [`tasks/8.5.0-adr-0010.md`](./tasks/8.5.0-adr-0010.md)
- [ ] **8.5.6a** Shell lifecycle & sizing: persistent `NSHostingView` (`sizingOptions = []`, `EmptyView()` on close), `PanelContentHeightKey` top-anchored window resize, `NSHostingController.sizeThatFits` pre-open measurement, single `ScrollView` across all tabs, close/show transition generation guard + status-item hit-test exclusion, visible pinned-panel guard, remove cross-view `matchedGeometryEffect`, animated pin/unpin (fixes **B1–B6**, **A10**, **A11**; lands first before `8.5.1`)
  - [`tasks/8.5.6a-shell-lifecycle-and-sizing.md`](./tasks/8.5.6a-shell-lifecycle-and-sizing.md)

### Stage 2 — Time-Domain Chart Engine & History v3 (`8.5.1` – `8.5.5`, Sub-phase 8.5A)
- [ ] **8.5.1** Pure chart math v3: `ChartTimeline` delayed-edge follower, `ChartScale` nice ladder & hysteresis, domain floors, `Downsampler.alignedBuckets` (min/max/mean)
  - [`tasks/8.5.1-chart-math-v3.md`](./tasks/8.5.1-chart-math-v3.md)
- [ ] **8.5.2** Timestamped telemetry series (`ChartPoint`, `ChartSeries`, `BucketPoint`) in `MetricsStore` and `MetricsCoordinator`, edge-aligned 60 s slicing, pure `powerWatts` + `powerChargePercent` (fixes **B8**, **B9**)
  - [`tasks/8.5.2-timestamped-series.md`](./tasks/8.5.2-timestamped-series.md)
- [ ] **8.5.3** `LiveChart` v3: time-domain coordinate projection, timestamp-driven glide follower (fixes **B7**), independent mirrored half-scales, dark-mode underlay bloom, left gutter axis, calm head bead
  - [`tasks/8.5.3-live-chart-v3.md`](./tasks/8.5.3-live-chart-v3.md)
- [ ] **8.5.4** Stocks-style Glance header scrub readout (`ChartScrubState`) & spring-filtered crosshair v2 with surface-colored ring (fixes **B11** crosshair ring)
  - [`tasks/8.5.4-header-scrub-and-crosshair.md`](./tasks/8.5.4-header-scrub-and-crosshair.md)
- [ ] **8.5.5** `HistoryPage` v3: time-aligned min–max envelope band + mean trace, `init`-loaded range & timestamp-pinned stat scrub (fixes **B10**), bottom time axis, hover-revealed AVG/MAX annotations, scrub-aware stats strip
  - [`tasks/8.5.5-history-v3-envelope.md`](./tasks/8.5.5-history-v3-envelope.md)

### Stage 3 — Header v2 & Instrument Kit v2 (`8.5.6b` – `8.5.7`, Sub-phase 8.5B)
- [ ] **8.5.6b** Header v2, text `PageSwitcher` & inline status chip: `18 pt` tinted category badge, `13 pt` semibold title, text `PageSwitcher` (`Now · Details · History`), inline status chip next to Glance numeral (reserving `StatusRibbon` for actionable states)
  - [`tasks/8.5.6b-header-v2-and-switcher.md`](./tasks/8.5.6b-header-v2-and-switcher.md)
- [ ] **8.5.7** Instrument Kit v2: integrated `Section` card, hairline table `MetricRow` (`isCopyable = false` default, fixes **B11**), unified `SegmentedControl` & `FilterChip`, `LiveNumber` decimal cadence throttle, animated `TopConsumersModule` reordering + `ProcessIconCache` miss caching (fixes **B12**), secondary series hues in `PaletteContrast`, remove dead `PanelHostView` & memoize panel glance (fixes **B14**)
  - [`tasks/8.5.7-instrument-kit-v2.md`](./tasks/8.5.7-instrument-kit-v2.md)

### Stage 4 — Per-Panel Instrument 2 Polish (`8.5.8a` – `8.5.8h`, Sub-phase 8.5C)
- [ ] **8.5.8a** CPU panel polish: P/E cluster columns (`cpuEfficiency` hue), Details Load Average Dot Plot, 2-column per-core sparkline grid — [`tasks/8.5.8a-cpu-panel-polish.md`](./tasks/8.5.8a-cpu-panel-polish.md)
- [ ] **8.5.8b** Memory panel polish: remove synthetic `ArcGauge` (**B13**), add 3-stage Pressure Segmented Pill, 2-column composition legend (`swatch · label · bytes · %`), remove duplicate Details chart — [`tasks/8.5.8b-memory-panel-polish.md`](./tasks/8.5.8b-memory-panel-polish.md)
- [ ] **8.5.8c** GPU panel polish: `RingStack` with right-hand tabular legend, consolidated VRAM section, 2-column architecture spec sheet — [`tasks/8.5.8c-gpu-panel-polish.md`](./tasks/8.5.8c-gpu-panel-polish.md)
- [ ] **8.5.8d** Temperature panel polish: merge Spectrum and Thermal Groups into one annotated spectrum + ranked legend card, collapsible sensor group tables on Details — [`tasks/8.5.8d-thermal-panel-polish.md`](./tasks/8.5.8d-thermal-panel-polish.md)
- [ ] **8.5.8e** Fan panel polish: replace per-fan `ArcGauge` with Min–Max RPM Range Bar + live marker, RPM-locked calm turbine, real hardware table Details page (fixes **B13**) — [`tasks/8.5.8e-fan-panel-polish.md`](./tasks/8.5.8e-fan-panel-polish.md)
- [ ] **8.5.8f** Network panel polish: independent-scale mirrored waveform, consolidated Active Link + session totals card, hairline routing/Wi-Fi tables — [`tasks/8.5.8f-network-panel-polish.md`](./tasks/8.5.8f-network-panel-polish.md)
- [ ] **8.5.8g** Disk panel polish: independent-scale mirrored R/W waveform, 2-column boot storage legend, compact mounted volume capacity bars — [`tasks/8.5.8g-disk-panel-polish.md`](./tasks/8.5.8g-disk-panel-polish.md)
- [ ] **8.5.8h** Power panel polish: calm wattage-proportional `PowerFlowView`, refined health ring + capacity meter, hairline electrical diagnostics table — [`tasks/8.5.8h-power-panel-polish.md`](./tasks/8.5.8h-power-panel-polish.md)

### Stage 5 — Live Preview Gallery & Verification (`8.5.9`, Sub-phase 8.5D)
- [ ] **8.5.9** `InstrumentGalleryPreview` (synthetic 1 Hz stream with spikes, late samples, sleep gaps), CPU/energy budget verification, accessibility & appearance matrix pass, and `report.md`
  - [`tasks/8.5.9-gallery-and-verification.md`](./tasks/8.5.9-gallery-and-verification.md)

---

## Exit criteria
- All 13 animation defects (A1–A13) and 14 shell/telemetry/panel correctness bugs (B1–B14) are resolved and verified via deterministic unit tests and `InstrumentGalleryPreview`.
- `swift test --scratch-path /tmp/istats-build` and `xcodebuild test -scheme iStats -destination 'platform=macOS'` pass green.
- Single open panel CPU stays `≤ 3.0%` (`LiveChart` `≤ 1.5%`) at 1 Hz refresh on Apple Silicon.
- Every task is committed in its own atomic, meaningful git commit.
- `docs/phases/phase-08.5-instrument-polish/report.md` and `docs/progress.md` are updated and complete.

