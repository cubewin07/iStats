# Phase 1 — Report

Phase 1 delivered the complete native application foundation, AppKit/SwiftUI menu bar shell, background concurrency and scheduling engine (`SampleScheduler`), in-memory rolling history store (`MetricsStore`), and persisted settings shell (`PreferencesStore` + `PreferencesView`).

---

## What was built

### 1. Application Scaffolding & Menu Bar Shell (Tasks 1.1, 1.2)
- **Xcode Project & App Target:** Created `iStats.xcodeproj` configured for macOS 13+, Swift 6, non-sandboxed (ADR 0005), linking the local `iStatsCore` SPM package.
- **Agent Lifecycle & Dock Icon Management:** Configured `LSUIElement = true` in `Info.plist` for background agent operation without a persistent Dock icon. Created `DockIconManager` (`@MainActor`) to dynamically toggle `NSApplication.ActivationPolicy` between `.accessory` and `.regular` at runtime based on user preference.
- **Menu Bar Status Item (`MenuBarController`):** `@MainActor` controller managing `NSStatusItem` in the system status bar with template SF Symbol icons (automatic light/dark mode adaptation) and an `NSPopover` with `.transient` dismissal behavior.
- **Detail Popover Shell (`DetailPopoverView`):** SwiftUI view presenting system status header, metric placeholders, quick action buttons, and navigation to the preferences window.

### 2. Core Domain Protocols & Value Models (Task 1.3)
- **Availability Model:** `enum Availability: Equatable, Codable, Sendable` (`.available`, `.unavailable(reason:)`) guaranteeing graceful degradation without crashes (ADR 0002).
- **Generic Sample Wrapper:** `struct Sample<T>: Equatable, Codable, Sendable` wrapping metric values with timestamps and availability status.
- **Metric Categories:** `enum MetricCategory: String, CaseIterable, Identifiable, Codable, Sendable` covering `.cpu`, `.memory`, `.thermal`, `.fan`, `.gpu`, `.network`, `.disk`, `.power`.
- **Sampler Abstraction:** `protocol Sampler: Sendable` with typed associated `Output`, and `enum SamplerError: Error, Equatable`.
- **Domain Value Types:** Full set of `Codable, Sendable, Equatable` models across all categories: `CPUSample`, `MemorySample`, `MemoryPressure`, `SensorReading`, `ThermalSample`, `ThermalPressure`, `FanReading`, `FanSample`, `InterfaceThroughput`, `NetworkSample`, `VolumeCapacity`, `DiskIO`, `DiskSample`, `BatteryState`, `PowerSample`, `GPUSample`.

### 3. Background Sampling Engine (Task 1.4)
- **`actor SampleScheduler`:** Background Swift actor coordinating metric sampling tasks strictly off the main thread (ADR 0002, Requirement 12.1).
- **Error & Timeout Isolation:** Each sampler execution is isolated using `withThrowingTaskGroup` racing against a configurable `timeBudget` (default: 2.0s). Sampler throws or timeouts yield `.unavailable(category:reason:)` without affecting or blocking concurrent samplers (Requirement 12.3).
- **Dynamic Interval Adjustment:** Per-category interval configuration with instantaneous task cancellation and timer restart when the user adjusts refresh intervals (Requirement 12.4).
- **Stream & Callback Delivery:** Asynchronous multi-consumer `AsyncStream<MetricReading>` along with `@MainActor` callbacks for direct UI view model publishing.

### 4. In-Memory Rolling History Store (Task 1.5)
- **`struct MetricsStore`:** Pure in-memory history store (ADR 0006, Requirement 10.2) holding rolling buffers of `MetricReading` across all 8 metric categories.
- **Ring Buffer Eviction:** Backed by `RingBuffer<MetricReading>` per category with FIFO ordering (oldest samples evicted once capacity is reached).
- **Typed Extractors & Filtered Histories:** Ergonomic query APIs (`latestCPU()`, `cpuHistory()`, `latestMemory()`, `memoryHistory()`, etc.) for seamless chart and sparkline consumption in future phases.

### 5. Preferences Shell & Persistence (Task 1.6)
- **`PreferencesStore`:** Thread-safe `ObservableObject` backed by `UserDefaults` with enforced clamping for sampling refresh intervals: `[minRefreshInterval (0.5s), maxRefreshInterval (60.0s)]` with default `2.0s` (Requirements 11.2, 11.4).
- **Settings Window (`PreferencesView` + `PreferencesWindowController`):** Multi-tab SwiftUI preferences view (`General`, `Categories`, `Units`, `About`) with sliders, interval presets, unit formatters (`TemperatureUnit`, `NetworkUnit`, `ByteUnitStandard`), Dock icon toggling, and `@MainActor` window presentation handling activation in `LSUIElement` mode.

---

## What was learned

### 1. AppKit Lifecycle, Menu Bar Dynamics & `LSUIElement`
- **Agent Activation:** Apps configured with `LSUIElement = true` operate as menu bar agents without a Dock icon. However, standard AppKit window management differs: secondary windows (like Preferences) will not automatically acquire focus unless `NSApp.activate(ignoringOtherApps: true)` is invoked before `orderFrontRegardless()` / `makeKeyAndOrderFront()`.
- **Menu Bar Item Sizing & Popover Anchoring:** Anchoring an `NSPopover` to `statusItem.button?.bounds` requires handling transient window dismissal and positioning relative to dynamic macOS menu bar screens. Using `NSPopover.Behavior.transient` provides native macOS popover UX out of the box.

