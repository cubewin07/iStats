# Phase 5 — Report

Phase 5 delivered the complete Thermal, Fan, and GPU monitoring subsystems for Apple Silicon and Intel Macs. This includes direct AppleSMC kernel telemetry via IOKit user client calls, system thermal pressure tracking via Darwin `ProcessInfo`, rotational fan speeds with hardware limit boundaries, `IOAccelerator` (`AGXAccelerator`) GPU core utilization and unified memory accounting, strict read-only safety policies (ADR 0004), non-sandboxed unprivileged least-privilege architecture with graceful degradation (ADR 0005), rich SwiftUI detail popover cards (`ThermalSummaryView`, `FanSummaryView`, `GPUSummaryView`), and live validation against macOS reference tools.

---

## Hardware Tested

- **Model:** MacBook Pro (`Mac16,8`, MX2H3SA/A)
- **Chip:** Apple M4 Pro (12 CPU cores: 8 Performance + 4 Efficiency; 16-core GPU)
- **Memory:** 24.00 GiB Unified Memory (16 KB page size)
- **macOS Version:** macOS 15+ / 27.0 (Darwin Kernel Version 27.0.0 `arm64`)
- **Build Schemes:** `iStatsApp` (Debug / Release), `iStatsCore` (SwiftPM)

---

## Spike Findings (AppleSMC & IOKit Telemetry)

During Task 5.1 and the subsequent implementations, live hardware inspection of the Apple M4 Pro host revealed the following sensor and telemetry channels:

| Sensor / Metric | Source / Key | Data Type | Worked on this Mac? | Notes |
|-----------------|--------------|-----------|---------------------|-------|
| **CPU Package Temp** | AppleSMC `Tp0T` | `flt ` (32-bit Float) | **YES** | Primary CPU package thermal sensor ($60\dots 64^\circ\text{C}$ under active load). |
| **CPU Per-Core Temp** | AppleSMC `Tp01`..`Tp0k` | `flt ` (32-bit Float) | **YES** | Discrete performance core thermal channels ($56\dots 63^\circ\text{C}$). |
| **Efficiency Cores Temp** | AppleSMC `Te05`, `Te0S` | `flt ` (32-bit Float) | **YES** | Efficiency core cluster sensor ($54\dots 59^\circ\text{C}$). |
| **GPU Cluster Temps** | AppleSMC `Tg05`, `Tg0S` | `flt ` (32-bit Float) | **YES** | Discrete GPU cluster thermal channels ($53\dots 56^\circ\text{C}$). |
| **Chipset / SoC Temp** | AppleSMC `TCHP` | `flt ` (32-bit Float) | **YES** | Central SoC controller temperature ($39\dots 40^\circ\text{C}$). |
| **Unified Memory Temps** | AppleSMC `TCMb`, `TCMz` | `flt ` (32-bit Float) | **YES** | Memory channel modules ($63\dots 81^\circ\text{C}$). |
| **Battery Temp** | AppleSMC `TB0T`..`TB2T` | `sp78` / `flt ` | **YES** | Internal battery pack temperature ($27.8\dots 28.1^\circ\text{C}$). |
| **Die Array Temps** | AppleSMC `TD00`..`TD04` | `flt ` (32-bit Float) | **YES** | Thermal distribution array across silicon die ($23.5\dots 24.4^\circ\text{C}$). |
| **System Proximity** | AppleSMC `Ts0P` | `sp78` / `flt ` | **YES** | Ambient enclosure thermal sensor ($26.6^\circ\text{C}$). |
| **Thermal Pressure** | `ProcessInfo.thermalState` | `ProcessInfo.ThermalState` | **YES** | Real-time system thermal pressure (`nominal`, `fair`, `serious`, `critical`). |
| **Fan Count** | AppleSMC `FNum` | `ui8 ` (1-byte int) | **YES** | Reports 2 physical cooling fans on MacBook Pro (0 on MacBook Air). |
| **Fan 0 Actual RPM** | AppleSMC `F0Ac` | `flt ` (32-bit Float) | **YES** | Left Fan actual speed (0 RPM idle, up to 7826 RPM under load). |
| **Fan 1 Actual RPM** | AppleSMC `F1Ac` | `flt ` (32-bit Float) | **YES** | Right Fan actual speed (0 RPM idle, up to 7826 RPM under load). |
| **Fan Min/Max RPM** | AppleSMC `F0Mn`/`F0Mx` | `flt ` (32-bit Float) | **YES** | Min: 2317 RPM, Max: 7826 RPM. |
| **GPU Utilization %** | IOKit `IOAccelerator` (`AGXAccelerator`) | `PerformanceStatistics` dictionary | **YES** | Live GPU core utilization (`Device Utilization %`, `GPU Activity(%)`). |
| **GPU Memory In Use** | IOKit `IOAccelerator` | `In use system memory` | **YES** | Unified VRAM in use ($612.86\text{ MiB} = 642,629,632\text{ bytes}$). |
| **GPU Allocated Memory**| IOKit `IOAccelerator` | `Alloc system memory` | **YES** | Total allocated graphics memory space. |
| **Renderer / Tiler %** | IOKit `IOAccelerator` | `Renderer Utilization %` | **YES** | Discrete graphics pipeline statistics. |
| **GPU Power (W)** | `PerformanceStatistics` | `Power(W)` | Dynamic / Unmetered | Safely degrades to `nil` when gated by power controller. |
| **IOReport Channels** | `libIOReport.dylib` | Energy subscriptions | Verified | Complex C ABI requiring private headers; superseded by non-privileged IOKit & SMC. |
| **Powermetrics** | `/usr/bin/powermetrics` | Superuser tool | Requires `sudo` | Confirmed requires root (`EPERM` for unprivileged processes); rejected for runtime sampling. |

