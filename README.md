# iStats

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13.0%2B-blue?style=flat-square&logo=apple" alt="macOS 13.0+">
  <img src="https://img.shields.io/badge/Swift-6.0-orange?style=flat-square&logo=swift" alt="Swift 6.0">
  <img src="https://img.shields.io/badge/Architecture-Apple%20Silicon%20%7C%20Intel-purple?style=flat-square" alt="Architecture">
  <img src="https://img.shields.io/badge/Tests-190%20passed-brightgreen?style=flat-square" alt="Tests">
  <img src="https://img.shields.io/badge/Telemetry-Zero%20Persistence-success?style=flat-square" alt="Zero Telemetry">
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="MIT License">
</p>

A high-performance, native macOS menu bar system monitor (AppKit `NSStatusItem` + SwiftUI popover) inspired by iStat Menus. Engineered with modern **Swift 6 concurrency**, **AppKit**, and **SwiftUI** for macOS 13+ (Ventura, Sonoma, Sequoia, and beyond). Optimized natively for Apple Silicon (M1/M2/M3/M4) with comprehensive graceful degradation on Intel Macs and restricted environments.

---

## Highlights

- ⚡ **100% Native & Hyper-Efficient:** Pure Swift 6 with zero third-party dependencies. All kernel sampling executes asynchronously on background tasks—zero main-thread blocking.
- 📊 **Modular Menu Bar Widgets:** Multi-item customizable menu bar layouts with authentic instrument aesthetics, CoreText vector glyphs, and dynamic decay-max scaling.
- 💡 **Human-First Verdict Architecture:** Instant answers with plain-English summaries ("Dad sentences") and 4 universal status colors (`Fine`, `Elevated`, `Warning`, `Critical`) before diving into diagnostic telemetry.
- 🔬 **Silicon Die & Hardware Visualizations:** Custom interactive SwiftUI hardware illustrations (CPU die with P/E cores, RAM stick PCB, Network streaming pipes, Volumetric disk tank, 4-zone thermal heat map, RPM tachometers, and GPU compute clusters).
- 🔒 **Privacy by Design (ADR 0006):** In-memory ring buffers only. Zero telemetry, logs, or sensor readings are ever saved to disk or transmitted over the network.
- 🛡️ **Fault-Tolerant (ADR 0002 & ADR 0005):** Missing sensors, denied permissions, or unsupported hardware degrade cleanly to `.unavailable(reason:)` without crashing.

---

## Architecture Overview

```
┌───────────────────────────────────────────────────────────────────────────┐
│                          Hardware & Kernel APIs                           │
│  (Mach host stats, sysctl, IOKit, AppleSMC, IOPowerSources, getifaddrs)  │
└─────────────────────────────────────┬─────────────────────────────────────┘
                                      │
                                      ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                      Background Sampling Layer (Async)                    │
│   CPUSampler       MemorySampler       NetworkSampler      DiskSampler    │
│   PowerSampler     ThermalSampler      FanSampler          GPUSampler     │
└─────────────────────────────────────┬─────────────────────────────────────┘
                                      │
                                      ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                           iStatsCore Framework                            │
│   SampleScheduler · MetricsStore (RingBuffer) · RateMath · Preferences    │
└─────────────────────────────────────┬─────────────────────────────────────┘
                                      │
                                      ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                       Presentation & UI Layer (AppKit)                    │
│     MenuBarController [NSStatusItem]  ──►  DetailPopoverView [SwiftUI]     │
│     MenuBarIconRenderer [CoreText]    ──►  PreferencesView [SwiftUI]       │
└───────────────────────────────────────────────────────────────────────────┘
```

---

## Features Tour

### 1. Modular Menu Bar Widgets
Customize which metrics appear in your menu bar and how they are visualized:
- **Display Styles:**
  - **Single-Line Text:** Compact percentage, rate, or temperature readout.
  - **Stacked 2-Line Text:** Authentic dual-line instruments (e.g., Upload/Download rates, Dual Fan RPM, Power Draw/Adapter wattage).
  - **Load Bars:** Horizontal mini-gauges with color-coded segment indicators.
  - **Gauge / Donut:** High-density circular percentage instruments.
  - **History Graphs (Sparklines):** Live scrolling sparkline mini-charts.
  - **Activity Instruments:** Dynamic hardware symbols (e.g., fan blades, activity arrows, R/W LEDs, memory pressure indicator).
  - **Component Thermals:** Dedicated individual temperature widgets for CPU, GPU, Memory, SSD Storage, and Battery.

### 2. Deep System Telemetry Subsystems

