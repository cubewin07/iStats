# Phase 8 — Design Specification ("Instrument" design language)

Visual and interaction spec for the premium panels. All values are proposals until ADR 0009 (Task 8.0) signs them off. After that this file is the source of truth for implementors.

---

## 1. Panel anatomy (shared by all 8 panels)

```
 ╭──────────────────────────────────────────────╮  ← 16 pt continuous corners, glass/vibrant surface, soft shadow
 │  ◉ CPU                      ◐  ▦  ◷     ⋯  ⌖ │  ① Eyebrow row (28 pt): glyph + name · page switcher · more · pin
 │                                              │
 │  34%                        Peak 92% · 3m ago│  ② Glance: display numeral (44 pt) + insight (trailing, 11 pt)
 │  Moderate load · 10 cores · 3.2 GHz          │     headline (13 pt, secondary)
 │░░░▁▂▃▅▇▆▅▃▂▁▂▃▄▅▆▇█▇▆▅▄▃▂▁▂▃▄▅▆▅▄▃▂▂▃▄▅▆●░░░│  ③ Living chart, full-bleed (0 pt side inset), 72 pt, fades into the surface
 │──────────────────────────────────────────────│     (no divider drawn; the chart's lower fade is the separation)
 │ ⚠ 3 P-cores pinned at 100% for 2m            │  ④ Status ribbon, shown only at ≥ .elevated
 │                                              │
 │  ┌ SIGNATURE INSTRUMENT ──────────────────┐  │  ⑤ Page body: signature instrument + 1–2 modules
 │  │                                        │  │
 │  └────────────────────────────────────────┘  │
 │  PROCESSES                                   │
 │  ◼ Xcode                         38%  ▁▃▅▇   │
 │  ◼ Safari                        12%  ▁▁▂▂   │
 ╰──────────────────────────────────────────────╯   (no footer)
```

| Zone | Rules |
|------|-------|
| ① Eyebrow | Category glyph (SF Symbol, 12 pt, category tint) + name in `Type.eyebrow`. Page switcher: 3 icon buttons (22×22) with a sliding glass "puck" (`matchedGeometryEffect`). `⋯` opens a menu (context app, Pause/Resume, Preferences…). Pin `⌖` toggles detach. |
| ② Glance | Display numeral uses `LiveNumber` (rolling digits). Unit sits on the baseline in `Type.unit`. The insight is trailing and top-aligned, `Type.caption`, tertiary, one line. The headline comes from `InsightEngine` / verdict. |
| ③ Chart | `LiveChart` (Task 8.4), full panel width, 72 pt, gradient fill in the category tint fading to transparent, live head dot with a 2 s pulse ring. Hover shows the crosshair lens and replaces the insight text with the hovered sample ("2m 14s ago · 71%"). |
| ④ Ribbon | Appears and disappears with a height spring. Tint = status colour at 12 % fill, icon + one sentence. Never shown at `.fine`. |
| ⑤ Body | 20 pt vertical rhythm between modules. Modules are borderless (§4). Section eyebrows replace dividers. |

**Size.** Width 352 pt. Height fits content (animated). Max 560 pt. The Overview page must fit without scrolling; Detail/History may use one inner `ScrollView` with soft top/bottom edge fades.

**Pages.** `PopoverTab.overview` → *Now* (◐), `.detail` → category detail (▦, per-category SF Symbol), `.history` → *History* (◷). Page transitions slide 24 pt in the direction of travel plus a crossfade, spring `Motion.snappy`. The glance header ① ② ③ stays fixed; only ⑤ changes. On History, ③ morphs into the larger history chart.

---

## 2. Surface & depth

| Token | macOS 26+ | macOS 13–15 fallback |
|-------|-----------|----------------------|
| `Surface.panel` | `glassEffect(.regular, in: .rect(cornerRadius: 16))` inside a `GlassEffectContainer` | `NSVisualEffectView` material `.popover`, `.behindWindow`, `state = .active`, layer `cornerRadius 16`, `cornerCurve .continuous`, `masksToBounds` |
| `Surface.module` | `Color.primary.opacity(0.045)` (light) / `0.06` (dark), radius 12, **no stroke** | same |
| `Surface.moduleHover` | +0.03 opacity, 120 ms ease | same |
| `Surface.inset` (meter tracks) | `Color.primary.opacity(0.07)` | same |
| `Surface.edgeHighlight` | none (glass provides it) | 0.5 pt top-inner highlight, `white.opacity(0.08)` in dark only |
| Window shadow | system `hasShadow = true` plus `NSShadow` blur 24, y −8, 18 % black | same |

Rules: **never** stroke a module. **Never** nest modules. Dividers are allowed only inside dense lists (0.5 pt, `separatorColor` at 50 %, inset 16 pt leading).

