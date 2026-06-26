# Phase 1 — App Foundation

**Goal:** A runnable menu bar app with the core architecture skeleton (scheduler, store, protocols) and a test harness — but no real metrics yet.

**Maps to Kiro spec task:** 1 (sub-tasks 1.1–1.7)

## Tasks
- [ ] Create the Xcode app target; set `LSUIElement` (no Dock icon).
- [ ] Install an `NSStatusItem` showing a placeholder; click opens an empty detail popover.
- [ ] Define core protocols/value types: `Sampler`, `Sample<T>`, `Availability`, `MetricCategory`.
- [ ] Implement `SampleScheduler` (background queue, per-category interval, publishes to main actor) with per-sampler error isolation.
- [ ] Implement `MetricsStore` ring buffer (pure) + unit tests for capacity/eviction.
- [ ] Preferences shell with a persisted settings store; wire interval bounds.
- [ ] Write this phase's `report.md`.

## Learning focus
- AppKit app lifecycle, `NSApplication`, `NSStatusBar`/`NSStatusItem`.
- `LSUIElement` and how a menu-bar-only app behaves.
- GCD / Swift concurrency basics; `@MainActor`; `AsyncStream` or Combine `@Published`.
- How a ring buffer works and why history is in-memory only (ADR 0006).

## Validation
- App launches, shows the status item, opens the popover, and runs without a Dock icon.
- `MetricsStore` unit tests pass (capacity, eviction order).
- A fake/dummy sampler proves the scheduler publishes values to the UI on the main thread.

## Exit criteria
- Runnable app + green tests + a working scheduler with a dummy sampler.
