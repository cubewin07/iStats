# ADR 0009 — "Instrument" Design Language and Glass Panels

**Status:** Accepted / Implemented (Phase 8)  
**Supersedes:** ADR 0008 popover presentation layer (`iStats/UI/Popovers/` and `iStats/UI/Design/`).  
**Preserves:** ADR 0008 data model (`PopoverTab`, `PopoverConfig`, `MetricVerdict` thresholds, `TrendChartMath`, `Downsampler`, 900-sample in-memory scalar history), multi-`NSStatusItem` lifecycle (ADR 0007), background sampling (ADR 0002), and zero telemetry disk persistence (ADR 0006).

---

## Context

Phase 7 delivered a unified catalog of 32 purpose-driven widgets, tabbed category popovers, and an in-memory scalar history buffer. However, an architectural and visual audit revealed that the presentation layer suffered from structural monotony and generic styling:

1. **Monolithic Layout Formula:** Every category popover adhered to an identical vertical stack (`PopoverHeader` → `TabBar` → `Divider` → `HeroMetric` + small thumbnail `TrendChart` → `SegmentedBar` → `LegendRow`s → `Divider` → `StatRow`s → `Divider` → `PopoverFooter`). CPU looked structurally identical to Disk and Battery.
2. **Stock SwiftUI Styling:** Reliance on default system colors (`.blue`, `.mint`, `.purple`), linear opacity ramps (`100/70/45/25%`), hairline-bordered card containers, and stroked tab pills gave the UI an "assembled template" feel rather than that of a custom-engineered macOS tool.
3. **Status Pill Overuse:** Displaying a status pill on every popover—including a green "Fine" badge when conditions were healthy—created visual clutter. Healthy instruments should remain calm and unobtrusive.
4. **Constrained Visual Hierarchy:** The 52 pt boxed thumbnail chart underemphasized the most compelling aspect of system monitoring: the live temporal trace. Typography hovered mostly around 11 pt with rounded bold numerals, lacking clear typographic rhythm.
5. **Static Presentation:** Telemetry values and meters jumped between samples without organic easing or rolling numeric transitions.
6. **Chrome Overhead & Clipping:** Standard AppKit `NSPopover` introduced fixed arrow chrome, clipped dynamic content at 480 pt, precluded seamless menu-style pointer tracking between adjacent menu bar icons, and could not be pinned or detached into floating utility monitors.
7. **Footer Waste:** A recurring footer with an Activity Monitor shortcut, pause toggle, and gear button consumed 32 pt of vertical space on every panel without contextual necessity.

---

## Decision

We adopt the **"Instrument" design language** and transition from `NSPopover` to a custom borderless **Glass Panel** host (`NSPanel`).

### 1. Panel Geometry and Layout (D1, D2, D8)
- **Dimensions:** Fixed width of **352 pt** (16 pt outer margins / gutters providing a **320 pt** content grid).
- **Height:** Dynamic content-fitting height animated via `Motion.smooth` up to a maximum of **560 pt**.
- **Scrolling Policy:** The *Overview* (*Now*) page never scrolls. The *Detail* and *History* pages are permitted a single inner `ScrollView` with soft top/bottom gradient mask fades when content exceeds 560 pt.
- **Footer Removal:** The recurring footer is eliminated across all 8 panels. Secondary actions (Activity Monitor launch, sampling pause/resume, preferences) move to a discreet `⋯` menu in the header and standard keyboard shortcuts.

### 2. Multi-Page Structure & Identity (D3)
- Retain the proven 3-page model from ADR 0008 (`PopoverTab.overview` → *Now* ◐, `.detail` → *Detail* ▦, `.history` → *History* ◷).
- Replace the pill tab bar with a compact 22×22 pt icon page switcher in the eyebrow row featuring a sliding glass puck (`matchedGeometryEffect`).
- Header eyebrow and glance summary remain pinned; only the panel body transitions with a 24 pt directional slide and crossfade (`Motion.snappy`).

