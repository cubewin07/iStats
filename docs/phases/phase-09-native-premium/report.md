# Phase 9 — Native-Premium Redesign — Report

**Status:** Complete (automated verification). The manual visual pass in §4 is still open.
**Branch:** `feature/popover-and-widget-redesign`
**Reference ADR:** [`ADR 0011`](../../architecture/adr/0011-native-premium-redesign.md). It amends ADR 0009.
**Deferred:** 9F, privileged fan control. Fans stay read-only under ADR 0004.

---

## 1. Summary

Phase 9 fixed the problems the Phase 7–8.5 UI audit found:
- popover navigation dead ends
- numbers repeated on one page
- inconsistent category identity
- a custom Settings window with dead settings
- token drift
- a 3,457-line menu bar renderer

Scope: 56 commits since `b063dcc` across 13 tasks (9.0–9.12). Code changed: 138 files under `Sources/`, `iStats/` and `Tests/` (+16.5k / −9.4k lines).

| Stage | Tasks | Outcome |
|-------|-------|---------|
| A Foundation | 9.0, 9.1, 9.2 | ADR 0011 and the spec package. `CategoryIdentity` is now the single source for name, symbol and short label. Each category keeps the same hue in light and dark mode. Semantic type ramp with a 10 pt minimum. `StatusThresholds` helpers. `PreferencesMigration` v2 with `AlertRule` and `PanelDestination`. |
| B Popover | 9.3, 9.4, 9.5, 9.6 | Panel shell v3 has a header strip (Overview plus categories, pin, ⋯ with Quit ⌘Q), a title row with pages, and a slim footer (quick action, updated/paused, pause, Settings gear). Keyboard: ⌘1–⌘9, ⌃Tab, ←/→. Space-to-pause is gone. Overview has a 2-column tile grid with sparklines and uptime. All 8 panels show each value once. The battery chart plots charge %. |
| C Menu bar | 9.7, 9.8 | Pure `WidgetModel` is the visual key. Renderers are split per style family into `iStats/UI/MenuBar/`, with one fixed width per style. One catalog vocabulary (Value / Dual / Bar / Ring / Graph / Glyph), with migration of legacy style values. `MenuBarAppearance` modes: monochrome, status tint, category color. Right-click menu. |
| D Settings | 9.9, 9.10 | One window path, `NavigationSplitView` with `SettingsSection` deep links (`iStats.openSettingsSection`), `Form` pages, and Copy Diagnostics. The Menu Bar editor has drag-to-reorder. Per-category pages with live widget previews. `AlertEvaluator` in core handles sustain, cooldown and hysteresis. `AlertMessageBuilder` on the app side. Legacy alert keys removed. |
| E Help | 9.11 | 3-step `WelcomeWindow` with hardware-aware `MenuBarPreset`. `MetricGlossary` / `MetricTerm`, `InfoButton` (ⓘ) and a `?` glossary sheet. DEBUG launch argument `-iStatsUseScratchDefaults`. |
| F Verify | 9.12 | This report, the invariant audit and dead-code removal. Per-task details are in `docs/handoffs/09-9.x-summary.md`. |

## 2. Automated verification (HEAD after `69e09f3`)

| Command | Result |
|---------|--------|
| `swift test --scratch-path /tmp/istats-build` | **880 passed**: 416 `iStatsCoreTests` + 464 `iStatsTests`, 0 failures (see the perf note in §5) |
| `swift build -c release --scratch-path /tmp/istats-build` | Build complete. The two `String(cString:)` deprecation warnings in `ProcessSampler` are fixed. |
| `xcodebuild -scheme iStats -configuration Debug build` | BUILD SUCCEEDED |
| `xcodebuild test -project iStats.xcodeproj -scheme iStatsApp -destination 'platform=macOS,arch=arm64'` | **TEST SUCCEEDED**, 456 tests |

The suites added in Phase 9 all pass:
- `CategoryIdentityTests`, `SymbolAvailabilityTests`, `TokenLintTests`, `PaletteContrastTests` (hue and no-flip checks)
- `PreferencesMigrationTests`, `AlertRuleTests`, `AlertEvaluatorTests`
- `PanelDestinationTests`, `PanelShellLogicTests`, `OverviewTileModelTests`, `OverviewViewTests`
- `WidgetModelTests`, `WidgetCatalogTests`, `MenuBarPresetTests`, `WidgetPreviewTests`
- `SettingsSectionTests`, `SettingsWindowTests`, `MenuBarSettingsTests`
- `MetricGlossaryTests`, `WelcomeFlowTests`, `PanelContentPassATests`, `PanelContentPassBTests`

Note: the `iStats` scheme still reports "no test bundles". This predates Phase 9. App tests run through the `iStatsApp` scheme, or through SwiftPM.

## 3. Invariant audit

