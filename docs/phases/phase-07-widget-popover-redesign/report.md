# Phase 7 — Widget & Popover Redesign — Report

**Status:** Completed

---

## 1. What was built

Phase 7 redesigned the menu bar presentation and popovers from a fragmented collection of 43 menu bar items and 33 legacy popover styles into a cohesive, purpose-driven design system following **ADR 0008**.

### Architecture & System Deliverables

1. **ADR 0008 Sign-off (`docs/architecture/adr/0008-purpose-driven-widgets-and-tabbed-popovers.md`):**
   - Consolidated 43 sprawling menu bar widgets down to **32 high-signal widgets** across all 8 metric categories.
   - Replaced 33 disparate popover styles with **8 purpose-driven category popovers** (23 tabs total).
   - Established strict 330 pt width and ≤ 480 pt height budgets.
   - Enforced unified 4-tier semantic status severity (`StatusThresholds`).

2. **Core Domain (`iStatsCore`):**
   - Single source of category identity: `MetricCategory.symbolName`, `CategoryPalette`, and `MetricSource`.
   - Unified status thresholds: `StatusThresholds` mapping values to `.fine`, `.nominal`, `.warning`, and `.critical`.
   - `ThermalSensorClassifier`: Heuristic classification of Apple Silicon and Intel thermal keys into CPU, GPU, Memory, Storage, Battery, and Ambient.
   - `Downsampler`: Pure Swift spike-preserving bucket downsampler (downsampling 900 samples to ≤ 120 display points).
   - Extended In-Memory Scalar Trends: `MetricsStore` maintains 900-sample in-memory scalar ring buffers for 11 chartable series across categories (`cpuUser`, `cpuSystem`, `memoryUsedPercent`, `gpuUtilization`, `thermalPeakCelsius`, `fanMaxRPM`, `networkInBytesPerSec`, `networkOutBytesPerSec`, `diskReadBytesPerSec`, `diskWriteBytesPerSec`, `powerWatts`).
   - `PopoverConfig` & `PopoverTab`: Decoupled popover tab configuration with backward-compatible legacy decoder.
   - Catalog: `MenuBarItemConfig.allAvailableItems` (32 widgets total).

3. **Design System Tokens & Primitives (`iStats/UI/Design/`):**
   - `Tokens`: Standard typography, colors, padding, corner radii, and animations.
   - `PopoverHeader`: 3-tier hierarchy (category badge, dad sentence, semantic status badge).
   - `TabBar`: Polished capsule tab switcher for category tabs.
   - Primitives: `HeroMetric`, `SegmentedBar`, `LegendRow`, `StatRow`, `StatGrid`, `RangeBar`, `CopyableValue`, `StatusBanner`, and `SkeletonView`.
   - `TrendChart`: Unified canvas chart supporting single line/area, stacked (user/system), and mirrored (in/out) modes with hover scrubber and decay max.

4. **Menu Bar Widgets & Preferences Studio:**
   - `MenuBarIconRenderer`: Overhauled to render all 32 widgets with pixel-perfect Retina crispness and dynamic dark/light mode tinting.
   - Multi-source Temperature widgets (`cpu`, `gpu`, `soc`, `battery`, `ssd`, `peak`).
   - Preferences Menu Bar Studio (`PreferencesMenuBarPane`): Visual widget gallery, drag-and-drop reordering, temperature source selection, layout/label toggles, and fanless Mac detection.

5. **8 Purpose-Driven Category Popovers (`iStats/UI/Popovers/`):**
   - `CPUPopover`: Overview (User/System, Cores, Uptime, Load) · Cores (E/P topology, per-core bars) · History (`1m | 5m | 15m`)
   - `MemoryPopover`: Overview (Hero, Donut composition, Pressure, Swap) · Details (Wired, Compressed, App, Cached breakdown) · History (`1m | 5m | 15m`)
   - `GPUPopover`: Overview (Hero, Renderer/Tiler, Memory, Temp) · Details (Engine, Displays, Cores) · History (`1m | 5m | 15m`)
   - `TemperaturePopover`: Overview (Peak hero, Thermal pressure, Top sensors) · Sensors (Categorized by CPU, GPU, Memory, Storage, Battery, Ambient) · History (`1m | 5m | 15m`)
   - `FanPopover`: Overview (Max RPM hero, Individual fan gauges/RPM, Min/Max) · Details (Fan profiles, Tachometer stats) · History (`1m | 5m | 15m`)
   - `NetworkPopover`: Overview (Bandwidth hero, Mirrored In/Out sparkline, Totals) · Connection (Local IP, Gateway, DNS, Wi-Fi SSID/RSSI/Noise/TxRate) · History (`1m | 5m | 15m`)
   - `DiskPopover`: Overview (Total storage, Read/Write rates, Volumes summary) · Volumes (Individual mounted volumes, Mount paths, Free/Total bars) · History (`1m | 5m | 15m`)
   - `PowerPopover`: Overview (Battery % hero, Charging state, Time remaining, Power draw) · Health (Condition, Cycle count, Current max capacity, Design capacity, Adapter wattage)
   - Fallback `NoWidgetsActiveView` card displayed when 0 widgets are active.

