# Progress

The only status file. Agent specs (`AGENTS.md`, `CLAUDE.md`) and phase plans do **not** keep a copy of this table.

- **Read this** to see where the build is.
- **Read the plan** (`docs/phases/…`, `docs/specs/tasks.md`) for what a task *is*.
- **Update this** when a task or phase actually finishes. Do not tick plan checkboxes.

---

## Now

| Field | Value |
|-------|--------|
| Phase | **5 — Thermal, fan, GPU** (in progress) |
| Next task | `5.4` ADR 0004 + opt-in fan control (if safe) |
| Last closed | **5.3** Implement FanSampler |
| Blocked by | — |

---

## Phases

| Phase | Theme | Status | Notes |
|-------|--------|--------|-------|
| 0 | Documentation & learning baseline | **done** | Specs, ADRs 0001–0006, phase folders, `iStatsCore` models/math, and `report.md` complete. |
| 1 | App foundation | **done** | App target, `LSUIElement`, `NSStatusItem` + detail popover, core protocols/types, `SampleScheduler`, `MetricsStore`, `PreferencesStore` + `PreferencesView`, and `report.md` complete. |
| 2 | CPU & memory | **done** | `CPUSampler`, `MemorySampler`, `MemoryPressureMonitor`, rolling history graphs, live detail cards, menu bar display modes, and `report.md` complete. |
| 3 | Network & disk | **done** | `NetworkSampler`, `DiskSampler`, mounted volume capacity, IOKit I/O throughput/IOPS, detail cards, units preferences, and `report.md` complete. |
| 4 | Battery & power | **done** | Charge, state, time-remaining, health, power draw, no-battery desktop handling, and `report.md` complete. |
| 5 | Thermal, fan, GPU | in progress | ThermalSampler, FanSampler, and ADR 0003 complete. Live AppleSMC telemetry on Apple Silicon. |
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
| 1.3 | Define core protocols and value types | **done** | [`docs/handoffs/01-1.3-summary.md`](./handoffs/01-1.3-summary.md), `swift test` (44 passed) |
| 1.4 | Implement the SampleScheduler | **done** | [`docs/handoffs/01-1.4-summary.md`](./handoffs/01-1.4-summary.md), `swift test` (55 passed) |
| 1.5 | Implement the MetricsStore ring buffer | **done** | [`docs/handoffs/01-1.5-summary.md`](./handoffs/01-1.5-summary.md), `swift test` (67 passed) |
| 1.6 | Build the preferences shell | **done** | [`docs/handoffs/01-1.6-summary.md`](./handoffs/01-1.6-summary.md), `xcodebuild -scheme iStats build` passed, `swift test` (75 passed) |
| 1.7 | Write the Phase 1 report | **done** | [`docs/handoffs/01-1.7-summary.md`](./handoffs/01-1.7-summary.md), [`docs/phases/phase-01-foundation/report.md`](./phases/phase-01-foundation/report.md), `swift test` (75 passed) |
| 2.1 | Implement CPUSampler (total + per-core) | **done** | [`docs/handoffs/02-2.1-summary.md`](./handoffs/02-2.1-summary.md), `xcodebuild test -scheme iStatsApp` (6 passed), `swift test` (78 passed) |
| 2.2 | Load average and CPU frequency | **done** | [`docs/handoffs/02-2.2-summary.md`](./handoffs/02-2.2-summary.md), `xcodebuild test -scheme iStatsApp` (6 passed), `swift test` (80 passed) |
| 2.3 | Property tests for CPU % math | **done** | [`docs/handoffs/02-2.3-summary.md`](./handoffs/02-2.3-summary.md), `xcodebuild test -scheme iStatsApp` (14 passed), `swift test` (85 passed) |
| 2.4 | Implement MemorySampler | **done** | [`docs/handoffs/02-2.4-summary.md`](./handoffs/02-2.4-summary.md), `xcodebuild test -scheme iStatsApp` (23 passed), `swift test` (85 passed) |
| 2.5 | Memory pressure level + UI surfacing | **done** | [`docs/handoffs/02-2.5-summary.md`](./handoffs/02-2.5-summary.md), `xcodebuild test -scheme iStatsApp` (28 passed), `swift test` (85 passed) |
| 2.6 | Render CPU + memory in the detail view | **done** | [`docs/handoffs/02-2.6-summary.md`](./handoffs/02-2.6-summary.md), `xcodebuild test -scheme iStatsApp` (35 passed), `swift test` (86 passed) |
| 2.7 | Validate vs reference tools + Phase 2 report | **done** | [`docs/handoffs/02-2.7-summary.md`](./handoffs/02-2.7-summary.md), [`docs/phases/phase-02-cpu-memory/report.md`](./phases/phase-02-cpu-memory/report.md), `xcodebuild test -scheme iStatsApp` (35 passed), `swift test` (86 passed) |
| 3.1 | Implement NetworkSampler | **done** | [`docs/handoffs/03-3.1-summary.md`](./handoffs/03-3.1-summary.md), `xcodebuild test -scheme iStatsApp` (43 passed), `swift test` (86 passed) |
| 3.2 | Network rate math with counter-reset handling | **done** | [`docs/handoffs/03-3.2-summary.md`](./handoffs/03-3.2-summary.md), `xcodebuild test -scheme iStatsApp` (46 passed), `swift test` (91 passed) |
| 3.3 | Implement DiskSampler (capacity per mounted volume) | **done** | [`docs/handoffs/03-3.3-summary.md`](./handoffs/03-3.3-summary.md), `xcodebuild test -scheme iStatsApp` (51 passed), `swift test` (91 passed) |
| 3.4 | Implement DiskSampler I/O throughput via IOKit | **done** | [`docs/handoffs/03-3.4-summary.md`](./handoffs/03-3.4-summary.md), `xcodebuild test -scheme iStatsApp` (57 passed), `swift test` (91 passed) |
| 3.5 | Network/disk in detail view + bytes/bits option | **done** | [`docs/handoffs/03-3.5-summary.md`](./handoffs/03-3.5-summary.md), `xcodebuild test -scheme iStatsApp` (61 passed), `swift test` (96 passed) |
| 3.6 | Validate vs reference tools + Phase 3 report | **done** | [`docs/handoffs/03-3.6-summary.md`](./handoffs/03-3.6-summary.md), [`docs/phases/phase-03-network-disk/report.md`](./phases/phase-03-network-disk/report.md), `xcodebuild test -scheme iStatsApp` (62 passed), `swift test` (96 passed) |
| 4.1 | PowerSampler: charge / state / time remaining | **done** | [`docs/handoffs/04-4.1-summary.md`](./handoffs/04-4.1-summary.md), `xcodebuild test -scheme iStatsApp` (70 passed), `swift test` (96 passed) |
| 4.2 | Battery health metrics | **done** | [`docs/handoffs/04-4.2-summary.md`](./handoffs/04-4.2-summary.md), `xcodebuild test -scheme iStatsApp` (73 passed), `swift test` (96 passed) |
| 4.3 | Instantaneous power draw / wattage | **done** | [`docs/handoffs/04-4.3-summary.md`](./handoffs/04-4.3-summary.md), `xcodebuild test -scheme iStatsApp` (77 passed), `swift test` (96 passed) |
| 4.4 | Handle the no-battery case | **done** | [`docs/handoffs/04-4.4-summary.md`](./handoffs/04-4.4-summary.md), `xcodebuild test -scheme iStatsApp` (89 passed), `swift test` (96 passed) |
| 4.5 | Validate vs reference tools + Phase 4 report | **done** | [`docs/handoffs/04-4.5-summary.md`](./handoffs/04-4.5-summary.md), [`docs/phases/phase-04-battery-power/report.md`](./phases/phase-04-battery-power/report.md), `xcodebuild test -scheme iStatsApp` (89 passed), `swift test` (96 passed) |
| 5.1 | Spike + ADR 0003: thermal/fan data source | **done** | [`docs/handoffs/05-5.1-summary.md`](./handoffs/05-5.1-summary.md), `swift test` (96 passed), `xcodebuild test` (89 passed) |
| 5.2 | Implement ThermalSampler | **done** | [`docs/handoffs/05-5.2-summary.md`](./handoffs/05-5.2-summary.md), `xcodebuild test -scheme iStatsApp` (101 passed), `swift test` (99 passed) |
| 5.3 | Implement FanSampler (read-only) | **done** | [`docs/handoffs/05-5.3-summary.md`](./handoffs/05-5.3-summary.md), `xcodebuild test -scheme iStatsApp` (111 passed), `swift test` (101 passed) |