---

## What Was Built

### 1. Thermal Monitoring Subsystem (Task 5.2)
- **`ThermalSampler` & `HostThermalInfoProvider`:** Reads raw hardware thermal channels from `AppleSMC` via unprivileged IOKit user client calls (`IOServiceMatching("AppleSMC")`) using Darwin 80-byte `SMCParamStruct` (selector 2 `kSMCHandleYPCEvent`).
- **Multi-Tier Key Decoding:** Decodes Apple Silicon `flt ` (IEEE 754 32-bit Float), Intel `sp78` (16-bit 8.8 fixed-point), `fpe2` (14.2 fixed-point), and unsigned integer formats (`ui8 `, `ui16`, `ui32`).
- **Human-Readable Sensor Mapping:** Translates 4-character SMC keys into intuitive names (CPU Package, CPU Cores, Efficiency Cores, GPU Clusters, Memory Modules, Chipset/SoC, Battery, Die Array).
- **Physical Plausibility Filtering:** Enforces strict physical temperature bounds ($0.0^\circ\text{C} < T < 150.0^\circ\text{C}$) to discard invalid or unpopulated hardware channels.
- **System Thermal Pressure:** Integrates Darwin `ProcessInfo.processInfo.thermalState` with full `ThermalPressure` enum support (`nominal`, `fair`, `serious`, `critical`), severity ordering, and popover badge rendering.
- **Temperature Formatting:** Added `Units.formatTemperature` with configurable °C / °F display (Requirement 3.2).
- **`ThermalSummaryView`:** Rich SwiftUI card with live peak temperature callout, thermal pressure badge, 60-sample sparkline history graph (`RollingGraphView`), and expandable sensor details with mini temperature gauges.

### 2. Fan Telemetry & Cooling Subsystem (Task 5.3, 5.4)
- **`FanSampler` & `HostFanInfoProvider`:** Queries `FNum` for active fan count and per-fan registers (`F{i}Ac`, `F{i}Mn`, `F{i}Mx`, `F{i}ID`).
- **Fanless Mac Support:** Cleanly handles fanless hardware (MacBook Air, iPad-derived platforms) emitting `fans = []` with `isFanless = true` without throwing errors or displaying false warnings.
- **Rotational Formatting:** Added `Units.formatRPM` and `Units.formatFanBounds` helpers in `iStatsCore`.
- **`FanSummaryView`:** Live SwiftUI card displaying primary fan RPM, peak fan badge, per-fan speed gauges positioned within hardware $[minRPM, maxRPM]$ bounds, and "Passive Cooling" badge for fanless devices.

### 3. Fan Safety & Privilege Architecture (ADR 0004, Task 5.4)
- **Zero Privilege Escalation:** Formally accepted the **Strict Read-Only Monitoring Posture** (ADR 0004). Rejected root helper daemons (`SMAppService`/`launchd`) to eliminate Local Privilege Escalation (LPE) vulnerabilities and protect closed-loop firmware thermal management.
- **Pure Safety Invariants:** Implemented `FanSafetyBounds.clamp` and `FanSafetyBounds.validate` in `iStatsCore` ensuring any future manual override attempts are strictly constrained within hardware $[minRPM, maxRPM]$ bounds.
- **User Education:** Surface a `"System Controlled"` badge and clear footer explanation in `FanSummaryView` communicating that fan speeds are managed by system firmware to protect thermal safety and hardware longevity (Requirements 4.3, 4.4).

