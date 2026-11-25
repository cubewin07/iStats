# ADR 0011 — Native-Premium Redesign: Category Identity, Navigable Popover, Per-Category Settings

**Status:** Accepted (Phase 9)
**Date:** 2026-11-26
**Phase:** Phase 9 (`phase-09-native-premium`)
**Amends:** [ADR 0009](0009-instrument-design-language-and-glass-panels.md). It adds a header strip, brings back a slim footer (ADR 0009 "Footer Removal" is reversed), adds the Overview destination, and replaces the "signature instrument per page" duplication with the one-value-once rule.
**Refines:** [ADR 0007](0007-per-category-menu-bar-items-and-popovers.md) (menu bar items and Settings window), [ADR 0008](0008-purpose-driven-widgets-and-tabbed-popovers.md) (widget catalog vocabulary).
**Preserves:** [ADR 0001](0001-language-and-ui-stack.md), [ADR 0002](0002-threading-and-scheduling-model.md), [ADR 0004](0004-privilege-and-fan-control.md) (fans stay read-only), [ADR 0006](0006-telemetry-privacy-no-persistence.md), [ADR 0010](0010-time-domain-chart-engine-and-synchronized-panel-motion.md).

---

## Context

Phases 7 to 8.5 shipped the Instrument panels, but three read-only audits (panel shell, Preferences, menu bar and icons) found the same root causes. They are summarised here; the full findings are folded into the task files under `docs/phases/phase-09-native-premium/tasks/`.

1. **Navigation dead ends.** A panel has no way to reach another category. `PanelController.swapToCategory` has exactly one caller (the fanless "Open Temperature" button in `FanPanel`). A category with no menu bar widget cannot be reached at all, and `NoWidgetsActiveView` is a dead-end fallback. Quit exists only in the status item right-click menu. `MetricPanel.keyDown` maps Space (key code 49) to pause, so a stray key press pauses sampling.
2. **Redundant content.** One number appears 3 to 4 times on a page (GPU utilization 4x, fan RPM 4x, CPU total usage 3x, swap 3x). The Battery hero shows charge % while the chart plots watts, and scrubbing flips the unit. `FanPanel` shows internal policy text ("Read-only (ADR 0004)") as user content.
3. **Inconsistent identity.** `MetricCategory.symbolName` (`square.3.layers.3d` for GPU, `arrow.up.arrow.down` for Network) disagrees with `thermometer.high`, `speedometer`, `network`, `wifi` and `wind` used in Alerts, General, per-interface rows and the fanless state. `StatusLevel.symbolName` (core) and `StatusLevel.iconName` (`CategoryPalette.swift`) disagree. In `PaletteContrast.Hex.categoryTint`, Network flips green to periwinkle and Disk flips indigo to pink between light and dark. Power green equals the "fine" status green, and Fan is close to Memory in hue.
4. **Settings drift.** The sidebar is custom (no keyboard navigation), one pane mixes four concepts, widgets cannot be reordered in-app, `menuBarDisplayMode`, `widgetPopoverStyles` and `PopoverStyle` are dead, the About pane shows a fake "Verified" pill, alerts fire on a single sample, and two paths open Settings (`PreferencesWindowController` and the SwiftUI `Settings {}` scene).
5. **Design-system drift.** Two token systems exist (`Instrument` is live, `iStats/UI/Design/Tokens.swift` is unreferenced). About 13 font sizes are hard-coded, some 8 to 9 pt. Panel thresholds (for example `CPUPanel` 90 / 75 and `1.5x` cores) bypass `StatusThresholds`. `MenuBarIconRenderer.swift` is 3,457 lines with roughly 1,000 lines of dead "Compatibility Drawings".

## Decision

### 1. Five design rules

1. **One identity per category.** `CategoryIdentity` (new, `Sources/iStatsCore/CategoryIdentity.swift`) is the only source of display name, short label, identity symbol and live symbol. The menu bar, popover strip, Settings sidebar, alerts and onboarding all read it.
2. **Each page answers one question.** Now answers "is it OK, and who is responsible?". Details answers "why?" (breakdowns, hardware specs). History answers "what is the trend?". A value appears at most once per page, and a hero and its chart always show the same quantity and unit.
3. **Native first.** System materials, SF Pro / SF Mono, and native controls (`Form`, `NavigationSplitView`, `Toggle`, `Picker`). Category color is an accent only: charts, the active strip button, and the active widget preview.
4. **Visible affordances.** Nothing is reachable only by hover or by a hidden shortcut; every shortcut appears in a tooltip or menu key hint. Text is at least 10 pt in panels and at least 9 pt in the menu bar.
5. **Calm defaults.** Menu bar widgets default to the status-tint appearance (monochrome until warning or above). Alerts require a sustained condition.

### 2. Category identity and icon table

`CategoryIdentity` supersedes `MetricCategory.symbolName(hasBattery:)` and `shortLabel(hasBattery:)` (they forward to it during migration, then are removed). Final hex values are set in task 9.1 and must pass the new hue and contrast tests; the hue values below are starting points.

