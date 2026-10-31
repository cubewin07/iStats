# Phase 7 — Widget & Popover Redesign

**Branch:** `feature/popover-and-widget-redesign` (from `feature/popover-customization-and-preview`)
**Status:** plan only. Track status in [`docs/progress.md`](../../progress.md), not here.
**Supersedes:** parts of [ADR 0007](../../architecture/adr/0007-per-category-menu-bar-items-and-popovers.md) (widget-to-popover binding model). Needs a new **ADR 0008** (task 7.0).

---

## 0. Why this phase exists (audit summary)

What the code does today:

| Area | Today | Problem |
|------|-------|---------|
| Widgets (`MetricDisplayStyle` × category) | **43** combinations across 8 categories ([`MenuBarItemConfig.swift#L137-L160`](../../../Sources/iStatsCore/MenuBarItemConfig.swift)) | Too many near-identical shapes. Thermal alone has 8 (one text widget per sensor group). Fans have 6. Several 18 pt drawings can't be read at menu bar size (4-segment memory donut, fan tachometer needle, GPU die, power ring with an icon inside). |
| Popovers (`PopoverStyle`) | **33** styles, all in one 5,082-line file ([`CategoryDetailPopoverView.swift`](../../../iStats/UI/CategoryDetailPopoverView.swift)) | Each style is a hand-built one-off. Most are the same data in a different shape (e.g. `fanDualRPM`, `fanTachometer`, `fanBlades`, `fanBars` all show RPM per fan; `powerChargeRing` and `powerBar` both show charge %). The 5 thermal subsystem popovers are copies of one template. |
| Invented / hard-coded data | `ThermalCPUPopoverView` "TJMax 105 °C headroom", `ThermalMemoryPopoverView` "Refresh Cycle Policy 2x", `ThermalStoragePopoverView` "NAND endurance limit", `ThermalRingPopoverView` per-zone limits, `GPUDiePopoverView` "Metal Acceleration: Hardware Enabled", `GPUSummaryView` core grid that lights *N of M* cores in proportion to total load | None of these come from a sensor. They look precise but aren't. That goes against invariant 2 ("no magic values"). |
| Decorative illustrations | `CPUDie`, `GPUDie`, `MemoryStick`, `FanBlades`, `NetworkPipes`, `DiskStorageTank`, `PowerBudget`, `ThermalHeatMap` illustration views | They take up the hero spot without adding information. |
| Design system | `PopoverHeaderView` + `CollapsibleSection` exist, but the popover file repeats `Color(nsColor: .controlBackgroundColor).opacity(…)` **84** times, mixes `.opacity(0.4/0.5)`, uses 8/9/10/10.5/11/13/14/24 pt fonts, and gives each popover its own temperature colour thresholds (`tempColor` 55/75/90 vs renderer `thermalColor` 50/70/85). | No shared tokens, so nothing looks consistent. |
| Category identity | Icon and colour are defined **3×** (`PopoverHeaderView`, `DetailPopoverView`, `PreferencesComponents`) and don't agree (Power is `.green` in popovers, `.mint` in Preferences). GPU uses `display` (a monitor). Memory and Power share green. Network's in/out colours are teal/purple in the widget and green/blue in the popover. | Identity drifts between surfaces. |
| History | `MetricsStore.defaultCapacity = 60` → 1 minute at 1 s | "History" popovers have very little to show. |

Data that **is** available (from `Models.swift`) and should drive the redesign. Nothing else may be shown:

- **CPU:** total, user, system, idle, per-core[], E/P core counts (+ derived E/P usage), load avg 1/5/15, frequency Hz.
- **Memory:** total, used, free, wired, compressed, cached, app, active, inactive, swap used/total/free, pressure (normal/warning/critical).
- **Thermal:** `[SensorReading(name, °C)]`, `ThermalPressure` (nominal/fair/serious/critical). The pressure value is the OS's real throttling signal and today it is barely surfaced.
- **Fan:** per fan: name, rpm, min, max; `isFanless`.
- **GPU:** utilization, renderer %, tiler %, memoryUsed, allocated, recommendedMax, temp, power W, core count, device name, UMA flag, displays, recovery count, ray tracing, Metal family.
- **Network:** per interface: rates, totals, IPv4, type; primary interface/type, local IP, gateway, DNS, Wi‑Fi RSSI/noise/SNR/tx rate/channel/band.
- **Disk:** volumes (name, mount, total/used/free), I/O bytes/s and ops/s read & write.
- **Power:** charge, state/variant, time remaining, cycle count / design cycles, condition, design / current max capacity, draw W, adapter W + name, voltage, amperage.
- **Not available:** per-process data (top CPU/memory/network apps). See optional task 7.8.

---

## 1. Design principles (apply to every task below)

1. **One job per surface.** A widget answers "what's the value right now?" A popover answers "is it OK, why, and what can I do?" Each popover tab has a one-line purpose written at the top of its spec.
2. **Only real data.** Every number comes from a sampler. If it's missing, show `.unavailable(reason:)` styling. Never show a fallback constant.
3. **Shape follows the data.** A ring only shows something with a natural 0–100 % (load, charge, capacity). Temperatures and RPM are numbers, not rings.
4. **One palette, two roles.** *Category colour* = identity (icon chip, chart series). *Status colour* (green/yellow/orange/red from `StatusLevel`) = severity only (pill, value tint above threshold). A category colour is never used to mean severity.
5. **One threshold table.** All warn/critical cut-offs live in `iStatsCore` (`StatusThresholds`) and are unit-tested. Widgets, popovers, verdicts and alerts read from it.
6. **Fixed frame, no surprise scrolling.** Popover width is **330 pt**, content height is **≤ 480 pt** per tab. Lists cap their row count and use "Show all (n)" instead of a nested `ScrollView`.
7. **Every graph widget is identifiable.** Multiple sparklines or rings in the menu bar must be told apart: graphs and rings get an optional 3-letter vertical label (`drawVerticalCategoryText` already exists).

