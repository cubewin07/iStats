# Energy Impact and Optimization Audit

**Branch:** `perf/energy-optimization`  
**Target:** macOS 13+, Apple Silicon & Intel  
**Scope:** Source-code telemetry, kernel/system API overhead, scheduling model, and WindowServer compositor interaction.

---

## 1. Executive Summary

A profiling review and source-code investigation was conducted across `iStats` to determine the underlying root causes of excessive energy consumption and battery drain. 

Five specific hypotheses proposed by Claude were audited against the actual implementation:

| Hypothesis | Verdict | Real Severity in `iStats` | Key Affected Modules |
| :--- | :---: | :---: | :--- |
| **1. Subprocess spawning (`Process`)** | ❌ **False** | None | Uses native Mach, sysctl, and IOKit calls. No shelling out. |
| **2. Opening/closing IOKit connections per sample** | ✅ **Real** | **High** | [FanSampler.swift](file:///Users/letanthang/learning_software/OS_Project/iStats/iStats/Sampling/FanSampler.swift), [ThermalSampler.swift](file:///Users/letanthang/learning_software/OS_Project/iStats/iStats/Sampling/ThermalSampler.swift), [GPUSampler.swift](file:///Users/letanthang/learning_software/OS_Project/iStats/iStats/Sampling/GPUSampler.swift) |
| **3. Timer granularity & lack of coalescing** | ✅ **Real** | **Critical** | [SampleScheduler.swift](file:///Users/letanthang/learning_software/OS_Project/iStats/Sources/iStatsCore/SampleScheduler.swift) |
| **4. Main-thread UI redraws every tick** | ✅ **Real** | **High** | [MenuBarController.swift](file:///Users/letanthang/learning_software/OS_Project/iStats/iStats/App/MenuBarController.swift), [MenuBarIconRenderer.swift](file:///Users/letanthang/learning_software/OS_Project/iStats/iStats/UI/MenuBarIconRenderer.swift) |
| **5. High QoS waking P-cores** | ✅ **Real** | **High** | [SampleScheduler.swift](file:///Users/letanthang/learning_software/OS_Project/iStats/Sources/iStatsCore/SampleScheduler.swift), [MetricsCoordinator.swift](file:///Users/letanthang/learning_software/OS_Project/iStats/iStats/App/MetricsCoordinator.swift) |

In addition to those 5 hypotheses, the audit revealed **three additional energy drivers**:
1. **Uncached Driver & Framework Querying:** Polling `MTLCopyAllDevices()`, `NSScreen.screens` + `CGDisplayCopyDisplayMode`, `SCDynamicStoreCreate`, and `CWWiFiClient` every 2 seconds.
2. **Task Churn / Allocation Overhead:** Spawning two asynchronous child tasks per category per sample in `withThrowingTaskGroup` (16 task allocations/destructions every 2s) purely for timeout enforcement.
3. **Redundant Array Copies on `@MainActor`:** Re-allocating and broadcasting rolling history arrays 8 times per 2-second period across Combine publishers.

---

## 2. In-Depth Codebase Audit

### 2.1 Subprocess Spawning (`Process` / Shelling Out)
* **Verdict:** ❌ **NOT PRESENT (Clean)**
* **Audit Result:**
  Zero instances of `Foundation.Process`, `NSTask`, `popen`, `posix_spawn`, or command execution exist in `iStats`. All 8 samplers interface directly with Darwin kernel APIs:
  - CPU: `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` in [`CPUSampler.swift:47`](file:///Users/letanthang/learning_software/OS_Project/iStats/iStats/Sampling/CPUSampler.swift#L47).
  - Memory: `host_statistics64(HOST_VM_INFO64)` and `sysctl([CTL_HW, HW_MEMSIZE])` in [`MemorySampler.swift:65`](file:///Users/letanthang/learning_software/OS_Project/iStats/iStats/Sampling/MemorySampler.swift#L65).
  - Network: `sysctl(NET_RT_IFLIST2)` and `getifaddrs()` in [`NetworkSampler.swift:87`](file:///Users/letanthang/learning_software/OS_Project/iStats/iStats/Sampling/NetworkSampler.swift#L87).
  - Disk: `getfsstat(MNT_NOWAIT)` and `IOBlockStorageDriver` in [`DiskSampler.swift:35`](file:///Users/letanthang/learning_software/OS_Project/iStats/iStats/Sampling/DiskSampler.swift#L35).
  - Thermal: `IOHIDEventSystemClient` and `AppleSMC` in [`ThermalSampler.swift:103`](file:///Users/letanthang/learning_software/OS_Project/iStats/iStats/Sampling/ThermalSampler.swift#L103).
  - Power: `IOPSCopyPowerSourcesInfo()` in [`PowerSampler.swift:30`](file:///Users/letanthang/learning_software/OS_Project/iStats/iStats/Sampling/PowerSampler.swift#L30).

---

### 2.2 IOKit & SMC Connection Lifecycle
* **Verdict:** ✅ **REAL AND COSTLY**
* **Audit Result:**
  Hardware user client connections are created and destroyed on every sample tick:
  - **Fan Sampling ([`FanSampler.swift:43-48`](file:///Users/letanthang/learning_software/OS_Project/iStats/iStats/Sampling/FanSampler.swift#L43-L48)):**
    ```swift
    public func fans() throws -> [FanReading] {
        guard let conn = openSMCConnection() else { ... }
        defer { IOServiceClose(conn) }
    ```
    Every 2 seconds, `IOServiceGetMatchingService` searches the IORegistry, `IOServiceOpen` allocates a Mach port and user client inside the kernel, reads the keys, and `IOServiceClose` destroys it.
  - **Thermal Sampling ([`ThermalSampler.swift:364-376`](file:///Users/letanthang/learning_software/OS_Project/iStats/iStats/Sampling/ThermalSampler.swift#L364-L376)):**
    `readAppleSMCThermals()` repeats the exact same `IOServiceOpen` $\to$ read $\to$ `IOServiceClose` teardown cycle on every tick.
  - **GPU Sampling ([`GPUSampler.swift:289-298`](file:///Users/letanthang/learning_software/OS_Project/iStats/iStats/Sampling/GPUSampler.swift#L289-L298)):**
    `readSMCGPUTemperature()` duplicates another `IOServiceOpen` and `IOServiceClose` call per sample.
  - **Uncached Heavy Subsystem Queries:**
    - [`GPUSampler.swift:227`](file:///Users/letanthang/learning_software/OS_Project/iStats/iStats/Sampling/GPUSampler.swift#L227): `MTLCopyAllDevices()` is invoked every 2s, allocating and initializing Metal device wrapper objects.
    - [`GPUSampler.swift:237`](file:///Users/letanthang/learning_software/OS_Project/iStats/iStats/Sampling/GPUSampler.swift#L237): `NSScreen.screens` and `CGDisplayCopyDisplayMode` are polled every 2s to check display resolutions.
    - [`NetworkSampler.swift:187`](file:///Users/letanthang/learning_software/OS_Project/iStats/iStats/Sampling/NetworkSampler.swift#L187): `SCDynamicStoreCreate(nil, ...)` establishes a new Mach IPC connection to `configd` every tick.
    - [`NetworkSampler.swift:220`](file:///Users/letanthang/learning_software/OS_Project/iStats/iStats/Sampling/NetworkSampler.swift#L220): Queries `CWWiFiClient.shared().interface()` for RSSI, noise, and channel every 2s, keeping the Wi-Fi driver and `airportd` actively communicating.

---

### 2.3 Timer Granularity, Lack of Coalescing, and Task Churn
* **Verdict:** ✅ **CRITICAL (Worse than hypothesized)**
* **Audit Result:**
  In [`SampleScheduler.swift:362-377`](file:///Users/letanthang/learning_software/OS_Project/iStats/Sources/iStatsCore/SampleScheduler.swift#L362-L377):
  ```swift
  private func startLoop(for category: MetricCategory) {
      tasks[category] = Task { [weak self, category] in
          while !Task.isCancelled {
              ...
              let sleepNanos = UInt64(currentInterval * 1_000_000_000)
              try await Task.sleep(nanoseconds: sleepNanos)
          }
      }
  }
  ```
  1. **8 Unaligned Wakeup Loops:** There are 8 active categories (`cpu`, `memory`, `thermal`, `fan`, `gpu`, `network`, `disk`, `power`). Because each sampler takes a variable duration to complete (from 0.2ms to 4ms), their sleep cycles drift apart immediately. Instead of waking the CPU once every 2 seconds, the CPU is interrupted **8 distinct times per 2-second interval** (4 wakeups/sec). This prevents Apple Silicon cores from entering low-power idle states (C-states).
  2. **Zero Coalescing:** `Task.sleep(nanoseconds:)` allows zero leeway. The kernel timer cannot align the wakeups with other system activity.
  3. **Task Churn on Every Sample ([`SampleScheduler.swift:396-410`](file:///Users/letanthang/learning_software/OS_Project/iStats/Sources/iStatsCore/SampleScheduler.swift#L396-L410)):**
     ```swift
     withThrowingTaskGroup(of: Sendable.self) { group in
         group.addTask { try sampler.sample() }
         group.addTask { try await Task.sleep(nanoseconds: budgetNanos); throw SamplerError.timedOut }
         ...
     }
     ```
     To enforce a timeout, the scheduler allocates two tasks inside a `TaskGroup` per reading. Across 8 categories, **16 asynchronous tasks are created, scheduled, and destroyed every 2 seconds**.

---

### 2.4 Main-Thread UI Redraws & WindowServer Compositor
* **Verdict:** ✅ **REAL AND HIGH OVERHEAD**
* **Audit Result:**
  In [`MenuBarController.swift:190-229`](file:///Users/letanthang/learning_software/OS_Project/iStats/iStats/App/MenuBarController.swift#L190-L229):
  1. `coordinator.$latestCPU`, `$latestMemory`, etc. publish on the main actor independently.
  2. For every sample, `updateItems(for: category)` invokes:
     ```swift
     let result = MenuBarIconRenderer.render(config: config, coordinator: coordinator, preferences: preferences)
     button.image = result.image
     button.title = result.title
     button.toolTip = result.toolTip
     ```
  3. [`MenuBarIconRenderer.swift`](file:///Users/letanthang/learning_software/OS_Project/iStats/iStats/UI/MenuBarIconRenderer.swift) draws a **brand-new `NSImage` via CoreGraphics/CoreText on every sample tick**, even when the quantified value (e.g. CPU 5%, Memory 42%) has not changed at all.
  4. Assigning a new `NSImage` instance to `button.image` invalidates the layer in AppKit and triggers an update across Mach IPC to `WindowServer`, forcing the compositor to re-render the status bar item 30 times a minute per active icon.

---

### 2.5 Quality of Service (QoS) & Core Scheduling
* **Verdict:** ✅ **REAL**
* **Audit Result:**
  - In [`MetricsCoordinator.swift:115`](file:///Users/letanthang/learning_software/OS_Project/iStats/iStats/App/MetricsCoordinator.swift#L115):
    `MetricsCoordinator.start()` is called from `@MainActor`. The child `Task { await scheduler.start() }` inherits the main thread's priority (`.userInitiated`).
  - In [`SampleScheduler.swift:362`](file:///Users/letanthang/learning_software/OS_Project/iStats/Sources/iStatsCore/SampleScheduler.swift#L362):
    `tasks[category] = Task { ... }` specifies no priority, thereby inheriting `.userInitiated`.
  - **Hardware Impact on Apple Silicon:**
    Tasks running at `.userInitiated` are scheduled on **Performance cores (P-cores)** and prompt macOS to boost the core clock frequency. Background polling work should run with `.utility` or `.background` QoS, allowing Darwin to place them strictly on **Efficiency cores (E-cores)** at minimal clock frequency and voltage.

---

## 3. Staged Implementation Plan

To ensure stability, maintain test coverage, and measure performance gains step by step, the work is broken into four distinct stages:

```
┌─────────────────────────────────────────────────────────────┐
│ Stage 1: QoS & Scheduler Coalescing                         │
│ • Downgrade task priorities to .utility / .background       │
│ • Unify 8 drifted loops into a single batched tick          │
│ • Introduce ContinuousClock timer tolerance (15-20% leeway) │
│ • Eliminate TaskGroup timeout allocation churn              │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ Stage 2: Persistent IOKit Connections & Static Caching      │
│ • Persistent AppleSMC user client connection                │
│ • Cache Metal device, screen resolution, SCDynamicStore     │
│ • Throttled / event-driven Wi-Fi link telemetry             │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ Stage 3: UI Dirty-Checking & Compositor Optimization        │
│ • Output memoization in MenuBarController                   │
│ • Skip button.image / title reassignment when value is same │
│ • Cache rendered templates for static / discrete states     │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ Stage 4: Coordinator Batching & Memory Churn Polish         │
│ • Batch multi-category store updates before publishing      │
│ • Avoid full array copying for history queries              │
│ • Profile with powermetrics & Instruments Energy Log        │
└─────────────────────────────────────────────────────────────┘
```

---

### Stage 1: QoS & Scheduler Coalescing (P0 — Immediate Impact)
* **Goal:** Reduce CPU wakeups from ~4–8 Hz to 0.5 Hz, allow timer coalescing, and bind work to Efficiency cores.
* **Tasks:**
  1. Set explicit task priority `Task(priority: .utility)` for all background sampling routines.
  2. Refactor `SampleScheduler` to run a **synchronized single tick** for all categories sharing the same interval, rather than 8 independent looping tasks.
  3. Replace `Task.sleep(nanoseconds:)` with `ContinuousClock().sleep(until:tolerance:)` providing a 15–20% tolerance (e.g. 300ms leeway on a 2s interval).
  4. Streamline `sampleWithTimeout`: replace per-sample `withThrowingTaskGroup` creation with lightweight cooperative cancellation or timeout checking.
* **Verification:** Assert `Thread.isMainThread == false`, run test suite with scratch path, verify no regressions in error isolation.

---

### Stage 2: Persistent IOKit Connections & Static Hardware Caching (P1)
* **Goal:** Eliminate kernel user-client alloc/dealloc churn and stop querying static hardware configurations.
* **Tasks:**
  1. Create a persistent `AppleSMCClient` actor or thread-safe manager that maintains one open `io_connect_t` across `FanSampler`, `ThermalSampler`, and `GPUSampler`. Add reconnection logic if the connection is terminated or the machine wakes from sleep.
  2. Cache static GPU parameters: query `MTLCopyAllDevices()`, device name, and core count once on startup or when display configuration changes.
  3. Cache display parameters in `GPUSampler`: observe `NSApplication.didChangeScreenParametersNotification` instead of polling `NSScreen.screens` and `CGDisplayCopyDisplayMode` every 2 seconds.
  4. Cache `SCDynamicStore` in `NetworkSampler` and throttle Wi-Fi link queries (RSSI / noise) to a lower cadence (e.g., every 10–30s or on network reachability change).
* **Verification:** Run `FanSamplerTests`, `ThermalSamplerTests`, `GPUSamplerTests`, and `NetworkSamplerTests`.

---

### Stage 3: UI Dirty-Checking & Compositor Elimination (P1)
* **Goal:** Eliminate redundant WindowServer drawing and CoreGraphics image allocations when telemetry values do not change.
* **Tasks:**
  1. Add a cache / state-tracking struct inside `MenuBarController` per `config.id` storing the previous quantified value (e.g. rounded percentage, discrete unit string, and tooltip).
  2. If the newly rendered `title`, `toolTip`, and visual state match the previous update, **skip** setting `button.image = ...`, `button.title = ...`, and `button.setAccessibilityLabel(...)`.
  3. Cache commonly repeated static images (e.g. idle symbols, unavailable icons) so identical `NSImage` pointers can be reused.
* **Verification:** Run `MenuBarDisplayTests` and `MenuBarControllerInteractionTests`.

---

### Stage 4: Coordinator Batching & Memory Polish (P2)
* **Goal:** Eliminate unnecessary `@Published` broadcasts and array allocations on `@MainActor`.
* **Tasks:**
  1. In `MetricsCoordinator`, batch incoming readings from a sampling tick so `objectWillChange` fires at most once per tick instead of 8 separate times.
  2. Avoid re-copying all history arrays (`store.cpuHistory()`, `store.memoryHistory()`) on every tick when detail popovers are closed. Only fetch histories when a popover is actively displayed.
  3. Profile the app using `powermetrics` and Instruments (`Energy Log`, `Time Profiler`) to record before-and-after baseline metrics.

---

## 4. Benchmark & Validation Protocol

Before and after each stage, the following commands and checks must be run:

```bash
# 1. Package test suite
swift test --scratch-path /tmp/istats-build

# 2. Specific test targets
swift test --scratch-path /tmp/istats-build --filter SampleSchedulerTests
swift test --scratch-path /tmp/istats-build --filter MenuBarDisplayTests
swift test --scratch-path /tmp/istats-build --filter PerformancePassTests

# 3. Xcode app target build (when applicable)
xcodebuild -scheme iStats -configuration Debug build
```

**Energy Measurement Tools:**
- **Activity Monitor:** Inspect the `Energy Impact` column (target: baseline idle < 0.5 under normal 2s sampling).
- **Instruments:** Profile with `Energy Log` and `Time Profiler` templates.
- **Terminal powermetrics:**
  ```bash
  sudo powermetrics -i 2000 -n 5 --samplers cpu_power,tasks -s cpu_power
  ```
