# Phase 2 — Report

Phase 2 delivered the complete CPU and Memory monitoring subsystems, including kernel Mach/sysctl sampling, pure rate calculations, memory pressure monitoring via dispatch sources, live vector rolling history graphs, menu bar presentation modes, and comprehensive side-by-side validation against macOS system reference tools (`top`, `uptime`, `vm_stat`, `sysctl`).

---

## What was built

### 1. CPU Monitoring Subsystem (Tasks 2.1, 2.2, 2.3)
- **`CPUSampler` & `HostProcessorInfoProvider`:** Reads cumulative per-core tick counters (`host_processor_info(PROCESSOR_CPU_LOAD_INFO)`), system load averages (`sysctl vm.loadavg`), and clock frequency (`sysctl hw.cpufrequency`).
- **Tick Delta Math:** Computes aggregate and per-core user, system, and idle percentages via pure rate math (`RateMath.counterDelta`, `RateMath.cpuUsagePercent`) strictly off the main thread (ADR 0002, Requirement 12.1).
- **Graceful Hardware Degradation:** Safely marks CPU frequency as `nil` / `.unavailable` on Apple Silicon hardware where sysctl does not expose fixed frequency (Requirements 1.3, 1.5).
- **Mathematical Property Invariants:** Tested across synthetic fuzzed data and UInt64 boundaries for boundedness ($[0.0, 100.0]$), partition of unity ($\text{user} + \text{sys} + \text{idle} \approx 100\%$), monotonicity, counter resets, and core subset wrap-arounds (Task 2.3).

### 2. Memory & Swap Subsystem (Tasks 2.4, 2.5)
- **`MemorySampler` & `HostMemoryInfoProvider`:** Queries Mach 64-bit VM statistics (`host_statistics64(HOST_VM_INFO64)`), dynamic page size (`host_page_size`), total physical RAM (`sysctl hw.memsize`), and swap usage (`sysctl vm.swapusage`).
- **Activity Monitor Standard Memory Model:** Faithfully derives:
  - **App Memory:** $(\text{internal pages} - \text{purgeable pages}) \times \text{page size}$
  - **Wired Memory:** $\text{wire pages} \times \text{page size}$
  - **Compressed Memory:** $\text{compressor page count} \times \text{page size}$
  - **Memory Used:** $\text{App Memory} + \text{Wired Memory} + \text{Compressed Memory}$
  - **Cached Files:** $(\text{purgeable pages} + \text{external file-backed pages}) \times \text{page size}$
  - **Free Memory:** $\text{free pages} \times \text{page size}$
- **`MemoryPressureMonitor`:** Proactively listens for kernel memory pressure notifications using `DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical])` and polls `kern.memorystatus_vm_pressure_level` sysctl, publishing real-time status transitions.
- **UI Surfacing:** Surfaces memory pressure badges (`Normal`, `Warning`, `Critical`) and prominent warning/critical banners in the detail popover (Requirement 2.4).

### 3. Detail Presentation & Live Rolling Graphs (Task 2.6)
- **`MetricsCoordinator`:** Central `@MainActor` coordinator bridging background `SampleScheduler` execution with `MetricsStore` rolling history buffers and SwiftUI views.
- **`RollingGraphView`:** Vector-based SwiftUI graph rendering live 60-sample historical trajectories with gradient fills and reference grids (Requirement 10.2).
- **`CPUSummaryView` & `MemorySummaryView`:** Rich visual cards presenting live percentage gauges, rolling sparklines, multi-segment breakdowns, 1m/5m/15m load averages, clock speed, and responsive per-core matrices (Requirements 10.1, 10.3).
- **`MenuBarDisplayMode`:** Configurable menu bar status item presentation (`Icon Only`, `CPU Usage`, `Memory Usage`, `CPU & Memory`) dynamically formatting `NSStatusItem` title and icon (Requirement 9.4).

---

## What was learned

