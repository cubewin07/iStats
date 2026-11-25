# Phase 9 — Native-Premium Redesign — Tasks

**Goal:** Give every category one identity, make every category reachable from every panel, show each number once, move widgets and alerts into native per-category Settings pages, and add first-run onboarding (see [`plan.md`](./plan.md), [`design.md`](./design.md), [`requirements.md`](./requirements.md), [ADR 0011](../../architecture/adr/0011-native-premium-redesign.md)).

**Status tracking:** Do not tick checkboxes here. Update [`docs/progress.md`](../../progress.md) when tasks finish.

**Commit policy:** Every task (`9.x`) gets at least one commit with a clear, meaningful message once its build and tests pass. Large tasks (9.1, 9.3, 9.7, 9.9, 9.10) are committed at natural sub-steps listed in each task's "Commit plan". Never commit a broken build.

**Project facts:** New files under `iStats/` or `Tests/iStatsTests` need `iStats.xcodeproj/project.pbxproj` edits (explicit references, `objectVersion = 56`); `iStatsCore` files do not. Use `--scratch-path /tmp/istats-build` for SwiftPM.

---

### Stage A — Foundation (`9.0` – `9.2`)
- [ ] **9.0** ADR 0011 and the Phase 9 spec package
  - [`tasks/9.0-adr-0011.md`](./tasks/9.0-adr-0011.md)
- [ ] **9.1** Identity and design-system foundation: `CategoryIdentity`, re-hued palette, unified `StatusLevel` symbols, delete `Tokens.swift`, type ramp, new size tokens, `StatusThresholds` adoption, token sweep
  - [`tasks/9.1-identity-and-design-system.md`](./tasks/9.1-identity-and-design-system.md)
- [ ] **9.2** Preferences model v2 and migration: `PreferencesMigration`, `AlertRule`, new keys, dead state removed (core, no UI)
  - [`tasks/9.2-preferences-v2-migration.md`](./tasks/9.2-preferences-v2-migration.md)

### Stage B — Popover (`9.3` – `9.6`)
- [ ] **9.3** Panel shell v3: `PanelDestination`, header strip, slim footer, keyboard map, `StatusRibbon` actions, `PanelChrome` refactor
  - [`tasks/9.3-panel-shell-v3.md`](./tasks/9.3-panel-shell-v3.md)
- [ ] **9.4** Overview destination: `OverviewPage`, `OverviewTile`, fallback status item, "Show Overview"
  - [`tasks/9.4-overview-destination.md`](./tasks/9.4-overview-destination.md)
- [ ] **9.5** Panel content pass A (one value once): CPU, Memory, GPU, Temperature
  - [`tasks/9.5-panel-content-pass-a.md`](./tasks/9.5-panel-content-pass-a.md)
- [ ] **9.6** Panel content pass B: Fans, Network, Disk, Battery/Power
  - [`tasks/9.6-panel-content-pass-b.md`](./tasks/9.6-panel-content-pass-b.md)

### Stage C — Menu bar (`9.7` – `9.8`)
- [ ] **9.7** Widget model and renderer refactor: pure `WidgetModel`, per-family renderers, dead code deleted (no behavior change)
  - [`tasks/9.7-widget-model-and-renderers.md`](./tasks/9.7-widget-model-and-renderers.md)
- [ ] **9.8** Widget catalog consolidation and appearance modes: Value / Dual / Bar / Ring / Graph / Glyph, legacy style migration map, `menuBarAppearance`, right-click menu
  - [`tasks/9.8-widget-catalog-and-appearance.md`](./tasks/9.8-widget-catalog-and-appearance.md)

### Stage D — Settings (`9.9` – `9.10`)
- [ ] **9.9** Settings shell: single window path, `NavigationSplitView`, General / Appearance / Notifications / About pages
  - [`tasks/9.9-settings-shell.md`](./tasks/9.9-settings-shell.md)
- [ ] **9.10** Menu Bar page, per-category pages, sustained alerts (`AlertEvaluator`)
  - [`tasks/9.10-menubar-and-category-settings.md`](./tasks/9.10-menubar-and-category-settings.md)

### Stage E — Help and onboarding (`9.11`)
- [ ] **9.11** `WelcomeWindow`, `MenuBarPreset`, `MetricGlossary`, `InfoButton`
  - [`tasks/9.11-onboarding-and-glossary.md`](./tasks/9.11-onboarding-and-glossary.md)

### Stage F — Verification (`9.12`)
- [ ] **9.12** Gallery, accessibility and performance pass, `report.md`
  - [`tasks/9.12-verification-and-report.md`](./tasks/9.12-verification-and-report.md)

### Sub-phase 9F — Privileged fan control (**DEFERRED: learning first**)
- [ ] **9F** Deferred. Not scheduled in Phase 9; ADR 0004 (read-only fans) still governs. Start with 9F.0 (spike + ADR 0012) when taken up.
  - [`tasks/9F-privileged-fan-control-DEFERRED.md`](./tasks/9F-privileged-fan-control-DEFERRED.md)

---

## Exit criteria
- Every category has one identity from `CategoryIdentity`; no stray symbols; palette tests (hue distance, light/dark drift, status separation, contrast) pass.
- From any panel, every enabled category is one click (or Cmd-N) away; Overview works with zero widgets enabled.
- No value repeats on a page; hero and chart agree on quantity and unit in every panel.
- One Settings window path with per-category pages; alerts are sustained; onboarding runs on fresh defaults.
- `swift test --scratch-path /tmp/istats-build`, `swift build -c release --scratch-path /tmp/istats-build`, and `xcodebuild test -scheme iStats -destination 'platform=macOS'` pass.
- One open panel stays at or under 3% CPU at 1 Hz on Apple Silicon.
- Every task is committed separately; `report.md` and `docs/progress.md` are updated.
- 9F is not implemented; fans remain read-only.