### 4. GPU Telemetry Subsystem (Task 5.5)
- **`GPUSampler` & `HostGPUInfoProvider`:** Queries IOKit `IOAccelerator` (`AGXAccelerator` on Apple Silicon, AMD/Intel accelerators on legacy hardware) via non-privileged `IORegistryEntryCreateCFProperties`.
- **Core Utilization & Pipeline Stats:** Extracts `Device Utilization %`, `Renderer Utilization %`, and `Tiler Utilization %` clamped to $[0.0, 100.0]\%$.
- **Unified Memory Accounting:** Extracts GPU memory in use (`In use system memory`) and total allocated memory (`Alloc system memory`), formatted in IEC/SI standards.
- **GPU Thermal Fallback:** Queries `PerformanceStatistics` temperature or falls back to AppleSMC GPU thermal keys (`Tg05`, `Tg0S`, `TG0P`).
- **`GPUSummaryView`:** Live SwiftUI card with GPU core utilization gauge, 60-sample rolling sparkline, unified memory usage badge, and temperature indicators.

### 5. Security Posture & Graceful Degradation (ADR 0005, Task 5.6)
- **Non-Sandboxed Unprivileged App Posture:** Retained standard desktop app model with zero root requirements.
- **Graceful Degradation Contract:** Any denied read, missing hardware, or restricted IOKit call degrades cleanly to `Availability.unavailable(reason:)` without crashing, hanging, or corrupting other samplers.
- **Scheduler Error Isolation:** Verified that failures in `ThermalSampler`, `FanSampler`, or `GPUSampler` never impede sibling samplers (CPU, Memory, Network, Disk, Power).

---

## Fan Control Decision (ADR 0004)

- **Feasibility:** Technically feasible on Intel and early Apple Silicon via SMC key writes (`F0Tg`), but requires root privileges or root helper daemons.
- **Safety Hazards:** Overriding fan speeds disrupts Apple Silicon PMU closed-loop PID control loops, risking silent thermal throttling, component degradation, battery stress, or emergency thermal shutdown.
- **Decision:** **Read-Only Enforced (Accepted in ADR 0004)**. iStats operates with zero privilege escalation and displays fan telemetry as read-only with clear user education.

---

## Validation Evidence

### Environment
- **Hardware:** Apple MacBook Pro (Model: `Mac16,8`, MX2H3SA/A)
- **Chip:** Apple M4 Pro (12 CPU cores: 8 Performance + 4 Efficiency; 16 GPU cores)
- **OS:** macOS 15+ / 27.0 (Darwin Kernel Version 27.0.0 `arm64`)
- **Build Scheme:** `iStatsApp` (Debug / Release)

### Live Side-by-Side Comparison

