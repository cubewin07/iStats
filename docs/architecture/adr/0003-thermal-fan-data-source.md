# ADR 0003 — Thermal, Fan & GPU Data Sources

**Status:** Accepted (confirmed by Phase 5 live spike on Apple Silicon & macOS)

---

## Context

Temperature, fan speed, and GPU utilization metrics have historically come from the **System Management Controller (SMC)** via IOKit on Intel Macs using 4-character keys (e.g., `TC0P` for CPU die, `F0Ac` for fan actual RPM). On **Apple Silicon (M-series)** hardware, sensor topologies, thermal management controllers, and GPU architectures differ substantially:
- Classic Intel-era temperature keys (such as `TC0P`, `TG0P`) are either absent or map to different internal indices.
- Fan telemetry is still managed via `AppleSMC` IOKit services, but utilizes standard 32-bit floating point representations (`flt`) rather than 16-bit fixed-point (`sp78`/`fpe2`).
- Apple Silicon thermal telemetry is surfaced extensively through `IOHIDEventSystemClient` with 70+ hardware-named sensor channels across the SoC, PMU dies, battery gas gauge, and NAND flash storage.
- GPU utilization and memory metrics are exposed directly via `IOKit` `IOAccelerator` (`AGXAccelerator`) performance statistics dictionaries without needing kernel extensions or elevated privileges.
- Energy and power accumulation channels are surfaced via private `libIOReport.dylib` APIs.
- The command-line utility `powermetrics` provides comprehensive metrics but requires superuser privileges (`sudo`), making process execution unusable for a low-overhead, unprivileged menu bar application.

---

## Options Evaluated During Spike

1. **AppleSMC Key Access via IOKit (`IOServiceMatching("AppleSMC")`)**:
   - **Mechanism:** Open user client connection (`IOServiceOpen`) and execute external method selector `2` (`kSMCHandleYPCEvent`) using an exact 80-byte C-compatible struct layout (`SMCParamStruct`).
   - **Spike Findings:**
     - Fully accessible without root privileges on both Intel and Apple Silicon (tested on Apple M4 Pro / macOS 27).
     - **Fans:** Reliably exposes `FNum` (fan count), `F0Ac`/`F1Ac` (current RPM as `flt`), `F0Mn`/`F1Mn` (minimum RPM), `F0Mx`/`F1Mx` (maximum RPM), `F0Md`/`F1Md` (mode), and `F0Tg`/`F1Tg` (target RPM).
     - **Thermals:** Exposes battery thermals (`TB0T`, `TB1T`, `TB2T`), SoC package (`Tp0T`, `Tp01`, `Tp05`, `Tp09`, `Tp0k`), die sensors (`TD00`..`TD24`), memory/chipset (`TCHP`, `TCMb`, `TCMz`), E-cores (`Te05`, `Te0S`), and GPU clusters (`Tg05`, `Tg0S`).
   - **Verdict:** **Primary source for Fan telemetry**; secondary fallback source for Thermal metrics.

2. **IOHIDEventSystemClient (`IOKit.framework`)**:
   - **Mechanism:** Query HID event system services matching `PrimaryUsagePage = 0xff00` (AppleVendor) and `PrimaryUsage = 5` (Temperature Sensor), querying `kIOHIDEventTypeTemperature` (event type 15) using dynamic symbol resolution (`IOHIDEventSystemClientCreateWithType`, `IOHIDServiceClientCopyEvent`).
   - **Spike Findings:**
     - Successfully discovered 77 live thermal sensor services without root.
     - Automatically supplies human-readable product labels: PMU die sensors (`PMU tdie1`..`PMU tdie14`), battery (`gas gauge battery`), NAND storage (`NAND CH0 temp`), and heatsink/calibration (`PMU tcal`).
     - Directly yields calibrated Celsius floating-point temperatures.
   - **Verdict:** **Primary source for Multi-Sensor Thermal telemetry**.

3. **IOKit `IOAccelerator` (`AGXAccelerator`) Registry Entry**:
   - **Mechanism:** Match `IOServiceMatching("IOAccelerator")` in IORegistry and inspect the `PerformanceStatistics` dictionary via `IORegistryEntryCreateCFProperties`.
   - **Spike Findings:**
     - Non-privileged, zero-overhead direct dictionary read.
     - Contains live metrics: `Device Utilization %` (GPU core load 0–100%), `In use system memory` (bytes), `Alloc system memory` (bytes), `Renderer Utilization %`, and `Tiler Utilization %`.
   - **Verdict:** **Primary source for GPU utilization and memory telemetry**.

