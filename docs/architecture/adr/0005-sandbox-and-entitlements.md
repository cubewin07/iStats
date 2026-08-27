# ADR 0005 — App Sandbox, Entitlements, Security Posture & Graceful Degradation

**Status:** Accepted (Settled in Phase 5)  
**Requirements:** 13.1, 13.2  
**Deciders:** Core Engineering Team  

---

## Context

A fundamental goal of **iStats** is providing deep, real-time hardware and system telemetry on macOS (Apple Silicon M-series and Intel architectures). Surfacing accurate CPU core loads, memory allocation breakdowns, disk I/O throughput, per-interface network rates, battery health, thermal sensor matrices, fan RPM dynamics, and GPU utilization requires querying low-level macOS kernel and hardware interfaces:

1. **Mach Kernel Interfaces:**
   - `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` for per-core tick counters.
   - `host_statistics64(HOST_VM_INFO64)` for wired, active, inactive, speculative, compressor, and purgeable memory pages.
2. **Darwin `sysctl` Subsystems:**
   - `vm.loadavg` (1m, 5m, 15m load averages).
   - `vm.swapusage` (total, used, free swap space).
   - `hw.memsize`, `hw.ncpu`, `hw.physicalcpu`, `hw.cpufrequency_max`.
   - `NET_RT_IFLIST2` for interface byte and packet counters.
3. **IOKit Registry & User Client Services:**
   - `IOServiceMatching("IOAccelerator")` (`AGXAccelerator`) performance statistics dictionaries for GPU core, renderer, and tiler utilization.
   - `IOServiceMatching("AppleSMC")` for fan telemetry (`FNum`, `F0Ac`, `F0Mn`, `F0Mx`) and thermal keys (`Tp0T`, `TB0T`, `TD00`).
   - `IOServiceMatching("AppleSmartBattery")` for exact millivolt, milliampere, cycle count, and temperature telemetry.
   - `IOServiceMatching("IOBlockStorageDriver")` for block-level disk I/O throughput and IOPS statistics.
4. **HID Event System & High-Level Frameworks:**
   - `IOHIDEventSystemClient` (Usage Page `0xff00`, Usage `5`) for Apple Silicon SoC/PMU thermal sensor channels.
   - `IOPowerSources` / `IOPSCopyPowerSourcesInfo` for AC state and battery charge percentages.
   - `getifaddrs` and `getfsstat` POSIX APIs for network interfaces and mounted volume capacities.

### macOS Security Architecture Constraints

macOS enforces robust security boundaries to isolate applications and protect user privacy:

- **App Sandbox (`com.apple.security.app-sandbox`):** Required for distribution through the Mac App Store. Confines processes to a sandbox container, strictly restricting Mach service lookups, POSIX file system access outside containers, raw network socket access, and direct IOKit registry connections to hardware drivers and user clients.
- **Hardened Runtime:** Enforces code integrity, prevents arbitrary code injection, and regulates debugging permissions (`get-task-allow`).
- **Transparency, Consent, and Control (TCC):** Controls access to user data (Documents, Camera, Location, Full Disk Access).

Under a standard App Sandbox without private entitlements, direct user client connections to `AppleSMC`, `IOBlockStorageDriver`, `IOAccelerator`, and `IOHIDEventSystemClient` are restricted or denied by kernel policy.

---

## Metric-by-Metric Sandbox Survivability & Entitlement Audit

The table below catalogs every metric category implemented in iStats, evaluating its behavior under a sandboxed container vs. a non-sandboxed runtime:

