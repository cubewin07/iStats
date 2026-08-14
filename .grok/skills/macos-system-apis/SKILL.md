---
name: macos-system-apis
description: >
  How iStats must call Mach, sysctl, IOKit, getifaddrs, and IOPowerSources.
  Use when implementing or reviewing any sampler, writing C/Swift interop for
  kernel stats, or when the user mentions CPU, memory, network, disk, battery,
  sysctl, host_statistics, or IOKit.
---

# macOS system APIs (iStats)

Canonical mapping: `docs/specs/design.md` (API table) and `docs/guides/prerequisites-and-learning.md`. Threading: ADR 0002. Privilege: ADR 0004. Sandbox: ADR 0005.

This skill does **not** cover AppleSMC keys or IOReport thermal channels — use `applesmc-iokit-spi`.

## Hard rules

1. Never call these APIs on `@MainActor` or the AppKit main thread. `SampleScheduler` (Phase 1) owns the background work.
2. Every kernel/IOKit return is checked. No force-unwrap of `kern_return_t`, `UnsafeMutablePointer`, or `Unmanaged`.
3. Failure → throw `SamplerError` (or equivalent). The scheduler turns that into `Availability.unavailable(reason:)`. Do not return a fake zero.
4. Cumulative counters become rates only through `RateMath` (`cpuUsagePercent`, `bytesPerSecond`). First sample and counter reset are 0, not a spike.
5. Import Darwin / IOKit only inside the Sampling layer. `iStatsCore` stays free of hardware headers.

## API map (implement only the phase you were asked for)

| Metric | Call | Output we need |
|--------|------|----------------|
| CPU total / per-core | Mach `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` | Per-core tick buckets (user, system, idle, nice). Keep previous snapshot. |
| Load average | `sysctl` `vm.loadavg` | Three doubles. |
| CPU frequency | `sysctl` `hw.cpufrequency*` / Apple Silicon limits | May be absent → unavailable. |
| Memory | `host_statistics64(HOST_VM_INFO64)` + `host_page_size` + `sysctl hw.memsize` | Page counts × page size. Match Activity Monitor's "used" definition (wired + active + compressed — see learning guide). |
| Swap | `sysctl vm.swapusage` | Decode `xsw_usage`. |
| Memory pressure | `DispatchSource` memory-pressure or documented `sysctl` | Map to `MemoryPressure.normal/warning/critical`. |
| Network | `getifaddrs` + `if_data` (`ifi_ibytes` / `ifi_obytes`) | Per-interface cumulative bytes → `RateMath.bytesPerSecond`. |
| Disk capacity | `statfs` / `FileManager` mounted volumes | Total / used / free per volume. |
| Disk I/O | IOKit `IOBlockStorageDriver` statistics | Optional early; same rate-math rules. |
| Battery | `IOPSCopyPowerSourcesInfo` / `IOPSCopyPowerSourcesList` + `AppleSmartBattery` registry | Charge, state, time remaining, cycle count, condition, design vs max. |
| GPU | IOKit `IOAccelerator` / `AGXAccelerator` performance stats | Keys vary; missing key → unavailable. |

## Interop notes

- Prefer a tiny private Swift wrapper per call site over scattering `withUnsafeMutablePointer` in view models.
- Copy Mach arrays out immediately; do not hold `processor_info_array_t` past `vm_deallocate`.
- For `sysctl`, size-query first (`oldp == nil`) then allocate. Treat `ENOENT` / `ENOTSUP` as unsupported, not a crash.
- IOKit: `IOServiceGetMatchingService` / `IORegistryEntryCreateCFProperty` — release `io_object_t` and `CF` objects you own. Missing property is unavailable, not 0.
- `getifaddrs`: walk, copy the fields you need, `freeifaddrs`. Skip interfaces you cannot read.

## Do not

- Shell out to `top`, `powermetrics`, or `pmset` as the production sampler. Those are **validation** tools (`metric-validation` skill).
- Run the app sandboxed (ADR 0005). Still degrade if a single read is denied.
- Install a privileged helper for ordinary reads (ADR 0004).