4. **ProcessInfo & Darwin Thermal Pressure**:
   - **Mechanism:** `ProcessInfo.processInfo.thermalState` augmented by Darwin notifications (`notify_register_dispatch` for `com.apple.system.thermalpressurelevel`).
   - **Spike Findings:** Standard public Foundation / Darwin API, zero permissions, maps cleanly to `.nominal`, `.fair`, `.serious`, `.critical`.
   - **Verdict:** **Primary source for system thermal pressure level**.

5. **IOReport Framework (`libIOReport.dylib`)**:
   - **Mechanism:** Private framework querying channel groups like `Energy Model`, `CPU Stats`, `GPU Stats`.
   - **Spike Findings:** Exposes cumulative energy counters in millijoules (`GPU (mJ)`, `ANE (mJ)`, `DRAM (mJ)`).
   - **Verdict:** Usable as an energy accumulation reference; not required for core thermal/fan/GPU utilization.

6. **Spawning `powermetrics`**:
   - **Verdict:** **Rejected** for live runtime sampling due to mandatory `sudo` requirement and process invocation overhead. Retained exclusively as an external validation reference.

---

## Decision

Adopt a **modular, multi-tier telemetry architecture** tailored to Apple Silicon while retaining Intel fallback compatibility:

| Domain | Primary Source | Secondary / Fallback Source | Failure Posture |
|--------|----------------|-----------------------------|-----------------|
| **Fan Speeds & Bounds** | `AppleSMC` keys (`FNum`, `F0Ac`, `F0Mn`, `F0Mx`, etc.) | System profile / hardware descriptors | Emit `FanSample(fans: [])` or `.unavailable` |
| **Thermal Sensors** | `IOHIDEventSystemClient` (Usage Page `0xff00`, Usage `5`) | `AppleSMC` thermal keys (`Tp0T`, `TB0T`, `TD00`, etc.) | Graceful partial reading or `.unavailable` |
| **Thermal Pressure** | `ProcessInfo.processInfo.thermalState` | Darwin `machdep.cpu.thermal_level` sysctl | `pressure = nil` |
| **GPU Utilization & Memory** | IOKit `IOAccelerator` (`PerformanceStatistics`) | IOReport `GPU Stats` / `Energy Model` | Graceful partial reading or `.unavailable` |

---

## Memory & Struct Layout Requirements (AppleSMC)

To ensure binary compatibility across Swift and Darwin kernel user clients, any `AppleSMC` interaction must maintain an exact **80-byte** memory stride:

```swift
public struct SMCParamStruct {
    public var key: UInt32 = 0
    public var vers_major: UInt8 = 0
    public var vers_minor: UInt8 = 0
    public var vers_build: UInt8 = 0
    public var vers_reserved: UInt8 = 0
    public var vers_release: UInt16 = 0
    public var _pad0: (UInt8, UInt8) = (0, 0)
    public var pLimit_version: UInt16 = 0
    public var pLimit_length: UInt16 = 0
    public var pLimit_cpuPLimit: UInt32 = 0
    public var pLimit_gpuPLimit: UInt32 = 0
    public var pLimit_memPLimit: UInt32 = 0
    public var keyInfo_dataSize: UInt32 = 0
    public var keyInfo_dataType: UInt32 = 0
    public var keyInfo_dataAttributes: UInt8 = 0
    public var _pad1: (UInt8, UInt8, UInt8) = (0, 0, 0)
    public var result: UInt8 = 0
    public var status: UInt8 = 0
    public var data8: UInt8 = 0
    public var _pad2: UInt8 = 0
    public var data32: UInt32 = 0
    public var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                       UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                       UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                       UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}
// MemoryLayout<SMCParamStruct>.stride == 80 bytes
```

---

## Consequences

1. **Safety & Stability:** All sampling operations run entirely off the main thread within background tasks managed by `SampleScheduler`.
2. **Zero Privileges Required:** No root escalation or helper daemon is needed to read temperatures, fan speeds, or GPU stats in normal operation.
3. **Resilience & Degraded Operation:** If a machine has zero fans (e.g. MacBook Air), `fanCount == 0` is reported cleanly without error. Missing temperature sensors or GPU performance keys return `nil` or `.unavailable` without crashing the application or impeding other samplers (CPU, Memory, Network, Disk, Battery).
4. **Fan Control Policy:** Fans remain strictly **read-only** under this ADR. Any future fan speed mutation must strictly satisfy ADR 0004.