---

## 2. Category identity (icons & colours)

Single source: `MetricCategory.symbolName` (in `iStatsCore`) + `CategoryPalette.color(for:)` (app). Delete the 3 duplicated switch statements.

| Category | Icon today | **New icon** | Colour today | **New colour** | Reason |
|----------|-----------|--------------|--------------|----------------|--------|
| CPU | `cpu` | `cpu` (keep) | blue | **blue** | Correct already. |
| Memory | `memorychip` | `memorychip` (keep) | green | **mint** | Green is the "fine" status colour and was shared with Power. |
| GPU | `display` | **`square.3.layers.3d`** | purple | **purple** | `display` means monitor. Stacked layers suggest a render pipeline and can't be confused with CPU. Also replace `square.grid.2x2` in thermal GPU rows. |
| Temperature | `thermometer.medium` | `thermometer.medium` (keep) | orange | **orange** | Intuitive. Rule 4 keeps it from reading as "warning". |
| Fans | `fan` | `fan` (keep; confirm it exists on macOS 13, else `wind`) | cyan | **cyan** | Correct already. |
| Network | `network` | **`arrow.up.arrow.down`** | teal | **indigo** | `network` is a node graph that suggests topology. Up/down arrows suggest throughput, which is what the widget shows. Teal was too close to cyan. |
| Disk | `internaldrive` | `internaldrive` (keep) | indigo | **teal** | Indigo moved to Network. |
| Battery & Power | `bolt.fill` | **`battery.100percent.bolt`** (battery Macs) / **`powerplug.fill`** (desktop) | green / mint | **pink** | A bolt alone looks like "charging". Pink is the only free system hue that doesn't clash with status colours. *Open decision: yellow is more conventional but clashes with the "elevated" status colour.* |

**Two-channel series colours** (same in widget, popover and preview):

| Pair | Channel A | Channel B |
|------|-----------|-----------|
| Network | ↓ Download = category colour (indigo) | ↑ Upload = `.pink` at 85 % |
| Disk | Read = category colour (teal) | Write = `.orange` at 85 % |
| CPU | User = blue | System = `.red` at 70 % (stacked) |
| Memory | App / Wired / Compressed / Cached / Free = mint 100 % / 70 % / 45 % / 25 % / track | |

---

## 3. Widget catalog — keep / modify / remove / add

Legend: ✅ keep as is · ✏️ modify · ❌ remove · ➕ add. "→" = what a removed widget migrates to for existing users.

### CPU — 4 widgets (was 4)

| Widget (style) | Verdict | Spec |
|----------------|---------|------|
| CPU % (`text`) | ✅ | Two-line `CPU` / `23%`. Value turns status-coloured at ≥ `StatusThresholds.cpu.warning`. |
| User/System (`gauge`) | ✏️ rename **"Load Ring"** | Ring = total. Two segments: user (blue) and system (red 70 %). Drop the "pie" look and use a 2.6 pt stroke like every other ring. |
| Core Cluster (`bar`) | ✏️ | Per-core micro bars, **grouped E | P with a 2 pt gap**, max 16 bars (above that, show cluster averages). Same height scale as today. |
| Usage History (`sparkline`) | ✏️ | Stacked area user+system instead of a single total line. Optional `CPU` vertical label. |

### Memory — 4 widgets (was 5)

