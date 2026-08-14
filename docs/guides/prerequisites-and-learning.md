# iStats — Prerequisites & Learning Guide

This is the most important document for the project's learning goal. It answers two questions for every part of the app:

1. **What do I need to understand before I can write or trust this code?**
2. **How do I verify the number iStats shows is actually correct?**

You come from a full-stack background (Spring Boot, React, system design) and have not done OS-level work. The notes below bridge from concepts you know to the macOS equivalents.

---

## Part 1 — Foundational concepts (study before Phase 1–2)

### Processes, the kernel, and user space
- Your app runs in **user space**; it asks the **kernel** for system information through well-defined interfaces (syscalls and frameworks). You never read hardware registers directly from a normal app.
- Analogy: like your Spring app calling a database driver instead of reading disk blocks itself. The kernel is the "driver" for the whole machine.

### The four data sources you'll use
| Source | What it is | Web-world analogy |
|--------|-----------|-------------------|
| `sysctl` | A key/value interface to read kernel state (memory size, load average, swap) | A read-only config/metrics endpoint |
| **Mach** `host_statistics` | Lower-level kernel calls for CPU ticks and VM stats | A metrics API that returns raw counters |
| **IOKit** | Framework to talk to device drivers via a registry tree | A service registry you query for device nodes |
| **AppleSMC** | The System Management Controller: temps, fans, power | A microcontroller exposing sensor "keys" |

### Counters vs. rates (critical mental shift)
Most OS metrics are **cumulative counters** (total CPU ticks since boot, total bytes sent). To show a *rate* (CPU %, MB/s) you take two samples and divide the delta by the time elapsed. This is the single most common source of bugs, so the rate math is pure and unit-tested.

### Threading on macOS
- The **main thread** must stay free for UI. System calls go on background queues (GCD / Swift concurrency).
- Study: Grand Central Dispatch basics, `@MainActor`, `AsyncStream` or Combine `@Published`.

### Menu bar app basics
- `NSStatusItem` = your icon in the menu bar.
- `LSUIElement` (Info.plist key) = run without a Dock icon.
- Study: AppKit app lifecycle, `NSApplication`, `NSStatusBar`.

---

## Part 2 — Per-metric learning + validation

For each category: the API to learn, the gotcha, and the **reference command** to check your output against.

### CPU
- **Learn:** Mach `host_processor_info(PROCESSOR_CPU_LOAD_INFO)`, per-core tick counters; `sysctl vm.loadavg`.
- **Gotcha:** you must keep the previous tick snapshot and compute deltas; first sample has no rate.
- **Validate:** open **Activity Monitor → CPU**, or run `top -l 2` in Terminal and compare the second sample's CPU usage. Load average: `uptime`.

### Memory
- **Learn:** Mach `host_statistics64(HOST_VM_INFO64)`, `host_page_size`, `sysctl hw.memsize`, `sysctl vm.swapusage`.
- **Gotcha:** macOS "memory used" is nuanced (wired + active + compressed); match Activity Monitor's definition.
- **Validate:** **Activity Monitor → Memory** (Memory Used, Swap, Pressure), or `vm_stat` and `sysctl vm.swapusage` in Terminal.

### Network
- **Learn:** `getifaddrs` + `if_data` (`ifi_ibytes`/`ifi_obytes`) per interface.
- **Gotcha:** counters reset when an interface restarts → never report a negative rate; clamp to 0 for that cycle.
- **Validate:** **Activity Monitor → Network** (data received/sent per second), or `netstat -ib` sampled twice.

### Disk
- **Learn:** `statfs`/`FileManager` for capacity; IOKit `IOBlockStorageDriver` statistics for I/O.
- **Validate:** capacity with `df -h`; I/O with **Activity Monitor → Disk** or `iostat`.

### Battery & Power
- **Learn:** `IOPowerSources` (charge, state, time remaining); `AppleSmartBattery` IORegistry entry (cycle count, condition, design vs max capacity); SMC/IOReport for wattage.
- **Validate:** `pmset -g batt` (charge/state), `system_profiler SPPowerDataType` (cycle count, condition, capacities). Power draw: `sudo powermetrics --samplers cpu_power,gpu_power`.

### Thermal, Fan, GPU (hardest — Phase 5)
- **Learn:** AppleSMC key reads via IOKit (`AppleSMC` service, key codes like `TC0P`, `F0Ac`); on Apple Silicon many classic SMC keys differ or are absent, so IOReport / `powermetrics` concepts matter.
- **Gotcha:** SMC keys are undocumented and vary by model and macOS version. Expect to mark sensors `.unavailable`. Do a **spike** first.
- **Validate:** `sudo powermetrics` (thermal pressure, GPU); for fans/temps cross-check with a known tool you trust on your specific machine, and record which keys worked in the Phase 5 report.

---

## Part 3 — How to validate in general

1. Put iStats and the reference tool side by side.
2. Apply a known load (e.g., run a stress loop, copy a large file, start a download).
3. Confirm iStats moves in the same direction and roughly the same magnitude.
4. Record the comparison (screenshots / numbers) in that phase's `report.md`. This is both QA and your learning record.

## Part 4 — Recommended reading

- Apple docs: `NSStatusItem`, `NSStatusBar`, App lifecycle, `SMAppService` (launch at login).
- Apple docs: IOKit Fundamentals, IORegistry, `IOPowerSources`.
- `man` pages: `sysctl`, `top`, `vm_stat`, `netstat`, `df`, `iostat`, `pmset`, `powermetrics`.
- Concepts: Mach host/processor info (kernel programming references), GCD and Swift concurrency.
