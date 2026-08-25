# Phase 0 — Report

Phase 0 established the complete architectural baseline, documentation scaffolding, task breakdowns, and initial pure-domain models and math routines.

## What was built

- **Master Specifications:**
  - `docs/specs/requirements.md` — 14 top-level requirements with verification criteria.
  - `docs/specs/design.md` — Layered architecture (Sampling → Core → Presentation), threading model, and UI wireframes.
  - `docs/specs/tasks.md` — Complete master task catalog and dependency graph across all phases.
- **Architectural Decision Records (ADRs 0001–0006):**
  - [ADR 0001](../../architecture/adr/0001-language-and-ui-stack.md): Swift 6 + AppKit/SwiftUI native stack.
  - [ADR 0002](../../architecture/adr/0002-threading-and-scheduling-model.md): Background actor-based `SampleScheduler` with `@MainActor` delivery.
  - [ADR 0003](../../architecture/adr/0003-thermal-fan-data-source.md): AppleSMC user-client and IOKit SPI fallback hierarchy.
  - [ADR 0004](../../architecture/adr/0004-privilege-and-fan-control.md): Read-only defaults with strict safety gates for fan control.
  - [ADR 0005](../../architecture/adr/0005-sandbox-and-entitlements.md): Non-sandboxed v1 with hardened runtime.
  - [ADR 0006](../../architecture/adr/0006-telemetry-privacy-no-persistence.md): Zero persistence for telemetry data (in-memory ring buffers only).
- **Documentation & Guides:**
  - `docs/architecture/overview.md`, `docs/architecture/architecture.md`, `docs/architecture/swift-app-structure-primer.md`.
  - `docs/guides/prerequisites-and-learning.md`, `docs/guides/build-and-run.md`, `docs/guides/glossary.md`, `docs/guides/skills-to-install.md`.
- **Phase Documentation & Task Stubs:**
  - `docs/phases/README.md` and self-contained folders for `phase-00` through `phase-06` with task specs, requirements, and reports.
- **Pure Core Foundation (`iStatsCore` SPM Package):**
  - Protocols & Enums: `Availability`, `MetricCategory`, `Sampler`, `SamplerError`.
  - Value Models: `CPUSample`, `MemorySample`, `MemoryPressure`, `SensorReading`, `FanReading`, `InterfaceThroughput`.
  - Pure Algorithms: `RateMath` (safe rate calculation with reset clamping), `RingBuffer` (bounded history), and `Units` (IEC/SI formatting, temperature conversions).
  - Test Suite: 19 unit tests across `RateMathTests`, `RingBufferTests`, and `UnitsTests` (100% green).

## What was learned

1. **macOS Data Source Hierarchy:**
   - **sysctl (`<sys/sysctl.h>`):** High-level BSD kernel MIB interface. Used for static hardware topologies (core counts, cache sizes, memory size), load averages, and interface enumeration (`getifaddrs`).
   - **Mach Kernel APIs (`<mach/mach.h>`):** Low-level microkernel statistics. Used for host CPU tick counters (`host_processor_info`, `processor_cpu_load_info`), VM page statistics (`host_statistics64`), and system memory pressure notifications.
   - **IOKit & IOReport (`<IOKit/IOKitLib.h>`):** Kernel driver registry and reporting framework. Provides block storage device statistics (`IOBlockStorageDriver`), power source state (`IOPowerSources`), and GPU/energy channel metrics.
   - **AppleSMC:** Low-level hardware controller interface accessed via `IOServiceOpen("AppleSMCClient")`. Handles raw thermal temperature keys and fan RPM tachometers.
2. **Rate Mathematics & Invariants:**
   - Cumulative monotonic counters (network bytes, disk bytes, CPU ticks) must never produce negative spikes when delta time is zero or when counters reset after driver restart / 32-bit overflow. `RateMath` guarantees clamping to zero.
3. **Threading Isolation:**
   - Kernel sampling APIs are blocking and must strictly execute off the main thread within background actor boundaries, streaming immutably packaged `Sample<T>` values to the UI.

## Open questions / risks carried forward

- **Apple Silicon SMC Key Divergence:** Different Apple Silicon SoC generations (M1 vs M2/M3/M4) expose distinct SMC four-character temperature keys (`TC0P`, `Tp09`, `Tp0T`, etc.). To be explored and validated in Phase 5.
- **IOReport / PowerMetrics Access:** IOReport APIs require private framework linkage or root entitlements for fine-grained per-package GPU milliwatt readings. Fallback to `IOAccelerator` device utilization where needed.

## Links

- **ADRs touched:** [ADR 0001](../../architecture/adr/0001-language-and-ui-stack.md), [ADR 0002](../../architecture/adr/0002-threading-and-scheduling-model.md), [ADR 0003](../../architecture/adr/0003-thermal-fan-data-source.md), [ADR 0004](../../architecture/adr/0004-privilege-and-fan-control.md), [ADR 0005](../../architecture/adr/0005-sandbox-and-entitlements.md), [ADR 0006](../../architecture/adr/0006-telemetry-privacy-no-persistence.md).
- **Docs updated:** `docs/progress.md`, `docs/phases/phase-00-documentation/report.md`.
