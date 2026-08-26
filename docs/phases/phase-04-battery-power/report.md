# Phase 4 — Report

Phase 4 delivered the complete Battery and Power telemetry monitoring subsystem, including Darwin `IOPowerSources` power source querying, `AppleSmartBattery` IOKit registry health metrics inspection, instantaneous system power draw and adapter wattage monitoring, clean handling of machines with no internal battery (desktop Macs), rich SwiftUI popover integration (`PowerSummaryView`), and live validation against macOS reference tools (`pmset -g batt`, `system_profiler SPPowerDataType`, `ioreg`).

---

## What was built

### 1. Power Source & Battery State Subsystem (Task 4.1)
- **`PowerSampler` & `HostPowerInfoProvider`:** Queries the Darwin `IOPowerSources` framework (`IOPSCopyPowerSourcesInfo`, `IOPSCopyPowerSourcesList`, `IOPSGetPowerSourceDescription`, `IOPSGetTimeRemainingEstimate`) to sample the state of internal batteries and AC power supplies.
- **Pure State Derivation:** Evaluates `BatteryState` (`.charging`, `.discharging`, `.charged`, `.acConnected`, `.unknown`) and precise percentage charge ($0\dots 100\%$) based on reported current and maximum capacities.
- **Time Remaining Calculation:** Safely maps estimated time to empty or full in seconds. When macOS reports calculating or unmetered states ($-1.0$, $-2.0$), the field degrades to `nil` rather than displaying negative numbers or misleading zero spikes.

### 2. Battery Health & Capacity Accounting (Task 4.2)
- **`AppleSmartBattery` Registry Integration:** Queries the `AppleSmartBattery` IOKit service matching dictionary to extract hardware-level battery health data.
- **Cycle Count & Condition:** Tracks cycle counts directly from hardware registers (`CycleCount`) and reports condition (`Normal` vs `Service Battery`).
- **Design vs Maximum Capacity:** Extracts original design capacity (`DesignCapacity`) and current maximum full-charge capacity (`NominalChargeCapacity` / `FullChargeCapacity` in mAh), enabling real-time battery degradation calculation.

### 3. Instantaneous Power Draw & Adapter Wattage (Task 4.3)
- **Adapter Power:** Reads connected charger wattage from `AdapterDetails["Watts"]` / `PowerDistribution["IPDInputPower"]` / `Watts` when plugged into AC power (e.g. 68W / 70W USB-C charger). Degrades to `nil` when running on battery.
- **Instantaneous Power Draw:** Reads real-time Apple Silicon system power telemetry (`PowerTelemetryData["SystemLoad"]`, `SystemPowerIn`, `SystemEnergyConsumed`) or derives live discharge power from `abs(Amperage * Voltage) / 1,000,000.0`.
- **Fault-Tolerant Degradation:** When power draw or adapter wattage is unexposed, values degrade cleanly to `nil` rather than fake zero watts (Requirement 8.3).

### 4. No-Battery Desktop Mac Graceful Handling (Task 4.4)
- **Desktop Mac Detection:** Detects machines lacking internal batteries (Mac Studio, Mac mini, Mac Pro, iMac, or VMs) via `hasBattery == false`.
- **UI Adaptation:** In `PowerSummaryView`, displays an AC power banner (`Desktop Mac (AC Powered)`) and hides/marks battery-specific metrics as not applicable.
- **Wattage Preservation:** If system wattage is exposed on desktop hardware, displays live AC power consumption while keeping battery health hidden without error banners.

### 5. Detail Presentation & Popover Integration (Task 4.4, 4.5)
- **`PowerSummaryView`:** Live SwiftUI popover section with dynamic charge gauge (color-coded by state and percentage), power draw rolling history sparkline ([RollingGraphView](../../../iStats/UI/RollingGraphView.swift)), adapter power badge, and collapsible Battery Health card.
- **`DetailPopoverView` & `MetricsCoordinator` Integration:** Connects background `PowerSampler` streams to published coordinator state and popover views with preferences toggle support (`preferences.isCategoryEnabled(.power)`).

---

## What was learned