### 1. Mach `host_processor_info` & Processor Tick Counters
- **Mach Memory Layout:** `host_processor_info` with `PROCESSOR_CPU_LOAD_INFO` returns a flat buffer of `integer_t` containing `CPU_STATE_MAX` states per processor. The caller is responsible for deallocating the returned buffer with `vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)`.
- **Signed to Unsigned Bit-Pattern Casting:** The returned `integer_t` values are signed 32-bit integers representing raw 32-bit tick counters. Direct casting to `UInt64` can produce negative sign extension if bit 31 is set; casting through `UInt64(UInt32(bitPattern: info[...]))` is necessary to ensure correct unsigned counter math.
- **First Sample Invariant:** CPU percentage is defined only over a delta in time. The first sample after application launch returns 0.0% cleanly, establishing the baseline tick snapshot without spurious spikes.

### 2. macOS Memory Accounting vs Traditional Unix
- **Beyond `free = total - used`:** Modern macOS virtual memory aggressively utilizes available RAM for file caching and transparent in-RAM compression (`vm_compressor`). Free memory is therefore routinely small even under low system load.
- **Activity Monitor Formula:** Matching Activity Monitor requires accounting for anonymous internal pages and subtractive purgeable cache. Memory pressure (`DISPATCH_SOURCE_TYPE_MEMORYPRESSURE`) provides the true indicator of system memory health rather than raw free bytes.
- **Dynamic Page Size:** Page size is architecture-dependent (4 KB on Intel x86_64 vs 16 KB on Apple Silicon arm64). Querying `host_page_size(mach_host_self(), &pageSize)` dynamically guarantees accurate byte conversions across all hardware.

### 3. Apple Silicon Sysctl Differences
- **CPU Frequency Sysctl:** Intel Macs expose `hw.cpufrequency` or `hw.cpufrequency_max` via sysctl. Apple Silicon manages dynamic core frequencies within hardware power controllers without exposing fixed sysctl values (returning `ENOENT`). Conforming to ADR 0002, the app returns `nil` (`Availability.unavailable`), preventing misleading 0 GHz readouts.

---

## Validation evidence

### Environment
- **Hardware:** Apple MacBook Pro (Mac16,8)
- **CPU:** Apple M4 Pro (12 cores: 4 Efficiency + 8 Performance)
- **RAM:** 24.00 GiB ($25,769,803,776$ bytes), 16 KB page size
- **OS:** macOS 14+ (Darwin Kernel Version 27.0.0 arm64)
- **Build Scheme:** `iStatsApp` (Debug / Release)

### Live Side-by-Side Comparison

| Metric | iStats Reading | Reference Command | Reference Reading | Match? |
|--------|----------------|-------------------|-------------------|--------|
| **CPU total % (idle)** | `12.60%` (User: 6.67%, Sys: 5.93%, Idle: 87.40%) | `top -l 2 -s 1 -n 0` | `CPU usage: 8.53% user, 5.86% sys, 85.59% idle` | **Match** (within 1s window tolerance) |
| **CPU total % (load)** | `47.28%` (User: 40.08%, Sys: 7.19%, Idle: 52.72%) | `top -l 2 -s 1 -n 0` (under 4-core synthetic load) | `CPU usage: 41.48% user, 4.35% sys, 54.16% idle` | **Match** (user CPU jumped to ~40% across both) |
| **Load average** | `1m: 3.85, 5m: 3.35, 15m: 3.26` | `uptime` | `load averages: 3.85 3.35 3.26` | **Exact Match** ($100\%$ agreement) |
| **CPU frequency** | `unavailable (Apple Silicon dynamic)` | `sysctl hw.cpufrequency` | `sysctl: unknown oid 'hw.cpufrequency'` | **Match** (gracefully degraded to nil) |
| **Per-core breakdown** | 12 cores (active cores registered up to `69.2%` under load) | Activity Monitor CPU History | 12 core channels reflected active load distribution | **Match** |
| **Physical RAM** | `24.00 GiB` ($25,769,803,776$ bytes) | `sysctl hw.memsize` | `hw.memsize: 25769803776` | **Exact Match** |
| **Memory used** | `18.70 GiB` (App: 7.37 GB, Wired: 3.36 GB, Compr: 7.97 GB) | `top` / `vm_stat` / Activity Monitor | `PhysMem: 23G used (3383M wired, 8158M compressor), 236M unused` | **Match** (Activity Monitor standard) |
| **Swap used / total** | `960.00 KiB` / `1.00 GiB` | `sysctl vm.swapusage` | `total = 1024.00M used = 0.94M free = 1023.06M` | **Exact Match** ($0.94\text{ MB} \times 1024 = 962.56\text{ KB}$) |
| **Memory pressure** | `Normal` (Green badge) | `kern.memorystatus_vm_pressure_level` | `0` (Normal) | **Exact Match** |

