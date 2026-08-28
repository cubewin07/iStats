# ADR 0007 — Per-Category Menu Bar Items and Dedicated Popovers

**Status:** Proposed

## Context
In the initial Phase 1 foundation, `MenuBarController` managed a single `NSStatusItem` that rendered either a single metric text/icon or an all-in-one menu bar label, opening a monolithic `DetailPopoverView` containing all metric categories in a single long scrollable list.

Users desire an experience matching modular system monitors (such as iStat Menus):
1. Users should be able to place multiple distinct icons/widgets in the macOS menu bar for any metric category (e.g. CPU can have both a circular load gauge and a historical sparkline).
2. Toggling a category in preferences should automatically manage (show/hide) all menu bar items associated with that category.
3. Rather than opening a monolithic all-in-one popover, clicking any menu bar icon belonging to a category should display a **dedicated popover specific to that category** (e.g. clicking any CPU icon displays the CPU metrics popover; clicking a Network icon displays the Network throughput popover).
4. All icons within the same category share the same category-specific popover content and view model.

## Decision
1. **Configurable Menu Bar Item Model (`MenuBarItemConfig`):**
   - Introduce `MenuBarItemConfig(id: UUID, category: MetricCategory, style: MetricDisplayStyle, isEnabled: Bool)` in `iStatsCore`.
   - Persist user-configured menu bar widgets in `PreferencesStore.menuBarItems`.
   - Toggling a `MetricCategory` off automatically filters out and removes all associated `NSStatusItem`s from the menu bar.
2. **Dynamic Multi-StatusItem Controller (`MenuBarController`):**
   - Refactor `MenuBarController` to manage a collection `[UUID: NSStatusItem]`.
   - Each `NSStatusBarButton` stores its `config.id` and `config.category` in its identifier or action context.
3. **Dedicated Category Popovers (`CategoryPopoverController` / `CategoryDetailView`):**
   - Create dedicated popover presentation routing keyed by `MetricCategory`.
   - Each category uses a focused popover view rendering its specialized summary (e.g. `CPUSummaryView`, `MemorySummaryView`, `GPUSummaryView`, `ThermalSummaryView`, `FanSummaryView`, `NetworkSummaryView`, `DiskSummaryView`, `PowerSummaryView`).
   - Clicking any icon of category $C$ opens the dedicated popover for category $C$, anchored directly to the clicked status item button.

## Options Considered
- **Single Monolithic Popover with Anchor Switching:** Keep one giant popover that opens regardless of which icon was clicked, auto-scrolling to the category section.
  - *Rejected:* Clutters the interface with unrelated metrics when the user specifically clicked a single category icon (e.g. clicking a small Network arrow icon shouldn't pop up a 500px window with CPU, RAM, and Disk metrics).
- **Single NSStatusItem per Category (1:1 fixed mapping):** Allow only one menu bar item per category.
  - *Rejected:* Restricts user customization; users frequently want both a graphical indicator (gauge/sparkline) and a numeric text reading for the same metric category.
- **Dedicated Per-Category Popovers with Multi-Item Mapping (Chosen):** Cleanest separation of concerns, lowest visual noise, optimal user experience matching modular menu bar monitors.

## Consequences
- `MenuBarController` transitions from a 1:1 `NSStatusItem` owner to a dynamic multi-item lifecycle manager.
- `PreferencesStore` schema expands to store ordered `[MenuBarItemConfig]` while maintaining backwards compatibility and migration from `MenuBarDisplayMode`.
- Popover state management handles category-specific views cleanly, reusing shared category summary components without duplicate telemetry subscriptions.
- UI preferences interface gains an item configuration and style picker per category.