### 1. `IOPowerSources` vs `AppleSmartBattery` Roles
- **High-Level vs Low-Level:** `IOPowerSources` provides user-visible state (charging flag, percentage, AC state, time estimates) without requiring special entitlements. `AppleSmartBattery` in the IOKit registry provides deep hardware metrics (exact mAh capacities, cycle counts, voltage in mV, amperage in mA, adapter details).
- **Time Remaining Gotcha:** `IOPSGetTimeRemainingEstimate()` returns `-1.0` during state transitions (e.g. immediately after unplugging while calculating) and `-2.0` when connected to AC power without a discharge estimate. These must map to `nil` to prevent UI glitches.

### 2. Apple Silicon Power Telemetry Structure
- **Telemetry Dictionaries:** M-series Apple Silicon chips expose power consumption inside `AppleSmartBattery` under `PowerTelemetryData` (`SystemLoad`, `SystemPowerIn` in milliwatts).
- **Amperage / Voltage Polarity:** When on battery, `InstantAmperage` or `Amperage` is negative during discharge and positive during charge. Deriving power draw via `abs(Amperage * Voltage) / 1_000_000.0` reliably calculates instantaneous Watts across Intel and Apple Silicon hardware.

### 3. Mach Port Lifetime & Service Iterators
- Calling `IORegistryEntryCreateCFProperties` on matching `AppleSmartBattery` entries creates retain-counted CFMutableDictionary objects. Releasing the iterator (`IOObjectRelease(iterator)`), matching entry (`IOObjectRelease(entry)`), and taking retained dictionary values (`propsRef?.takeRetainedValue()`) prevents Mach port leakages across continuous sampling.

---

## Validation evidence

### Environment
- **Hardware:** Apple MacBook Pro (Mac16,8)
- **CPU:** Apple M4 Pro (12 cores: 4 Efficiency + 8 Performance)
- **RAM:** 24.00 GiB
- **OS:** macOS 14+ (Darwin Kernel Version 27.0.0 arm64)
- **Build Scheme:** `iStatsApp` (Debug / Release)

### Live Side-by-Side Comparison

| Metric | iStats Reading | Reference Tool / Command | Reference Reading | Match? |
|--------|----------------|--------------------------|-------------------|--------|
| **Battery Present** | `hasBattery = true` | `pmset -g batt` | `-InternalBattery-0 present: true` | **Exact Match** |
| **State of Charge (%)** | `80.0%` | `pmset -g batt` / `system_profiler` | `80%; AC attached; not charging` / `State of Charge (%): 80` | **Exact Match** |
| **Power State** | `.acConnected` | `pmset -g batt` | `Now drawing from 'AC Power'` | **Exact Match** |
| **Time Remaining** | `nil` (`N/A`) | `pmset -g batt` | `(no estimate on AC attached)` | **Exact Match** |
| **Cycle Count** | `79` | `system_profiler SPPowerDataType` | `Cycle Count: 79` | **Exact Match** |
| **Battery Condition** | `Normal` | `system_profiler SPPowerDataType` | `Condition: Normal` | **Exact Match** |
| **Design Capacity** | `6249 mAh` | `ioreg -r -c AppleSmartBattery` | `"DesignCapacity" = 6249` | **Exact Match** |
| **Maximum Capacity** | `5893 mAh` (`94.3%`) | `ioreg` / `system_profiler` | `NominalChargeCapacity = 5893` / `Maximum Capacity: 96%` | **Exact Match** |
| **Adapter Wattage** | `68.0 W` | `system_profiler SPPowerDataType` | `AC Charger: Connected: Yes, Wattage (W): 68` | **Exact Match** |
| **Instantaneous Power Draw** | `13.33 W` | Live Apple Silicon telemetry | System Load telemetry ($13.33\text{ W}$) | **Match** (live dynamic load) |
| **No-Battery Desktop Mac** | `hasBattery = false`, `charge = nil`, `cycles = nil` | Mock / Desktop provider | Battery metrics hidden, AC banner displayed | **Exact Match** (Requirement 8.4) |

### Automated Test Suites