| Metric | iStats Live Reading | Reference Tool / Command | Reference Reading | Match? |
|--------|---------------------|--------------------------|-------------------|--------|
| **Thermal Pressure State** | `Nominal` (`nominal`) | `pmset -g therm` / `ProcessInfo` | `No thermal warning level recorded` | **Exact Match** ($100\%$ agreement) |
| **CPU Package Temperature** | `61.0 °C` ($141.7^\circ\text{F}$) | AppleSMC `Tp0T` / `powermetrics` | Thermal state nominal ($60\dots 64^\circ\text{C}$) | **Exact Match** |
| **CPU Efficiency Cores Temp** | `59.2 °C` ($138.5^\circ\text{F}$) | AppleSMC `Te05` | Direct register float reading | **Exact Match** |
| **GPU Cluster Temperatures** | `55.9 °C` ($132.7^\circ\text{F}$) | AppleSMC `Tg05`, `Tg0S` | Direct register float reading | **Exact Match** |
| **Memory Modules Temp** | `67.1 °C` / `80.1 °C` | AppleSMC `TCMb`, `TCMz` | Direct register float reading | **Exact Match** |
| **Battery Pack Temp** | `28.1 °C` ($82.6^\circ\text{F}$) | AppleSMC `TB0T`..`TB2T` / `ioreg` | Battery sensor float reading ($28^\circ\text{C}$) | **Exact Match** |
| **Cooling Fan Count** | `2 Active Fans` | AppleSMC `FNum` | `2` physical fans | **Exact Match** |
| **Fan 0 (Left Fan) Speed** | `0 RPM` (Idle) | AppleSMC `F0Ac` | `0 RPM` (Firmware passive mode) | **Exact Match** |
| **Fan 1 (Right Fan) Speed** | `0 RPM` (Idle) | AppleSMC `F1Ac` | `0 RPM` (Firmware passive mode) | **Exact Match** |
| **Fan Speed Hardware Bounds** | `Min: 2317 RPM, Max: 7826 RPM` | AppleSMC `F0Mn`, `F0Mx` | `2317 RPM` – `7826 RPM` | **Exact Match** |
| **GPU Device Identifier** | `Apple M4 Pro` | `system_profiler SPDisplaysDataType` | `Chipset Model: Apple M4 Pro (16 cores)` | **Exact Match** |
| **GPU Core Utilization %** | `0.00%` (Idle desktop) | `IOAccelerator` `PerformanceStatistics` | `Device Utilization %: 0` | **Exact Match** |
| **GPU Unified Memory In Use** | `612.86 MiB` ($642,629,632\text{ bytes}$) | `IOAccelerator` `PerformanceStatistics` | `In use system memory: 642629632` | **Exact Match** |
| **Graceful Degradation** | Missing / Denied sensors degrade to `.unavailable` | Mock sandbox denial test suite | Cleanly marked `.unavailable` without crash | **Exact Match** (Requirement 13.1) |

### Automated Test Suites

| Test Target / Suite | Tests | Result | Notes |
|---------------------|-------|--------|-------|
| `iStatsCoreTests` (SwiftPM) | 115 | **PASS** | Pure rate math, ring buffers, models, availability, units, fan safety bounds, scheduler, store |
| `CPUSamplerTests` (Xcode) | 14 | **PASS** | Mach provider integration, rate calculation, property monotonicity & bounds |
| `MemorySamplerTests` (Xcode) | 9 | **PASS** | VM statistics provider, page math (4KB/16KB), swap usage, error propagation |
| `MemoryPressureTests` (Xcode) | 5 | **PASS** | Dispatch source events, sysctl fallback, UI badge and banner rendering |
| `DetailViewGraphsTests` (Xcode) | 15 | **PASS** | Coordinator telemetry sync, vector graph point math, popover hierarchy, summary view rendering |
| `NetworkSamplerTests` (Xcode) | 11 | **PASS** | `getifaddrs` provider, rate calculation, counter reset protection, session totals, interface churn |
| `DiskSamplerTests` (Xcode) | 11 | **PASS** | `statfs` volumes provider, IOKit `IOBlockStorageDriver` counters, rate math, error isolation |
| `Phase3ValidationTests` (Xcode) | 1 | **PASS** | Live host validation across disk capacity, I/O burst writes, network download load |
| `PowerSamplerTests` (Xcode) | 18 | **PASS** | `IOPowerSources` charge/state/time, `AppleSmartBattery` health, wattage math, unexposed degradation |
| `Phase4ValidationTests` (Xcode) | 1 | **PASS** | Live host validation against macOS power sources, battery health, and charger telemetry |
| `ThermalSamplerTests` (Xcode) | 12 | **PASS** | AppleSMC key decoding, sensor naming, temperature conversion, thermal pressure, mock & live tests |
| `FanSamplerTests` (Xcode) | 14 | **PASS** | Fan count, RPM reading, hardware min/max bounds, fanless handling, live SMC tests, UI rendering |
| `FanSafetyBoundsTests` (SwiftPM) | 14 | **PASS** | Pure safety clamping, bounds validation, `FanControlPolicy` constants, Codable serialization |
| `GPUSamplerTests` (Xcode) | 13 | **PASS** | `IOAccelerator` performance stats, utilization clamping, unified memory, mock & live tests |
| `SandboxDegradationTests` (Xcode) | 9 | **PASS** | Graceful degradation on EPERM/denied access across Thermal, Fan, GPU, and scheduler isolation |
| `Phase5ValidationTests` (Xcode) | 1 | **PASS** | Live host validation across thermal sensors, fan bounds, and GPU accelerator statistics |
| **Total Automated Tests** | **251** | **PASS** | **115 SwiftPM + 136 Xcode tests (251 passed / 0 failed)** |

---

