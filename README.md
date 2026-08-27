# iStats

A lightweight, native macOS system monitoring application (menu bar status item + SwiftUI detail popover) inspired by iStat Menus. Built with modern Swift 6, AppKit, and SwiftUI for macOS 13+ (optimized for Apple Silicon, with graceful degradation on Intel and restricted environments).

---

## Features

- **Menu Bar Monitor:** Live system telemetry displayed directly in the macOS menu bar with 8 customizable modes (`Icon Only`, `CPU Usage`, `Memory Usage`, `CPU & Memory`, `Network Rate`, `Battery Level`, `SoC Temperature`, `GPU Usage`), plus a rich multi-metric hover tooltip.
- **Rich Detail Popover:** Interactive cards for all 8 system categories:
  - **CPU:** Total usage, system/user/idle breakdown, per-core utilization bars, and load averages (1m, 5m, 15m).
  - **Memory:** Active, wired, compressed, free memory breakdown, swap utilization, and live macOS memory pressure badge (`Normal`, `Warning`, `Critical`).
  - **Network:** Real-time upload/download throughput with historical rolling graphs, active interface detection, and session byte totals.
  - **Disk:** Read/write I/O transfer rates with historical rolling graphs and APFS/HFS+ volume capacity gauges.
  - **Power & Battery:** Battery charge percentage, time remaining, charging state, cycle count, health, temperature, and AC adapter wattage.
  - **Thermals:** Multi-sensor temperature readings across SoC package, CPU/GPU clusters, PMU dies, memory, and battery with live Darwin thermal pressure state.
  - **Fans:** Live fan RPM speeds, min/max bounds, speed gauges, and automatic system-controlled safety indicators.
  - **GPU:** GPU core utilization percentage and allocated/in-use video memory.
- **Preferences & Customization:**
  - Configurable sampling refresh interval (`0.5s` to `60.0s`).
  - Granular category enablement toggles.
  - Unit format customization: Temperature (`°C` vs `°F`), Network rates (`Bytes/s` vs `Bits/s`), Byte standards (`IEC / Binary` vs `SI / Decimal`).
  - Launch at Login via native macOS `SMAppService`.
  - Dock icon visibility toggle via `NSApplication.ActivationPolicy`.
- **Zero Telemetry Persistence (ADR 0006):** Complete user privacy. Only explicit user preferences are saved to disk; strictly zero hardware metrics or sensor readings are ever persisted or transmitted.
- **Robust Failure Isolation (ADR 0002 & ADR 0005):** All sampling executes exclusively on background tasks off the main thread. Missing hardware sensors or restricted sandbox permissions degrade gracefully to `.unavailable(reason:)` without crashing.

---

## Architecture Overview

```
Hardware / Kernel APIs
  (sysctl, Mach host statistics, IOKit, AppleSMC, IOPowerSources, getifaddrs, IOHIDEventSystemClient)
        │
        ▼
Sampling Layer (Background Tasks)
  (CPUSampler, MemorySampler, NetworkSampler, DiskSampler, PowerSampler, ThermalSampler, FanSampler, GPUSampler)
        │
        ▼
iStatsCore Framework
  (SampleScheduler, MetricsStore [RingBuffer], Models, RateMath, Units, PreferencesStore)
        │
        ▼
Presentation Layer
  (MenuBarController [NSStatusItem] + DetailPopoverView [NSPopover] + PreferencesView [SwiftUI])
```

---

## Building and Testing

### Prerequisites
- macOS 13.0 (Ventura) or later
- Xcode 15.0+ / Swift 6.0+

### Build with SwiftPM
Always use `--scratch-path` to avoid SQLite build database lock conflicts:
```bash
swift build --scratch-path /tmp/istats-build
swift test  --scratch-path /tmp/istats-build
```

### Build & Test with Xcode
Open `iStats.xcodeproj` in Xcode or run via CLI:
```bash
# Build app target
xcodebuild -scheme iStatsApp -configuration Debug build

# Run entire test suite (155+ tests)
xcodebuild test -scheme iStatsApp -destination 'platform=macOS'
```

---

## Documentation & Specifications

All architectural designs, specifications, task roadmaps, and reports live under [`docs/`](./docs/):

- **Project Progress & Status**: [`docs/progress.md`](./docs/progress.md) *(Source of truth)*
- **Specifications**:
  - [`docs/specs/requirements.md`](./docs/specs/requirements.md) — Canonical EARS requirements
  - [`docs/specs/design.md`](./docs/specs/design.md) — System design & macOS kernel API map
  - [`docs/specs/tasks.md`](./docs/specs/tasks.md) — Comprehensive work breakdown structure
- **Architecture Decision Records (ADRs)**:
  - [`0001 — Language and UI Stack`](./docs/architecture/adr/0001-language-and-ui-stack.md)
  - [`0002 — Threading and Scheduling Model`](./docs/architecture/adr/0002-threading-and-scheduling-model.md)
  - [`0003 — Thermal, Fan, and GPU Data Sources`](./docs/architecture/adr/0003-thermal-fan-data-source.md)
  - [`0004 — Privilege Model & Fan Control Policy`](./docs/architecture/adr/0004-privilege-and-fan-control.md)
  - [`0005 — App Sandbox and Entitlements`](./docs/architecture/adr/0005-sandbox-and-entitlements.md)
  - [`0006 — Telemetry Privacy & No Persistence`](./docs/architecture/adr/0006-telemetry-privacy-no-persistence.md)
- **Phase Roadmap & Validation Reports**:
  - [`Phase 0 — Documentation & Planning`](./docs/phases/phase-00-documentation/)
  - [`Phase 1 — Foundation & Core Framework`](./docs/phases/phase-01-foundation/)
  - [`Phase 2 — CPU & Memory Subsystems`](./docs/phases/phase-02-cpu-memory/)
  - [`Phase 3 — Network & Disk Subsystems`](./docs/phases/phase-03-network-disk/)
  - [`Phase 4 — Battery & Power Subsystems`](./docs/phases/phase-04-battery-power/)
  - [`Phase 5 — Thermal, Fan & GPU Subsystems`](./docs/phases/phase-05-thermal-fan-gpu/)
  - [`Phase 6 — Polish & Preferences`](./docs/phases/phase-06-polish-prefs/)

---

## License & Privacy

iStats is open-source under the MIT License. It does not collect, log, or transmit any user analytics, system statistics, or network telemetry.
