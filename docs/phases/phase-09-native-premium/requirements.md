# Phase 9 — Native-Premium Redesign — Requirements

**ADR:** [`0011-native-premium-redesign.md`](../../architecture/adr/0011-native-premium-redesign.md)

## Goal of this phase

Make iStats feel native to macOS and easy to understand. Every category has one identity (name, symbol, color). From any panel you can reach any category in one click. Each number appears once per page. Settings live in native per-category pages with live previews. First-run setup takes about 30 seconds.

Stages A to F ship independently; Phase 9 can stop cleanly after any stage. Sub-phase 9F (privileged fan control) is **deferred** and not part of this phase's scope.

---

## Requirement 13: Native-Premium Redesign

**User story:** As a user, I want to move between categories without hunting for menu bar items, trust that each number is shown once, and configure everything in native Settings pages, so the app feels like a first-party macOS utility.

### R9.1 Category identity (rule 1)
1. `CategoryIdentity` SHALL be the only source of display name, short label, identity symbol and live symbol. No view or renderer SHALL hard-code a category symbol or name.
2. Display names are `CPU`, `Memory`, `GPU`, `Temperature`, `Fans`, `Network`, `Disk`, and `Battery` (laptop) or `Power` (desktop). Identity symbols are `cpu`, `memorychip`, `cube.transparent`, `thermometer.medium`, `fan`, `network`, `internaldrive`, `battery.100percent` / `powerplug`.
3. Category tint hue SHALL be stable between light and dark (drift at most 15 deg), pairwise at least 25 deg apart between saturated categories, and at least 15 deg from every status hue except where noted (Fans uses a neutral steel family separated by saturation). Each tint SHALL keep WCAG AA contrast on its surface.
4. `StatusLevel` SHALL have one symbol mapping.
5. Every identity and live symbol SHALL resolve through `NSImage(systemSymbolName:)` on the test host.

### R9.2 Design tokens (rules 3, 4)
1. `iStats/UI/Design/Tokens.swift` SHALL be deleted. `Instrument` is the only token system.
2. `Instrument.Typography` SHALL be the semantic ramp: display 44, displayCompact 30, title 15, headline 13, body 12, value 12 mono, caption 11, micro 10. No size below 10 pt SHALL appear in `iStats/UI/Panels` or `iStats/UI/Instrument` (the 11.5, 9 and 8 pt sizes are removed).
3. Tokens `Space.sectionGap`, `Size.headerStripHeight` (28), `Size.footerHeight` (24) and a chart height per variant SHALL replace literals.
4. Panel thresholds SHALL come from `StatusThresholds`, not literals (for example the CPU 90 / 75 and `1.5x` cores checks).
5. A `TokenLintTests` test SHALL fail if a literal `.font(.system(size:` appears under `iStats/UI/Panels`.

### R9.3 Preferences v2 (rule 5)
1. `PreferencesMigration` SHALL upgrade stored defaults through a `preferencesSchemaVersion` key. It SHALL be idempotent, lossless on v1 fixtures, and keep unknown values.
2. `AlertRule` SHALL replace the 15 scattered alert keys. New keys: `lastPanelDestination`, `lastSettingsSection`, `hasCompletedOnboarding` (true for existing users), `menuBarAppearance` (default `.statusTint`), `networkInterfaceSelection`.
3. Tab memory SHALL be per category only (`categoryLastTabs`). `MenuBarDisplayMode`, `formatTitle`, `widgetPopoverStyles` and `PopoverStyle` SHALL be removed.

### R9.4 Popover navigation (rules 1, 4)
1. `PanelDestination` (`.overview`, `.category(MetricCategory)`) SHALL drive `PanelController`. Switching destinations SHALL crossfade, keep pinned state, and remember the pinned origin per destination.
2. A 28 pt header strip SHALL list Overview and every enabled category (24 pt buttons; all nine fit in 320 pt). A 24 pt footer SHALL show a contextual action, update cadence or "Paused", pause/resume, and a Settings gear that opens that category's Settings page.
3. Keyboard: Cmd-1..9, Ctrl-Tab / Ctrl-Shift-Tab, Left/Right, Cmd-P, Cmd-W, Esc, Cmd-Q. Space SHALL NOT pause sampling. The `...` menu SHALL show key hints and **Quit iStats**.
4. `StatusRibbon` SHALL show any message at warning or above, with a real action.
5. The Overview page SHALL list only enabled categories (identity symbol, name, 22 pt primary value, 24 pt sparkline, status dot). The fallback status item SHALL open it, replacing `NoWidgetsActiveView`.

### R9.5 One value once (rule 2)
1. A value SHALL appear at most once per page; hero and chart SHALL share quantity and unit (including while scrubbing).
2. Battery SHALL plot charge %. Fans SHALL contain no policy text citing ADRs. Temperature spectrum SHALL use `Size.contentWidth`. Disk hero SHALL format through `Units`.
3. Section order and spacing (`Space.sectionGap`) SHALL be the same in every panel.

### R9.6 Menu bar widgets (rules 3, 5)
1. `WidgetModel` SHALL be pure and `Hashable`, and SHALL replace the `visualKeyForX` family.
2. Every category SHALL offer only the vocabulary Value, Dual, Bar, Ring, Graph, Glyph. Every legacy style raw value SHALL map to a new style.
3. Widgets SHALL have fixed width classes (no jitter), text at least 9 pt, one thermal range constant, colors from `CategoryPalette` / status palette only, and sparklines redraw only on a new sample.
4. `menuBarAppearance` SHALL support `.monochrome`, `.statusTint` (default), `.categoryColor`. The right-click menu SHALL offer Show Overview, Settings for this category, Hide This Widget, Pause/Resume, Quit.

### R9.7 Settings (rules 3, 4)
1. There SHALL be one Settings window path (`PreferencesWindowController`). The SwiftUI `Settings {}` scene SHALL forward Cmd-, to it.
2. `NavigationSplitView` sidebar with keyboard navigation; groups General/Appearance/Menu Bar, eight category pages, Notifications/About. Last section persisted.
3. Pages use `Form` with `.formStyle(.grouped)`; every toggle has an accessibility label; no zero-opacity shortcut buttons.
4. Menu Bar page: drag-to-reorder synced with Cmd-drag. Category pages: widget gallery with live previews, popover options, alerts (`AlertRule`), extras (interface, volume, sensor).
5. Alerts SHALL fire only when a condition holds for `sustainSeconds`; cooldown and hysteresis SHALL be enforced by `AlertEvaluator`; titles carry no emoji.
6. About SHALL show the bundle app icon, version/build, links, Copy Diagnostics (no telemetry values) and Show Welcome Again, and SHALL NOT show a "Verified" pill.

### R9.8 Onboarding and explainers
1. `WelcomeWindow` SHALL appear when `hasCompletedOnboarding == false`: three steps (privacy promise; preset Minimal / Balanced / Everything with live preview; optional notifications and launch at login).
2. `MenuBarPreset` SHALL be hardware-aware. `MetricGlossary` SHALL cover every `MetricTerm` with non-empty text. `InfoButton` SHALL appear on section titles and alert threshold rows.

### R9.9 Performance and invariants
1. One open panel at 1 Hz SHALL stay at or under 3% CPU on Apple Silicon.
2. All CLAUDE.md invariants hold: no sysctl/Mach/IOKit/SMC on `@MainActor`, failures map to `Availability.unavailable(reason:)`, telemetry in memory only (ADR 0006), fans read-only (ADR 0004).

### R9.10 Deferred (not required)
Privileged fan control (9F). No fan write path, helper, or fan control UI SHALL be added in Phase 9.