When a task is done, set Status to `done` and put the handoff summary path (or test command) in Evidence.

---

## On disk (so you do not invent types)

Verified against the tree, not the design wish-list. Update a row when the matching code lands.

| Exists | Missing (designed, not built) |
|--------|-------------------------------|
| `Package.swift` → `iStatsCore` + `iStatsCoreTests`, `iStats.xcodeproj` (app target `iStats`, test target `iStatsTests`), `iStatsApp`, `AppDelegate`, `MenuBarController`, `MetricsCoordinator`, `DetailPopoverView`, `CPUSummaryView`, `RollingGraphView`, `DockIconManager`, `PreferencesView`, `PreferencesWindowController`, `MemoryPressureBadgeView`, `MemoryPressureAlertBanner`, `MemorySummaryView`, `NetworkSummaryView`, `DiskSummaryView`, `PowerSummaryView`, `ThermalSummaryView`, `FanSummaryView`, `Info.plist` (`LSUIElement = true`), `NSStatusItem`, `NSPopover` | — |
| `Availability`, `Sample<T>`, `Sampler`, `SamplerError`, `MetricCategory`, `AnySampler`, `MetricReading`, `SampleScheduler`, `MetricsStore`, `PreferencesStore`, `MenuBarDisplayMode`, `CPUSampler`, `ProcessorTicks`, `CPUInfoProvider`, `HostProcessorInfoProvider`, `MemorySampler`, `RawVMStatistics`, `SwapUsageData`, `MemoryInfoProvider`, `HostMemoryInfoProvider`, `MemoryPressureMonitor`, `NetworkSampler`, `RawInterfaceCounters`, `NetworkInfoProvider`, `HostNetworkInfoProvider`, `InterfaceState`, `InterfaceSessionTotal`, `DiskSampler`, `RawDiskIOCounters`, `DiskInfoProvider`, `HostDiskInfoProvider`, `PowerSampler`, `RawPowerSourceSnapshot`, `RawSmartBatteryData`, `PowerInfoProvider`, `HostPowerInfoProvider`, `ThermalSampler`, `ThermalInfoProvider`, `HostThermalInfoProvider`, `FanSampler`, `FanInfoProvider`, `HostFanInfoProvider`, `SMCParamStruct` | Concrete samplers: gpu |
| `LoadAverage`, `CPUSample`, `MemorySample`, `MemoryPressure`, `ThermalPressure`, `SensorReading`, `ThermalSample`, `FanReading`, `FanSample`, `InterfaceThroughput`, `NetworkSample`, `VolumeCapacity`, `DiskIO`, `DiskSample`, `BatteryState`, `PowerSample`, `GPUSample` | Metric validation reports |
| `RateMath`, `RingBuffer`, `Units` (`TemperatureUnit`, `NetworkUnit`, `ByteUnitStandard`) | — |
| Tests: `RateMathTests`, `RingBufferTests`, `UnitsTests`, `AvailabilityTests`, `MetricCategoryTests`, `SamplerTests`, `ModelsTests`, `SampleSchedulerTests`, `MetricsStoreTests`, `PreferencesStoreTests`, `CPUSamplerTests`, `MemorySamplerTests`, `MemoryPressureTests`, `DetailViewGraphsTests`, `NetworkSamplerTests`, `DiskSamplerTests`, `Phase3ValidationTests`, `PowerSamplerTests`, `Phase4ValidationTests`, `ThermalSamplerTests`, `FanSamplerTests` | — |



---

## How to update (one edit)

After an implementor summary and green tests:

1. Set the task row to `done` and cite `docs/handoffs/…-summary.md`.
2. Set **Next task** to the following id in [`docs/specs/tasks.md`](./specs/tasks.md).
3. If that was the last task in the phase, set the phase to `done` only when `report.md` is filled.
4. If you added or removed a type, edit the **On disk** table.

Do not also edit `AGENTS.md`, `CLAUDE.md`, or plan checkboxes for status.