| Category | Telemetry & Visualizations | Underlying Kernel / Darwin APIs |
| :--- | :--- | :--- |
| **CPU** | Total load %, User/System/Idle split, Per-Core (P-Core & E-Core) load distribution, 1m/5m/15m Load Averages, CPU Die visualizer. | Mach Host Statistics (`host_processor_info`), `sysctl` (`vm.loadavg`) |
| **Memory** | Active, Wired, Compressed, Free memory, Swap usage, Live Darwin memory pressure state (`Normal`, `Warning`, `Critical`), RAM PCB visualizer. | Mach VM Statistics (`host_statistics64`), Darwin Memory Pressure Dispatch Source |
| **Network** | Real-time upload & download throughput, session byte counters, active network interface autodetection, rolling throughput history, stream pipes visualizer. | BSD `getifaddrs`, Interface Link Statistics, Monotonic `RateMath` |
| **Disk** | Mounted APFS/HFS+ volume capacity & usage, real-time read/write I/O throughput (Bytes/s), live IOPS, storage tank visualizer. | POSIX `statfs`, IOKit `IOBlockStorageDriver` Statistics |
| **Power & Battery** | Battery charge %, charging status, time remaining, cycle count, designed vs actual maximum capacity health %, instantaneous wattage draw, AC adapter power, desktop Mac AC detection. | `IOPowerSources` API, IOKit `AppleSmartBattery` Registry |
| **Thermals** | 30+ hardware sensor channels (SoC Package, CPU Cores, GPU Clusters, PMU, Memory modules, SSD flash, Battery, Enclosure), Darwin thermal pressure monitoring, 4-zone heat map visualizer. | AppleSMC Keys, `IOHIDEventSystemClient`, Darwin Thermal Pressure Notifications |
| **Fans** | Live fan RPM readings, min/max hardware speed limits, % cooling effort tachometer, dynamic rotating fan blades, firmware auto-safety policy. | AppleSMC Fan Subsystem |
| **GPU** | Graphics processor core utilization %, active VRAM allocation, GPU compute cluster die visualizer. | IOKit Accelerator Framework (`IOAccelerator`) |

### 3. Preferences & Customization
- **Refresh Rates:** Configurable background sampling interval (`0.5s` to `60.0s`).
- **Category Management:** Granular enable/disable toggles for all 8 subsystems.
- **Unit Standards:**
  - Temperature: Celsius (`°C`) vs Fahrenheit (`°F`).
  - Network Rates: Bytes/second (`B/s`, `KB/s`, `MB/s`) vs Bits/second (`bps`, `Kbps`, `Mbps`).
  - Byte Capacity: IEC Binary (`KiB`, `MiB`, `GiB`, `TiB` - 1024 base) vs SI Decimal (`KB`, `MB`, `GB`, `TB` - 1000 base).
- **System Integration:**
  - Launch at Login via native macOS `SMAppService.mainApp`.
  - Dock Icon toggle via `NSApplication.ActivationPolicy` (`.regular` vs `.accessory`).

---

## Architectural Principles & Invariants

1. **No OS / Kernel Calls on Main Thread (ADR 0002):** `sysctl`, Mach, IOKit, SMC, and `IOPowerSources` queries execute exclusively in background worker tasks managed by `SampleScheduler`.
2. **Degrade, Do Not Crash (ADR 0005):** Missing hardware sensors, restricted sandboxes, or denied Mach ports surface typed `Availability.unavailable(reason:)` states rather than fatal crashes or incorrect fallbacks.
3. **Pure Monotonic Rate Math:** All counter differentials (network bytes, disk I/O) are processed through `RateMath` with zero-elapsed protection and counter overflow/reset safeguards.
4. **Zero Telemetry Persistence (ADR 0006):** In-memory ring buffer (`RingBuffer`) retains only the recent historical window for sparkline graphs. No metrics are logged to disk or transmitted over the network.
5. **Firmware-Safe Fan Policy (ADR 0004):** Fan speeds are read-only and monitored within hardware safety bounds.

---

## Project Structure