---

## 3. Colour

### 3.1 Principles
- Category colours are **tuned P3 values in an asset catalog** (`iStats/Assets.xcassets/Palette/*.colorset`) with Any/Dark and High-Contrast variants. No more stock `.blue`.
- Every category has `tint` (strokes, numerals on hover, glyph) and `tintDeep` (gradient end, ~12° hue shift, darker). Chart fills use `tint → tintDeep → clear`.
- Status colours are used **only** for state, never for identity: `elevated` amber, `warning` orange, `critical` red. **There is no green "fine" UI.**
- Text on colour must reach WCAG 4.5:1. Checked by a unit test (`PaletteContrastTests`) against the asset hex values.

### 3.2 Proposed palette (Light / Dark)

| Category | `tint` light | `tint` dark | `tintDeep` dark | Note |
|----------|-------------|-------------|-----------------|------|
| CPU | `#2E6BF0` | `#5C8DFF` | `#3B5BDB` | electric blue |
| Memory | `#0FA37F` | `#33D1A6` | `#13997A` | jade |
| GPU | `#7C4DEB` | `#A386FF` | `#6E4BD8` | violet |
| Thermal | `#E2611E` | `#FF8A4C` | `#E0532A` | ember; the sensor spectrum uses its own ramp (§3.3) |
| Fan | `#0C93B8` | `#3CC6E8` | `#1A8FB5` | glacier |
| Network | `#4F55E6` | `#8389FF` | `#5A5FE0` | indigo |
| Disk | `#D23D72` | `#FF6E9C` | `#D8467A` | rose (was teal; too close to Fan/Memory) |
| Power | `#2AA44F` | `#4ADE80` | `#22A355` | green = battery convention. Safe because "fine" no longer uses green |

| Series | Channel A | Channel B |
|--------|-----------|-----------|
| CPU | User = CPU tint | System = `#FF6B5E` (coral-red) |
| Network | ↓ Download = Network tint | ↑ Upload = `#FF8A5B` (coral) |
| Disk | Read = Disk tint | Write = `#F5B83D` (amber) |
| Memory | App = tint · Wired = `tintDeep` · Compressed = tint 55 % · Cached = tint 28 % · Free = `Surface.inset` | |

| Status | Light | Dark |
|--------|-------|------|
| elevated | `#C98A00` | `#FFC53D` |
| warning | `#E06A00` | `#FF9F45` |
| critical | `#D92D2D` | `#FF5C5C` |

### 3.3 Semantic ramps
- **Thermal spectrum:** 30 °C `#4FB3FF` → 55 °C `#7ED957` → 75 °C `#FFC53D` → 90 °C `#FF8A4C` → 105 °C `#FF4D4D`. Used by the thermal spectrum bar and per-sensor dots.
- **Pressure arc (memory):** a three-zone arc in green-free neutrals: normal = tint, warn = elevated amber, critical = critical red.

---

## 4. Typography

All SF Pro (system). **Numerals always use `.monospacedDigit()`.** SF Mono is only for identifiers (IP, MAC, BSD names).

| Token | Spec | Use |
|-------|------|-----|
| `Type.display` | 44 pt, `.regular`, tracking −1.2, monospacedDigit | glance numeral |
| `Type.unit` | 17 pt, `.medium`, secondary, baseline-aligned | `%`, `GB`, `°C` |
| `Type.displayCompact` | 30 pt, `.regular`, tracking −0.6 | secondary hero values (Network ↑, Power watts) |
| `Type.title` | 15 pt `.semibold` | detached window title, empty states |
| `Type.headline` | 13 pt `.regular`, secondary | glance headline |
| `Type.body` | 12 pt `.regular` | row labels |
| `Type.value` | 12 pt `.medium`, monospacedDigit, primary | row values |
| `Type.caption` | 11 pt `.regular`, tertiary | insight, hints |
| `Type.eyebrow` | 10 pt `.semibold`, UPPERCASE, tracking +0.8, tertiary | section labels, category name |
| `Type.micro` | 9 pt `.medium`, monospacedDigit, quaternary | chart axis ticks, core indices |
| `Type.mono` | 11 pt SF Mono `.regular` | IP, MAC, interface names |

Hierarchy rule: at most **3 type sizes** visible in a module.

---

## 5. Motion

