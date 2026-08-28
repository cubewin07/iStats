# Popover and Menu Bar UI Audit

**Scope:** source-code review only. No screenshots, runtime observation, or visual comparison build was used for this report. Findings describe the layout and behavior implied by the Swift/AppKit source; final pixel-level judgments still need an on-device review at the end.

**Target:** an iStat Menus-like monitor: compact, stable menu-bar instruments; one clearly prioritized reading per popover; dense secondary detail; and no misleading state when telemetry is missing.

## Executive assessment

The project already has the right product split: configurable per-category status items, a dedicated popover per category, fixed-width popover shells, native transient popovers, live histories, and metric-specific detail rather than one generic dashboard. That is a far stronger foundation than treating the menu bar as a single text label.

The largest visible weakness is not the visual vocabulary; it is **unstable geometry and ambiguous state**:

1. Menu items are explicitly variable-width and many renderers size themselves from live strings or core count. That is the direct cause of the menu-bar jumping reported by the user.
2. Dedicated popovers have no scroll/height boundary. Thermal, disk, network, and fan detail can grow without a practical screen-bound limit.
3. Every graph calls itself `60s`, but storage is 60 samples while the user-selectable interval is `0.5...60` seconds (default `2`). The actual duration is 30 seconds to 60 minutes, and normally two minutes.
4. The source preserves unavailable reasons in the domain layer but discards them before presentation. Several widgets then draw a quiet zero-like or even plausible value rather than an unavailable state.

Fix those four issues before adding more decoration. They will make the app feel much closer to a deliberate monitoring tool immediately.

---

## What is already great

### Product architecture and interaction model