| Widget | Verdict | Spec |
|--------|---------|------|
| Used % (`text`) | ✏️ | `MEM` / `68%`. Value tint = **pressure** status, not used % (high used % with normal pressure is healthy on macOS). |
| Composition (`gauge`) | ✏️ rename **"Pressure Ring"** | Ring fill = used %, ring colour = pressure status. The 4-segment donut can't be read at 18 pt, so it goes. |
| Allocation (`bar`) | ✏️ | 3 segments only: App / Wired / Compressed (drop cached; it's reclaimable and makes the bar look fuller than it really is). |
| Used % History (`sparkline`) | ✅ | Line colour = current pressure. Add optional label. |
| Pressure (`symbol`) | ❌ → `gauge` | The 3-bar badge looks like a signal-strength icon (wrong metaphor), and the Pressure Ring now carries pressure. |

### GPU — 4 widgets (was 5)

| Widget | Verdict | Spec |
|--------|---------|------|
| GPU % (`text`) | ✅ | |
| Load Ring (`gauge`) | ✏️ | Ring colour = **category purple**, status colour only ≥ threshold. Remove the temperature-tinted ring (temperature belongs to the Temperature category). |
| Load Bar (`bar`) | ✅ | |
| Load History (`sparkline`) | ✅ | + optional label. |
| GPU Die (`symbol`) | ❌ → `gauge` | Decorative die glyph that shows the same single value as the ring. |

### Temperature — 3 widgets (was 8)

The biggest change. Merge the six "°C text" widgets into **one** widget with a **source** option.

| Widget | Verdict | Spec |
|--------|---------|------|
| **Temperature** (`text` + `source`) | ✏️ | `source ∈ {peak, cpu, gpu, memory, ssd, battery}` (battery hidden on desktops). Title row shows the source abbreviation (`TMP`, `CPU`, `GPU`, `MEM`, `SSD`, `BAT`). Several instances are allowed (one per source). Value tint uses `StatusThresholds.temperature(for: source)`. When `ThermalPressure ≥ .serious`, a 3 pt status dot is drawn top-right. |
| CPU °C / GPU °C / Memory °C / SSD °C / Battery °C (`cpuTemp`…`batteryTemp`) | ❌ → `text` + matching `source` | |
| Temp Ring (`gauge`) | ❌ → ➕ `glyph` | Mapping 30–100 °C onto a ring is arbitrary. |
| ➕ **Thermometer** (`glyph` + `source`) | ➕ | 9 pt thermometer glyph whose bulb fill uses the status colour, followed by `62°`. Narrower than the two-line text. |
| Peak History (`sparkline`) | ✅ | + optional `TMP` label. |
| `bar` (dead fallback in renderer) | ❌ | Delete the code path. |

### Fans — 5 widgets (was 6)

| Widget | Verdict | Spec |
|--------|---------|------|
| Fan % (`text`) | ✏️ **"Fan RPM"** | `FAN` / `1840`. % of max isn't what users look for. A fanless Mac shows `—` + tooltip "Passive cooling". |
| Dual RPM (`throughput`) | ✏️ | Only offered when `fans.count ≥ 2`. Lines `L 1840` / `R 1910`. |
| Tachometer (`gauge`) | ❌ → `glyph` | Needle can't be read at 18 pt. |
| Blades (`symbol`) | ❌ → `glyph` | Decorative. |
| ➕ **Fan glyph** (`glyph`) | ➕ | SF `fan` glyph (status-tinted above 80 % of max) + RPM. |
| Fan Bars (`bar`) | ✅ | One capsule per fan. |
| RPM History (`sparkline`) | ✏️ | Plot **max** fan RPM (today it plots `fans.first`). + label. |
| Category on fanless Macs | ✏️ | Hide the Fans category rail entry in Preferences behind a disabled row: "This Mac has no fans". |

### Network — 3 widgets (was 4)

| Widget | Verdict | Spec |
|--------|---------|------|
| Up / Down (`throughput`) | ✏️ | Keep the signature stacked layout. Add a **layout option** `stacked | single-line` (`↓1.2M ↑84K`) for crowded menu bars. Fixed-width digits so it doesn't jitter. |
| Duplex History (`sparkline`) | ✅ | Mirrored ↓ above / ↑ below, in the series colours from §2. |
| Activity Arrows (`symbol`) | ✅ | |
| In / Out Bars (`bar`) | ❌ → `symbol` | Bars are scaled against a decaying max, so "full" means nothing. It's a less clear copy of the arrows. |

### Disk — 5 widgets (was 5, one swapped)

| Widget | Verdict | Spec |
|--------|---------|------|
| Read / Write (`throughput`) | ✅ | Same layout options as Network. |
| I/O History (`sparkline`) | ✏️ | **Mirrored read/write** (like network) instead of a combined sum. |
| R/W LEDs (`symbol`) | ✅ | |
| Storage Ring (`gauge`) | ✏️ | Ring = boot volume used %. Status colour at ≥ 90 % / 95 %. Optional `SSD` label. |
| Storage Bar (`bar`) | ❌ → ➕ `text` | Same value as the ring. |
| ➕ **Free Space** (`text`) | ➕ | `SSD` / `412G`. Free space in bytes is more useful than a %. |

### Battery & Power — 4 widgets battery / 2 desktop (was 6 / 2)

| Widget | Verdict | Spec |
|--------|---------|------|
| Battery (`symbol`) | ✏️ | Signature battery shell. Option: % inside / % beside / none. State overlays (bolt, plug, pause, !) stay. |
| Charge + Time (`text`) | ✅ | |
| Draw / Adapter W (`throughput`) | ✅ | Desktop: draw only. |
| Wattage History (`sparkline`) | ✅ | + label. |
| Charge Ring (`gauge`) | ❌ → `symbol` | The icon inside the ring is illegible, and it duplicates the battery shell. |
| Charge Bar (`bar`) | ❌ → `symbol` | Duplicate. |

**Result:** 43 → **32** widgets. Every remaining widget shows something that no other widget in its category shows in the same way.

---

## 4. Popover model — one popover per category, with tabs

### 4.1 Model change

Today: a widget picks 1 of 33 `PopoverStyle`s, and each style is a separate view.
New: **each category has exactly one popover** with a **segmented tab bar** (2–3 tabs). The widget's popover setting chooses the **opening tab** (and, for Temperature, the **focused component**). Nothing is lost: every old style is now a tab or a focus of the new popover.

```swift
// iStatsCore
public enum PopoverTab: String, Codable, CaseIterable, Sendable {
    case overview, detail, history      // "detail" is titled per category (Cores, Pressure, Engines…)
}
public struct PopoverConfig: Codable, Hashable, Sendable {
    public var openingTab: PopoverTab            // default .overview
    public var rememberLastTab: Bool             // default true
}
// MenuBarItemConfig: replace `popoverStyle: PopoverStyle?` with `popover: PopoverConfig?`
// and add `source: MetricSource?` (Temperature only for now).
```

Legacy `PopoverStyle` raw values decode into `PopoverConfig` (table in §6). Unknown values fall back to `.overview`.

### 4.2 Shared skeleton (every category, every tab)

```
┌──────────────────────────── 330 pt ───────────────────────────┐
│ [icon chip] Title                         [● Status pill]     │  Header: 28 pt chip, 13 pt semibold title,
│             One-line status sentence                          │  11 pt secondary sentence (from verdict)
│ ┌ Overview ┬ <Detail> ┬ History ┐                             │  Segmented tabs (⌘1 ⌘2 ⌘3)
├───────────────────────────────────────────────────────────────┤
│  HERO  — 1 big number (28 pt rounded, monospaced digits)      │
│          + unit + context line ("of 16 GB", "on 10 cores")    │
│          + 60-pt sparkline with hover scrub (value + time ago)│
├───────────────────────────────────────────────────────────────┤
│  BREAKDOWN — category-specific (segmented bar / rows)         │
├───────────────────────────────────────────────────────────────┤
│  DETAILS — ≤ 6 StatRows; collapsible, state remembered        │
├───────────────────────────────────────────────────────────────┤
│ [Context action]                          [⏸]  [⚙︎]           │  Footer: 1 category action + icon-only
└───────────────────────────────────────────────────────────────┘  pause & settings (tooltips)
```

- **Background:** `NSVisualEffectView(.popover)`. Cards use `Tokens.cardFill` (`.quaternary` fill, 10 pt radius, 0.5 pt hairline). No more ad-hoc opacities.
- **States** (shared, not per popover): *Loading* = skeleton shimmer for the hero and rows (respects Reduce Motion). *Unavailable* = muted hero "—" + reason from `Availability`. *Paused* = thin banner under the header with a "Resume" link.
- **Charts:** one `TrendChart` component: area/line, optional mirrored mode, hover scrubber, min/avg/max captions, Y axis auto-scaled with `RateMath`-safe decay max.
- **Keyboard / a11y:** ⌘1–3 tabs, Esc closes, every metric has an `accessibilityLabel` with unit, VoiceOver reads the status sentence first.
- **Footer context action** (one per category): CPU/Memory/GPU → "Activity Monitor"; Network → "Network Settings"; Disk → "Storage Settings"; Power → "Battery Settings"; Temperature/Fans → none (pause and settings only). Settings URLs open via `x-apple.systempreferences:` and are not cached.

### 4.3 History tab (shared template, every category)

Purpose: *"Has this been going on for a while?"*
- Range picker `1m | 5m | 15m` (needs task 7.6; until then only `1m` is enabled).
- Big `TrendChart` (140 pt) + Min / Avg / Max / Now stat strip.
- Category series: CPU user+system stacked · Memory used % with a pressure band underlay · GPU util · Temperature peak + per-component toggle chips · Fans max RPM · Network mirrored ↓/↑ · Disk mirrored R/W · Power draw W (+ charge % on the secondary axis).

---

## 5. Per-category popover specs

Each spec lists: **purpose**, **tabs**, **what replaces what**, and **what gets deleted**.

### 5.1 CPU — "Why is my Mac busy?"

Tabs: **Overview · Cores · History**

**Overview**
- Hero: `34%` total, context "on 10 cores · 3.2 GHz" (frequency only if non-nil).
- Breakdown: stacked bar User / System / Idle with legend values.
- Clusters: two compact rows "Performance (6) 41%" and "Efficiency (4) 12%", each with a mini bar (from `performanceUsage` / `efficiencyUsage`).
- Details: Load average 1/5/15 shown as `2.1 · 1.8 · 1.6` with a load/core ratio hint ("below core count — no queueing"), Uptime.

**Cores**
- Grid of vertical per-core bars, grouped **P** then **E**, labelled by index; hover shows `Core 3 · 72%`. Fits 24 cores in 2 rows without scrolling.
- Cluster averages above each group.

Replaces: `categoryDefault`, `cpuUserSystem` (→ Overview), `cpuCluster` (→ Cores), `history`.
Deletes: `CPUPopoverView`, `CPUUserSystemPopoverView`, `CPUClusterPopoverView`, `CPUHistoryPopoverView`, `CPUSummaryView`, `CPUDieIllustrationView`.

### 5.2 Memory — "Do I need to close something?"

Tabs: **Overview · Pressure · History**

**Overview**
- Hero: `11.2 GB` used, context "of 16 GB". The status pill is **pressure**, not %.
- Breakdown: segmented bar App / Wired / Compressed / Cached / Free with legend rows (bytes + %).
- One-sentence guidance from the verdict (e.g. "Plenty of headroom — cached memory is reclaimed automatically").

**Pressure**
- Pressure band timeline (green/yellow/red strip over the window).
- Swap: used / total bar + "Swap in use" explanation if > 0.
- Compressed: bytes + share of used.
- Active / Inactive rows when available.

Replaces: `categoryDefault`, `memoryComposition`, `memoryAllocation` (→ Overview), `memoryPressure` (→ Pressure), `history`.
Deletes: 5 `Memory*PopoverView`s, `MemorySummaryView`, `MemoryStickIllustrationView`. `MemoryPressureAlertBanner` → becomes the shared status banner.

### 5.3 GPU — "Is the GPU the bottleneck?"

Tabs: **Overview · Engines · History**

**Overview**
- Hero: `58%` util, context = device name + "· 10-core".
- Breakdown rows: Renderer %, Tiler % (each with a bar, only when non-nil).
- Memory: allocated vs recommended max bar ("3.1 GB of 10.7 GB working set").
- Details: Power W, Temperature (tap → opens the Temperature popover focused on GPU).

**Engines** (renamed "Device" if renderer/tiler are nil)
- Renderer / Tiler history mini-charts.
- Displays list (from `displayDescriptions`).
- GPU recoveries (only if > 0, as a warning row — this is a real fault signal).
- Collapsible "About this GPU": Metal family, ray tracing, UMA, core count.

Replaces: `categoryDefault`, `gpuLoadRing` (→ Overview), `gpuEngine`, `gpuDie` (→ Engines), `history`.
Deletes: 5 `GPU*PopoverView`s, `GPUSummaryView` (including the **synthetic core grid**), `GPUDieIllustrationView`, the "Metal Acceleration: Hardware Enabled" row.

### 5.4 Temperature — "Is it hot or throttling, and where?"

Tabs: **Overview · Sensors · History**

**Overview**
- Hero: **thermal pressure** (`Nominal` / `Fair` / `Serious` / `Critical`) as the headline with peak °C next to it. Pressure is the OS's actual throttling state, so it goes first.
- Component rows (CPU, GPU, Memory, SSD, Battery — only those with sensors): icon · peak °C · status-coloured bar on a shared 20–110 °C scale · 60-pt sparkline. The row matching the widget's `source` starts highlighted/expanded with its sensor list.
- No invented limits: delete TJMax headroom, DRAM refresh policy, NAND endurance, charging safety zone and the per-zone ring limits.

**Sensors**
- All sensors grouped by component (collapsible), sorted hottest first, raw SMC key/name in a tooltip, "Show all (n)" after 8 per group.

Replaces: `categoryDefault`, `thermalRing` (→ Overview), `thermalCPU/GPU/Memory/Storage/Battery` (→ Overview with `focus = source`), `history`.
Deletes: 8 thermal popover views, `ThermalSummaryView`, `ThermalHeatMapIllustrationView`, `ThermalSubsystem` (logic moves to `MetricSource` + `ThermalSensorClassifier` in core, with tests).

### 5.5 Fans — "Why is it loud?"

Tabs: **Overview · History** (2 tabs)

**Overview**
- One card per fan: name, big RPM, a min→max range bar with a current-position marker, "% of max".
- Cause line: "Peak 78 °C · CPU" (pulled from Temperature, read-only) so the user sees *why* the fan is spinning.
- Mode row: "Automatic (firmware)". Read-only per ADR 0004.
- Fanless Mac: a compact "Passive cooling" card + thermal pressure row instead of an empty state.

Replaces: `categoryDefault`, `fanDualRPM`, `fanTachometer`, `fanBlades`, `fanBars` (→ Overview), `history`.
Deletes: 6 fan popover views, `FanSummaryView`, `FanBladesIllustrationView`.

### 5.6 Network — "How fast, over what, and is the link healthy?"

Tabs: **Overview · Connection · History**

**Overview**
- Hero: two numbers side by side, `↓ 4.2 MB/s` and `↑ 310 KB/s`, in the series colours.
- Mirrored duplex `TrendChart` with hover.
- Active interfaces only (rates > 0 or primary): icon (from `NetworkConnectionType.iconName`), name, ↓/↑.
- Session totals since boot ↓ / ↑.

**Connection**
- Primary: type + interface, local IPv4 (click to copy, "Copied" toast), gateway, DNS.
- Wi‑Fi block (only if `wifiDetails`): signal quality bar from SNR, RSSI / noise dBm, Tx rate, channel · band.
- No public IP lookup (it would be a network call, see ADR 0006).

Replaces: `categoryDefault`, `networkBars` (→ Overview), `networkDiagnostics` (→ Connection), `history`.
Deletes: 4 network popover views, `NetworkSummaryView`, `NetworkPipesIllustrationView`.

### 5.7 Disk — "Am I running out of space, and what's hitting the disk?"

Tabs: **Overview · Volumes · History**

**Overview**
- Hero: `412 GB free`, context "of 994 GB · Macintosh HD", capacity bar with status colour at 90 / 95 %.
- Live: Read / Write rates + IOPS in a 2×2 stat grid.
- Mirrored R/W `TrendChart`.

**Volumes**
- Every mounted volume: name, mount point, used/total bar, free bytes. Internal first, then external.

Footer action: "Storage Settings".

Replaces: `categoryDefault`, `diskStorageRing`, `diskActivityLEDs` (→ Overview), `diskStorageTanks` (→ Volumes), `history`.
Deletes: 5 disk popover views, `DiskSummaryView`, `DiskStorageTankIllustrationView`.

### 5.8 Battery & Power — "How long will it last, is the charger enough, how healthy is it?"

Tabs: **Overview · Health · History** (desktop: **Overview · History**)

**Overview**
- Hero: `82%` + state ("Charging · 38 min to full" / "On battery · 4 h 12 min left" / "Charging on hold").
- **Power flow strip**: `Adapter 67 W → System 23 W → Battery +18 W` (or `Battery −14 W` when discharging). Deficit is shown in status orange with the sentence "Draw exceeds adapter". This keeps the useful part of the old "Power Budget" as real numbers.
- Adapter name row.

**Health**
- Maximum capacity: `currentMax / design` %, with a bar.
- Cycle count vs design cycles bar.
- Condition, voltage, amperage, battery temperature (from the Temperature battery sensors).

Desktop Overview: system draw hero + `TrendChart` + adapter info.

Replaces: `categoryDefault`, `powerBudget`, `powerWattage`, `powerChargeRing`, `powerBar` (→ Overview), health parts of `powerBudget` (→ Health), `history`.
Deletes: 6 power popover views, `PowerSummaryView`, `PowerBudgetIllustrationView`.

**Popover result:** 33 styles / ~40 view structs → **8 popovers, 23 tabs**, all built from one component kit.

---

## 6. Migration tables (decode-time, tested)

**Widgets** (`MetricDisplayStyle` decode → new config, then dedupe by new `id`, keeping order of first occurrence):

| Old | New |
|-----|-----|
| `memory.symbol` | `memory.gauge` |
| `gpu.symbol` | `gpu.gauge` |
| `thermal.cpuTemp / gpuTemp / memoryTemp / storageTemp / batteryTemp` | `thermal.text` + `source: cpu / gpu / memory / ssd / battery` |
| `thermal.gauge` | `thermal.glyph` + `source: peak` |
| `fan.gauge`, `fan.symbol` | `fan.glyph` |
| `network.bar` | `network.symbol` |
| `disk.bar` | `disk.text` (free space) |
| `power.gauge`, `power.bar` | `power.symbol` |

New `id` = `category.style[.source]` (e.g. `thermal.text.cpu`).

**Popovers** (`PopoverStyle` raw value → `PopoverConfig.openingTab` [+ focus]):

| Old | New |
|-----|-----|
| `categoryDefault`, `cpuUserSystem`, `memoryComposition`, `memoryAllocation`, `gpuLoadRing`, `thermalRing`, `fan*`, `networkBars`, `diskStorageRing`, `diskActivityLEDs`, `powerBudget`, `powerWattage`, `powerChargeRing`, `powerBar` | `.overview` |
| `thermalCPU/GPU/Memory/Storage/Battery` | `.overview` + focus = matching source |
| `cpuCluster`, `memoryPressure`, `gpuEngine`, `gpuDie`, `networkDiagnostics`, `diskStorageTanks` | `.detail` |
| `history` | `.history` |

---

## 7. Code layout after the phase

```
Sources/iStatsCore/
  MetricCategory.swift          + symbolName
  MenuBarItemConfig.swift       widget catalog (32), source, PopoverConfig, migrations
  PopoverConfig.swift           PopoverTab, PopoverConfig, legacy decode
  StatusThresholds.swift        one table: cpu, memory, gpu, temperature(per source), fan, disk, battery
  ThermalSensorClassifier.swift sensor name → MetricSource (moved from ThermalSubsystem)
iStats/UI/Design/
  Tokens.swift                  spacing 4/8/12/16, radii 6/10, type scale (11/13/28), card fill
  CategoryPalette.swift         category colours, series colours
  Components/                   PopoverScaffold, PopoverHeader, TabBar, HeroMetric, TrendChart,
                                SegmentedBar, LegendRow, StatRow, StatGrid, RangeBar, StatusBanner,
                                SkeletonView, CopyableValue
iStats/UI/Popovers/
  CPUPopover.swift  MemoryPopover.swift  GPUPopover.swift  TemperaturePopover.swift
  FanPopover.swift  NetworkPopover.swift DiskPopover.swift PowerPopover.swift
  HistoryTab.swift  PopoverFactory.swift
iStats/UI/MenuBarIconRenderer.swift   remove dead paths and removed styles, add glyph/label/source
```

Delete when done: `CategoryDetailPopoverView.swift`, the 7 `*SummaryView.swift`, `MemoryPressureView.swift` (after moving the banner), the 8 `*IllustrationView.swift`, `DetailPopoverView.swift` (the fallback popover in `MenuBarController` becomes a minimal "No widgets — open Settings" view).

---

## 8. Sub-phase & Step Breakdown

Phase package files in this folder:
- [`requirements.md`](./requirements.md) — Phase 7 requirements & acceptance criteria
- [`design.md`](./design.md) — Sub-phase dependency flow, core domain additions, and component architecture
- [`tasks.md`](./tasks.md) — Master checklist and execution dependency graph
- [`report.md`](./report.md) — Phase 7 validation report template
- [`tasks/`](./tasks/) — Step-by-step implementation files (each step keeps `swift test` and `xcodebuild test` green)

**Execution order:** Sub-phase 7A (`7.0 → 7.1a`) → Sub-phase 7B (`7.1b → 7.1c → 7.1d`) → Sub-phase 7C (`7.2a → 7.2b → 7.2c → 7.2d`) ∥ Sub-phase 7D (`7.3a → 7.3b → 7.3c`) → Sub-phase 7E (`7.4a–h` in parallel) → Sub-phase 7F (`7.5`, optional `7.6`/`7.8`) → Sub-phase 7G (`7.7`).

| Sub-phase | Step | Title & Spec File | Key Steps | Definition of done |
|-----------|------|-------------------|-----------|--------------------|
| **7A — Core Domain** | **7.0** | [ADR 0008 + spec sign-off](./tasks/7.0-adr-0008-and-decisions.md) | `7.0.1–7.0.4` Resolve §10 decisions; author ADR 0008; update ADR 0007. | ADR 0008 merged; §10 decisions recorded. |
| **7A — Core Domain** | **7.1a** | [Core identity, `StatusThresholds` & `ThermalSensorClassifier`](./tasks/7.1a-core-identity-thresholds-classifier.md) | `7.1a.1` `MetricCategory.symbolName` & `shortLabel`; `7.1a.2` `MetricSource` & `ThermalSensorClassifier`; `7.1a.3` `StatusThresholds`; `7.1a.4` unit tests. | `swift test` green incl. `StatusThresholdsTests` & `ThermalSensorClassifierTests`. |
| **7B — Design System** | **7.1b** | [`Tokens`, `CategoryPalette` & switch deduplication](./tasks/7.1b-design-tokens-and-palette.md) | `7.1b.1` `Tokens.swift`; `7.1b.2` `CategoryPalette.swift`; `7.1b.3` remove 3 duplicate icon/colour switches & wire `VerdictEvaluator` to `StatusThresholds`. | `xcodebuild test` green; zero duplicate icon/colour switches in UI. |
| **7B — Design System** | **7.1c** | [Core popover & stat UI primitives](./tasks/7.1c-primitives-and-stat-components.md) | `7.1c.1` `PopoverHeader`, `TabBar`, `HeroMetric`; `7.1c.2` `SegmentedBar`, `LegendRow`, `StatRow`, `StatGrid`, `RangeBar`, `CopyableValue`; `7.1c.3` `StatusBanner`, `SkeletonView`. | All 11 components compile with Light & Dark `#Preview`s. |
| **7B — Design System** | **7.1d** | [Unified `TrendChart` component](./tasks/7.1d-trend-chart-component.md) | `7.1d.1` single/stacked/mirrored modes; `7.1d.2` `RateMath`-safe decay max; `7.1d.3` hover scrubber + `Min/Avg/Max/Now` strip; `7.1d.4` `TrendChartMath` tests. | `TrendChart` renders 60 pt & 140 pt modes with factual time captions. |
| **7C — Widgets** | **7.2a** | [Core widget catalog (43 → 32) & migration](./tasks/7.2a-core-widget-catalog-and-migration.md) | `7.2a.1` `.glyph` + 32-widget catalog; `7.2a.2` `source`, `throughputLayout`, `showLabel`, composite `id`; `7.2a.3` §6 decode migration + dedupe; `7.2a.4` tests. | `MenuBarItemConfigMigrationTests` cover every row of §6. |
| **7C — Widgets** | **7.2b** | [Renderer: CPU, Memory, GPU, Temperature](./tasks/7.2b-renderer-cpu-memory-gpu-thermal.md) | `7.2b.1` 2.6 pt ring & vertical label helpers; `7.2b.2` CPU (E\|P gap, stacked sparkline); `7.2b.3` Memory (pressure-tinted); `7.2b.4` GPU & Temperature (`source` + `glyph`). | CPU, Memory, GPU, Thermal widgets render at invariant widths. |
| **7C — Widgets** | **7.2c** | [Renderer: Fans, Network, Disk, Power](./tasks/7.2c-renderer-fan-network-disk-power.md) | `7.2c.1` Fan RPM & `glyph`; `7.2c.2` Network/Disk `stacked\|singleLine` & Disk Free Space; `7.2c.3` Power cleanup; `7.2c.4` dirty-check keys & geometry tests. | All 32 widgets pass `MenuBarItemMatrixTests` & `MenuBarGeometryInvarianceTests`. |
| **7C — Widgets** | **7.2d** | [Preferences Menu Bar Studio updates](./tasks/7.2d-preferences-widget-studio.md) | `7.2d.1` multi-source Temperature widgets; `7.2d.2` layout & 3-letter label options; `7.2d.3` fanless Mac state; `7.2d.4` Live Menu Bar Strip preview. | Studio configures all 32 widgets & options cleanly. |
| **7D — Popover Shell** | **7.3a** | [Core `PopoverTab`, `PopoverConfig` & migration](./tasks/7.3a-core-popover-config-and-migration.md) | `7.3a.1` `PopoverTab` & `PopoverConfig`; `7.3a.2` legacy `PopoverStyle` → `PopoverConfig` migration (§6); `7.3a.3` `PopoverConfigTests`. | `PopoverConfigTests` cover all 33 legacy `PopoverStyle` values. |
| **7D — Popover Shell** | **7.3b** | [`PopoverScaffold` & shared states](./tasks/7.3b-popover-scaffold-and-shared-states.md) | `7.3b.1` 330 × ≤480 pt scaffold + `⌘1`–`⌘3` tabs; `7.3b.2` shared Loading / Unavailable / Paused states; `7.3b.3` category context footer. | `PopoverScaffold` passes state & shortcut tests. |
| **7D — Popover Shell** | **7.3c** | [`PopoverFactory`, controller sizing & studio picker](./tasks/7.3c-popover-factory-controller-and-prefs.md) | `7.3c.1` `PopoverFactory`; `7.3c.2` `MenuBarController` fixed 330 pt width & animated tab height; `7.3c.3` Preferences `"Opens on"` tab picker. | Switching tabs never resizes width; studio live preview works. |
| **7E — Category Popovers** | **7.4a** | [CPU Popover (`Overview · Cores · History`)](./tasks/7.4a-cpu-popover.md) | `7.4a.1` Overview (hero, User/System/Idle, E/P clusters, load avg); `7.4a.2` 24-core P/E grid; `7.4a.3` delete legacy CPU views. | Fits ≤ 480 pt with 24 cores; legacy CPU views deleted. |
| **7E — Category Popovers** | **7.4b** | [Memory Popover (`Overview · Pressure · History`)](./tasks/7.4b-memory-popover.md) | `7.4b.1` Overview (pressure pill, 5-segment breakdown); `7.4b.2` Pressure timeline & swap; `7.4b.3` delete legacy Memory views. | Fits ≤ 480 pt; 5 legacy Memory views deleted. |
| **7E — Category Popovers** | **7.4c** | [GPU Popover (`Overview · Engines · History`)](./tasks/7.4c-gpu-popover.md) | `7.4c.1` Overview (util, Renderer/Tiler, working set); `7.4c.2` Engines/Device tab & recovery warning; `7.4c.3` delete legacy GPU views & synthetic core grid. | Fits ≤ 480 pt; synthetic core grid & 5 GPU views deleted. |
| **7E — Category Popovers** | **7.4d** | [Temperature Popover (`Overview · Sensors · History`)](./tasks/7.4d-temperature-popover.md) | `7.4d.1` Overview (`ThermalPressure` hero, component rows + `focusSource`); `7.4d.2` Sensors tab (`Show all (n)`); `7.4d.3` delete 8 Thermal views & invented limits. | Fits ≤ 480 pt with 40 sensors; zero invented limits remain. |
| **7E — Category Popovers** | **7.4e** | [Fans Popover (`Overview · History`)](./tasks/7.4e-fan-popover.md) | `7.4e.1` Overview (per-fan RPM range bar, thermal cause line, fanless card); `7.4e.2` delete 6 legacy Fan views. | Multi-fan & fanless states verified; 6 Fan views deleted. |
| **7E — Category Popovers** | **7.4f** | [Network Popover (`Overview · Connection · History`)](./tasks/7.4f-network-popover.md) | `7.4f.1` Overview (dual hero, mirrored chart, active interfaces); `7.4f.2` Connection (copyable IPv4, Wi‑Fi SNR); `7.4f.3` delete 4 legacy Network views. | No external IP calls; 4 Network views deleted. |
| **7E — Category Popovers** | **7.4g** | [Disk Popover (`Overview · Volumes · History`)](./tasks/7.4g-disk-popover.md) | `7.4g.1` Overview (free space hero, 2×2 I/O + IOPS grid, mirrored R/W chart); `7.4g.2` Volumes tab (internal first); `7.4g.3` delete 5 legacy Disk views. | Fits ≤ 480 pt with 12 volumes; 5 Disk views deleted. |
| **7E — Category Popovers** | **7.4h** | [Battery & Power Popover (`Overview · Health · History`)](./tasks/7.4h-power-popover.md) | `7.4h.1` Overview (state hero, numeric power flow strip, desktop mode); `7.4h.2` Health tab (capacity & cycles); `7.4h.3` delete 6 legacy Power views. | Battery (3-tab) & desktop (2-tab) verified; 6 Power views deleted. |
| **7F — History & Optional** | **7.5** | [Shared `HistoryTab`](./tasks/7.5-shared-history-tab.md) | `7.5.1` `HistoryTab` (`140 pt` `TrendChart` + `Min/Avg/Max/Now`); `7.5.2` per-category series & thermal filter chips; `7.5.3` series tests. | History tab works across all 8 categories. |
| **7F — History & Optional** | *7.6* | [*(Optional)* Extended `5m \| 15m` trends](./tasks/7.6-extended-in-memory-trends.md) | `7.6.1` 900-point in-memory scalar ring buffers; `7.6.2` spike-preserving downsampler; `7.6.3` range picker; `7.6.4` RAM overhead check. | `< 100 KB` memory overhead recorded in `report.md`. |
| **7F — History & Optional** | *7.8* | [*(Optional, own ADR)* Top processes sampler](./tasks/7.8-top-processes-sampler.md) | `7.8.1` ADR 0009; `7.8.2` `ProcessCPUReading` delta math; `7.8.3` `ProcessSampler`; `7.8.4` CPU/Memory Top Apps rows. | ADR 0009; `< 0.5%` CPU at 2 s; sampler tests green. |
| **7G — Final Cleanup** | **7.7** | [Cleanup, docs, benchmark & `report.md`](./tasks/7.7-cleanup-docs-and-validation.md) | `7.7.1` delete `CategoryDetailPopoverView.swift` & `DetailPopoverView.swift`; `7.7.2` §9 checklist & CPU refresh check; `7.7.3` update `design.md`, `report.md`, `progress.md`. | Build + all tests green; zero legacy popover references remain. |

---

## 9. Acceptance checklist for the whole phase

- [ ] 32 widgets, 8 popovers, 23 tabs. No two widgets in a category render the same value in the same shape.
- [ ] Every displayed number maps to a `Models.swift` field or a pure derivation with a unit test.
- [ ] One icon + one colour per category, used identically in menu bar previews, popover header and Preferences.
- [ ] All severity colours come from `StatusThresholds`.
- [ ] No nested scroll views in popovers; each tab ≤ 480 pt.
- [ ] Existing user configs migrate with no lost widgets (deduped) and no crash on unknown raw values.
- [ ] Light/dark, Reduce Motion, VoiceOver pass on every tab.
- [ ] Invariants from `AGENTS.md` §3 still hold (no main-thread OS calls, degrade to `.unavailable`).

---

## 10. Open decisions (answer before 7.0 closes)

1. **Power colour:** pink (proposed, no clash with status colours) vs yellow (more conventional, clashes with "elevated").
2. **Remember last tab** per category: on by default (proposed) or always open on the widget's configured tab?
3. **Optional 7.6 (15-min history)** and **7.8 (top processes)**: include in this phase or defer?
4. **Fans on fanless Macs:** hide the category (proposed) or show a disabled row?