| Token | Curve | Use |
|-------|-------|-----|
| `Motion.snappy` | `.spring(response: 0.32, dampingFraction: 0.86)` | page switch, puck, pin, ribbon |
| `Motion.smooth` | `.spring(response: 0.5, dampingFraction: 0.92)` | panel height resize, module appear |
| `Motion.value` | `.easeOut(duration: min(0.6, interval × 0.6))` | meters, bars, gauges, numerals |
| `Motion.glide` | linear over `refreshInterval` | chart scroll between samples |
| `Motion.panelIn` | scale 0.96 → 1, opacity 0 → 1, y −6 → 0, `snappy`, anchor = status item | open |
| `Motion.panelOut` | opacity → 0, scale → 0.98, 120 ms easeIn | close |
| `Motion.pulse` | head-dot ring 1 → 2.2×, opacity 0.5 → 0, 2 s, repeats | live head |

**Reduce Motion:** no glide (step updates with `Motion.value` crossfade), no pulse, no fan spin, no power-flow particles (static arrows with wattage), crossfade-only page change, panel opens with opacity only.
**Low Power Mode / paused sampling:** same as Reduce Motion, plus the chart freezes.

---

## 6. Per-category blueprints (Overview = *Now*, Detail, History)

Every number below maps to an existing `Models.swift` field or a tested pure derivation. Unavailable fields hide their row (they never show 0).

### 6.1 CPU — signature: **Core Map**
- **Glance:** `totalUsage` % · headline e.g. "Moderate load · 10 cores · 3.2 GHz" (frequency only if `frequencyHz != nil`) · chart = stacked User/System.
- **Now:** *Core Map*: one row per cluster (`P` then `E`). Each core is a 10 pt-wide capsule bar, 36 pt tall, filled from the bottom with the tint, height eased by `Motion.value`. The cluster label and average sit leading (`P · 62%`). Hover shows "Core 4 · 81%" in the eyebrow slot. Below it: a *Load* row with three values `1m 5m 15m` and a micro dot-plot against a dashed "core count" reference line. Then *Processes* (8.9) top 5.
- **Detail (▦ Cores):** larger grid, each core gets a 60-sample in-memory micro-sparkline (new `CoreHistory` ring, memory only), plus a User/System/Idle split meter, then uptime.
- **History:** shared (8.10), stacked user/system.

### 6.2 Memory — signature: **Pressure Arc + Composition Capsule**
- **Glance:** `used` formatted ("11.2 GB") with "of 16 GB" in the unit slot · headline from pressure ("Pressure normal · 2.1 GB compressed") · chart = used %.
- **Now:** 200° *Pressure Arc* (gauge, 120 pt) with zones and a needle eased by `Motion.value`. Centre label = pressure level word. Trailing column: Swap used (only if `swapUsed > 0`), Compressed, Wired. Then the *Composition Capsule*: one 12 pt capsule split into App/Wired/Compressed/Cached/Free. Hovering a segment raises it 2 pt and shows "Wired · 3.4 GB · 21%". Then *Processes* (by footprint, 8.9).
- **Detail (▦ Pressure):** pressure history band chart (pressure level as coloured bands under the used % line), page-ins/outs if available, swap detail.

### 6.3 GPU — signature: **Engine Rings**
- **Glance:** utilization % · headline with device name · chart = utilization.
- **Now:** concentric rings (Device / Renderer / Tiler when engine data exists, else a single ring) with tracked labels; GPU memory in use as a meter; recovery count shown only when > 0, in the status ribbon.
- **Detail (▦ Engines / Device):** per-engine meters + device facts (name, cores if exposed).

### 6.4 Temperature — signature: **Thermal Spectrum**
- **Glance:** peak °C · headline "Warm · CPU 71°, GPU 64°" · chart = peak temperature.
- **Now:** *Spectrum bar*: a 10 pt capsule with the thermal ramp (§3.3) from 30 to 110 °C. Each classifier group (`ThermalSensorClassifier`: CPU, GPU, SoC, Memory, SSD, Battery) is a labelled marker dot placed at its max; markers that collide stack vertically. Below it: the group list (name, max value, tiny min-max range bar). The thermal pressure chip only shows when not nominal.
- **Detail (▦ Sensors):** every sensor, grouped, sorted by temperature, with a search-free collapse per group (disclosure) and copy on click.

### 6.5 Fans — signature: **Turbine**
- **Glance:** RPM (max across fans) · headline "Quiet · 1,250 rpm" · chart = RPM.
- **Now:** per fan, a 64 pt *Turbine* glyph (custom 5-blade path) rotating at `rpm/maxRPM` (capped visual speed; Reduce Motion = static) beside an arc dial from `minRPM` to `maxRPM` with the current needle. Read-only per ADR 0004.
- **Fanless:** a polished empty state: large `wind` symbol in Surface.inset, "Fanless by design", sub-copy "This Mac cools passively. See Temperature for heat." with a button that opens the Temperature panel.
- **Detail:** none (2 pages: Now, History), same as Phase 7.

