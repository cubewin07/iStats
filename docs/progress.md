# Progress

The only status file. Agent specs (`AGENTS.md`, `CLAUDE.md`) and phase plans do **not** keep a copy of this table.

- **Read this** to see where the build is.
- **Read the plan** (`docs/phases/…`, `docs/specs/tasks.md`) for what a task *is*.
- **Update this** when a task or phase actually finishes. Do not tick plan checkboxes.

---

## Now

| Field | Value |
|-------|--------|
| Phase | **1 — Foundation** (next implementation work) |
| Next task | `1.1` app target + `LSUIElement` |
| Last closed | none (Phase 0 docs are on disk; phase not formally closed) |
| Blocked by | — |

---

## Phases

| Phase | Theme | Status | Notes |
|-------|--------|--------|-------|
| 0 | Documentation & learning baseline | **docs on disk, not closed** | Specs, ADRs 0001–0006, phase folders exist. `report.md` is still a stub. Close 0 only after that report is written. |
| 1 | App foundation | **next** | No Xcode project, no `SampleScheduler`, no `MetricsStore`. |
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
| 0.1–0.5 | Phase 0 documentation set | **partial** | Folders, specs, ADRs, phase stubs exist. Phase `report.md` not written. |
| 1.1 | App target + `LSUIElement` | not started | — |

When a task is done, set Status to `done` and put the handoff summary path (or test command) in Evidence.

---

## On disk (so you do not invent types)

Verified against the tree, not the design wish-list. Update a row when the matching code lands.

| Exists | Missing (designed, not built) |
|--------|-------------------------------|
| `Package.swift` → `iStatsCore` + `iStatsCoreTests` | Xcode app, `LSUIElement`, `NSStatusItem`, popover |
| `Availability`, `Sample<T>`, `Sampler`, `SamplerError`, `MetricCategory` | `SampleScheduler`, `MetricsStore`, preferences store |
| `CPUSample`, `MemorySample`, `MemoryPressure`, `SensorReading`, `FanReading`, `InterfaceThroughput` | Composite `ThermalSample` / `FanSample` / `NetworkSample` / Disk / GPU / Power wrappers |
| `RateMath`, `RingBuffer`, `Units` | Any concrete sampler (CPU, memory, …) |
| Tests: `RateMathTests`, `RingBufferTests`, `UnitsTests` | App target tests, metric validation reports |

---

## How to update (one edit)

After an implementor summary and green tests:

1. Set the task row to `done` and cite `docs/handoffs/…-summary.md`.
2. Set **Next task** to the following id in [`docs/specs/tasks.md`](./specs/tasks.md).
3. If that was the last task in the phase, set the phase to `done` only when `report.md` is filled.
4. If you added or removed a type, edit the **On disk** table.

Do not also edit `AGENTS.md`, `CLAUDE.md`, or plan checkboxes for status.
