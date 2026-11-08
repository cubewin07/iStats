# Phase 8.5 — Instrument 2: Chart Engine v3, Synchronized Motion & Popover Polish — Tasks

**Goal:** Eliminate the 13 animation defects (A1–A13) and 10 structural/visual weaknesses across all 8 category panels by shipping the time-domain chart engine v3, time-aligned min/max/mean history envelopes, synchronized window morphing, and Instrument 2 panel polish (see [`plan.md`](./plan.md), [`design.md`](./design.md), [`requirements.md`](./requirements.md)).

**Status tracking:** Do not tick checkboxes here. Update [`docs/progress.md`](../../progress.md) when tasks finish.

**Commit policy:** Every task (`8.5.x`) MUST be committed separately with a clear, meaningful commit message once its tests pass.

---

### Sub-phase 8.5A — Time-Domain Chart Engine & History v3 (Stage 1: Animation Core)
- [ ] **8.5.0** ADR 0010 time-domain chart engine v3, synchronized panel motion, and Phase 8.5 specification package
  - [`tasks/8.5.0-adr-0010.md`](./tasks/8.5.0-adr-0010.md)
- [ ] **8.5.1** Pure chart math v3: `ChartTimeline` delayed-edge follower, `ChartScale` nice ladder & hysteresis, domain floors, `Downsampler.alignedBuckets` (min/max/mean)
  - [`tasks/8.5.1-chart-math-v3.md`](./tasks/8.5.1-chart-math-v3.md)
- [ ] **8.5.2** Timestamped telemetry series (`ChartPoint`, `ChartSeries`, `BucketPoint`) in `MetricsStore` and `MetricsCoordinator`
  - [`tasks/8.5.2-timestamped-series.md`](./tasks/8.5.2-timestamped-series.md)
- [ ] **8.5.3** `LiveChart` v3: time-domain coordinate projection, independent mirrored half-scales, dark-mode underlay bloom, left gutter axis, calm head bead
  - [`tasks/8.5.3-live-chart-v3.md`](./tasks/8.5.3-live-chart-v3.md)
- [ ] **8.5.4** Stocks-style Glance header scrub readout (`ChartScrubState`) & spring-filtered crosshair v2
  - [`tasks/8.5.4-header-scrub-and-crosshair.md`](./tasks/8.5.4-header-scrub-and-crosshair.md)
- [ ] **8.5.5** `HistoryPage` v3: time-aligned min–max envelope band + mean trace, bottom time axis, hover-revealed AVG/MAX annotations, scrub-aware stats strip
  - [`tasks/8.5.5-history-v3-envelope.md`](./tasks/8.5.5-history-v3-envelope.md)

### Sub-phase 8.5B — Synchronized Shell Motion & Kit v2 (Stage 1 → Stage 2 Bridge)
- [ ] **8.5.6** Synchronized shell motion & header v2: persistent `NSHostingView` category switch, `PreferenceKey` top-anchored window resize matched to `Motion.snappy`, tinted category badge, text `PageSwitcher`, inline status pill
  - [`tasks/8.5.6-shell-motion-and-header.md`](./tasks/8.5.6-shell-motion-and-header.md)
- [ ] **8.5.7** Instrument Kit v2: integrated `Section` card, hairline table `MetricRow`, unified `SegmentedControl` & `FilterChip`, `LiveNumber` decimal cadence throttle, animated `TopConsumersModule` reordering, secondary series hues in `PaletteContrast`
  - [`tasks/8.5.7-instrument-kit-v2.md`](./tasks/8.5.7-instrument-kit-v2.md)

### Sub-phase 8.5C — Per-Panel Instrument 2 Polish (Stage 2: Category Panels)
- [ ] **8.5.8a** CPU panel polish: P/E cluster columns (`cpuEfficiency` hue), Details Load Average Dot Plot, 2-column per-core sparkline grid — [`tasks/8.5.8a-cpu-panel-polish.md`](./tasks/8.5.8a-cpu-panel-polish.md)
- [ ] **8.5.8b** Memory panel polish: remove synthetic `ArcGauge`, add 3-stage Pressure Segmented Pill, 2-column composition legend (`swatch · label · bytes · %`), remove duplicate Details chart — [`tasks/8.5.8b-memory-panel-polish.md`](./tasks/8.5.8b-memory-panel-polish.md)
- [ ] **8.5.8c** GPU panel polish: `RingStack` with right-hand tabular legend, consolidated VRAM section, 2-column architecture spec sheet — [`tasks/8.5.8c-gpu-panel-polish.md`](./tasks/8.5.8c-gpu-panel-polish.md)
- [ ] **8.5.8d** Temperature panel polish: merge Spectrum and Thermal Groups into one annotated spectrum + ranked legend card, collapsible sensor group tables on Details — [`tasks/8.5.8d-thermal-panel-polish.md`](./tasks/8.5.8d-thermal-panel-polish.md)
- [ ] **8.5.8e** Fan panel polish: replace per-fan `ArcGauge` with Min–Max RPM Range Bar + live marker, RPM-locked calm turbine — [`tasks/8.5.8e-fan-panel-polish.md`](./tasks/8.5.8e-fan-panel-polish.md)
- [ ] **8.5.8f** Network panel polish: independent-scale mirrored waveform, consolidated Active Link + session totals card, hairline routing/Wi-Fi tables — [`tasks/8.5.8f-network-panel-polish.md`](./tasks/8.5.8f-network-panel-polish.md)
- [ ] **8.5.8g** Disk panel polish: independent-scale mirrored R/W waveform, 2-column boot storage legend, compact mounted volume capacity bars — [`tasks/8.5.8g-disk-panel-polish.md`](./tasks/8.5.8g-disk-panel-polish.md)
- [ ] **8.5.8h** Power panel polish: calm wattage-proportional `PowerFlowView`, refined health ring + capacity meter, hairline electrical diagnostics table — [`tasks/8.5.8h-power-panel-polish.md`](./tasks/8.5.8h-power-panel-polish.md)

### Sub-phase 8.5D — Live Preview Gallery & Verification
- [ ] **8.5.9** `InstrumentGalleryPreview` (synthetic 1 Hz stream with spikes, late samples, sleep gaps), CPU/energy budget verification, accessibility & appearance matrix pass, and `report.md`
  - [`tasks/8.5.9-gallery-and-verification.md`](./tasks/8.5.9-gallery-and-verification.md)

---

## Exit criteria
- All 13 animation defects (A1–A13) are resolved and verified via deterministic unit tests and `InstrumentGalleryPreview`.
- `swift test --scratch-path /tmp/istats-build` and `xcodebuild test -scheme iStats -destination 'platform=macOS'` pass green.
- Single open panel CPU stays `≤ 3.0%` (`LiveChart` `≤ 1.5%`) at 1 Hz refresh on Apple Silicon.
- Every task is committed in its own atomic, meaningful git commit.
- `docs/phases/phase-08.5-instrument-polish/report.md` and `docs/progress.md` are updated and complete.