| Category | Underlying APIs & Interfaces | Non-Sandboxed Behavior | Standard App Sandbox Behavior | Sandbox Entitlement / Workaround Needed | Fallback & Degradation Posture |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **CPU** | Mach `host_processor_info`, Darwin `sysctl` (`vm.loadavg`, `hw.ncpu`) | ✅ Full per-core & total load | ✅ Survives (Mach host ports accessible) | Standard entitlement (none required) | Emits `.unavailable` on Mach error |
| **Memory** | Mach `host_statistics64`, Darwin `sysctl` (`vm.swapusage`, `hw.memsize`), `DISPATCH_SOURCE_TYPE_MEMORYPRESSURE` | ✅ Full virtual memory & swap telemetry | ⚠️ Partial (`host_statistics64` works; `vm.swapusage` sysctl is restricted) | None available for public sandboxed apps | Degrades swap to nil; memory pages continue |
| **Network** | POSIX `getifaddrs`, Darwin `sysctl` (`NET_RT_IFLIST2`) | ✅ Full interface list & live bitrates | ⚠️ Requires `com.apple.security.network.client` entitlement; interface enumeration permitted | `com.apple.security.network.client` | Degrades to `.unavailable` if interface queries fail |
| **Disk** | POSIX `getfsstat`, IOKit `IOBlockStorageDriver` / `IOMedia` | ✅ Mounted capacities & live I/O throughput | ⚠️ Capacity survives for sandbox container / mounted roots; IOKit I/O throughput blocked | Requires Full Disk Access or unsandboxed helper | Degrades I/O throughput to nil; displays volume capacities |
| **Power** | `IOPowerSources`, IOKit `AppleSmartBattery` | ✅ Full charge, health, cycles, voltage, wattage | ⚠️ `IOPowerSources` survives; `AppleSmartBattery` IOKit registry entry blocked | `IOPowerSources` only | Degrades smart battery metrics to nil; displays basic charge & AC state |
| **Thermal** | `IOHIDEventSystemClient` (`0xff00:5`), `AppleSMC`, `ProcessInfo.processInfo.thermalState` | ✅ 20+ sensor channels & thermal pressure | ❌ IOHID client and AppleSMC blocked; only `ProcessInfo.thermalState` survives | None available for public sandboxed apps | Degrades to thermal pressure only or `.unavailable` |
| **Fans** | `AppleSMC` (`FNum`, `F0Ac`, `F0Mn`, `F0Mx`) | ✅ Full fan RPM and min/max limits | ❌ AppleSMC user client blocked | None available for public sandboxed apps | Degrades to empty fans / `.unavailable` |
| **GPU** | IOKit `IOAccelerator` (`AGXAccelerator` performance dictionary), AppleSMC | ✅ Core load, memory, temperature, power | ❌ `IOAccelerator` registry property queries blocked | Metal performance HUD private entitlement | Degrades to `.unavailable` |

---

## Options Evaluated

### Option 1: Non-Sandboxed Unprivileged Desktop Application — **CHOSEN FOR V1**
- Build and distribute iStats as a non-sandboxed macOS application with Hardened Runtime enabled.
- Execute all sensor sampling directly within the application process on background threads.
- Request **zero elevated root privileges** (`sudo`, `AuthorizationExecuteWithPrivileges`).
- No background root helper daemon.

*Pros:*
- **Maximum Metric Fidelity:** Full, direct access to AppleSMC, IOKit accelerator statistics, battery gas gauge, and thermal event systems.
- **Zero Friction:** No installer packages, no root authorization dialogs, and no background daemon management.
- **Zero Attack Surface:** Zero privileged helper tools (`SMAppService`/`launchd`) running as root, eliminating Local Privilege Escalation (LPE) vulnerabilities (ADR 0004).
- **Simple Architecture:** Unifies sampling, domain modeling, and presentation in a clean, self-contained bundle.

*Cons:*
- Cannot be distributed via the Mac App Store in this configuration.

---

### Option 2: Sandboxed App + Privileged/Unsandboxed Helper Daemon via XPC (`SMAppService`)
- Sandbox the main menu bar application and UI.
- Bundle an unsandboxed or root privileged helper daemon using `SMAppService` or `launchd`.
- Communicate via `NSXPCConnection`.

*Pros:*
- UI layer remains strictly sandboxed.

