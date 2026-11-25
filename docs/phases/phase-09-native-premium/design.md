# Phase 9 — Native-Premium Redesign — Design

Canonical design slice for ADR 0011. Refines [`../phase-08-premium-redesign/design.md`](../phase-08-premium-redesign/design.md) and [`../phase-08.5-instrument-polish/design.md`](../phase-08.5-instrument-polish/design.md).

---

## 1. Layering

```
Hardware samplers (background) -> MetricsCoordinator / MetricsStore (iStatsCore ring buffers)
        |                                   |
        |                       pure core: CategoryIdentity, PanelDestination, AlertRule/AlertEvaluator,
        |                       WidgetModel, MenuBarPreset, MetricGlossary, PreferencesMigration
        v                                   v
 AppKit: MenuBarController (status items) -> PanelController (destinations) -> MetricPanel (NSPanel + SwiftUI)
                                                                                |
                                       SwiftUI: PanelChrome (strip, title row, footer) + Overview / category panels
 AppKit: PreferencesWindowController -> SwiftUI Settings (NavigationSplitView)   WelcomeWindow
```

Rule: pure logic lives in `iStatsCore` so SwiftPM tests cover it and the Xcode project needs no extra file references.

## 2. Popover shell v3 (320 pt content, 352 pt panel)

```
 +--------------------------------------------------+
 | [grid][cpu][mem][gpu][tmp][fan][net][dsk][bat] [pin][...]   28 pt strip (24 pt buttons)
 | CPU                         Now | Details | History          title row (15 pt) + PageSwitcher
 |  hero numeral + headline                                      glance
 |  chart (Size.chartHeight variant)
 |  status chip / StatusRibbon (>= warning, with action)
 |  sections (Space.sectionGap)                                  single ScrollView (ADR 0010)
 | Activity Monitor >      Updated - every 2 s       [pause][gear]   24 pt footer
 +--------------------------------------------------+
```

- `PanelChrome` (new struct) carries the scaffold's chrome configuration (ribbon and its action, pause/pin callbacks, loading and low-power flags, availability); `PanelGlance` (existing) keeps the glance data model. `PanelScaffold` moves from 16 parameters to `PanelChrome` + `PanelGlance` + pages. Probe infrastructure moves to `PanelScaffoldProbes.swift`.
- `PanelDestination.storageKey` is `"overview"` or `MetricCategory.rawValue`, so existing `pinnedPanelOrigins` entries keep working without migration.
- Strip shows only enabled categories (`PreferencesStore.enabledCategories`), in `MetricCategory.allCases` order, with the Power button using the battery/desktop identity.

### Keyboard map

| Key | Action |
|---|---|
| Cmd-1..9 | select strip position (Overview first) |
| Ctrl-Tab / Ctrl-Shift-Tab | next / previous destination |
| Left / Right | previous / next page |
| Cmd-P / Cmd-W / Esc | pin / close-or-unpin / close (Esc is a no-op when pinned) |
| Cmd-, | Settings (current category page) |
| Cmd-Q | quit |
| (Space) | no longer mapped |

The old page shortcuts Cmd-1/2/3 change meaning (strip positions). Pages are reached by Left/Right and by clicking `PageSwitcher`; its tooltip lists this.

## 3. Page contract (one value once)

| Page | Question | Allowed content |
|---|---|---|
| Now | Is it OK, and who is responsible? | hero + chart (same quantity/unit), signature instrument, top consumers |
| Details | Why? | breakdowns not already in a Now legend, hardware specs |
| History | What is the trend? | range control, envelope chart, stats strip |

Order inside a page: signature instrument, then "who is responsible", spaced by `Space.sectionGap`.

## 4. Identity, palette, tokens

- `CategoryIdentity`: `displayName(hasBattery:)`, `shortLabel(hasBattery:)`, `symbol(hasBattery:)`, `liveSymbol(state:)` where `state` is a small value struct (for example battery charge/charging, interface kind, volume external flag, thermal peak, fanless).
- Palette: new hex pairs in `PaletteContrast.Hex.categoryTint` / `categoryDeep`, with a hue helper in core for tests (hue distance, light/dark drift, status separation).
- Tokens: type ramp (11.5/9/8 removed), `Space.sectionGap`, `Size.headerStripHeight`, `Size.footerHeight`, per-variant chart heights.

## 5. Menu bar

- `WidgetModel(sample, style, options, appearance)` -> text, fractions, color role, width class; `Hashable`; used as render cache key.
- Renderers under `iStats/UI/MenuBar/`: `ValueWidgetRenderer`, `DualWidgetRenderer`, `BarWidgetRenderer`, `RingWidgetRenderer`, `GraphWidgetRenderer`, `GlyphWidgetRenderer`, plus `MenuBarIconRenderer` as a thin facade.
- Appearance: `.monochrome` renders template images; `.statusTint` templates until status is warning or above; `.categoryColor` uses `CategoryPalette`.

## 6. Settings

Sections (`SettingsSection`, persisted as `lastSettingsSection`): `general`, `appearance`, `menuBar`, `category(MetricCategory)` x8, `notifications`, `about`. The footer gear calls `PreferencesWindowController.shared.show(section:)`.

## 7. Alerts

`AlertRule { enabled, threshold, comparison (above / below), sustainSeconds, cooldownSeconds, target }` per alert kind. `AlertEvaluator.evaluate(rule:value:now:state:)` returns a decision plus updated state (pure). The existing app-side message builder keeps title/body copy.

## 8. Onboarding and glossary

`WelcomeWindow` (three steps) driven by `MenuBarPreset.items(for:hasBattery:hasFans:)`; `MetricGlossary.entry(for: MetricTerm)` returns `(title, meaning, typical)`; `InfoButton(term:)` shows it in a popover.

## 9. Deferred (9F)

Recorded in [`tasks/9F-privileged-fan-control-DEFERRED.md`](./tasks/9F-privileged-fan-control-DEFERRED.md). ADR 0004 governs; the only fan UI change in Phase 9 is read-only copy.