### 2. Swift 6 Concurrency & Actor Isolation
- **Pure Actors for Background Work:** Modeling `SampleScheduler` as a Swift `actor` guarantees race-free state management for registered samplers, active background tasks, and timing intervals without manual locks.
- **Thread Boundaries & Kernel Isolation:** System calls (`sysctl`, Mach, IOKit) must never execute on `@MainActor`. The scheduler spawns background `Task` loops, streaming immutable `Sendable` `MetricReading` structs over `AsyncStream` to `@MainActor` view models.
- **Timeout Racing with Task Groups:** Using `withThrowingTaskGroup` to race sampler execution against `Task.sleep` guarantees that stalled or slow hardware reads (e.g. unresponsive SMC or disk drives) timeout deterministically without hanging the scheduling loop.

### 3. SwiftPM vs Xcode Project Integration
- **Separation of Concerns:** `iStatsCore` remains a pure, modular, platform-agnostic Swift package focused strictly on domain logic, math, models, scheduling, and in-memory storage.
- **Xcode Target:** `iStats.xcodeproj` manages app packaging, bundle identifier, `Info.plist`, code signing, entitlements, and AppKit presentation controllers, directly consuming `iStatsCore` as a local package dependency.

---

## Validation evidence

| Area | Verification Method | Result | Evidence |
|------|---------------------|--------|----------|
| **App Build** | `xcodebuild -scheme iStats -configuration Debug build` | **Pass** | Build succeeded; binary produced in DerivedData |
| **App Launch & LSUIElement** | `plutil -p .../Info.plist` & manual run | **Pass** | `LSUIElement = true` verified; launches as menu bar agent |
| **Status Item & Popover** | `MenuBarController` + `DetailPopoverView` | **Pass** | Status item installed in menu bar, opens detail popover on click |
| **Off-Main-Thread Sampling** | `SampleSchedulerTests.testSamplingRunsOffMainThread` | **Pass** | `Thread.isMainThread == false` explicitly asserted during sample execution |
| **Error & Timeout Isolation** | `SampleSchedulerTests.testErrorIsolation` & `testTimeoutIsolation` | **Pass** | Throws and hanging samplers produce `.unavailable` without affecting other samplers |
| **Dynamic Interval Adjustment** | `SampleSchedulerTests.testDynamicIntervalAdjustment` | **Pass** | Interval updates immediately cancel running timer and adjust task cadence |
| **Rolling History Eviction** | `MetricsStoreTests.testAppendAtCapacityEvictsOldest` & FIFO order | **Pass** | Oldest samples evicted first; history maintains strictly chronological order |
| **Preferences & Clamping** | `PreferencesStoreTests.testRefreshIntervalClamping` | **Pass** | Values < 0.5s clamped to 0.5s; values > 60.0s clamped to 60.0s |
| **Full Unit Test Suite** | `swift test --scratch-path /tmp/istats-build` | **Pass** | **75 passed / 0 failed** across 10 test suites |

---

## Surprises / gotchas

1. **Accessory App Window Ordering:** Secondary windows in `LSUIElement` apps can remain hidden behind other application windows unless `NSApp.activate(ignoringOtherApps: true)` is explicitly called when presenting the window.
2. **SwiftPM Disk I/O Lock on macOS:** SwiftPM command-line builds on certain macOS setups encounter SQLite build database locks when using default `.build`; using `--scratch-path /tmp/istats-build` completely eliminates the issue.
3. **Swift 6 Sendable Strictness:** All data models passed through the scheduler and stored in `MetricsStore` must strictly adhere to `Sendable`. Using immutable structs and value-typed enums ensures compile-time data race safety.

---

## Carried forward to Phase 2 (CPU & Memory)

- **Phase 2 Implementation:** Wire real Mach kernel calls (`host_processor_info`, `processor_cpu_load_info`, `host_statistics64`) into concrete `CPUSampler` and `MemorySampler`.
- **Graphing in Detail View:** Feed rolling historical data from `MetricsStore.cpuHistory()` and `MetricsStore.memoryHistory()` into SwiftUI line graphs and sparklines inside `DetailPopoverView`.
- **Metric Validation:** Validate CPU percentage and memory metrics against macOS `top` / Activity Monitor reference baselines.

---

## Links

- **ADRs touched / validated:**
  - [ADR 0001](../../architecture/adr/0001-language-and-ui-stack.md) (Swift 6 + AppKit/SwiftUI)
  - [ADR 0002](../../architecture/adr/0002-threading-and-scheduling-model.md) (Actor-based background scheduler)
  - [ADR 0005](../../architecture/adr/0005-sandbox-and-entitlements.md) (Non-sandboxed v1)
  - [ADR 0006](../../architecture/adr/0006-telemetry-privacy-no-persistence.md) (In-memory ring buffers only)
- **Handoff Summaries:**
  - [`01-1.1-summary.md`](../../handoffs/01-1.1-summary.md) — App target + `LSUIElement`
  - [`01-1.2-summary.md`](../../handoffs/01-1.2-summary.md) — Status item and detail popover
  - [`01-1.3-summary.md`](../../handoffs/01-1.3-summary.md) — Core protocols and value types
  - [`01-1.4-summary.md`](../../handoffs/01-1.4-summary.md) — `SampleScheduler`
  - [`01-1.5-summary.md`](../../handoffs/01-1.5-summary.md) — `MetricsStore` ring buffer
  - [`01-1.6-summary.md`](../../handoffs/01-1.6-summary.md) — Preferences shell
- **Status update:** `docs/progress.md`.