- **The per-category model is right for this product.** A click on a CPU, network, or disk item routes to a dedicated category popover rather than a long, unrelated dashboard. `MenuBarController` creates a category-specific `NSHostingController` and anchors it to the clicked button ([`iStats/App/MenuBarController.swift:280-290`](../../iStats/App/MenuBarController.swift#L280-L290)). This follows the intent of ADR 0007 and is substantially closer to iStat Menus than a single all-metrics sheet.
- **The fallback avoids orphaning the user.** If all widgets are disabled, a persistent iStats status item remains and opens the universal popover/settings path ([`MenuBarController.swift:44-72`](../../iStats/App/MenuBarController.swift#L44-L72)). That is a thoughtful failure mode.
- **Native popover behavior is used.** The popover is `.transient` ([`MenuBarController.swift:32-35`](../../iStats/App/MenuBarController.swift#L32-L35)), so outside clicks dismiss it in the expected macOS manner.
- **Telemetry updates are scoped.** Each publisher updates only widgets in the changed category ([`MenuBarController.swift:122-163`](../../iStats/App/MenuBarController.swift#L122-L163)), not every item on every sample. This is a good baseline for UI responsiveness.
- **The core keeps finite rolling history in memory.** `MetricsStore` uses a 60-sample ring buffer per category ([`Sources/iStatsCore/MetricsStore.swift:10-39`](../../Sources/iStatsCore/MetricsStore.swift#L10-L39)), which is appropriate for a lightweight monitor and respects the project’s no-persistence requirement.

### Visual system foundations

- **The popover has a stable width.** Both the universal and category popovers use `330` points ([`DetailPopoverView.swift:258`](../../iStats/UI/DetailPopoverView.swift#L258), [`CategoryDetailPopoverView.swift:131`](../../iStats/UI/CategoryDetailPopoverView.swift#L131)). This is the correct instinct: monitor panels should not reflow horizontally as numbers change.
- **There is a coherent card grammar.** Cards consistently use modest corner radii, subtle control-background fills, hairline borders, a large primary metric, graph, and secondary metric grid. See CPU ([`CPUSummaryView.swift:20-131`](../../iStats/UI/CPUSummaryView.swift#L20-L131)) and memory ([`MemoryPressureView.swift:116-251`](../../iStats/UI/MemoryPressureView.swift#L116-L251)). The hierarchy is easy to infer from source.
- **Color is generally semantic rather than random.** CPU usage, memory pressure, thermal pressure, disk fullness, battery charge, and fan speed all map to warning states. The UI normally repeats color with text/badges, which is much better than color-only signaling.
- **Monochrome template menu-bar graphics are a sound choice.** Renderer images set `isTemplate = true` throughout, allowing macOS to tint them correctly in light/dark menu bars. That restrained treatment is more native than putting multicolor dashboard art in the menu bar.
- **Metric-specific mini-instruments are more appropriate than one shared icon.** The code differentiates CPU user/system ring and per-core bars, duplex network graph, disk R/W indicators, and battery body ([`MenuBarIconRenderer.swift:88-410`](../../iStats/UI/MenuBarIconRenderer.swift#L88-L410)). The intent is strong and materially better than generic SF Symbols.

---

## Highest-priority improvements

| Priority | Finding | Why it matters | Source evidence |
|---|---|---|---|
| P0 | Live menu-bar content changes the status-item width. | It shifts adjacent menu extras and makes the whole bar look unstable. | Items are created with `.variableLength` and receive newly sized `image`/`title` values every update. [`MenuBarController.swift:56,84,183-202`](../../iStats/App/MenuBarController.swift#L56) |
| P0 | Dedicated popovers have unbounded body height. | A category with many sensors/interfaces/volumes can become taller than a usable menu-bar popover. | `CategoryDetailPopoverView` has no `ScrollView` or max height, while its children render arbitrary arrays. [`CategoryDetailPopoverView.swift:47-131`](../../iStats/UI/CategoryDetailPopoverView.swift#L47-L131) |
| P1 | “60s” graph labels are false at nearly every refresh setting. | Monitors must be trustworthy; incorrect time windows undermine the presentation. | 60 samples are retained, while refresh is `0.5...60s`, default `2s`. [`MetricsStore.swift:10`](../../Sources/iStatsCore/MetricsStore.swift#L10), [`PreferencesStore.swift:11-17`](../../Sources/iStatsCore/PreferencesStore.swift#L11-L17) |
| P1 | Unavailable telemetry is flattened into `nil`/zero-looking presentation. | A calm empty chart is materially different from “sensor denied” or “not supported.” | Core preserves unavailable reasons, but typed extractors cannot return the `.unavailable` enum case. [`Availability.swift:7-20`](../../Sources/iStatsCore/Availability.swift#L7-L20), [`MetricsStore.swift:140-183`](../../Sources/iStatsCore/MetricsStore.swift#L140-L183) |
| P1 | Several card sections default expanded. | Long details compete with the primary reading and amplify the height issue. | Thermal sensors, disk volumes, network interfaces, and power health start as `true`. [`ThermalSummaryView.swift:12`](../../iStats/UI/ThermalSummaryView.swift#L12), [`DiskSummaryView.swift:11`](../../iStats/UI/DiskSummaryView.swift#L11), [`NetworkSummaryView.swift:12`](../../iStats/UI/NetworkSummaryView.swift#L12), [`PowerSummaryView.swift:11`](../../iStats/UI/PowerSummaryView.swift#L11) |

### P0 — Stabilize every menu-bar item

This is the exact source-level cause of the user’s width issue.

`MenuBarController` creates each item with `NSStatusItem.variableLength` ([`MenuBarController.swift:84`](../../iStats/App/MenuBarController.swift#L84)). On each update it replaces the button image and title ([`MenuBarController.swift:183-202`](../../iStats/App/MenuBarController.swift#L183-L202)). AppKit therefore recomputes the item width from the current content.

The renderer makes this especially visible:

- Single-line text grows at digit boundaries: `CPU 9%` to `CPU 100%`, RAM and temperature strings do the same ([`MenuBarIconRenderer.swift:110-112,157-159,225-227`](../../iStats/UI/MenuBarIconRenderer.swift#L110-L112)).
- Network and disk text change at both digit and unit boundaries, for example B/s → KiB/s → MiB/s ([`MenuBarIconRenderer.swift:315-316,366-367`](../../iStats/UI/MenuBarIconRenderer.swift#L315-L316)).
- Stacked text computes its image canvas from the current text width. Only network imposes a small lower bound; it does not impose a maximum fixed width ([`MenuBarIconRenderer.swift:426-470`](../../iStats/UI/MenuBarIconRenderer.swift#L426-L470)).
- CPU bar width is proportional to the number of cores, not a stable instrument width ([`MenuBarIconRenderer.swift:567-577`](../../iStats/UI/MenuBarIconRenderer.swift#L567-L577)). It will not jump during sampling, but produces inconsistent widget widths across machines.

**Recommendation:** make width a property of the selected widget style, never a property of its current reading.

- Assign a fixed `NSStatusItem.length` for every selected configuration instead of `.variableLength`.
- Render all image styles into fixed-size canvases. A CPU core bar may need to compress, group, or cap visible bars; it should not become wider just because a Mac has more cores.
- Render text and stacked text into fixed-width images using tabular figures, right-aligned within the reserved slot. `drawStackedText` already uses a monospaced-digit font, so this is a small extension of the existing approach—not a new UI system.
- Pick product limits rather than trying to display every possible string. In particular, one-line disk `R: … W: …` is inherently too wide for a polished status bar. Prefer the already available compact stacked R/W style, or constrain the text grammar.
- Preserve a useful accessibility title/tool tip even if the visible readout is canvas-rendered.

The desired result is a slightly wider but **unchanging** widget slot. Empty space inside a stable instrument is preferable to every other menu-bar item moving each time a rate crosses a unit threshold.

### P0 — Bound dedicated popovers

The universal popover is protected: it puts the metric stack in a vertical `ScrollView` and caps that region at 520 points ([`DetailPopoverView.swift:149-223`](../../iStats/UI/DetailPopoverView.swift#L149-L223)). The dedicated category popover does not: it inserts `categoryContent` directly between dividers ([`CategoryDetailPopoverView.swift:92-131`](../../iStats/UI/CategoryDetailPopoverView.swift#L92-L131)).

This becomes severe for data that is explicitly array-backed:

- thermal renders every sensor when expanded ([`ThermalSummaryView.swift:151-177`](../../iStats/UI/ThermalSummaryView.swift#L151-L177));
- network renders every interface when expanded ([`NetworkSummaryView.swift:198-250`](../../iStats/UI/NetworkSummaryView.swift#L198-L250));
- disk renders every mounted volume when expanded ([`DiskSummaryView.swift:151-174`](../../iStats/UI/DiskSummaryView.swift#L151-L174));
- fan renders every fan ([`FanSummaryView.swift:112-116`](../../iStats/UI/FanSummaryView.swift#L112-L116)).

**Recommendation:** give every category popover the same body contract: fixed width, bounded vertical scrolling body, and a footer that remains reachable. Default long detail sections to collapsed. For iStat-like density, show a curated first set (for example primary sensor and worst sensor) above the fold, then let “All sensors”, “Interfaces”, or “Volumes” reveal the full list inside the scroll region.

### P1 — Make graph labels factual

All eight categories use labels such as “60s CPU Activity,” “60s Network Traffic,” or “60s Temperature History.” The history capacity is 60 *samples*, not 60 seconds. With the default two-second refresh, the line represents about two minutes; at 60 seconds it represents about an hour; at 0.5 seconds it represents 30 seconds.

**Recommendation:** either label it “Last 60 samples” or derive a duration from first and last timestamps and display the actual time range. The latter will feel most like a professional monitor because it remains correct when the user changes the interval.

---

## Popover shell review

### Universal `DetailPopoverView`

**What works**

- The outer header, divider, scroll body, and fixed footer make a sensible general shell ([`DetailPopoverView.swift:130-258`](../../iStats/UI/DetailPopoverView.swift#L130-L258)).
- The fixed 330-point width and 520-point scrolling region prevent horizontal and vertical instability in the all-category case.
- It correctly respects category enablement when composing cards ([`DetailPopoverView.swift:152-221`](../../iStats/UI/DetailPopoverView.swift#L152-L221)).

**What to improve**

- It is now primarily a fallback experience, but it still carries the weight of eight full cards. That is acceptable as an “overview,” yet the fixed header and footer leave less room for telemetry. Keep it as an overview/fallback, not the primary click path.
- `statusFooterText` is calculated but never presented ([`DetailPopoverView.swift:266-275`](../../iStats/UI/DetailPopoverView.swift#L266-L275)). Either show a concise sampling/pressure state in the shell or remove it. Dead status logic is a source of future UI drift.
- The view’s initializer has sixteen test/preview override fields ([`DetailPopoverView.swift:9-24`](../../iStats/UI/DetailPopoverView.swift#L9-L24)). This is not directly visual debt, but it makes visual state easy to desynchronize. A later cleanup can use a fixture/coordinator, but it is not necessary for the first UI pass.

### Dedicated `CategoryDetailPopoverView`

**What works**

- The category title, contextual subtitle, and live state give the panel an immediate identity ([`CategoryDetailPopoverView.swift:47-96`](../../iStats/UI/CategoryDetailPopoverView.swift#L47-L96)). This is better than opening a card with no orientation.
- Category-specific accent colors are restrained to the popover and leave menu-bar graphics native/tinted ([`CategoryDetailPopoverView.swift:300-313`](../../iStats/UI/CategoryDetailPopoverView.swift#L300-L313)).
- `categoryContent` routes to one specialized view per category and applies units consistently ([`CategoryDetailPopoverView.swift:140-188`](../../iStats/UI/CategoryDetailPopoverView.swift#L140-L188)).

**What to improve**

1. **Use one source of truth for header and content.** The content can use a supplied override sample, while `statusBadgeText`, `statusDotColor`, and subtitle read the live coordinator directly ([`CategoryDetailPopoverView.swift:192-297`](../../iStats/UI/CategoryDetailPopoverView.swift#L192-L297)). A preview/test can therefore show CPU fixture content with a “Ready” or unrelated header state. Derive all three from the same presented sample.
2. **“Live” means scheduler running, not current data valid.** Generic categories get a green `Live` badge whenever `coordinator.isRunning` is true. It does not check whether the category has produced a sample, whether its latest sample is unavailable, or whether it is stale ([`CategoryDetailPopoverView.swift:206-243`](../../iStats/UI/CategoryDetailPopoverView.swift#L206-L243)). Reserve green for fresh/available data; use “Waiting,” “Unavailable,” or “Last updated …” otherwise.
3. **The header competes with already strong card heroes.** The icon badge, two lines of title/subtitle, and status pill consume substantial top-of-popover space before a card that repeats the same category and health state. For the iStat direction, simplify the shell header: category title plus a small freshness/status token. Let the first card own the hero metric.
4. **The footer is too action-heavy for every category.** Activity Monitor, Preferences, and Quit appear in every dedicated popover ([`CategoryDetailPopoverView.swift:105-126`](../../iStats/UI/CategoryDetailPopoverView.swift#L105-L126)). Preferences is valuable; Quit and Activity Monitor can live in the right-click menu already implemented by the controller ([`MenuBarController.swift:241-276`](../../iStats/App/MenuBarController.swift#L241-L276)). Removing duplicate actions would make more room for data and reduce “utility panel” noise.

---

## Per-category review

| Category | Strong points | Improve next |
|---|---|---|
| CPU | Clear hero, user/system/idle breakdown, core topology, fixed 0–100 graphs. | Remove dead expansion state; make dense core detail optional; avoid raw `Dynamic` as a data value. |
| Memory | Pressure is prominent; composition and swap are useful. | Align bar math with displayed values; do not let a clamped residual hide an inconsistent breakdown. |
| GPU | Good graceful layout for partial metrics and useful three-value summary. | Do not present unknown data as “Unified” or “Dynamic”; distinguish unavailable from not applicable. |
| Thermal | Excellent primary sensor/pressure treatment and sensor rows. | Collapse/scroll the potentially long list; preserve sensor identity through history. |
| Fan | Correctly communicates firmware control and fanless Macs. | Do not graph “maximum of any fan” as if it were the primary fan; shorten repeated policy text. |
| Network | Download/upload separation and interface rows match monitor mental models. | Preserve duplex data in the detail graph; distinguish loading from genuine zero traffic; cap interface list. |
| Disk | Read/write split, IOPS, capacity, and thresholds are useful. | Collapse/scroll volumes, de-duplicate APFS-related volumes, and establish a primary-volume policy. |
| Power | Battery/no-battery branches are thoughtful; health is appropriately secondary. | Make absent charge/telemetry explicit; do not graph a single point as a 60-second trend. |

### CPU

**Great**

- CPU has the best overall visual hierarchy: a large total, explicit user/system/idle micro-breakdown, a fixed 0–100 graph, and per-core topology ([`CPUSummaryView.swift:20-131`](../../iStats/UI/CPUSummaryView.swift#L20-L131)).
- The core matrix handles low and high core counts differently, which prevents a 24-core Mac from becoming a single impractical horizontal row ([`CPUSummaryView.swift:219-264`](../../iStats/UI/CPUSummaryView.swift#L219-L264)).
- The bar uses three semantic segments rather than treating all load as one undifferentiated color ([`CPUSummaryView.swift:142-158`](../../iStats/UI/CPUSummaryView.swift#L142-L158)).

**Improve**

- `isPerCoreExpanded` is declared but never used ([`CPUSummaryView.swift:10`](../../iStats/UI/CPUSummaryView.swift#L10)); per-core detail is always visible. Make this a real disclosure or delete the state. In a compact monitor popover, the total/load/graph should be immediately visible and core rings should be secondary.
- “Dynamic” for unavailable clock frequency is ambiguous ([`CPUSummaryView.swift:106`](../../iStats/UI/CPUSummaryView.swift#L106)). Dynamic frequency behavior is not the same as “this data is unavailable.”
- The current CPU graph has the correct fixed scale. Keep this decision; it makes one moment comparable to another.

### Memory

**Great**

- Pressure has a strong, explicit warning treatment, including text—not just color ([`MemoryPressureView.swift:8-88`](../../iStats/UI/MemoryPressureView.swift#L8-L88)).
- The primary reading uses used/total rather than only a percentage, which is more useful on machines with different RAM capacities ([`MemoryPressureView.swift:121-150`](../../iStats/UI/MemoryPressureView.swift#L121-L150)).
- Swap is present but not overemphasized unless nonzero.

**Improve**

- The composition bar computes its “free” segment as `total - app - wired - compressed - cached` ([`MemoryPressureView.swift:260-295`](../../iStats/UI/MemoryPressureView.swift#L260-L295)), while the data tile shows `sample.free` ([`MemoryPressureView.swift:233-236`](../../iStats/UI/MemoryPressureView.swift#L233-L236)). If those differ, the picture and label disagree. The `max(0, …)` clamp can conceal an over-summed breakdown. Define one display composition invariant and use those exact numbers in both the bar and labels.
- Six tiles, a composition legend, pressure badge, alert, graph, and hero make this one of the densest cards. Keep alert + hero + graph at the top; make the full breakdown a disclosure when pressure is normal.

### GPU

**Great**

- The card accommodates partial telemetry and has an explicit unavailable branch ([`GPUSummaryView.swift:29-168`](../../iStats/UI/GPUSummaryView.swift#L29-L168)). This is important for variable IOKit capabilities.
- The three secondary fields—memory, temperature, power—are a sensible compact set.

**Improve**

- The card reports missing memory as `Unified` and missing power as `Dynamic` ([`GPUSummaryView.swift:144-160`](../../iStats/UI/GPUSummaryView.swift#L144-L160)). These strings can sound like valid measurements. “Unified memory architecture” is not a memory-used value; “Dynamic” is not a wattage. Label absent values `—` with a short availability hint instead.
- A card with a sample but no actual GPU metrics shows “Active” ([`GPUSummaryView.swift:52-57`](../../iStats/UI/GPUSummaryView.swift#L52-L57)), which can overstate what was read. Prefer “Limited telemetry” or the reason from `Availability`.

### Thermal

**Great**

- Choosing a CPU/SoC/package sensor as the hero and separately exposing peak temperature is the right hierarchy ([`ThermalSummaryView.swift:32-88`](../../iStats/UI/ThermalSummaryView.swift#L32-L88)).
- Thermal pressure and temperature threshold colors are separate concepts and are both surfaced. That is a mature monitoring decision.
- Sensor rows have a compact name/value/bar pattern and fixed width for values ([`ThermalSummaryView.swift:180-214`](../../iStats/UI/ThermalSummaryView.swift#L180-L214)).

**Improve**

- “All Sensors” starts expanded and renders every sensor ([`ThermalSummaryView.swift:12,151-177`](../../iStats/UI/ThermalSummaryView.swift#L12-L12)). This is the clearest example of the dedicated-popover height defect. Default it closed and use a bounded scroller.
- The history tries to use the named primary sensor but falls back to the maximum sensor in each historic sample ([`ThermalSummaryView.swift:39-46`](../../iStats/UI/ThermalSummaryView.swift#L39-L46)). A graph can silently switch from CPU package to a different hottest sensor, so the line is not always one physical sensor over time. Record/choose a stable sensor identity for the hero graph, or label it “Hottest sensor.”
- The graph upper bound is based on current max temperature rather than historical peak ([`ThermalSummaryView.swift:95-102`](../../iStats/UI/ThermalSummaryView.swift#L95-L102)); an earlier hotter point can be clipped after the system cools. Include history maximum in the scale.

### Fan

**Great**

- It responsibly communicates system-controlled firmware mode and read-only safety ([`FanSummaryView.swift:62-76,118-133`](../../iStats/UI/FanSummaryView.swift#L62-L76)). This is excellent product communication for a hardware monitor.
- It handles fanless systems as a valid, calm state rather than an error ([`FanSummaryView.swift:134-156`](../../iStats/UI/FanSummaryView.swift#L134-L156)).
- The per-fan gauge respects hardware-reported min/max boundaries ([`FanSummaryView.swift:169-226`](../../iStats/UI/FanSummaryView.swift#L169-L226)).

**Improve**

- The featured number is the first fan, but graph history takes the maximum RPM of all fans ([`FanSummaryView.swift:21-34`](../../iStats/UI/FanSummaryView.swift#L21-L34)). The trend can therefore disagree with the hero. Either graph the same primary fan or label the graph “Peak fan speed.”
- The full firmware explanation repeats in every expanded card. Keep the concise “System Controlled” badge visible and move the sentence to a help affordance/footer to recover vertical space.

### Network

**Great**

- Separate download and upload hero cards match the user’s mental model and avoid hiding directionality ([`NetworkSummaryView.swift:47-63`](../../iStats/UI/NetworkSummaryView.swift#L47-L63)).
- Session totals and per-interface rows provide a good progression from current activity to diagnosis ([`NetworkSummaryView.swift:91-113,198-250`](../../iStats/UI/NetworkSummaryView.swift#L91-L113)).
- The menu-bar renderer has an especially appropriate duplex mini-graph and stacked in/out presentation ([`MenuBarIconRenderer.swift:296-317,460-555`](../../iStats/UI/MenuBarIconRenderer.swift#L296-L317)).

**Improve**

- The detail graph sums inbound and outbound throughput into one line ([`NetworkSummaryView.swift:27-42`](../../iStats/UI/NetworkSummaryView.swift#L27-L42)). That loses the best part of network telemetry: direction. Reuse the duplex concept from the menu-bar renderer or use two clearly distinct lines.
- Before any sample exists, the two hero cards display `0 B/s` ([`NetworkSummaryView.swift:52-60`](../../iStats/UI/NetworkSummaryView.swift#L52-L60)), while lower content says it is waiting. This conflates loading with no traffic. Use `—`/“Waiting” in the hero until a valid sample exists.
- Interfaces begin expanded with no cap. Collapse by default and show only active/nonzero interfaces first; put inactive interfaces behind an explicit disclosure.

### Disk

**Great**

- Read/write rate plus IOPS is exactly the right primary performance pairing ([`DiskSummaryView.swift:43-85`](../../iStats/UI/DiskSummaryView.swift#L43-L85)).
- Capacity presentation has clear warning thresholds and surfaces free/used/total ([`DiskSummaryView.swift:181-266`](../../iStats/UI/DiskSummaryView.swift#L181-L266)).

**Improve**

- Mounted volumes begin expanded and are unbounded ([`DiskSummaryView.swift:151-174`](../../iStats/UI/DiskSummaryView.swift#L151-L174)). macOS can expose many system and APFS-related mounts, so this should be a disclosure in a bounded scroll area.
- There is no source-level policy distinguishing a primary user volume from technical/system mounts. The renderer picks `/` first for its gauge ([`MenuBarIconRenderer.swift:332-340`](../../iStats/UI/MenuBarIconRenderer.swift#L332-L340)), but the detail view shows every returned volume equally. A professional monitor should lead with the startup/data volume, then list external/relevant volumes, with implementation mounts deemphasized or filtered.
- Like network, dynamically formatted rates can become visually long. This is particularly damaging in one-line menu-bar text; steer disk to a stable compact style.

### Power

**Great**

- The separate battery-present and desktop/no-battery branches are a very good piece of platform-aware design ([`PowerSummaryView.swift:39-53,177-228`](../../iStats/UI/PowerSummaryView.swift#L39-L53)).
- Charge, state, remaining time, power draw, adapter wattage, and health are correctly ordered from immediate status to deeper detail.
- Battery health is already a disclosure, which is the right precedent for other long sections ([`PowerSummaryView.swift:254-314`](../../iStats/UI/PowerSummaryView.swift#L254-L314)).

**Improve**

- `powerDrawGraphSection` can draw a one-point graph by substituting the current draw into an otherwise empty history ([`PowerSummaryView.swift:230-246`](../../iStats/UI/PowerSummaryView.swift#L230-L246)). A one-point line is not a trend; show a loading baseline until there are at least two readings.
- Menu-bar power has a serious unavailable-state bug: the symbol renderer treats missing power as a battery-bearing device, and `drawBatteryInstrument` substitutes `80` when charge is nil ([`MenuBarIconRenderer.swift:374-410,810-826`](../../iStats/UI/MenuBarIconRenderer.swift#L374-L410)). A missing sample can therefore draw an apparently 80% battery. Never substitute a plausible measurement for unavailable telemetry.

---

## Menu-bar style review

### Style suitability

| Style | Assessment | Stable-width requirement |
|---|---|---|
| Gauge / symbol | Best default. Fast to parse, naturally compact, visually iStat-like. | Fixed 16–22 point canvas per category. |
| Sparkline | Strong secondary widget if it uses a stable scale policy. | Fixed 32–34 point canvas. |
| Bar | Useful, especially CPU, but current CPU width varies by hardware core count. | Fixed canvas; group/condense high core counts. |
| Stacked throughput | Best network/disk text option because it is compact and directional. | Fixed-width, right-aligned two-line canvas. |
| Single-line text | Useful as an option, but least iStat-like and the main source of width churn. | Fixed slot, tabular figures, constrained grammar; avoid full disk R/W text. |

### Menu-bar configuration model

**Good**

- The configuration is persisted and naturally filters items when their parent category is disabled ([`PreferencesStore.swift:135-141,270-276`](../../Sources/iStatsCore/PreferencesStore.swift#L135-L141)).
- Defaults are restrained: CPU gauge, memory gauge, and network throughput ([`MenuBarItemConfig.swift:77-84`](../../Sources/iStatsCore/MenuBarItemConfig.swift#L77-L84)). That is an excellent initial composition.

**Improve**

- ADR 0007 describes UUID item IDs and an ordered collection, but the implemented ID is deterministic `category.style` ([`MenuBarItemConfig.swift:44-57`](../../Sources/iStatsCore/MenuBarItemConfig.swift#L44-L57)). The preference operations prevent duplicates of the same category/style ([`PreferencesStore.swift:251-266`](../../Sources/iStatsCore/PreferencesStore.swift#L251-L266)), and the preferences UI offers no reordering ([`PreferencesView.swift:151-250`](../../iStats/UI/PreferencesView.swift#L151-L250)). That means a user cannot place two copies of the same widget or control menu-bar order—the specific customization ADR 0007 proposed. Either update the ADR to the intentionally simpler model or add stable IDs plus ordering only if that flexibility is truly desired.
- `menuBarDisplayMode` remains persisted and subscribed to, but the modular renderer does not consume it ([`PreferencesStore.swift:128-132`](../../Sources/iStatsCore/PreferencesStore.swift#L128-L132), [`MenuBarController.swift:100-117`](../../iStats/App/MenuBarController.swift#L100-L117)). This legacy setting adds conceptual noise to a now better widget model. Remove/migrate it once compatibility is no longer required.
- Every possible style can be enabled, so the user can create a very crowded bar. The preference UI should make aggregate width visible and warn rather than silently letting macOS hide overflowed extras.
- `imagePosition == .imageLeading` is currently unreachable: renderer branches return either an image or a title, not both ([`MenuBarController.swift:196-202`](../../iStats/App/MenuBarController.swift#L196-L202), [`MenuBarIconRenderer.swift:88-410`](../../iStats/UI/MenuBarIconRenderer.swift#L88-L410)). This is harmless, but simplifies cleanly when the width work is done.

---

## Availability, truthfulness, and accessibility

### Availability must reach the UI

The domain model correctly defines `.unavailable(reason:)` ([`Availability.swift:7-20`](../../Sources/iStatsCore/Availability.swift#L7-L20)), and `MetricReading` preserves it ([`SampleScheduler.swift:70-80`](../../Sources/iStatsCore/SampleScheduler.swift#L70-L80)). The visual layer mainly consumes `coordinator.latestX?.value`, however. When the latest reading is the `.unavailable` enum case, the typed accessor returns `nil` ([`MetricsStore.swift:140-183`](../../Sources/iStatsCore/MetricsStore.swift#L140-L183)). The reason is therefore unavailable to cards and menu widgets.

This causes misleading fallbacks:

- Missing network is rendered numerically as zero in detail and menu graphics.
- Missing CPU/memory/fan/thermal data creates a zero-ish empty instrument even if the tooltip sometimes says `--`.
- Missing power can render as a plausible 80% battery as noted above.

**Recommendation:** publish category availability alongside each latest sample and make every card/menu renderer follow a three-state contract:

1. **Waiting:** no first sample yet;
2. **Available:** fresh reading with a timestamp;
3. **Unavailable:** explicit reason, never a zero or a plausible substitute.

### Accessibility needs an intentional pass

This cannot be fully verified without assistive-technology testing, but source identifies clear review targets:

- Most information is hard-coded at 8–11 point type (`CPUSummaryView`, `MemoryPressureView`, and other cards); this does not follow the user’s system text preference as well as semantic text styles.
- Graphs, progress bars, core rings, and colored gauges have no explicit accessibility value/label in their source. `CoreRingGauge` has a `.help` string ([`CPUSummaryView.swift:333-365`](../../iStats/UI/CPUSummaryView.swift#L333-L365)), but help text is not a complete substitute for an accessibility value.
- The gear and power footer buttons have tooltips but no explicit accessibility labels ([`CategoryDetailPopoverView.swift:111-126`](../../iStats/UI/CategoryDetailPopoverView.swift#L111-L126)).
- Several dynamic text values use `.lineLimit(1)` in a fixed 330-point layout. Long rates, sensor names, and mount points can truncate without an alternate display path.

Use semantic text styles where density allows; give instruments a concise value such as “CPU utilization, 42 percent”; and expose full truncated values with an accessibility label/help.

---

## Recommended implementation order

1. **Make status-item lengths style-specific and fixed.** This resolves the reported layout instability first.
2. **Normalize renderer canvas sizes.** Fixed text/stacked-text canvases, fixed CPU bar canvas, and no data-dependent image width.
3. **Add a bounded scroll body to dedicated popovers** and default long lists collapsed.
4. **Surface `Availability` and freshness in every card and renderer.** Fix the power 80% fallback in the same change.
5. **Replace all “60s” labels** with actual duration or “60 samples.”
6. **Tighten per-category hierarchy:** collapse CPU core detail, memory breakdown, sensor/interface/volume lists when normal; preserve the hero + trend above the fold.
7. **Resolve model/document drift:** either support actual ordered/duplicate widgets or simplify ADR 0007; retire legacy `menuBarDisplayMode`.
8. **Add source-level layout tests for the regressions.** Current tests instantiate views and verify renderer existence, but do not assert fixed output width across boundary values or bounded popover layout ([`MenuBarDisplayTests.swift:446-496`](../../Tests/iStatsTests/MenuBarDisplayTests.swift#L446-L496), [`DetailViewGraphsTests.swift:337-390`](../../Tests/iStatsTests/DetailViewGraphsTests.swift#L337-L390)). The first two tests to add should prove: (a) a given config’s image/title footprint is equal for low, threshold, and high values; (b) each category popover has a bounded scrollable body.

## Bottom line

The project is already conceptually aligned with iStat Menus: modular instruments, category-focused drill-down, fast visual parsing, and rich hardware-specific detail. Do not replace that foundation with a wholesale redesign.

Make the menu bar **stable**, make popovers **bounded**, and make unavailable data **honest**. Then reduce default-expanded detail so each category opens with one decisive metric and one readable trend. Those changes will make the existing design feel intentional, native, and substantially more iStat-like without adding a larger UI framework or more visual chrome.
