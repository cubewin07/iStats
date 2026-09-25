# Stage 1 Technical Design & TDD Plan: QoS & Scheduler Coalescing

**Branch:** `perf/energy-optimization`  
**Target:** `Sources/iStatsCore/SampleScheduler.swift`  
**Test Suite:** `Tests/iStatsCoreTests/SampleSchedulerTests.swift`, `Tests/iStatsCoreTests/SampleSchedulerCoalescingTests.swift`  
**Status:** In Progress (TDD Phase: Tests & Design First)

---

## 1. Problem Statement & Objectives

### Current Architecture Flaws
In the current implementation of [`SampleScheduler.swift`](/Sources/iStatsCore/SampleScheduler.swift):
1. **8 Unaligned Loop Tasks:** A separate `Task` is launched for every metric category:
   ```swift
   tasks[category] = Task { [weak self, category] in
       while !Task.isCancelled {
           ...
           try await Task.sleep(nanoseconds: sleepNanos)
       }
   }
   ```
   Each category takes a variable duration to execute (e.g. CPU $\approx 0.2\text{ms}$, Disk $\approx 2.5\text{ms}$, GPU $\approx 3.0\text{ms}$). Because each task sleeps for a fixed duration after finishing, the wakeups drift out of phase within seconds. The CPU is woken up up to 8 separate times every 2 seconds, destroying C-state residency.
2. **Zero Timer Tolerance:** `Task.sleep(nanoseconds:)` passes no leeway to the Darwin kernel, disabling timer coalescing.
3. **High QoS (P-Core Scheduling):** Tasks inherit `.userInitiated` priority when started from `MetricsCoordinator` on `@MainActor`, prompting the scheduler to wake Apple Silicon Performance cores at high frequencies.
4. **Task Allocation Churn:** In `sampleWithTimeout`, `withThrowingTaskGroup` allocates 2 subtasks per sample (one running `Task.sleep` for timeout), generating 16 task allocations and cancellations per 2-second interval.

### Stage 1 Goals
1. **Explicit `.utility` Priority:** Guarantee that all background sampling routines execute with `TaskPriority.utility` (or `.background`), routing them strictly to Apple Silicon Efficiency cores.
2. **Batched Tick Scheduling:** Consolidate categories sharing the same sampling interval into a single synchronized tick.
3. **ContinuousClock with Tolerance:** Replace `Task.sleep(nanoseconds:)` with `ContinuousClock.sleep(until:tolerance:)` using 15–20% leeway (e.g., 300ms on a 2s interval).
4. **Lightweight Timeout Enforcement:** Eliminate `withThrowingTaskGroup` task churn in normal execution paths while preserving full per-category timeout and error isolation.
5. **100% Backward Compatibility:** Maintain all existing public methods (`register`, `unregister`, `start`, `stop`, `setInterval`, `setEnabled`, `sampleOnce`, `sampleAll`, `stream`).

---

## 2. Technical Design

### 2.1 Unified Cadence Engine
Instead of mapping `[MetricCategory: Task]`, the scheduler maintains **Cadence Groups**:
- Most categories share `defaultInterval` (typically 2.0s).
- Categories with identical intervals are grouped into a single `CadenceGroup`.
- Each `CadenceGroup` runs **one master loop task** at `TaskPriority.utility`.
- When the cadence ticks, all enabled categories in that group are sampled concurrently using cooperative task execution.

```
Existing (8 Unaligned Loops):
Time (s) ────► 0.00   0.25   0.50   0.75   1.00   1.25   1.50   1.75   2.00
CPU Loop:      [Wake]                                                   [Wake]
Mem Loop:             [Wake]                                                   [Wake]
Disk Loop:                   [Wake]                                                   [Wake]
Net Loop:                           [Wake]
... (8 wakeups per cycle)

New (Stage 1 Unified Batched Tick):
Time (s) ────► 0.00 (± tolerance)                               2.00 (± tolerance)
Batched Tick:  [All 8 Categories Sampled on E-Cores]            [All 8 Categories Sampled]
CPU Sleep:     ════════════════════════════════════════════════► ═══════════════════════════►
               (Deep C-State sleep uninterrupted)
```

