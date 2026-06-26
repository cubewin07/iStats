# iStats — Architecture (narrated)

This is the teaching-oriented narration of the canonical design in `.kiro/specs/iStats/design.md`. Read this to understand *why* the system is shaped the way it is.

## The one big idea: isolate the OS

The risky, unfamiliar, version-fragile code is the code that talks to the kernel and hardware. We quarantine all of it inside a **Sampling layer**. Everything above that layer works with plain Swift value types and is fully unit-testable without any hardware. If Apple changes an API in a future macOS release, only the Sampling layer should need to change.

```
Hardware / kernel APIs
        │   (sysctl, Mach host_statistics, IOKit, AppleSMC, IOPowerSources, getifaddrs)
        ▼
Sampling layer  ── one Sampler per metric category, wraps the C/IOKit calls
        │   (returns typed Sample<T> values; never crashes the app)
        ▼
Domain Core ── SampleScheduler, MetricsStore (ring buffer), models, rate/unit math (PURE)
        │
        ▼
Presentation ── MenuBarController (NSStatusItem), detail view + graphs, preferences (SwiftUI/AppKit)
```

## Layer responsibilities

### Sampling layer
- One `Sampler` per category (CPU, Memory, Thermal, Fan, GPU, Network, Disk, Power).
- Each `Sampler` exposes `func sample() throws -> Output` and runs **off the main thread**.
- Any failure (a bad `kern_return_t`, a missing SMC key, a timeout) is caught and turned into an `.unavailable(reason:)` reading — it never propagates as a crash.

### Domain Core (pure, testable)
- **`SampleScheduler`** — owns a background queue/async tasks; triggers each enabled sampler at its configured interval; publishes results to the main actor. This is where per-sampler isolation lives.
- **`MetricsStore`** — fixed-capacity ring buffer per category holding the last *N* minutes of samples for the graphs. In-memory only (privacy: telemetry is never persisted).
- **Models** — `CPUSample`, `MemorySample`, etc. (plain value types).
- **Math** — CPU % from tick deltas, network rate from byte deltas (with counter-reset handling), unit conversions. All pure functions with unit/property tests.

### Presentation
- **`MenuBarController`** — owns the `NSStatusItem`; configurable as to which metric(s) appear in the bar; supports no-Dock-icon mode (`LSUIElement`).
- **Detail view** — SwiftUI in a popover/window, shows all enabled categories with live values and rolling graphs.
- **Preferences** — SwiftUI: toggle categories, set interval (bounded), units, launch-at-login.

## Threading model in detail

1. The scheduler wakes on a timer per category (categories can have different intervals).
2. It dispatches `sampler.sample()` on a background queue.
3. The result is wrapped in a `Sample<T>` with a timestamp and availability.
4. The result is handed to the `@MainActor` store/view-models via an `AsyncStream` or `@Published` property.
5. SwiftUI re-renders. The UI thread never performs a system call.

Why this matters: a blocking or slow system call (some SMC/IOKit reads can stall) must not freeze the menu bar. The background+isolation design keeps the UI responsive and the footprint low.

## Data flow for one CPU sample (worked example)

1. Timer fires for the CPU category.
2. `CPUSampler.sample()` calls Mach `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` → raw cumulative tick counters per core.
3. The sampler stores the previous counters, computes `busyDelta/totalDelta` per core → utilization %.
4. Returns `CPUSample(totalUsage:perCore:user:system:idle:)`.
5. Scheduler timestamps it, appends to the CPU ring buffer.
6. The CPU view model (main actor) publishes the new value; the menu bar text and the detail graph update.

## Error handling philosophy

- No force-unwraps on system call results. Every `kern_return_t` / IOKit return is checked.
- Per-sampler watchdog: if a read exceeds its time budget, skip this cycle and mark `.unavailable`.
- A failing sampler is logged and isolated; all others keep updating.

## Where the learning concentrates

- **Phase 2** (CPU/Memory): Mach host statistics and `sysctl` — the foundational kernel interfaces.
- **Phase 5** (Thermal/Fan/GPU): AppleSMC + IOKit — the least-documented, most version-fragile area, especially on Apple Silicon. This is deliberately last so earlier phases build confidence first.

See `prerequisites-and-learning.md` for the concepts to study before each phase and how to validate each metric.
