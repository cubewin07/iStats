# Phase 2 — CPU & Memory — Requirements

## Goal of this phase

Deliver the first real metrics: CPU utilization (total + per-core, user/system/idle, load
average) and memory (used/free/wired/compressed/cached/swap + pressure), rendered live in
the detail view with rolling graphs and selectable for the menu bar. Validate values
against Activity Monitor and `top`.

## Requirements covered by this phase

### Requirement 1: CPU monitoring

**User Story:** As a power user, I want to see CPU usage and load in real time, so that I
can tell when the machine is under heavy load and which behavior caused it.

#### Acceptance Criteria

1. WHEN the app is running THEN iStats SHALL sample total CPU utilization at the configured
   refresh interval.
2. WHEN the app samples the CPU THEN iStats SHALL report per-core utilization in addition
   to the aggregate.
3. WHERE the hardware exposes it, iStats SHALL report CPU frequency and the system load
   average (1/5/15 minute).
4. WHEN displaying CPU utilization THEN iStats SHALL distinguish user, system, and idle
   time.
5. IF a CPU metric is unavailable on the current hardware THEN iStats SHALL mark that
   metric as "unavailable" rather than displaying a misleading zero.

### Requirement 2: Memory monitoring

**User Story:** As a power user, I want detailed memory information, so that I can
understand memory pressure and swap behavior when I run heavy workloads.

#### Acceptance Criteria

1. WHEN the app samples memory THEN iStats SHALL report used, free, active, inactive,
   wired, and cached/compressed memory.
2. WHEN the app samples memory THEN iStats SHALL report swap used and the macOS memory
   pressure level (normal/warning/critical).
3. WHEN total physical memory is queried THEN iStats SHALL report it accurately for the
   host.
4. WHEN memory pressure transitions to warning or critical THEN iStats SHALL surface that
   state visibly in the UI.

### Requirement 9.4 / 10 / 12.1: Presentation & performance for these metrics

#### Acceptance Criteria

1. WHERE the user configures it, iStats SHALL allow choosing CPU or memory to appear in the
   menu bar (9.4).
2. WHEN the detail view is open THEN iStats SHALL show all enabled categories with current
   values, rolling history graphs, and live refresh (10.1, 10.2, 10.3).
3. WHEN sampling CPU/memory THEN iStats SHALL perform reads off the main thread (12.1).

## Definition of done for Phase 2

- CPU and memory samplers produce correct values, validated against Activity Monitor/`top`.
- CPU % math is pure and property-tested (monotonic, bounded 0–100%).
- Memory pressure is surfaced in the UI.
- CPU/memory render in the detail view with live rolling graphs and can be chosen for the
  menu bar.
- Phase 2 report written.