| Invariant | Method | Result |
|-----------|--------|--------|
| No sysctl / Mach / IOKit / SMC calls on `@MainActor` | Grep of every `@MainActor` file for `import IOKit`, `sysctl`, `host_statistics`, `host_processor_info`, `IOServiceGetMatching`, `IORegistryEntry`, `AppleSMCClient(`, `SMCParamStruct` | **Pass.** The only hit is `MetricsCoordinator` importing `IOKit.ps`, which it uses only to register the power-source change notification (`IOPSNotificationCreateRunLoopSource`), not to sample. Unchanged since Phase 4. Process sampling runs in `Task.detached(priority: .utility)`. |
| Telemetry in memory only (ADR 0006) | Grep for `UserDefaults` / file writes outside preferences | **Pass.** The only other `UserDefaults` uses are throwaway suites in `#if DEBUG` previews. The new keys (`lastPanelDestination`, `lastSettingsSection`, `menuBarAppearance`, `alertRules`, …) are preferences, not samples. |
| Fans read-only (ADR 0004) | Grep for SMC write keys (`F0Md`, `F0Tg`, write helpers) | **Pass.** No write paths. 9F is still deferred. |
| Failures → `Availability.unavailable(reason:)` | Sampler code unchanged in Phase 9, apart from the `ProcessSampler` string fix | **Pass** (`SandboxDegradationTests`). |
| Menu bar text ≥ 9 pt, no `.systemX` colors, no "Compatibility Drawings" | Grep of `iStats/UI/MenuBar*` | **Pass.** |
| Panel text ≥ 10 pt, no literal font sizes in panels | `TokenLintTests` plus grep | **Pass.** `MetricSourceBadge` (Settings) was 9 pt and now uses `Typography.micro` (10 pt). |

### Cleanup done in 9.12
- Removed `PanelHeadline.power`, which had no callers because `PowerPanel` builds its own headline, along with its test.
- Removed the leftover pre-9.9 Settings components: `SidebarVisualEffectView`, `SettingsCard`, `SettingsRow`, and the `preferenceCategoryColor/Icon` helpers.
- `ProcessSampler` now decodes `proc_name` / `proc_pidpath` by the length they return, replacing the deprecated `String(cString:)`.

## 4. Manual checklist

Visual and assistive-technology checks need a real Mac session. Per the project rule, no desktop screenshots were taken, and unit tests are not offered as proof of how things look. Each item below is either covered by automated tests or still needs a manual run.

| Check | Automated coverage | Manual status |
|-------|--------------------|---------------|
| Header strip and footer on every destination, 9 buttons fitting in 320 pt | `PanelScaffoldTests`, `PanelShellLogicTests` | Open |
| Overview tiles, opening a category from a tile, fallback status item opening Overview | `OverviewViewTests`, `OverviewTileModelTests` | Open |
| Every category × Now/Details/History in light and dark | `PanelContentPassA/BTests`, `SwiftUIViewsTests` (render smoke tests) | Open. Use `InstrumentGalleryPreview` |
| Keyboard map (⌘1–⌘9, ⌃Tab, ←/→, ⌘P, ⌘W, Esc, ?, ⌘Q) | `PanelShellLogicTests`, `PanelControllerLifecycleTests` | Open |
| Pin/unpin, position remembered per destination | `PanelControllerLifecycleTests` | Open |
| Every widget style × appearance mode | `MenuBarItemMatrixTests`, `MenuBarGeometryInvarianceTests`, `WidgetPreviewTests` | Open. The rotated 9 pt vertical labels have only been size-tested |
| Settings sections, deep link from the footer gear and the right-click menu | `SettingsSectionTests`, `SettingsWindowTests` | Open |
| Alert fires only after the sustain window | `AlertEvaluatorTests` (sustain, cooldown, hysteresis, °F) | Open (injected-value run) |
| Welcome flow on clean defaults | `WelcomeFlowTests` | Open. Run with `-iStatsUseScratchDefaults YES` |
| Migration from a real v1 defaults domain | `PreferencesMigrationTests` (v1 fixtures, idempotence) | Open (copy of a real domain) |
| VoiceOver rotor over header, footer and rows. Increase Contrast, Reduce Motion, Reduce Transparency | `AccessibilityAppearanceTests` | Open |

## 5. Performance

- **Synthetic single-panel benchmark** (`PerformancePassTests.testSinglePanel1HzRefreshTotalAppCPUBudget`, budget ≤ 3.0% from R8.5.6): isolated runs gave **2.29–2.90%**. One run inside the full parallel suite gave 3.10%, then passed on re-run. Phase 8.5 recorded < 2.5%. The margin to the budget is now thin, and the test can flake on a loaded machine. Follow-up: profile the panel shell v3 per-tick layout (header strip and footer "Updated" text) before raising the budget.
- **Live run** (Debug build, scratch defaults, default widgets, Welcome window open, no metric panel, 3:00 wall time):
  - CPU: 3.52 s total, a **1.96% average**. This includes launch, the first sample of all 8 categories, and the Welcome window. `ps` showed 0.0–0.2% at each 10 s sample after the first 20 s.
  - Memory: resident size peaked at **≈ 107 MB** during the first minute, then settled at **≈ 81–83 MB**.
  - No errors in the log. The single `sandbox_extension_issue_file_to_process` line is expected when the binary is launched outside LaunchServices.
  - Not measured: a 10-minute run with every widget enabled, and a run with a panel open. Both need interaction in the UI and belong to the manual pass in §4.
- Redraws: `MenuBarDirtyCheckingTests` confirm that images are rebuilt only when the `WidgetModel` key changes, and sparklines only once per sample.

## 6. Follow-ups (not blockers)

1. **Memory Details rows:** page-ins, page-outs, faults and compressions need new `MemorySample` fields from `vm_statistics64`. The Details page shows only what the sampler provides today.
2. **Unused headlines:** `PanelHeadline.gpu` and `.disk` are now unused in the app. Only their tests call them. Either remove them or adopt them in the panels.
3. **Perf headroom:** see §5.
4. **The `iStats` scheme** has no test action. Either add the `iStatsTests` bundle to it, or document that `iStatsApp` is the test scheme.
5. **Temperature spectrum width:** 296 pt (content width minus card padding) is intentional, not the old 296-vs-320 bug.
6. **9F, privileged fan control:** start with 9F.0 (spike plus ADR 0012) once you've learned the area.