```
iStats/
├── Package.swift                       # SwiftPM configuration
├── iStats.xcodeproj                    # Xcode application & test targets
├── Sources/
│   └── iStatsCore/                     # Pure domain framework
│       ├── Models.swift                # Strongly typed telemetry models
│       ├── Availability.swift          # Graceful degradation model
│       ├── RateMath.swift              # Monotonic counter rate calculations
│       ├── RingBuffer.swift            # Thread-safe in-memory rolling storage
│       ├── SampleScheduler.swift       # Asynchronous background scheduler
│       ├── MetricsStore.swift          # Central metrics repository
│       ├── MenuBarItemConfig.swift     # Menu bar widget definitions & styles
│       ├── Units.swift                 # Unit formatting & localization
│       └── PreferencesStore.swift      # User settings persistence
├── iStats/
│   ├── App/                            # Application layer
│   │   ├── iStatsApp.swift             # SwiftUI App lifecycle
│   │   ├── AppDelegate.swift           # AppKit application delegate
│   │   ├── MenuBarController.swift     # Multi-item NSStatusItem manager
│   │   ├── MetricsCoordinator.swift    # Scheduler & store coordinator
│   │   ├── LaunchAtLoginManager.swift  # SMAppService login item manager
│   │   └── DockIconManager.swift       # Activation policy manager
│   ├── Sampling/                       # Hardware sampling implementations
│   │   ├── CPUSampler.swift            # Mach processor info & loadavg
│   │   ├── MemorySampler.swift         # Mach VM statistics & swap
│   │   ├── MemoryPressureMonitor.swift # Darwin memory pressure dispatch
│   │   ├── NetworkSampler.swift        # getifaddrs network interfaces
│   │   ├── DiskSampler.swift           # statfs & IOKit disk I/O
│   │   ├── PowerSampler.swift          # IOPowerSources & AppleSmartBattery
│   │   ├── ThermalSampler.swift        # AppleSMC & IOHID thermal sensors
│   │   ├── FanSampler.swift            # AppleSMC fan RPM & limits
│   │   └── GPUSampler.swift            # IOKit GPU utilization & VRAM
│   └── UI/                             # SwiftUI presentation layer
│       ├── MenuBarIconRenderer.swift   # High-resolution vector icon renderer
│       ├── MetricVerdict.swift         # 4-stage human verdict evaluator
│       ├── DetailPopoverView.swift     # Main aggregated metric popover
│       ├── CategoryDetailPopoverView.swift # Dedicated category popovers
│       ├── PopoverCommonComponents.swift # Shared popover UI components
│       ├── RollingGraphView.swift      # Historical sparklines and graphs
│       ├── PreferencesView.swift       # Settings & customization UI
│       └── *IllustrationView.swift     # Hardware die & component visualizers
├── Tests/
│   ├── iStatsCoreTests/                # Core domain & math test suite
│   └── iStatsTests/                    # Sampling, integration & UI test suite
└── docs/                               # Architectural documentation & ADRs
```

---

## Building and Testing

### Prerequisites
- macOS 13.0 (Ventura) or later
- Xcode 15.0+ / Swift 6.0+

### Build & Test with SwiftPM
> [!NOTE]
> Always use `--scratch-path` to avoid SQLite build database lock conflicts on macOS:

```bash
# Build iStatsCore and iStats libraries
swift build --scratch-path /tmp/istats-build

# Run all package test suites
swift test --scratch-path /tmp/istats-build

# Run a specific test suite
swift test --scratch-path /tmp/istats-build --filter RateMathTests
```

### Build & Test with Xcode
Open `iStats.xcodeproj` in Xcode or run from the command line:

```bash
# Build application target
xcodebuild -scheme iStatsApp -configuration Debug build

# Run complete test suite (190 tests)
xcodebuild test -scheme iStatsApp -destination 'platform=macOS'
```

---

## Documentation & Architecture Decision Records

Comprehensive technical documentation, specifications, and design rationales live in [`docs/`](./docs/):

- **Status & Progress:** [`docs/progress.md`](./docs/progress.md) *(Canonical source of truth)*
- **Specifications:**
  - [`Requirements (EARS format)`](./docs/specs/requirements.md)
  - [`System Design & Kernel API Map`](./docs/specs/design.md)
  - [`Task Breakdown Structure`](./docs/specs/tasks.md)
- **Architecture Decision Records (ADRs):**
  - [ADR 0001: Language and UI Stack](./docs/architecture/adr/0001-language-and-ui-stack.md)
  - [ADR 0002: Threading and Scheduling Model](./docs/architecture/adr/0002-threading-and-scheduling-model.md)
  - [ADR 0003: Thermal, Fan, and GPU Data Sources](./docs/architecture/adr/0003-thermal-fan-data-source.md)
  - [ADR 0004: Privilege Model and Fan Control Policy](./docs/architecture/adr/0004-privilege-and-fan-control.md)
  - [ADR 0005: App Sandbox and Entitlements](./docs/architecture/adr/0005-sandbox-and-entitlements.md)
  - [ADR 0006: Telemetry Privacy & No Persistence](./docs/architecture/adr/0006-telemetry-privacy-no-persistence.md)
- **Phase Roadmap & Validation Reports:**
  - [Phase 0 — Documentation & Foundation](./docs/phases/phase-00-documentation/report.md)
  - [Phase 1 — App Target & Core Framework](./docs/phases/phase-01-foundation/report.md)
  - [Phase 2 — CPU & Memory Subsystems](./docs/phases/phase-02-cpu-memory/report.md)
  - [Phase 3 — Network & Disk Subsystems](./docs/phases/phase-03-network-disk/report.md)
  - [Phase 4 — Battery & Power Subsystems](./docs/phases/phase-04-battery-power/report.md)
  - [Phase 5 — Thermal, Fan & GPU Subsystems](./docs/phases/phase-05-thermal-fan-gpu/report.md)
  - [Phase 6 — Polish & Preferences](./docs/phases/phase-06-polish-prefs/report.md)

---

## Privacy & Security

iStats is committed to complete user privacy:
- **Zero Telemetry:** No system statistics, hardware metrics, or telemetry are ever written to disk or sent across the network.
- **Local Settings Only:** Only user configuration preferences (such as temperature unit or refresh rate) are persisted via local `UserDefaults`.
- **Open Source:** Fully inspectable and auditable Swift codebase.

---

## License

iStats is open-source software licensed under the [MIT License](LICENSE).
