# Phase 7 — Widget & Popover Redesign — Tasks

**Goal:** Consolidate the menu bar catalog from 43 to 32 high-signal widgets, establish a unified design system and threshold table, and replace 33 one-off popovers with 8 tabbed category popovers backed strictly by real telemetry.

**Status tracking:** Do not tick checkboxes here. Update [`docs/progress.md`](../../progress.md) when tasks finish.

---

## Sub-phase Breakdown & Step Index

### Sub-phase 7A — Architecture & Core Domain Foundation (`7.0` – `7.1a`)
- [ ] **7.0** Author ADR 0008 & resolve open design decisions
  - Detail: [`tasks/7.0-adr-0008-and-decisions.md`](./tasks/7.0-adr-0008-and-decisions.md)
- [ ] **7.1a** Core identity, `StatusThresholds`, `MetricSource`, & `ThermalSensorClassifier`
  - Detail: [`tasks/7.1a-core-identity-thresholds-classifier.md`](./tasks/7.1a-core-identity-thresholds-classifier.md)

### Sub-phase 7B — Design System & Reusable UI Component Kit (`7.1b` – `7.1d`)
- [ ] **7.1b** `Tokens`, `CategoryPalette`, & deduplicating category icon/colour switches
  - Detail: [`tasks/7.1b-design-tokens-and-palette.md`](./tasks/7.1b-design-tokens-and-palette.md)
- [ ] **7.1c** Core popover & stat UI primitives (`PopoverHeader`, `TabBar`, `HeroMetric`, bars, rows, states)
  - Detail: [`tasks/7.1c-primitives-and-stat-components.md`](./tasks/7.1c-primitives-and-stat-components.md)
- [ ] **7.1d** Unified `TrendChart` component (single, stacked, mirrored, hover scrub)
  - Detail: [`tasks/7.1d-trend-chart-component.md`](./tasks/7.1d-trend-chart-component.md)

### Sub-phase 7C — Widget Catalog Consolidation & Menu Bar Renderer (`7.2a` – `7.2d`)
- [ ] **7.2a** Core widget catalog (43 → 32), `glyph` style, `source`, & decode migration/deduplication
  - Detail: [`tasks/7.2a-core-widget-catalog-and-migration.md`](./tasks/7.2a-core-widget-catalog-and-migration.md)
- [ ] **7.2b** `MenuBarIconRenderer` overhaul: CPU, Memory, GPU, & Temperature
  - Detail: [`tasks/7.2b-renderer-cpu-memory-gpu-thermal.md`](./tasks/7.2b-renderer-cpu-memory-gpu-thermal.md)
- [ ] **7.2c** `MenuBarIconRenderer` overhaul: Fans, Network, Disk, & Power
  - Detail: [`tasks/7.2c-renderer-fan-network-disk-power.md`](./tasks/7.2c-renderer-fan-network-disk-power.md)
- [ ] **7.2d** Preferences Menu Bar Studio updates (source picker, layout options, fanless state)
  - Detail: [`tasks/7.2d-preferences-widget-studio.md`](./tasks/7.2d-preferences-widget-studio.md)

### Sub-phase 7D — Tabbed Popover Model, Scaffold & Shell (`7.3a` – `7.3c`)
- [ ] **7.3a** Core `PopoverTab`, `PopoverConfig`, & legacy `PopoverStyle` migration
  - Detail: [`tasks/7.3a-core-popover-config-and-migration.md`](./tasks/7.3a-core-popover-config-and-migration.md)
- [ ] **7.3b** `PopoverScaffold`, keyboard shortcuts (`⌘1`–`⌘3`), & shared Loading/Unavailable/Paused states
  - Detail: [`tasks/7.3b-popover-scaffold-and-shared-states.md`](./tasks/7.3b-popover-scaffold-and-shared-states.md)
- [ ] **7.3c** `PopoverFactory`, `MenuBarController` tab sizing, & Preferences "Opens on" picker
  - Detail: [`tasks/7.3c-popover-factory-controller-and-prefs.md`](./tasks/7.3c-popover-factory-controller-and-prefs.md)

