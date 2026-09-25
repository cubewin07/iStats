# Technical Task Document: Stage 3 — UI Dirty-Checking & Compositor Elimination

**Branch:** `perf/energy-optimization`  
**Status:** In Progress (TDD Phase)  
**Related Documents:**  
- Audit Report: [`/docs/reports/energy-impact-and-optimization-audit.md`](/docs/reports/energy-impact-and-optimization-audit.md)  
- Stage 1 TDD: [`/docs/reports/stage-01-qos-and-coalescing-tdd.md`](/docs/reports/stage-01-qos-and-coalescing-tdd.md)  
- Stage 2 TDD: [`/docs/reports/stage-02-persistent-iokit-and-caching-tdd.md`](/docs/reports/stage-02-persistent-iokit-and-caching-tdd.md)  

---

## 1. Problem Statement

In macOS, `NSStatusItem` is backed by a dedicated window managed by `WindowServer`. Every time a property on `NSStatusBarButton` is assigned (such as `button.image = ...` or `button.title = ...`), AppKit invalidates the cell layout (`needsLayout = true`), marks the view dirty (`needsDisplay = true`), and requests a compositing transaction from `WindowServer`.

In the current implementation:
1. Every 2-second sampling tick (and on every telemetry event across CPU, Memory, GPU, Thermal, Fans, Network, Disk, Power), `MenuBarController.updateStatusItem(config:)` unconditionally reassigns:
   - `button.image = result.image`
   - `button.title = result.title`
   - `button.toolTip = result.toolTip`
   - `button.setAccessibilityLabel(result.accessibilityLabel)`
   - `button.imagePosition = ...`
2. Even when telemetry has not changed (e.g., an idle system with stable 3% CPU usage, or constant memory pressure, or inactive disk/network), `MenuBarIconRenderer` executes CoreGraphics closures, allocates brand new `NSImage` instances, renders CoreText typography into fresh bitmap contexts, and hands new image pointers to AppKit.
3. This forces continuous WindowServer wakeups, unnecessary GPU compositing passes, and heap allocations every 2 seconds, which directly inflates the macOS **Energy Impact** metric even when the app is completely idle.

---

## 2. Architectural Design

```
                     Sampling Telemetry / Coordinator Event
                                       │
                                       ▼
                         MenuBarIconRenderer.render
                                       │
           ┌───────────────────────────┴───────────────────────────┐
           ▼                                                       ▼
   Discrete / Quantized                            Sparkline / History
       Image Cache                                     Fresh Render
(NSCache<NSString, NSImage>)                                       │
           │                                                       │
           └───────────────────────────┬───────────────────────────┘
                                       │
                                       ▼
                       RenderResult(image, title, tip, visualKey)
                                       │
                                       ▼
                        MenuBarController.updateStatusItem
                                       │
                                       ▼
                       Dirty-Check vs previousRenderState
                                       │
                 ┌─────────────────────┴─────────────────────┐
                 │                                           │
          [State Unchanged]                           [State Changed]
                 │                                           │
                 ▼                                           ▼
       Skip AppKit Mutations!                      Update ONLY changed fields
     dirtyCheckBypassCount += 1                     buttonMutationCount += 1
(0 WindowServer redraws, 0 C-state wake)            Store new previousRenderState
```

### 2.1 Visual Caching & Quantization (`MenuBarIconRenderer`)
- Maintain an `NSCache<NSString, NSImage>` for rendered bitmap templates and discrete visual states:
  - `stackedText`: Caches invariant two-line stacked typography (e.g. `"CPU 42%"` or `"MEM 50%"`). With integer percentages, there are at most ~101 entries per category.
  - `drawMemoryPressureBadge`: Caches the 3 discrete states (`.normal`, `.warning`, `.critical`).
  - `drawNetworkActivityArrows`: Caches the 4 discrete arrow states (in/out active/idle).
  - `drawDiskActivityLeds`: Caches the 4 discrete LED states (read/write active/idle).
  - `drawCPUSymbol` / `drawCPUGauge`: Quantizes floating percentages to nearest integer.
- Include an optional `visualKey: String?` in `RenderResult` describing the visual signature of the output.
- Reusing identical `NSImage` instances allows instant pointer equality (`===`) checks in `MenuBarController`.

### 2.2 Dirty-Checking Engine (`MenuBarController`)
- Introduce an internal state tracker:
  ```swift
  struct ItemRenderState: Equatable {
      let title: String
      let toolTip: String
      let accessibilityLabel: String
      let imagePosition: NSControl.ImagePosition
      let imageRef: ObjectIdentifier?
      let visualKey: String?
  }
  ```
- Before touching `NSStatusBarButton`, compare `newState` against `previousRenderStates[config.id]`:
  - Image is unchanged if `previous.imageRef == newState.imageRef` (same pointer or both nil) OR (`previous.visualKey != nil && previous.visualKey == newState.visualKey`).
  - If image, title, tooltip, accessibility label, and image position are all unchanged, **return immediately**.
  - If any property changed, only mutate the specific properties that differ.
- Telemetry instrumentation:
  - `buttonMutationCount`: Tracks real AppKit DOM modifications.
  - `dirtyCheckBypassCount`: Tracks bypassed redundant updates.

---

## 3. Test-Driven Development Plan

### Test Target: `/Tests/iStatsTests/MenuBarDirtyCheckingTests.swift`

1. **`testIdenticalTelemetrySkipsButtonMutations`**:
   - Configure a CPU item.
   - Send initial sample (e.g., totalUsage: 25.0). Initial render occurs (`buttonMutationCount == 1`).
   - Send identical sample (totalUsage: 25.0).
   - Assert `buttonMutationCount` remains 1 and `dirtyCheckBypassCount == 1`.
2. **`testDifferentTelemetryTriggersMutation`**:
   - Send sample A (25.0%), then sample B (50.0%).
   - Assert `buttonMutationCount == 2`.
3. **`testTextOnlyModeSkipsImageAssignment`**:
   - For a text-only item config, verify `button.image` is nil and `imagePosition == .noImage`.
   - Repeated text updates with same string result in 0 mutations.
4. **`testDiscreteStatesReuseSameImagePointer`**:
   - Render `drawMemoryPressureBadge(pressure: .normal)` twice.
   - Assert `image1 === image2` (identical memory address).
5. **`testStackedTextReusesSameImagePointer`**:
   - Render `drawCategoryStackedText(title: "CPU", value: "42%")` twice.
   - Assert `image1 === image2`.
6. **`testStatusItemRemovalCleansUpState`**:
   - Add item, render, verify state entry exists.
   - Remove item via `syncStatusItems()`, verify state dictionary removes entry.

---

## 4. Invariants & Guardrails
- **ADR 0002 Compliance:** All rendering occurs on `@MainActor` without any synchronous kernel / Mach / IOKit calls.
- **Zero Visual Regression:** Quantization is constrained to perceptual limits (<= 1% rounding where micro-gauges have fewer than 100 screen pixels).
- **Template Compatibility:** All cached template images maintain `image.isTemplate = true` so macOS automatically adapts to light/dark menu bar modes and changing desktop wallpaper tints.
- **Automatic Cache Eviction:** `NSCache` automatically evicts images if the operating system issues memory pressure warnings.
