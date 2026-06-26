# Phase 6 — Polish, Preferences & Performance — Requirements

## Goal of this phase

Finalize configuration (per-category enable/disable, configurable menu bar content, unit
options), launch-at-login and Dock-icon toggle, full preference persistence, and a
performance pass confirming the monitor stays lightweight. Finalize all docs/ADRs and the
project README.

## Requirements covered by this phase

### Requirement 11: Configuration and preferences (full)

**User Story:** As a user, I want to configure what's shown and how often, so that the app
fits my workflow and resource budget.

#### Acceptance Criteria

1. WHERE the user opens preferences, iStats SHALL allow enabling/disabling each metric
   category.
2. WHERE the user opens preferences, iStats SHALL allow choosing units (°C/°F, bytes vs
   bits, IEC vs SI byte units).
3. WHEN preferences change THEN iStats SHALL persist them across launches.
4. WHERE the user enables it, iStats SHALL support launch at login.

### Requirement 9: Menu bar presentation (finalize)

#### Acceptance Criteria

1. WHERE the user configures it, iStats SHALL allow choosing which metric(s) appear
   directly in the menu bar (9.4).
2. WHEN running as a menu bar app THEN iStats SHALL be able to run without a Dock icon,
   toggleable in preferences (9.5).

### Requirement 12: Performance and resource footprint (finalize)

#### Acceptance Criteria

1. WHEN sampling metrics THEN iStats SHALL perform reads off the main thread (12.1).
2. WHEN idle at the default interval THEN iStats SHALL keep its own CPU usage low (12.2).
3. WHEN the refresh interval is increased THEN iStats SHALL reduce sampling frequency to
   lower its footprint (12.4).

### Requirement 14: Documentation deliverables (finalize)

#### Acceptance Criteria

1. WHEN the project is complete THEN iStats SHALL have all ADRs, the documentation set, and
   each phase's report finalized (14.1, 14.2, 14.3).

## Definition of done for Phase 6

- Per-category enable/disable, configurable menu bar content, and unit options all work.
- Launch-at-login via `SMAppService` and Dock-icon toggle work.
- All preferences persist across launches.
- Performance pass confirms off-main-thread sampling, low idle CPU, and interval scaling.
- All docs/ADRs finalized; Phase 6 report and project README written.