| Category | Display name | Identity symbol | Live / contextual symbol | Color family (same hue in light and dark) |
|---|---|---|---|---|
| CPU | CPU | `cpu` | none | blue (~215 deg), keep |
| Memory | Memory | `memorychip` | none | mint (~160 deg), lighter in light mode |
| GPU | GPU | `cube.transparent` (was `square.3.layers.3d`) | none | violet (~265 deg), keep |
| Temperature | Temperature | `thermometer.medium` (also replaces `thermometer.high` in Alerts) | `thermometer.low` / `.medium` / `.high` by peak, menu bar glyph only | orange (~22 deg), keep |
| Fans | Fans | `fan` | `fan.slash` when fanless (replaces `wind`) | neutral steel: desaturated blue-gray, separated by saturation not hue |
| Network | Network | `network` (was `arrow.up.arrow.down`) | `wifi` / `cable.connector` per active interface | cyan (~190 deg), no light/dark flip |
| Disk | Disk | `internaldrive` | `internaldrive.fill` / `externaldrive.fill` per volume | pink-magenta (~335 deg), no flip |
| Battery / Power | "Battery" on laptops, "Power" on desktops (was "Battery & Power") | `battery.100percent` / `powerplug` | `battery.{0,25,50,75,100}percent` (`.bolt` when charging) by charge and state | lime (~85 deg), moved off the status green |

`StatusLevel` gets one symbol mapping (core owns it; the UI `iconName` becomes a thin forwarder or is deleted). A `SymbolAvailabilityTests` app test asserts `NSImage(systemSymbolName:)` is non-nil for every identity and live symbol on the test host (macOS 13 floor; GPU falls back to `display` if `cube.transparent` is missing on the floor).

### 3. Popover shell: header strip, Overview, slim footer

- **Header strip (28 pt).** Leading: an Overview button (`square.grid.2x2`) then one 24 pt button per *enabled* category; the active destination has a tinted capsule. Trailing: pin and the `...` menu. At most nine buttons must fit in the 320 pt content width (geometry test).
- **Destinations.** `PanelDestination` (new core enum, Codable): `.overview` or `.category(MetricCategory)`. `PanelController` presents destinations rather than categories, crossfades between them, keeps pinned state, and remembers the pinned origin per destination.
- **Overview.** A 2-column grid of tiles (identity symbol, name, 22 pt mono primary value, 24 pt sparkline from the `MetricsStore` ring buffers, status dot). Clicking a tile opens that category's Now page. This is the landing page of the fallback status item and replaces `NoWidgetsActiveView`.
- **Slim footer (24 pt).** Leading: a contextual quick action ("Activity Monitor", "Network Settings", "Storage"). Center: "Updated - every 2 s" or "Paused". Trailing: pause/resume and a Settings gear that opens *that category's* Settings page. This **reverses ADR 0009's Footer Removal**: the footer is smaller (24 pt, one line, no per-category content), exists to make Settings, pause state and last-updated time visible (rule 4), and replaces the hidden Space shortcut.
- **Keyboard.** Cmd-1..9 select strip positions (Overview is Cmd-1), Ctrl-Tab / Ctrl-Shift-Tab cycle destinations, Left/Right switch pages, Cmd-P pins, Cmd-W and Esc close, Cmd-Q quits. The Space-to-pause shortcut is removed.
- **Status ribbon.** `StatusRibbon` shows for any message at warning or above and always carries a real action ("Battery Settings...", "Open Activity Monitor", "Manage Storage...", "Wi-Fi Settings...").

### 4. One-value-once page rule

Per page, a value is shown once: hero, chart, legend, row and tooltip must not repeat the same number. Panels follow a common order and spacing (`Space.sectionGap`): signature instrument first, then "who is responsible". History owns trends; Details owns breakdowns not already in a Now legend. Per-category consequences are specified in tasks 9.5 and 9.6 (for example Battery plots charge % to match its hero, with watts in the headline and Power Flow). Panel text never cites ADRs.

### 5. Menu bar appearance modes and widget vocabulary

- `menuBarAppearance` (new preference): `.monochrome` (template images only), `.statusTint` (**default**: monochrome until warning or above, then the status color), `.categoryColor` (category palette accents). Colors come from `CategoryPalette` and the status palette, never `.systemX`.
- **Vocabulary (all categories):** **Value** (text), **Dual** (two values: up/down, read/write, L/R fans), **Bar**, **Ring**, **Graph** (sparkline), **Glyph**. Temperature's five per-sensor styles collapse to Value with a `source` option. The overloaded `.throughput` style for Fan and Power is removed. A migration map sends every legacy raw value to a new style; nothing is dropped silently.
- A pure `WidgetModel` (core, `Hashable`) computes text, fractions, color role and width class, and doubles as the visual key. `MenuBarIconRenderer` splits into per-family renderers under `iStats/UI/MenuBar/`. Each style has a fixed width class from its worst-case string.

### 6. Settings: one window path, one page per category

