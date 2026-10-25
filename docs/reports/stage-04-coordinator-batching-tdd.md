# Technical Task Document: Stage 4 — Coordinator Batching & Memory Polish

**Branch:** `perf/energy-optimization`  
**Status:** In Progress (TDD Phase)  
**Related Documents:**  
- Audit Report: [`/docs/reports/energy-impact-and-optimization-audit.md`](/docs/reports/energy-impact-and-optimization-audit.md)  
- Stage 1 TDD: [`/docs/reports/stage-01-qos-and-coalescing-tdd.md`](/docs/reports/stage-01-qos-and-coalescing-tdd.md)  
- Stage 2 TDD: [`/docs/reports/stage-02-persistent-iokit-and-caching-tdd.md`](/docs/reports/stage-02-persistent-iokit-and-caching-tdd.md)  
- Stage 3 TDD: [`/docs/reports/stage-03-ui-dirty-checking-tdd.md`](/docs/reports/stage-03-ui-dirty-checking-tdd.md)  

---

## 1. Problem Statement

Even with QoS coalescing (Stage 1), persistent IOKit clients (Stage 2), and UI dirty checking (Stage 3), two significant memory and main-thread energy bottlenecks remain:

1. **Main-Thread Context Switch & `@Published` Churn:**
   - In `SampleScheduler`, active categories on the same cadence are sampled concurrently, but as each subtask finishes, it calls `publish(reading)`.
   - When 8 categories complete, `continuation.yield(reading)` delivers 8 separate events to `MetricsCoordinator.startListeningToStream()`.
   - This results in 8 separate `@MainActor` task resumptions within a few milliseconds.
   - Each resumption calls `store.append(reading)` on `@Published var store: MetricsStore` and updates `@Published` properties, triggering up to 32+ Combine `objectWillChange` broadcasts per sampling tick.

2. **Eager History Array Allocations:**
   - In `MenuBarIconRenderer.render`, history arrays for CPU, Memory, GPU, Thermal, Fan, Network, Disk, and Power are eagerly mapped into new `[Double]` arrays (e.g. `coordinator.cpuHistory.map { $0.value.totalUsage }`).
   - For 95% of users who configure `.text`, `.gauge`, `.bar`, or `.symbol` display styles, the `history` argument is completely ignored by the renderer.
   - This causes ~8 unneeded heap allocations and array copies every tick.

---

## 2. Architectural Design

```
             SampleScheduler Cadence Loop (Utility QoS)
                                │
                  withTaskGroup(of: MetricReading.self)
                  (Samples all categories concurrently)
                                │
                                ▼
                   Collects [MetricReading] batch
                                │
               publish(batch: [MetricReading])
                                │
           ┌────────────────────┴────────────────────┐
           ▼                                         ▼
batchStream: AsyncStream<[MetricReading]>   stream: AsyncStream<MetricReading>
(New Batch Pipeline)                        (Backward Compatibility)
           │
           ▼
MetricsCoordinator.startListeningToStream
           │
           ▼
handleReadings(_ batch: [MetricReading])  <── SINGLE @MainActor pass per tick!
           │
 ┌─────────┴─────────────────────────────────────────┐
 │ • store.append(batch)                 (1 mutation)│
 │ • Update latest samples for batch     (1 pass)    │
 │ • Update availability dictionary      (1 pass)    │
 └───────────────────────────────────────────────────┘
```

### 2.1 Scheduler Batch Pipeline (`SampleScheduler`)
- In `SampleScheduler`, refactor `startCadenceLoop(for:)` so the `withTaskGroup` returns `[MetricReading]` collected from all active category samplers in that tick.
- Introduce `batchStream: AsyncStream<[MetricReading]>` and `publish(readings: [MetricReading])`.
- Yield each reading individually to `stream: AsyncStream<MetricReading>` so existing single-reading consumers remain 100% compatible.

### 2.2 Batched Coordinator Ingestion (`MetricsCoordinator`)
- Add `public func handleReadings(_ readings: [MetricReading])`.
- Call `store.append(readings)` once for the whole batch (which `MetricsStore` already supports natively).
- Update `latestCPU`, `latestMemory`, etc. and history arrays in a single atomic pass on `@MainActor`.
- Track `batchIngestionCount` and `singleIngestionCount` for test validation and energy observability.

### 2.3 Conditional Lazy History Mapping (`MenuBarIconRenderer`)
- In `MenuBarIconRenderer.render`, only map history arrays if the configured style actually renders a sparkline or history graph:
  ```swift
  let history = (config.style == .sparkline)
      ? coordinator.cpuHistory.map { $0.value.totalUsage }
      : []
  ```
- Eliminates 8 array allocations per tick when non-sparkline styles are displayed.

---

## 3. Test-Driven Development Plan

### Test Target: `/Tests/iStatsTests/CoordinatorBatchingTests.swift`

1. **`testSchedulerYieldsBatchedReadings`**:
   - Register multiple mock samplers in `SampleScheduler`.
   - Consume from `scheduler.batchStream`.
   - Trigger a tick and verify readings arrive grouped together in a single `[MetricReading]` array.
2. **`testCoordinatorProcessesBatchInSinglePass`**:
   - Provide a batch of 4 readings (CPU, Memory, Disk, Network) to `coordinator.handleReadings(batch)`.
   - Assert all 4 latest metrics are updated concurrently.
   - Assert `batchIngestionCount` increments by 1.
3. **`testLazyHistoryMappingInMenuBarRenderer`**:
   - Verify that for non-sparkline styles (`.gauge`, `.text`, `.bar`), `MenuBarIconRenderer.render` produces identical output without requiring pre-computed history arrays.
4. **`testBackwardCompatibilityWithSingleStream`**:
   - Verify that `scheduler.stream` still yields each `MetricReading` individually for backward-compatible consumers.

---

## 4. Invariants & Guardrails
- **ADR 0002 Compliance:** Scheduler sampling remains strictly off the main thread; coordinator ingestion executes on `@MainActor`.
- **Zero Data Loss:** `batchStream` captures errors and unavailable states identically to single-reading streams.
- **Pure Domain Integrity:** `MetricsStore` ring buffer mechanics and timestamp ordering remain untouched.
