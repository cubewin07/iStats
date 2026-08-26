# Progress

The only status file. Agent specs (`AGENTS.md`, `CLAUDE.md`) and phase plans do **not** keep a copy of this table.

- **Read this** to see where the build is.
- **Read the plan** (`docs/phases/…`, `docs/specs/tasks.md`) for what a task *is*.
- **Update this** when a task or phase actually finishes. Do not tick plan checkboxes.

---

## Now

| Field | Value |
|-------|--------|
| Phase | **1 — Foundation** (in progress) |
| Next task | `1.3` define core protocols and value types |
| Last closed | **Phase 0 — Documentation & learning baseline** |
| Blocked by | — |

---

## Phases

| Phase | Theme | Status | Notes |
|-------|--------|--------|-------|
| 0 | Documentation & learning baseline | **done** | Specs, ADRs 0001–0006, phase folders, `iStatsCore` models/math, and `report.md` complete. |
| 1 | App foundation | **in progress** | App target, `LSUIElement`, `NSStatusItem` + detail popover created; next: verify core protocols/types. |
| 2 | CPU & memory | not started | After Phase 1. Independent of 3 and 4. |
| 3 | Network & disk | not started | After Phase 1. |
| 4 | Battery & power | not started | After Phase 1. |
| 5 | Thermal, fan, GPU | not started | After 2–4. Highest risk. ADR 0003/0004 still Proposed. |
| 6 | Polish & preferences | not started | After Phase 5. |

Status values: `not started` · `in progress` · `docs on disk, not closed` · `done` · `blocked`.

---

## Tasks (mark only here)

Copy a row from [`docs/specs/tasks.md`](./specs/tasks.md) when you start it. Leave the plan file’s `[ ]` alone.

| Id | Title | Status | Evidence |
|----|-------|--------|----------|
| 0.1–0.5 | Phase 0 documentation set | **done** | [`docs/phases/phase-00-documentation/report.md`](./phases/phase-00-documentation/report.md), `swift test` (19 passed) |
| 1.1 | App target + `LSUIElement` | **done** | [`docs/handoffs/01-1.1-summary.md`](./handoffs/01-1.1-summary.md), `xcodebuild -scheme iStats build` passed, `swift test` (19 passed) |
| 1.2 | Install status item and detail popover | **done** | [`docs/handoffs/01-1.2-summary.md`](./handoffs/01-1.2-summary.md), `xcodebuild -scheme iStats build` passed, `swift test` (19 passed) |

When a task is done, set Status to `done` and put the handoff summary path (or test command) in Evidence.

---

## On disk (so you do not invent types)

Verified against the tree, not the design wish-list. Update a row when the matching code lands.

| Exists | Missing (designed, not built) |
|--------|-------------------------------|
| `Package.swift` → `iStatsCore` + `iStatsCoreTests`, `iStats.xcodeproj` (app target `iStats`), `iStatsApp`, `AppDelegate`, `MenuBarController`, `DetailPopoverView`, `DockIconManager`, `Info.plist` (`LSUIElement = true`), `NSStatusItem`, `NSPopover` | `SampleScheduler`, `MetricsStore`, preferences store |
| `Availability`, `Sample<T>`, `Sampler`, `SamplerError`, `MetricCategory` | Composite `ThermalSample` / `FanSample` / `NetworkSample` / Disk / GPU / Power wrappers |
| `CPUSample`, `MemorySample`, `MemoryPressure`, `SensorReading`, `FanReading`, `InterfaceThroughput` | Any concrete sampler (CPU, memory, …) |
| `RateMath`, `RingBuffer`, `Units` | App target tests, metric validation reports |
| Tests: `RateMathTests`, `RingBufferTests`, `UnitsTests` | — |

---

## How to update (one edit)

After an implementor summary and green tests:

1. Set the task row to `done` and cite `docs/handoffs/…-summary.md`.
2. Set **Next task** to the following id in [`docs/specs/tasks.md`](./specs/tasks.md).
3. If that was the last task in the phase, set the phase to `done` only when `report.md` is filled.
4. If you added or removed a type, edit the **On disk** table.

Do not also edit `AGENTS.md`, `CLAUDE.md`, or plan checkboxes for status.