### 3. Tuned P3 Asset Palette (D4)
- Retire stock system colors and programmatic opacity cascades.
- Introduce tuned Display P3 asset catalog colors with Light, Dark, and High-Contrast variants:
  - **CPU:** Electric Blue (`#2E6BF0` light / `#5C8DFF` dark / `#3B5BDB` deep)
  - **Memory:** Jade (`#0FA37F` light / `#33D1A6` dark / `#13997A` deep)
  - **GPU:** Violet (`#7C4DEB` light / `#A386FF` dark / `#6E4BD8` deep)
  - **Thermal:** Ember (`#E2611E` light / `#FF8A4C` dark / `#E0532A` deep)
  - **Fan:** Glacier (`#0C93B8` light / `#3CC6E8` dark / `#1A8FB5` deep)
  - **Network:** Indigo (`#4F55E6` light / `#8389FF` dark / `#5A5FE0` deep)
  - **Disk:** Rose (`#D23D72` light / `#FF6E9C` dark / `#D8467A` deep; distinct from glacier/jade)
  - **Power:** Green (`#2AA44F` light / `#4ADE80` dark / `#22A355` deep; battery convention)
- Strict severity color isolation: Amber (`.elevated`), Orange (`.warning`), Red (`.critical`). **No green "fine" badge or ribbon is rendered.** All text-on-color combinations must satisfy WCAG AA (4.5:1).

### 4. Custom Borderless Glass Panel Host (D5, D6)
- Replace `NSPopover` with a specialized `NSPanel` subclass (`styleMask: [.borderless, .nonactivatingPanel]`) overriding `canBecomeKey = true`.
- **Surface Material:**
  - **macOS 26+:** Native SwiftUI `glassEffect(.regular, in: .rect(cornerRadius: 16))` wrapped in `GlassEffectContainer` / `NSGlassEffectView`.
  - **macOS 13–15:** Seamless fallback to `NSVisualEffectView(material: .popover, blendingMode: .behindWindow, state: .active)` with 16 pt continuous corner mask and subtle top-inner edge highlight.
- **Pin & Detach:** Users can toggle the pin button (`⌖` or `⌘P`) to detach any panel into a movable, floating utility window (`NSWindow.Level.floating`).
- **Menu-Style Pointer Tracking:** When a panel is open, hovering over another iStats status item swaps the panel content instantaneously with an 80 ms crossfade, mirroring system menu bar behavior.

### 5. Signature Instruments per Category
Each category receives a distinct signature visual:
- **CPU:** Core Map (P/E cluster capsule bars with load distribution).
- **Memory:** 200° Pressure Arc gauge + App/Wired/Compressed/Cached/Free Composition Capsule.
- **GPU:** Multi-engine concentric rings (Device / Renderer / Tiler).
- **Thermal:** 30–110 °C Spectrum Bar with colliding sensor group markers.
- **Fans:** Rotating 5-blade turbine glyph + RPM arc dial (with dedicated passive cooling state for fanless Macs).
- **Network:** Mirrored download/upload waveform + copyable connection link card.
- **Disk:** System Storage bar + mirrored I/O throughput waveform.
- **Power:** Live Power Flow nodes (`Adapter` → `Mac` → `Battery`) scaled by wattage (battery) / System Draw Gauge (desktop).

### 6. Living Chart & Motion System
- **The Trace is the Hero:** A full-bleed (0 pt margin) 72 pt live chart sits directly below the glance numeral, fading smoothly into the background.
- **Live Head & Crosshair Lens:** Pulsing current sample head with scrubbable inspection lens; haptic tick (`NSHapticFeedbackManager.perform(.alignment)`) on peak samples.
- **Rolling Numerals:** Tabular numbers roll vertically on value updates via `contentTransition(.numericText())` on macOS 14+ (graceful crossfade on macOS 13).
- **Respect for System Accessibility:** Full compliance with Reduce Motion and Low Power Mode (disabling gliding chart animations, turbine rotations, and live pulses).

