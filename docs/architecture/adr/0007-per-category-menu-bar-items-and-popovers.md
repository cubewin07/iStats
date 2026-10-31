# ADR 0007 — Per-Category Menu Bar Items, Decoupled Popovers, and Interactive Preview

**Status:** Accepted (Partially superseded by [ADR 0008](0008-purpose-driven-widgets-and-tabbed-popovers.md) for `PopoverStyle` 33-style sprawl; multi-item controller and studio architecture preserved)

## Context
In the initial Phase 1 foundation, `MenuBarController` managed a single `NSStatusItem` that rendered either a single metric text/icon or an all-in-one menu bar label, opening a monolithic `DetailPopoverView` containing all metric categories in a single long scrollable list.

Users desire an experience matching modular system monitors (such as iStat Menus):
1. Users should be able to place multiple distinct icons/widgets in the macOS menu bar for any metric category (e.g. CPU can have both a circular load gauge and a historical sparkline).
2. Toggling a category in preferences should automatically manage (show/hide) all menu bar items associated with that category.
3. Rather than opening a monolithic all-in-one popover, clicking any menu bar icon belonging to a category should display a **dedicated popover specific to that category or customized to the user's preference**.
4. Users should be able to decouple menu bar widgets from their popover designs (e.g. binding a compact core cluster bar to an overview popover, or a temperature text widget to a full subsystem panel), with unset widgets falling back cleanly to natural defaults (such as specialized thermal subsystem popovers for thermal widgets).
5. In Preferences, users should be able to preview what each popover looks like and interact directly with the live popover.

## Decision
1. **Configurable Menu Bar Item Model (`MenuBarItemConfig` & `PopoverStyle`):**
   - Introduce `PopoverStyle` in `iStatsCore` representing selectable popovers across all categories.
   - Extend `MenuBarItemConfig(category:style:popoverStyle:)` with optional `popoverStyle: PopoverStyle?`.
   - Persist user-configured menu bar widgets and custom popover styles in `PreferencesStore`.
   - Unset (`nil`) popover styles resolve to `PopoverStyle.defaultStyle(for:widgetStyle:)`, preserving natural subsystem popovers (e.g. `cpuTemp` -> CPU Thermals).
2. **Dynamic Multi-StatusItem Controller (`MenuBarController`):**
   - Manage status items and dedicated NSPopovers dynamically keyed by item configuration ID.
   - Detect popover style updates and invalidate cached view controllers dynamically.
3. **Decoupled Popover Factory (`ConfigPopoverFactory`):**
   - Provide `makePopoverView(category:popoverStyle:...)` and `makeHostingController(category:popoverStyle:...)` to instantiate any popover view independently of the triggering widget.
4. **System Settings Architecture & Live Menu Bar Studio (`PreferencesView`):**
   - Modern macOS System Settings-style translucent sidebar (`SidebarVisualEffectView`) supporting keyboard navigation (`⌘1`–`⌘4`).
   - Interactive Live Menu Bar Strip: renders active widgets in exact screen order, supporting 1-click selection, `<` / `>` button shifts (`moveActiveMenuBarItem(id:direction:)`), removal, and crowding feedback.
   - Category rail with active widget counts, master sampler toggles, and dedicated widget style cards.
   - Single-source-of-truth Popover Stage: directly binds custom popover styles to `PreferencesStore` with immediate live interactive preview.
   - Modular panes: `PreferencesMenuBarPane`, `PreferencesGeneralPane`, `PreferencesAlertsPane`, `PreferencesAboutPane`.

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