### Automated Test Suites

| Test Target / Suite | Tests | Result | Notes |
|---------------------|-------|--------|-------|
| `iStatsCoreTests` (SwiftPM) | 86 | **PASS** | Pure rate math, ring buffers, models, availability, units, scheduler, store |
| `CPUSamplerTests` (Xcode) | 14 | **PASS** | Mach provider integration, rate calculation, property monotonicity & bounds |
| `MemorySamplerTests` (Xcode) | 9 | **PASS** | VM statistics provider, page math (4KB/16KB), swap usage, error propagation |
| `MemoryPressureTests` (Xcode) | 5 | **PASS** | Dispatch source events, sysctl fallback, UI badge and banner rendering |
| `DetailViewGraphsTests` (Xcode) | 7 | **PASS** | Coordinator telemetry sync, vector graph point math, popover hierarchy, menu bar formatting |
| **Total Automated Tests** | **121** | **PASS** | **121 passed / 0 failed** |

---

## Surprises / gotchas

1. **Mach Memory Deallocation Requirement:** `host_processor_info` allocates memory in the Mach task address space using `vm_allocate`. Omitting `vm_deallocate` causes a gradual kernel virtual memory leak during continuous background sampling. The `defer` block in `HostProcessorInfoProvider` ensures robust deallocation on every sample.
2. **Purgeable Memory Edge Cases:** On systems with extensive purgeable asset caches, `purgeablePages` can occasionally exceed `internalPages` during rapid memory churn. Clamping `appMemory = 0` prevents integer underflow.
3. **Fixed-Point Scaling in `vm.loadavg`:** The kernel `loadavg` struct stores load averages as integer numerators with a divisor `fscale` (typically 65536.0 or 1000.0). Dividing by `Double(load.fscale)` accurately produces standard floating-point load averages matching `uptime`.

---

## Carried forward to Phase 3 (Network & Disk)

- **Network Sampling:** Implement `NetworkSampler` using `getifaddrs` / `if_data64` to sample interface throughput (bytes/s, packets/s) with counter wrap-around and interface hot-plug handling.
- **Disk Monitoring:** Implement `DiskSampler` to monitor mounted volume capacities (`statfs` / `URLResourceValues`) and real-time disk I/O throughput (`IOBlockStorageDriver`).
- **Units Customization:** Connect byte/bit rate formatters (`Units.bytesPerSecond` vs `Units.bitsPerSecond`) and SI/IEC data size formatters to the detail popover and preferences settings.

---

## Links

- **ADRs touched / validated:**
  - [ADR 0001](../../architecture/adr/0001-language-and-ui-stack.md) (Swift 6 + AppKit/SwiftUI)
  - [ADR 0002](../../architecture/adr/0002-threading-and-scheduling-model.md) (Background actor sampling & thread isolation)
  - [ADR 0005](../../architecture/adr/0005-sandbox-and-entitlements.md) (Mach / sysctl sampling non-sandboxed)
  - [ADR 0006](../../architecture/adr/0006-telemetry-privacy-no-persistence.md) (In-memory ring buffers only)
- **Handoff Summaries:**
  - [`02-2.1-summary.md`](../../handoffs/02-2.1-summary.md) — Implement CPUSampler (total + per-core)
  - [`02-2.2-summary.md`](../../handoffs/02-2.2-summary.md) — Load average and CPU frequency
  - [`02-2.3-summary.md`](../../handoffs/02-2.3-summary.md) — Property tests for CPU % math
  - [`02-2.4-summary.md`](../../handoffs/02-2.4-summary.md) — Implement MemorySampler
  - [`02-2.5-summary.md`](../../handoffs/02-2.5-summary.md) — Memory pressure level + UI surfacing
  - [`02-2.6-summary.md`](../../handoffs/02-2.6-summary.md) — Render CPU + memory in the detail view
  - [`02-2.7-summary.md`](../../handoffs/02-2.7-summary.md) — Validate vs reference tools + Phase 2 report
- **Status update:** `docs/progress.md`.