### 7. Process Telemetry (D7)
- Integrate a lightweight, background `libproc` sampler to show top 5 consumer applications with icons for CPU and Memory.
- Strict security adherence (ADR 0004/0005): Displays only processes accessible without privilege elevation under the label "Your apps". GPU and Network process attribution remain deferred unless a non-elevated OS API is identified.

---

## Consequences

- **Aesthetic and Functional Elevation:** Each category is immediately recognizable by its signature layout and motion, eliminating the generic "dashboard" look while respecting macOS human interface principles.
- **Side-by-Side Coexistence:** Implementation proceeds cleanly under `iStats/UI/Instrument/` and `iStats/UI/Panels/`. Existing Phase 7 views remain untouched until final deprecation and deletion in Task 8.12.
- **Zero Disruption to Persistence:** Underlying preferences (`PopoverConfig`, `PopoverTab`) remain identical; no configuration migration is required.
- **Performance Discipline:** Animation timers execute strictly when panels are visible and cease when panels close or under Low Power Mode.

---

## Alternatives Considered and Rejected

1. **Retain `NSPopover` and Restyle Subviews:**  
   *Rejected.* `NSPopover` enforces window-level chrome, mandatory arrows, arbitrary content clipping, and rigid window level behaviors that prohibit menu-style status item hover switching, seamless pin/detach floating windows, and customized corner glass radii.
2. **Single Continuous Scrolling Page:**  
   *Rejected.* Merging overview, diagnostic details, and 15-minute history into a single scrolling view destroys at-a-glance legibility, requires constant scrolling for routine checks, and breaks established keyboard flows (`⌘1–3`).
3. **Third-Party Charting Frameworks:**  
   *Rejected.* Third-party libraries introduce binary bloat, lack seamless integration with custom SwiftUI Canvas renderers, cannot achieve our required energy budget, and do not support spike-preserving downsampling or custom haptic scrub lenses.

---

## Appendix: API Spike Verification (macOS SDK Spike)

The API spike for Task 8.0 was compiled and verified against the macOS SDK with the following findings:

| API | Availability | Status on SDK | Signature & Integration Notes |
|-----|--------------|---------------|-------------------------------|
| `View.glassEffect(_:in:)` | macOS 26.0+ | **Available** | `nonisolated public func glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape()) -> some View`<br>Also AppKit `NSGlassEffectView` (`style: .regular/.clear`, `cornerRadius: CGFloat`, `tintColor: NSColor?`, `effectIsInteractive: Bool`). |
| `GlassEffectContainer` | macOS 26.0+ | **Available** | `public struct GlassEffectContainer<Content: View>: View`<br>`init(spacing: CGFloat? = nil, content: () -> Content)`.<br>Also AppKit `NSGlassEffectContainerView` (`spacing: CGFloat`). |
| `contentTransition(.numericText)` | macOS 14.0+ | **Available** | `ContentTransition.numericText(value: Double)` & `ContentTransition.numericText(countsDown: Bool = false)`. |
| `symbolEffect(...)` | macOS 14.0+ | **Available** | Discrete and indefinite symbol effects (e.g. `.symbolEffect(.bounce, value: trigger)`). |
| `sensoryFeedback(...)` | macOS 14.0+ | **Available** | `View.sensoryFeedback(_:trigger:)` for discrete user interactions; paired with `NSHapticFeedbackManager` for crosshair scrub snaps. |
| `pointerStyle(...)` | macOS 15.0+ | **Available** | `View.pointerStyle(_ style: PointerStyle?)`. Provides `.link`, `.grabIdle`, `.columnResize`, etc., avoiding unbalancing `NSCursor` push/pop stacks. |
| `NSPanel` (`borderless`, `nonactivating`) Key Window in `LSUIElement` | macOS 13.0+ | **Verified** | Custom `NSPanel` overriding `canBecomeKey = true` successfully receives key status, `keyDown` (Esc), and `performKeyEquivalent` (`⌘1–3`) without bringing the accessory app forward. |