### 6.6 Network — signature: **Mirrored Waveform + Link Card**
- **Glance:** two `displayCompact` tickers side by side: ↓ download (Network tint) and ↑ upload (coral). The chart is a mirrored waveform (download above the axis, upload below), full-bleed.
- **Now:** *Link card*: Wi-Fi signal as 4 animated bars from `signalPercent`, SSID, band · channel, `qualityRating` word; or an Ethernet glyph + interface. Then rows: Local IP, Gateway, DNS. Values are copyable (click → value morphs to "Copied" with a checkmark for 1.2 s). Then session totals ↓/↑.
- **Detail (▦ Connection):** all interfaces list (active first) with per-interface micro rates; Wi-Fi SNR/noise/tx rate.

### 6.7 Disk — signature: **Storage Bar + I/O Waveform**
- **Glance:** boot volume free ("214 GB free") · headline "of 494 GB · 57% used" · chart = mirrored read/write throughput.
- **Now:** *Storage bar*: a 14 pt capsule like System Settings → Storage (used = Disk tint gradient, free = inset), with tick labels. Then live Read/Write rows with IOPS as secondary text.
- **Detail (▦ Volumes):** each mounted volume as a mini storage bar + mount point (mono) + free/total; external volumes get a "Show in Finder" hover action.

### 6.8 Power — signature: **Power Flow** (battery Macs) / **Draw Gauge** (desktop)
- **Glance:** charge % (battery Macs) or system watts (desktop) · headline "Charging · full in 42 m" / "On battery · 4 h 10 m left" · chart = charge % or watts.
- **Now (battery):** a *Battery glyph* hero (88×40 custom shape) filled to `charge` with the Power tint; when charging, a slow liquid shimmer runs across the fill (Reduce Motion: static + bolt). Then *Power Flow*: three nodes `Adapter (adapterWatts)` → `Mac (powerDrawWatts)` → `Battery (±W)`, joined by paths with particles whose speed is proportional to watts. Node values are real fields; the battery net comes from tested `PowerFlowMath` using voltage × amperage when available, otherwise the battery edge is hidden. The `onHold` / `powerDeficit` variants recolour the edges and post a ribbon.
- **Detail (▦ Health):** health ring (`healthPercentage`), cycles `cycleCount / designCycleCount` meter, condition, design vs max capacity (mAh), adapter name.
- **Desktop:** Overview = draw gauge + adapter; no Health page (2 pages).

### 6.9 History page (all categories, Task 8.10)
Range control `1m · 5m · 15m` as a glass segmented control under the eyebrow. Large chart (140 pt) with y-axis ticks (`Type.micro`), a peak marker (▲ + value), an avg dashed line, a "now" head, and the crosshair lens. A stats strip (Min · Avg · Max · Now) uses `LiveNumber`. Dual-series categories get a legend toggle to isolate a channel.

---

## 7. States

| State | Rendering |
|-------|-----------|
| Loading (no first sample) | Glance header shows a ghost numeral `––` in quaternary and a flat chart baseline drawing in. **No shimmer skeletons.** The body fades in with `Motion.smooth` when data arrives. |
| Unavailable (category) | Glance numeral `—`, headline = reason (one line), the body shows an inset module with an SF Symbol + reason + a "Learn more" link to the relevant doc. No status ribbon. |
| Unavailable (single field) | Row hidden. If a signature instrument loses its input, it renders its empty variant (e.g. a single GPU ring with a "No engine data" caption). |
| Paused | The chart freezes and desaturates to 40 %. A ribbon (elevated) reads "Sampling paused" with a **Resume** button. The numeral shows the last value in secondary. |
| Low Power auto-pause | Same as Paused, with the copy "Paused for Low Power Mode". |
| Detached (pinned) | Panel becomes a movable floating window, the pin icon is filled, the eyebrow gets a close button, and it can be resized in height only. |

---

## 8. Interaction details

- **Hover:** rows tint with `Surface.moduleHover`. Charts show the crosshair lens: a vertical 1 pt line plus a value bubble that follows the pointer and snaps to samples, with `NSHapticFeedbackManager.defaultPerformer.perform(.alignment)` when it snaps onto the series peak.
- **Copy:** any value with the `copyable` modifier copies on click. `⌘C` copies the hovered value.
- **Keyboard:** `⌘1–3` pages, `←/→` previous/next page, `Esc` closes (or un-pins), `⌘,` Preferences, `⌘P` pin toggle, `Space` pause/resume.
- **Menu tracking:** when a panel is open and the pointer enters another iStats status item, swap panels with no close/open animation (crossfade 80 ms).
- **Cursor:** no `NSCursor.push/pop` on hover (the current `PopoverFooter` pattern can unbalance the cursor stack). Use `.pointerStyle` on 15+ only, otherwise the default cursor.

