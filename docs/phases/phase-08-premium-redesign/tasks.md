# Phase 8 — Premium Panel Redesign — Tasks

**Goal:** Replace the Phase 7 popover presentation with a premium, instrument-grade panel experience (see [`plan.md`](./plan.md), [`design.md`](./design.md), [`requirements.md`](./requirements.md)).

**Status tracking:** Do not tick checkboxes here. Update [`docs/progress.md`](../../progress.md) when tasks finish.

**Default role sequence per task:** examiner → planner → implementor. Handoffs go in `docs/handoffs/08-<task>-{exam,plan,summary}.md`.

---

### Sub-phase 8A — Decisions & Foundation
- [ ] **8.0** ADR 0009 "Instrument" design language, panel host decision, API availability spike
  - [`tasks/8.0-adr-0009-and-spike.md`](./tasks/8.0-adr-0009-and-spike.md)
- [ ] **8.1** Design language v2: tokens, asset-catalog palette, typography, surfaces
  - [`tasks/8.1-design-language-v2.md`](./tasks/8.1-design-language-v2.md)
- [ ] **8.2** Motion system & `LiveNumber` rolling numerals
  - [`tasks/8.2-motion-and-live-number.md`](./tasks/8.2-motion-and-live-number.md)
- [ ] **8.3** Glass panel host (`MetricPanel`): placement, dismissal, menu tracking, pin/detach
  - [`tasks/8.3-glass-panel-host.md`](./tasks/8.3-glass-panel-host.md)

### Sub-phase 8B — Instrument Kit
- [ ] **8.4** `LiveChart`: full-bleed, glide, live head, crosshair lens, haptics
  - [`tasks/8.4-live-chart.md`](./tasks/8.4-live-chart.md)
- [ ] **8.5** Instrument kit: modules, meters, gauges, rings, capsules, rows, copyable
  - [`tasks/8.5-instrument-kit.md`](./tasks/8.5-instrument-kit.md)
- [ ] **8.6** `PanelScaffold`: eyebrow, glance, page switcher, status ribbon, states, keyboard
  - [`tasks/8.6-panel-scaffold.md`](./tasks/8.6-panel-scaffold.md)
- [ ] **8.7** `InsightEngine` + headline copy table (iStatsCore, pure, tested)
  - [`tasks/8.7-insight-engine.md`](./tasks/8.7-insight-engine.md)

### Sub-phase 8C — Category Panels (parallel after 8.6)
- [ ] **8.8a** CPU: Core Map — [`tasks/8.8a-cpu-panel.md`](./tasks/8.8a-cpu-panel.md)
- [ ] **8.8b** Memory: Pressure Arc + Composition Capsule — [`tasks/8.8b-memory-panel.md`](./tasks/8.8b-memory-panel.md)
- [ ] **8.8c** GPU: Engine Rings — [`tasks/8.8c-gpu-panel.md`](./tasks/8.8c-gpu-panel.md)
- [ ] **8.8d** Temperature: Thermal Spectrum — [`tasks/8.8d-thermal-panel.md`](./tasks/8.8d-thermal-panel.md)
- [ ] **8.8e** Fans: Turbine + fanless state — [`tasks/8.8e-fan-panel.md`](./tasks/8.8e-fan-panel.md)
- [ ] **8.8f** Network: Mirrored Waveform + Link Card — [`tasks/8.8f-network-panel.md`](./tasks/8.8f-network-panel.md)
- [ ] **8.8g** Disk: Storage Bar + I/O Waveform — [`tasks/8.8g-disk-panel.md`](./tasks/8.8g-disk-panel.md)
- [ ] **8.8h** Power: Battery glyph + Power Flow — [`tasks/8.8h-power-panel.md`](./tasks/8.8h-power-panel.md)

### Sub-phase 8D — Signature Features
- [ ] **8.9** Top consumers (`ProcessSampler`, background `libproc`) — finishes the unbuilt 7.8
  - [`tasks/8.9-top-consumers.md`](./tasks/8.9-top-consumers.md)
- [ ] **8.10** History v2: range control, annotations, scrub, channel isolation
  - [`tasks/8.10-history-v2.md`](./tasks/8.10-history-v2.md)

### Sub-phase 8E — Polish & Ship
- [ ] **8.11** Accessibility & appearance matrix
  - [`tasks/8.11-accessibility-appearance-matrix.md`](./tasks/8.11-accessibility-appearance-matrix.md)
- [ ] **8.12** Performance budget, legacy deletion, docs sync, report
  - [`tasks/8.12-performance-cleanup-report.md`](./tasks/8.12-performance-cleanup-report.md)

---

## Exit criteria
- All 8 panels run in the new shell; `NSPopover`, `PopoverFactory`, and the unused Phase 7 components are deleted.
- `swift test --scratch-path /tmp/istats-build` and `xcodebuild test -scheme iStatsApp -destination 'platform=macOS'` are green.
- The performance budget (R8.6) is measured and recorded in `report.md`.
- The appearance matrix (8.11) is signed off by the user (visual review is done by the user, not by agent screen capture).
- ADR 0009 is accepted, ADR 0008 is annotated "presentation superseded by 0009", and `docs/specs/design.md` is updated.

## Learning focus
- `NSPanel` window management for menu bar apps (key status, non-activating panels, event monitors).
- SwiftUI animation: `TimelineView`, `Canvas`, `contentTransition`, `matchedGeometryEffect`, `#available` gating.
- Design systems: tokens, asset catalogs, contrast math.
- `libproc` (`proc_listpids`, `proc_pid_rusage`) and its privilege boundaries.