- One window path: `PreferencesWindowController` (presented as **Settings**). The SwiftUI `Settings {}` scene becomes an empty stub that forwards Cmd-, to the controller.
- `NavigationSplitView` with `List(selection:)`. Groups: General, Appearance, Menu Bar; the eight category pages; Notifications, About. The last section is persisted (`lastSettingsSection`). Pages use `Form` with `.formStyle(.grouped)`.
- Each category page holds: a "Monitor <Category>" toggle, a widget gallery with live light/dark previews (via `WidgetModel` + renderers), popover options, alerts, and category extras (network interface, disk volume for alerts, temperature sensor). A category that is enabled but has no widgets shows "Shown in Overview only".
- The Menu Bar page has a drag-to-reorder list synced with Cmd-drag through `MenuBarOrdering.observedOrder`.
- About: real app icon, version, links, Copy Diagnostics (model, macOS, per-sampler `Availability`; no telemetry values), Show Welcome Again. The fake "Verified" pill is removed.

### 7. Preferences v2 and sustained alerts

- `preferencesSchemaVersion` plus an idempotent `PreferencesMigration` (core). New keys: `lastPanelDestination`, `lastSettingsSection`, `hasCompletedOnboarding` (set true for existing users during migration), `menuBarAppearance`, `networkInterfaceSelection`. Dead state is removed (`MenuBarDisplayMode`, `formatTitle`, `widgetPopoverStyles` / `PopoverStyle`, unused store helpers). `categoryLastTabs` becomes the single tab-memory scope; the per-item "Remember last tab" is removed. `pinnedPanelOrigins` stays and is keyed by `PanelDestination.storageKey`.
- `AlertRule` (new, core, Codable): `enabled`, `threshold`, `comparison`, `sustainSeconds`, optional `target` (volume or interface), replacing the 15 scattered alert keys. A pure `AlertEvaluator` (core) implements sustain window, cooldown and hysteresis; `AlertCoordinator` delegates to it. Alert titles carry no emoji.

### 8. Onboarding and metric explainers

- `WelcomeWindow` appears when `hasCompletedOnboarding == false`: what iStats does plus the in-memory privacy promise (ADR 0006); pick a preset (Minimal / Balanced / Everything) with a live menu bar preview; optional notification permission and launch at login.
- `MenuBarPreset` (core) is hardware-aware (no battery means no Battery widget; fanless means no Fan widget).
- `MetricGlossary` (core, pure strings, keyed by `MetricTerm`) explains terms such as memory pressure, swap, compressed, wired, load average, P/E cores, cycle count, max capacity, IOPS, RSSI/SNR, throttling. An `InfoButton` (popover) appears on section titles and alert threshold rows.

### 9. Privileged fan control (9F) is deferred

The Phase 9 spec package records a sub-phase 9F (spike, ADR 0012 "Opt-in privileged fan control", helper, UI) but **it is not implemented or spiked in Phase 9**. **ADR 0004 still governs: fans are read-only.** No Phase 9 task adds an SMC write path, a privileged helper, an `SMAppService` daemon, or fan control UI. Fan panel copy states only "macOS manages fan speed automatically." If 9F is ever started, the first deliverable is a throwaway spike and ADR 0012; this ADR does not accept any fan write.

## Options considered

| Option | Verdict |
|---|---|
| Keep one panel per category, add only a "Next" arrow | Rejected: still no overview, strip hides how many categories exist. |
| One tall combined dashboard popover | Rejected: breaks the per-widget, per-category model of ADR 0007 and the 560 pt height cap. |
| Keep the footerless shell (ADR 0009) and add Quit/Settings to `...` only | Rejected: Settings, pause state and update cadence stay hidden; Space remains the only quick pause. |
| Per-category color derived from system accent | Rejected: breaks the stable identity colors checked by `PaletteContrastTests`. |
| SwiftUI `Settings {}` scene as the only Settings path | Rejected: no autosave control, cannot deep-link to a category page from a panel footer, cannot be opened reliably from an `.accessory` app. |
| Keep per-item `PopoverConfig.rememberLastTab` | Rejected: disagreed with the per-category `categoryLastTabs` store. |
| Implement fan control in this phase | Rejected: needs a signed helper with Team ID, differing SMC write semantics, and real hardware risk; gated by a spike and ADR 0012. |

## Consequences

- `PanelController`, `MetricPanel`, `PanelScaffold` and `MenuBarController` change signature from categories to destinations; tests in `PanelControllerLifecycleTests` and `PanelScaffoldTests` migrate.
- Existing users keep their configuration: schema migration is idempotent, keeps unknown values, and skips onboarding.
- Several core files are added and many app files are split or deleted. The Xcode project uses explicit file references (`objectVersion = 56`, no synchronized groups), so every added or removed file under `iStats/` or `Tests/iStatsTests` also needs a `project.pbxproj` edit. Pure logic therefore goes into `iStatsCore`, which SwiftPM picks up automatically.
- New core type `AlertEvaluator` collides with an existing app-target `struct AlertEvaluator` in `iStats/App/AlertCoordinator.swift`; task 9.10 renames the app one first.
- ADR 0009's footer removal is reversed; ADR 0009 and the ADR index are annotated accordingly.
- Fan control stays out of scope; a future ADR 0012 is required before any write path.