### 2.2 Clock & Tolerance Model
- Use Swift's native `ContinuousClock`.
- Define tolerance:
  $$\text{tolerance} = \text{clamp}(\text{interval} \times 0.15, \, 0.05\,\text{s}, \, 0.5\,\text{s})$$
- Target sleep:
  ```swift
  let clock = ContinuousClock()
  var nextTick = clock.now + .seconds(interval)
  while !Task.isCancelled {
      try await clock.sleep(until: nextTick, tolerance: .seconds(tolerance))
      nextTick += .seconds(interval)
      // Execute batch sample
  }
  ```
  Using `nextTick += interval` prevents timer drift over long uptimes.

### 2.3 Lightweight Timeout & Error Isolation
- In steady-state execution, a sampler runs off the main thread.
- If a sampler takes longer than `timeBudget`, the task group cancels and degrades that specific category to `.unavailable(reason: "Sample timed out after ...")`.
- Sibling samplers running concurrently within the same batched tick are isolated and deliver their results without delay.

---

## 3. Test-Driven Development (TDD) Specification

We define concrete tests to be committed and executed **before** modifying the implementation. The tests will specify:

### Test Suite: `SampleSchedulerCoalescingTests.swift`

| Test Name | Specification & Assertion | Expected Initial State |
| :--- | :--- | :---: |
| `testSamplingTasksExecuteWithUtilityPriority` | When sampling runs periodically, the executing task's `Task.currentPriority` must equal `.utility` (or `.background`), even if `scheduler.start()` was invoked from `@MainActor`. | **Fails on current main** (runs at `.userInitiated`) |
| `testBatchedSamplingTickExecutesConcurrentlyWithinLeewayWindow` | Register 4 fast samplers. In periodic mode, record timestamps of each invocation. All 4 samplers in a tick must fire within $\le 50\text{ms}$ of each other, proving they share a unified tick rather than independent drifted loops. | **Fails on current main** (independent tasks drift) |
| `testTimeoutIsolationInBatchedTick` | In a single batched tick with 1 hanging sampler (sleeps 1.0s, budget 0.1s) and 1 healthy sampler (0.01s), the healthy sampler completes immediately ($\le 0.05\text{s}$) while the slow sampler degrades to `.unavailable` without blocking the healthy reading. | Validates non-blocking invariant |
| `testContinuousClockToleranceParameter` | Verify scheduler exposes and configures sleep tolerance without crashing or throwing errors. | New capability |
| `testMixedIntervalCadenceGroups` | Category A at 0.1s, Category B at 0.2s. Over 0.4s, Category A must fire $\approx 4$ times while Category B fires $\approx 2$ times, confirming multiple cadence groups function smoothly. | Regression prevention |
| `testDirectSampleOncePreservesIsolation` | `sampleOnce(category:)` remains immediate and isolated from the periodic batch ticks. | Backward compatibility |

---

## 4. Implementation Steps (After Tests are Committed)

1. **Step 1 (Red):** Add `SampleSchedulerCoalescingTests.swift` to `Tests/iStatsCoreTests/`. Confirm new assertions properly capture the missing coalescing and priority behavior.
2. **Step 2 (Green - Priorities):** Update `SampleScheduler.swift` to explicitly use `Task(priority: .utility)` for all background tasks and detached workers.
3. **Step 3 (Green - Unified Batch Loop):** Refactor `tasks: [MetricCategory: Task]` into `cadenceTasks: [TimeInterval: Task]` (or unified loop) where categories with equal intervals run in a single batched tick.
4. **Step 4 (Green - ContinuousClock with Leeway):** Replace `Task.sleep(nanoseconds:)` with `clock.sleep(until:tolerance:)`.
5. **Step 5 (Refactor & Verify):** Run `swift test --scratch-path /tmp/istats-build` across the entire test suite, ensuring all existing and new tests pass with zero regression.