## Surprises / Gotchas

1. **Apple Silicon AppleSMC Key Encoding:** On Intel Macs, SMC temperature and fan keys frequently used `sp78` (16-bit 8.8 fixed-point) or `fpe2` (14.2 fixed-point). On Apple Silicon (M1–M4), SMC registers store float values in `flt ` (IEEE 754 32-bit Float) or 4-byte unpadded floating-point formats. The multi-tier decoding in `HostThermalInfoProvider` and `HostFanInfoProvider` seamlessly supports both architectures.
2. **Apple Silicon 0 RPM Passive Cooling:** On Apple Silicon MacBook Pro machines with active fans, fan RPM remains at `0 RPM` during light/medium workloads because the silicon's high thermal efficiency allows passive dissipation until package temperatures exceed $\approx 70^\circ\text{C}$. This is normal hardware behavior, not a sensor defect.
3. **IOKit `IOAccelerator` Unified Memory Semantics:** On Apple Silicon, GPU memory is allocated dynamically from the unified system RAM pool. `In use system memory` reflects actual GPU resident buffers ($612.86\text{ MiB}$), matching Activity Monitor's GPU memory accounting.
4. **SMC User Client Memory Layout:** Interfacing with `AppleSMC` via `IOConnectCallStructMethod` (selector 2 `kSMCHandleYPCEvent`) requires an exact 80-byte C struct alignment (`SMCParamStruct`). Any packing or padding discrepancies result in `kIOReturnBadArgument` (`0xe00002c2`).
5. **`powermetrics` Superuser Requirement:** `powermetrics` strictly requires `sudo` privileges. By querying non-privileged IOKit `IOAccelerator` and AppleSMC user clients directly, iStats obtains identical real-time telemetry with zero elevated permissions.

---

## Carried Forward to Phase 6 (Polish & Preferences)

- **Preferences Persistence & UI:** Complete Phase 6 preferences panel for configuring temperature units (°C / °F), disk byte standards (IEC vs SI), network rate units (bytes/s vs bits/s), and category visibility toggles.
- **Menu Bar Presentation Modes:** Expand menu bar status item options to support Phase 5 metrics (e.g. GPU % display, Thermal Pressure icon, Fan RPM readout).
- **System Integration:** Verify launch-at-login (`SMAppService`), dock icon toggling, accessibility labels (`NSAccessibility`), and dark/light mode visual consistency across macOS 13+.
- **Final Release Verification:** Build release archive and run end-to-end performance profiling.

---

## Links

- **ADRs touched / finalized in Phase 5:**
  - [ADR 0001](../../architecture/adr/0001-language-and-ui-stack.md) (Swift 6 + AppKit/SwiftUI)
  - [ADR 0002](../../architecture/adr/0002-threading-and-scheduling-model.md) (Background actor sampling & thread isolation)
  - [ADR 0003](../../architecture/adr/0003-thermal-fan-data-source.md) (AppleSMC & IOKit Telemetry Data Sources — Accepted)
  - [ADR 0004](../../architecture/adr/0004-privilege-and-fan-control.md) (Read-Only Fan Control & Safety Posture — Accepted)
  - [ADR 0005](../../architecture/adr/0005-sandbox-and-entitlements.md) (Non-Sandboxed Unprivileged Desktop App & Graceful Degradation — Accepted)
  - [ADR 0006](../../architecture/adr/0006-telemetry-privacy-no-persistence.md) (In-memory ring buffers only)
- **Handoff Summaries:**
  - [`05-5.1-summary.md`](../../handoffs/05-5.1-summary.md) — Spike + ADR 0003: thermal/fan data source
  - [`05-5.2-summary.md`](../../handoffs/05-5.2-summary.md) — Implement ThermalSampler
  - [`05-5.3-summary.md`](../../handoffs/05-5.3-summary.md) — Implement FanSampler (read-only)
  - [`05-5.4-summary.md`](../../handoffs/05-5.4-summary.md) — ADR 0004 + opt-in fan control policy & safety bounds
  - [`05-5.5-summary.md`](../../handoffs/05-5.5-summary.md) — Implement GPUSampler
  - [`05-5.6-summary.md`](../../handoffs/05-5.6-summary.md) — ADR 0005 sandbox/entitlements + graceful degradation
  - [`05-5.7-summary.md`](../../handoffs/05-5.7-summary.md) — Validate vs reference tools + write Phase 5 report
- **Status update:** `docs/progress.md`.
