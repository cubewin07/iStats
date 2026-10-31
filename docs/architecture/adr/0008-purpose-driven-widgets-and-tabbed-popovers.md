# ADR 0008 — Purpose-Driven Widgets and Tabbed Category Popovers

**Status:** Accepted  
**Supersedes:** ADR 0007 Decision 1 & 3 regarding the 33-style `PopoverStyle` binding model.  
**Preserves:** ADR 0007 multi-`NSStatusItem` lifecycle management, System Settings preferences studio, and zero-telemetry disk persistence.

---

## Context

Phase 6 and ADR 0007 introduced per-category menu bar widgets and decoupled popovers, giving users high flexibility. However, an architectural and UX audit revealed several compounding issues:

1. **Widget Bloat (43 styles):** Near-identical shapes populated the catalog (e.g. 8 separate text styles for thermal sensors, 6 fan styles). Several 18 pt menu bar drawings lacked legible signal at standard menu bar heights (such as 4-segment memory donuts, fan tachometer needles, GPU die outlines, and power rings with internal icon glyphs).
2. **Popover Sprawl (33 styles across 5,082 lines in a single file):** Popovers duplicated structural layouts with minor visual variations (e.g. `fanDualRPM`, `fanTachometer`, `fanBlades`, `fanBars`). Five thermal subsystem popovers were duplicate templates with hardcoded constants.
3. **Synthetic / Invented Data Violations:** Hardcoded limits (TJMax 105 °C headroom, DRAM refresh cycle policy 2x, NAND endurance, GPU core grids lighting synthetic proportions of cores) violated Invariant 2 ("Degrade, do not crash; no magic values").
4. **Lack of Design Tokens:** Layout and typography tokens drifted across files: `Color(nsColor: .controlBackgroundColor).opacity(...)` repeated 84 times with differing opacities (0.4 vs 0.5), font sizes varied erratically (8/9/10/10.5/11/13/14/24 pt), and category colors were duplicated and conflicted across three separate files.

---

## Decision

1. **Consolidate Widget Catalog (43 → 32 Widgets):**
   - Retain only widgets that present distinct, high-signal data.
   - Introduce `.glyph` style for compact glyph-based readings (e.g. thermometer glyph + temperature, fan icon + RPM, battery shell).
   - Parameterize multi-source categories (Temperature) via `source: MetricSource?` (`peak`, `cpu`, `gpu`, `memory`, `ssd`, `battery`).
   - Add layout options (`stacked` vs `singleLine`) for throughput widgets (Network, Disk) and optional 3-letter vertical labels for sparklines and rings.
   - Transparently migrate legacy styles on decode without loss of configuration.

2. **Unified Tabbed Popover Architecture (33 styles → 8 Category Popovers, 23 Tabs):**
   - Each category provides **exactly one popover** with 2–3 tabs: `Overview`, `<Detail>` (category-specific: `Cores`, `Pressure`, `Engines`, `Sensors`, `Volumes`, `Health`), and `History`.
   - The popover setting on a widget selects its default `openingTab` (and, for Temperature, its focused component sensor group).
   - Structured layout: fixed width of **330 pt**, maximum tab height of **≤ 480 pt**, strictly eliminating nested scroll views.
   - Reusable component kit: `PopoverScaffold`, `PopoverHeader`, `TabBar`, `HeroMetric`, `StatRow`, `StatGrid`, `SegmentedBar`, `RangeBar`, `CopyableValue`, `StatusBanner`, and unified `TrendChart`.

3. **Single Source of Truth for Identity and Severity:**
   - Icons: `MetricCategory.symbolName` in `iStatsCore`.
   - Colors: `CategoryPalette` in UI (`CPU`: blue, `Memory`: mint, `GPU`: purple, `Temperature`: orange, `Fans`: cyan, `Network`: indigo, `Disk`: teal, `Power`: pink).
   - Strict separation between Category identity color and Status severity color (`StatusLevel`: green, yellow, orange, red).
   - Shared severity thresholds: `StatusThresholds` in `iStatsCore`, covered by unit tests.

4. **Strict Telemetry Grounding:**
   - Every metric displayed must map directly to a `Sampler` reading in `Models.swift` or a pure derivation tested in `iStatsCore`.
   - All synthetic limits and decorative die illustrations are permanently deleted. Missing telemetry renders cleanly as `.unavailable(reason:)`.

5. **In-Memory History Extension:**
   - Maintain 900-sample (15-minute) compact scalar ring buffers in `MetricsStore` for historical chart rendering with spike-preserving downsampling (Task 7.6), while keeping telemetry zero-persistence on disk (ADR 0006).

---

## Consequences

- **Code Simplification:** The monolithic 5,082-line `CategoryDetailPopoverView.swift` and redundant illustration files are retired in favor of modular, composable SwiftUI views under `iStats/UI/Popovers/` and `iStats/UI/Design/`.
- **Consistency:** Design tokens (`Tokens.swift`, `CategoryPalette.swift`) and `StatusThresholds.swift` eliminate visual drift and inconsistent alert/verdict thresholds.
- **Backwards Compatibility:** Legacy `MenuBarItemConfig` and `PopoverStyle` decodes map seamlessly to consolidated widget configurations and popover tabs with deduplication.
