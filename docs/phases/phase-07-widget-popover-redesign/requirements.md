# Phase 7 — Widget & Popover Redesign — Requirements

## Goal of this phase

Consolidate and redesign the menu bar widget catalog (43 → 32 purpose-driven widgets) and replace the 33 one-off popover styles with **8 unified, tabbed category popovers** (23 tabs total) built from a shared design system and single threshold table, eliminating all invented/hard-coded metrics and decorative illustrations while migrating existing user configurations cleanly.

## Requirements covered by this phase

### Requirement 9: Menu bar presentation (redesign)

**User Story:** As a user, I want compact, readable, stable-width menu bar widgets where every widget has a distinct job and graphing widgets are identifiable at a glance.

#### Acceptance Criteria

1. WHERE a category offers menu bar widgets, iStats SHALL provide only distinct, legible representations at 18 pt menu bar height (32 widgets across 8 categories; no duplicate shapes for the same metric).
2. WHEN displaying temperature in the menu bar THEN iStats SHALL use a unified Temperature widget (`text` or `glyph`) parameterized by `MetricSource` (`peak`, `cpu`, `gpu`, `memory`, `ssd`, `battery`) rather than separate hard-coded widget styles.
3. WHERE multiple sparkline or ring widgets are active in the menu bar, iStats SHALL support an optional 3-letter vertical category label so instruments can be distinguished.
4. WHERE Network or Disk throughput is shown in the menu bar, iStats SHALL support both `stacked` and `singleLine` layouts with fixed-width tabular digits to prevent menu bar jitter.
5. WHEN a user upgrades from an earlier configuration THEN iStats SHALL migrate removed widget styles to their replacement equivalents and deduplicate by `id` without losing widget order.

### Requirement 10: Category detail popovers (tabbed architecture)

**User Story:** As a user, I want clicking a category widget to open a focused, consistent popover that answers "is it OK, why, and what can I do?" using only real sensor data and predictable layout bounds.

#### Acceptance Criteria

1. WHEN a menu bar widget is clicked THEN iStats SHALL open that category's unified tabbed popover (`Overview`, category-specific `Detail`, and `History` tabs; 2 tabs for Fans and desktop Power) at a fixed width of **330 pt** and content height **≤ 480 pt** without nested scroll views.
2. WHEN rendering any metric in a popover THEN iStats SHALL display only values backed by `Models.swift` sampler fields or unit-tested pure derivations, and SHALL surface missing data via `Availability.unavailable(reason:)` styling rather than fallback constants or synthetic illustrations.
3. WHEN switching tabs (`⌘1`–`⌘3` or segmented control) THEN iStats SHALL preserve the 330 pt width, animate height smoothly, and optionally remember the last active tab per category.
4. WHEN a legacy `PopoverStyle` configuration is decoded THEN iStats SHALL map it deterministically to `PopoverConfig` (`openingTab` + optional `MetricSource` focus), falling back to `.overview` for unknown values.

### Requirement 13: Unified visual identity & status thresholds

**User Story:** As a user, I want consistent category icons, colours, typography, and severity thresholds across menu bar widgets, popovers, verdicts, alerts, and Preferences.

#### Acceptance Criteria

1. WHERE category identity (icon or colour) is rendered, iStats SHALL read from a single source of truth (`MetricCategory.symbolName` in `iStatsCore` and `CategoryPalette` in the app target).
2. WHERE status severity (fine / elevated / warning / critical) is evaluated, iStats SHALL read from a single unit-tested `StatusThresholds` table in `iStatsCore`, never repurposing category identity colours as severity indicators.
3. WHEN viewing popovers in Light Mode, Dark Mode, Reduce Motion, or with VoiceOver enabled THEN all tabs SHALL meet contrast, motion, and accessibility label requirements.

## Definition of done for Phase 7

- ADR 0008 accepted and open design decisions recorded.
- `StatusThresholds`, `MetricCategory.symbolName`, `MetricSource`, `ThermalSensorClassifier`, and `PopoverConfig` implemented and unit-tested in `iStatsCore`.
- Shared design system (`Tokens`, `CategoryPalette`, 13 `Design/Components/*`) implemented with state previews.
- 32-widget catalog and `MenuBarIconRenderer` shipped with full migration and deduplication tests.
- All 8 tabbed category popovers and shared `HistoryTab` shipped; all 33 legacy popover styles, 7 summary views, and 8 decorative illustration views deleted.
- All `swift test` and `xcodebuild test` suites pass; Phase 7 `report.md` and `docs/progress.md` updated.

