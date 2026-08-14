# Phase 1 — Foundation — Requirements

## Goal of this phase

Deliver a runnable menu bar app shell: an `NSStatusItem`, the sampling/scheduling
skeleton (protocols + scheduler + rolling store), and a preferences shell. No real metrics
yet — this is the scaffolding every later sampler plugs into.

> Scope note: this phase covers the menu bar presentation shell, the detail-view shell,
> the scheduling/threading foundation, and the preferences shell. Concrete metric
> requirements are satisfied in Phases 2–5.

## Requirements covered by this phase

### Requirement 9: Menu bar presentation (shell)

**User Story:** As a user, I want a compact menu bar display, so that I can glance at key
metrics without opening a window.

#### Acceptance Criteria

1. WHEN the app launches THEN iStats SHALL install a menu bar status item.
2. WHEN the user clicks the status item THEN iStats SHALL present a detail view
   (popover or window).
3. WHEN running as a menu bar app THEN iStats SHALL be able to run without a Dock icon
   (configurable).

### Requirement 10.2: Rolling history store

#### Acceptance Criteria

1. WHEN displaying a metric over time THEN iStats SHALL hold a rolling short-term history
   (last N minutes) in memory. (Phase 1 builds the ring-buffer store; graphs are wired in
   Phase 2.)

### Requirement 12: Performance and resource footprint (foundation)

**User Story:** As a power user, I want the monitor itself to be lightweight.

#### Acceptance Criteria

1. WHEN sampling metrics THEN iStats SHALL perform reads off the main thread and publish
   results to the UI thread.
2. WHEN the refresh interval is increased THEN iStats SHALL reduce sampling frequency
   accordingly.
3. WHEN a sampler fails THEN iStats SHALL isolate the failure to that sampler and continue
   updating the others.

### Requirement 11: Configuration and preferences (shell)

#### Acceptance Criteria

1. WHERE the user opens preferences, iStats SHALL allow setting the refresh interval with
   sane min/max bounds.
2. WHEN preferences change THEN iStats SHALL persist them across launches.

### Requirement 1.5 / 12.3: Availability + isolation primitives

#### Acceptance Criteria

1. IF a metric is unavailable on the current hardware THEN iStats SHALL be able to mark
   that metric "unavailable" rather than display a misleading value. (Phase 1 defines the
   `Availability` type and per-sampler error isolation used by all later samplers.)

## Definition of done for Phase 1

- App launches, shows a status item, and opens an (empty) detail popover on click.
- `Sampler`, `Sample<T>`, `Availability`, `MetricCategory` types exist.
- `SampleScheduler` runs off the main thread with per-sampler isolation.
- `MetricsStore` ring buffer exists with unit tests.
- Preferences shell persists the refresh interval.