### Sub-phase 7E — Category Popovers (`7.4a` – `7.4h`, parallelizable)
- [ ] **7.4a** CPU Popover (`Overview · Cores · History`) & legacy CPU view removal
  - Detail: [`tasks/7.4a-cpu-popover.md`](./tasks/7.4a-cpu-popover.md)
- [ ] **7.4b** Memory Popover (`Overview · Pressure · History`) & legacy Memory view removal
  - Detail: [`tasks/7.4b-memory-popover.md`](./tasks/7.4b-memory-popover.md)
- [ ] **7.4c** GPU Popover (`Overview · Engines · History`) & legacy GPU view removal
  - Detail: [`tasks/7.4c-gpu-popover.md`](./tasks/7.4c-gpu-popover.md)
- [ ] **7.4d** Temperature Popover (`Overview · Sensors · History`) & legacy Thermal view removal
  - Detail: [`tasks/7.4d-temperature-popover.md`](./tasks/7.4d-temperature-popover.md)
- [ ] **7.4e** Fans Popover (`Overview · History`) & legacy Fan view removal
  - Detail: [`tasks/7.4e-fan-popover.md`](./tasks/7.4e-fan-popover.md)
- [ ] **7.4f** Network Popover (`Overview · Connection · History`) & legacy Network view removal
  - Detail: [`tasks/7.4f-network-popover.md`](./tasks/7.4f-network-popover.md)
- [ ] **7.4g** Disk Popover (`Overview · Volumes · History`) & legacy Disk view removal
  - Detail: [`tasks/7.4g-disk-popover.md`](./tasks/7.4g-disk-popover.md)
- [ ] **7.4h** Battery & Power Popover (`Overview · Health · History`) & legacy Power view removal
  - Detail: [`tasks/7.4h-power-popover.md`](./tasks/7.4h-power-popover.md)

### Sub-phase 7F — Shared History Tab & Optional Enhancements (`7.5`, `7.6`, `7.8`)
- [ ] **7.5** Shared `HistoryTab` integration & per-category series configuration
  - Detail: [`tasks/7.5-shared-history-tab.md`](./tasks/7.5-shared-history-tab.md)
- [ ] **7.6** *(Optional)* Extended in-memory trends (5m / 15m scalar ring buffers & downsampling)
  - Detail: [`tasks/7.6-extended-in-memory-trends.md`](./tasks/7.6-extended-in-memory-trends.md)
- [ ] **7.8** *(Optional, own ADR)* Top processes sampler (`ProcessSampler`) & CPU/Memory top apps rows
  - Detail: [`tasks/7.8-top-processes-sampler.md`](./tasks/7.8-top-processes-sampler.md)

### Sub-phase 7G — Final Cleanup, Verification & Phase Report (`7.7`)
- [ ] **7.7** Delete remaining legacy popover files, update docs/ADRs, benchmark popover CPU cost, & write `report.md`
  - Detail: [`tasks/7.7-cleanup-docs-and-validation.md`](./tasks/7.7-cleanup-docs-and-validation.md)

---

## Execution Order & Parallelism

```
7.0 ──► 7.1a ──► 7.1b ──► 7.1c ──► 7.1d
                           │        │
              ┌────────────┴────────┴────────────┐
              ▼                                  ▼
   Sub-phase 7C (Widgets)             Sub-phase 7D (Popover Shell)
   7.2a ──► 7.2b ──► 7.2c ──► 7.2d    7.3a ──► 7.3b ──► 7.3c
              │                                  │
              └────────────────┬─────────────────┘
                               ▼
                    Sub-phase 7E (parallel)
              7.4a | 7.4b | 7.4c | 7.4d | 7.4e | 7.4f | 7.4g | 7.4h
                               │
                               ▼
                         7.5 ──► (7.6) ──► 7.7 ──► (7.8)
```

## Validation & Exit Criteria

- `swift test --scratch-path /tmp/istats-build` and `xcodebuild test -scheme iStatsApp -destination 'platform=macOS'` pass after every step.
- 32 widgets, 8 popovers, 23 tabs; zero invented constants or synthetic hardware illustrations remain.
- All legacy configs migrate without data loss or duplicate IDs.
- Every tab fits within `330 × ≤480 pt` without nested `ScrollView`s under realistic max hardware counts (24 cores, 12 volumes, 40 sensors).