6. **Complete Legacy Code Deletion:**
   - Removed 20 legacy files totaling over 8,000 lines of obsolete SwiftUI code:
     - `CategoryDetailPopoverView.swift` (5,082 lines)
     - `DetailPopoverView.swift`
     - 7 summary views (`CPUSummaryView`, `MemoryPressureView`, `GPUSummaryView`, `ThermalSummaryView`, `FanSummaryView`, `NetworkSummaryView`, `DiskSummaryView`, `PowerSummaryView`)
     - 8 illustration views (`CPUDieIllustrationView`, `MemoryStickIllustrationView`, `GPUDieIllustrationView`, `ThermalHeatMapIllustrationView`, `FanBladesIllustrationView`, `NetworkPipesIllustrationView`, `DiskStorageTankIllustrationView`, `PowerBudgetIllustrationView`)
     - `RollingGraphView.swift` & `PopoverCommonComponents.swift`
   - Cleaned up Xcode project structure (`iStats.xcodeproj/project.pbxproj`).

---

## 2. Migration & Test Verification

All tests across both suites execute cleanly with zero failures.

| Test Suite | Command | Tests Run | Result | Duration |
|------------|---------|-----------|--------|----------|
| `iStatsCoreTests` | `swift test --scratch-path /tmp/istats-build` | 176 | **Passed** | 1.45s |
| `iStatsTests` (App) | `xcodebuild test -scheme iStatsApp -destination 'platform=macOS'` | 296 | **Passed** | 5.88s |
| **Combined** | — | **472** | **All Passed** | **~7.3s** |

### Key Test Coverage Highlights
- `PopoverConfigTests`: Validates legacy string decoding and default opening tab mappings.
- `MetricsStoreTests`: Validates 900-sample retention across 11 scalar series, time filtering, spike-preserving downsampling, and RAM ceiling (≤ 160 KB).
- `MenuBarItemMatrixTests`: Validates 32-widget catalog, dimension bounds, and icon rendering.
- `SwiftUIViewsTests`: Validates `PopoverFactory` across all 32 widgets and 8 popovers under cold-start and live-data states.
- `DetailViewGraphsTests`: Validates chart rendering, stats strips, relative time formatting, and popover views.
- `SandboxDegradationTests`: Validates graceful degradation to `.unavailable(reason:)` across all categories.

---

## 3. UI & Performance Validation

1. **Popover Height & Width Budget:**
   - Width is strictly fixed to **330 pt** across all 8 popovers (`Tokens.popoverWidth`).
   - Every tab fits comfortably within the **≤ 480 pt** vertical budget without unbounded expansion.

2. **Memory Footprint:**
   - `MemoryLayout<ScalarPoint>.stride` is 16 bytes (8-byte `Date` timestamp + 8-byte `Double` scalar).
   - 11 series × 900 points × 16 bytes = **158,400 bytes (~154 KB)** total raw in-memory history overhead.
   - Zero telemetry is persisted to disk, fully satisfying **ADR 0006**.

3. **Background Sampling Threading Invariant:**
   - All OS calls (`sysctl`, Mach, IOKit, SMC, `IOPowerSources`, `statfs`, `getifaddrs`) remain strictly on background scheduler queues (**ADR 0002**).
   - UI views are strictly `@MainActor` consumers of `@Published` readings from `MetricsCoordinator`.

4. **Accessibility & Design Polish:**
   - Full support for macOS Light and Dark mode using system material vibrancy (`PopoverVisualEffectView`).
   - High-contrast text using standard system design typography.
   - Smooth tab switching and animated progress bars.