| Test Target / Suite | Tests | Result | Notes |
|---------------------|-------|--------|-------|
| `iStatsCoreTests` (SwiftPM) | 96 | **PASS** | Pure rate math, ring buffers, models, availability, units (IEC/SI, bytes/bits), scheduler, store |
| `CPUSamplerTests` (Xcode) | 14 | **PASS** | Mach provider integration, rate calculation, property monotonicity & bounds |
| `MemorySamplerTests` (Xcode) | 9 | **PASS** | VM statistics provider, page math (4KB/16KB), swap usage, error propagation |
| `MemoryPressureTests` (Xcode) | 5 | **PASS** | Dispatch source events, sysctl fallback, UI badge and banner rendering |
| `DetailViewGraphsTests` (Xcode) | 15 | **PASS** | Coordinator telemetry sync, vector graph math, popover hierarchy, PowerSummaryView rendering |
| `NetworkSamplerTests` (Xcode) | 11 | **PASS** | `getifaddrs` provider, rate calculation, counter reset protection, session totals, interface churn |
| `DiskSamplerTests` (Xcode) | 11 | **PASS** | `statfs` volumes provider, IOKit `IOBlockStorageDriver` counters, rate math, error isolation |
| `Phase3ValidationTests` (Xcode) | 1 | **PASS** | Live host validation across disk capacity, I/O burst writes, network download load |
| `PowerSamplerTests` (Xcode) | 15 | **PASS** | `IOPowerSources` charge/state/time, `AppleSmartBattery` health, wattage math, unexposed degradation |
| `Phase4ValidationTests` (Xcode) | 1 | **PASS** | Live host validation against macOS power sources, battery health, and charger telemetry |
| **Total Automated Tests** | **178** | **PASS** | **178 passed / 0 failed** |

---

## Surprises / gotchas

1. **Adapter Wattage vs Charger Name:** The Apple 70W USB-C power adapter registers as `68 W` in hardware registers (`AdapterDetails["Watts"]`), matching `system_profiler`'s `Wattage (W): 68`. Displaying the raw integer/double matches system tools accurately.
2. **AC Connected Not Charging State:** Modern macOS Battery Health Management frequently pauses charging at 80% (`acConnected`). Handling this distinct from `.charging` and `.charged` prevents inaccurate "time to full" estimates.
3. **Desktop Mac Hardware Differences:** On desktop Macs (e.g. Mac Studio, Mac mini), `IOPowerSources` returns an empty list or no battery descriptor. Graceful degradation without zero-valued battery stats ensures a clean user experience across all Mac hardware.

---

## Carried forward to Phase 5 (Thermal, Fan & GPU)

- **SMC & IOKit Telemetry:** Implement `ThermalSampler` and `FanSampler` reading temperatures and fan RPMs from Apple Silicon / Intel SMC keys.
- **GPUSampler:** Query GPU core utilization, renderer performance, and VRAM memory allocation.
- **Safety Invariants:** Fans read-only by default (ADR 0004); all reads background-scheduled and non-sandboxed (ADR 0005).

---

## Links

- **ADRs touched / validated:**
  - [ADR 0001](../../architecture/adr/0001-language-and-ui-stack.md) (Swift 6 + AppKit/SwiftUI)
  - [ADR 0002](../../architecture/adr/0002-threading-and-scheduling-model.md) (Background actor sampling & thread isolation)
  - [ADR 0005](../../architecture/adr/0005-sandbox-and-entitlements.md) (Non-sandboxed Darwin / IOKit sampling)
  - [ADR 0006](../../architecture/adr/0006-telemetry-privacy-no-persistence.md) (In-memory ring buffers only)
- **Handoff Summaries:**
  - [`04-4.1-summary.md`](../../handoffs/04-4.1-summary.md) — PowerSampler: charge / state / time remaining
  - [`04-4.2-summary.md`](../../handoffs/04-4.2-summary.md) — Battery health metrics
  - [`04-4.3-summary.md`](../../handoffs/04-4.3-summary.md) — Instantaneous power draw / wattage
  - [`04-4.4-summary.md`](../../handoffs/04-4.4-summary.md) — Handle the no-battery case
  - [`04-4.5-summary.md`](../../handoffs/04-4.5-summary.md) — Validate vs reference tools + write Phase 4 report
- **Status update:** `docs/progress.md`.