*Cons:*
- Substantial architectural complexity (XPC serialization, process lifecycle management, code signing synchronization).
- Installing helper daemons requires root authorization or manual user approval in System Settings.
- Over-engineering for a local open-source menu bar monitor.
- Security risk: XPC endpoints in privileged helpers represent significant attack surfaces.

---

### Option 3: Sandboxed Application with Restricted Metric Subset
- Enforce App Sandbox (`com.apple.security.app-sandbox`) on the entire app.
- Drop AppleSMC, GPU performance dictionaries, thermal sensors, and disk I/O throughput.
- Display only basic CPU load, memory statistics, volume capacities, network traffic, and `IOPowerSources` battery state.

*Pros:*
- Directly eligible for Mac App Store distribution.

*Cons:*
- Strips away critical capabilities (fans, detailed temperatures, GPU utilization, disk throughput), defeating the core purpose of a comprehensive hardware monitor.

---

## Decision

iStats adopts **Option 1: Non-Sandboxed, Unprivileged Desktop Application with Strict Least Privilege and Graceful Degradation**.

1. **Non-Sandboxed Posture (Requirement 13.1):**
   - iStats is built without the `com.apple.security.app-sandbox` entitlement for development and local personal monitoring.
   - All sampling occurs in-process on background queues managed by `SampleScheduler` (ADR 0002).

2. **Strict Least Privilege & No Privilege Escalation (Requirement 13.2, ADR 0004):**
   - iStats requires **zero root privileges** and never prompts the user for administrator credentials.
   - All IOKit, Mach, and sysctl queries are unprivileged user-space reads.
   - Fan control remains read-only with automatic firmware control (ADR 0004).

3. **Graceful Degradation Contract (Requirement 13.1):**
   - If any sensor read, Mach system call, IOKit registry lookup, or Darwin sysctl is denied (due to permissions, missing hardware, or future sandbox confinement), the sampler **must not crash, hang, or throw fatal errors**.
   - The sampler maps errors to `SamplerError.unsupported`, `SamplerError.systemCallFailed`, or returns nil/empty models.
   - `SampleScheduler` intercepts errors and generates `Availability.unavailable(reason:)` readings.
   - All other healthy samplers continue running and publishing live telemetry without interruption.

4. **UI Resilience:**
   - Views (`DetailPopoverView`, `ThermalSummaryView`, `FanSummaryView`, `GPUSummaryView`, etc.) cleanly display placeholder states, status badges (e.g. `"Passive Cooling"`, `"No Battery"`, `"Unavailable"`), or hide disabled sections without throwing exceptions or visual glitches.

---

## Graceful Degradation Architecture

```
Hardware / Kernel Query
  (IOKit, Mach, AppleSMC, sysctl)
        │
        ├── [Success] ────────────► Pure Calculation ──────────► Sample<T>(value: data, availability: .available)
        │                                                               │
        └── [Denied / Unavailable] ──► Throws SamplerError ─────────────┼──► SampleScheduler Catch Block
                                                                        │          │
                                                                        │          ▼
                                                                        │    MetricReading.unavailable(category:reason:)
                                                                        │          │
                                                                        ▼          ▼
                                                             Downstream Store / Detail Views
                                                             (Surfaces .unavailable cleanly,
                                                              sibling samplers keep running)
```

---

## Consequences

- **Developer & User Experience:** Complete access to all Apple Silicon and Intel telemetry channels without configuration hurdles or security prompts.
- **Security:** Zero privilege escalation, aligned with ADR 0004 (no root helper daemons) and ADR 0006 (100% on-device telemetry with zero external transmission).
- **Reliability:** Every metric channel is fully isolated; hardware variations (e.g., fanless MacBook Air, desktop Mac without battery, discrete vs integrated GPUs) degrade gracefully without application failure.
- **Traceability:** Fully satisfies Requirements 13.1, 13.2, 12.3, and 12.4.

