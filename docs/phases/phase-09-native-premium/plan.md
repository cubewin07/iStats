# Phase 9 — Native-Premium Redesign — Plan

**Status:** Spec package on disk (task 9.0). See [`docs/progress.md`](../../progress.md) for status.
**ADR:** [`docs/architecture/adr/0011-native-premium-redesign.md`](../../architecture/adr/0011-native-premium-redesign.md)
**Spec files:** [`requirements.md`](./requirements.md) · [`design.md`](./design.md) · [`tasks.md`](./tasks.md)

---

## 1. Why Phase 9 Exists

Phases 7 to 8.5 delivered Instrument panels with correct motion and charts, but three read-only audits found structural product gaps:

| Area | Finding | Task |
|---|---|---|
| Navigation | No in-panel category switching; `swapToCategory` has one caller (`FanPanel` fanless button); categories without a menu bar widget are unreachable; Quit only in the status item right-click menu; Space silently pauses (`MetricPanel.keyDown`, key code 49) | 9.3, 9.4 |
| Redundancy | Same number 3 to 4 times per page (GPU util 4x, fan RPM 4x); Battery hero is % but chart is watts; Fans panel shows "ADR 0004" | 9.5, 9.6 |
| Identity | GPU `square.3.layers.3d`, Network `arrow.up.arrow.down`, `thermometer.high`, `speedometer`, `wind` strays; Network/Disk hue flips between light and dark; Power green equals status green; two `StatusLevel` symbol maps | 9.1 |
| Design system | Dead `Tokens.swift`; about 13 hard-coded font sizes (8 to 11.5 pt); literal thresholds in panels | 9.1 |
| Settings | Custom sidebar, mixed panes, dead `menuBarDisplayMode` / `widgetPopoverStyles` / `PopoverStyle`, per-item "Remember last tab" vs per-category `categoryLastTabs`, fake "Verified" pill, single-sample alerts, two window paths | 9.2, 9.9, 9.10 |
| Menu bar | 3,457-line `MenuBarIconRenderer`, about 1,000 lines dead, `visualKeyForX` mirror, `.systemX` colors, unreachable styles silently dropped by `PreferencesStore.init` | 9.7, 9.8 |
| Help | No onboarding, no metric explanations | 9.11 |

## 2. Stages and dependencies

| Stage | Tasks | Notes |
|---|---|---|
| A Foundation | 9.0, 9.1, 9.2 | strictly in order |
| B Popover | 9.3, 9.4, 9.5, 9.6 | 9.3 then 9.4; 9.5 and 9.6 need 9.3 and 9.1 |
| C Menu bar | 9.7, 9.8 | needs 9.1 and 9.2; independent of B and D |
| D Settings | 9.9, 9.10 | 9.9 independent of B, C; 9.10 needs 9.7 (widget previews), 9.2 (`AlertRule`), 9.9 |
| E Help | 9.11 | needs 9.2 and 9.10 |
| F Verification | 9.12 | last |
| 9F | 9F.0 to 9F.4 | **deferred**, learning first |

```
9.0 -> 9.1 -> 9.2 -+-> 9.3 -> 9.4 -> 9.5 / 9.6 -+
                   +-> 9.7 -> 9.8 --------------+-> 9.10 -> 9.11 -> 9.12
                   +-> 9.9 ----------------------+
```

## 3. Project facts every task must respect

- `Package.swift` compiles `iStats/` (target `iStats`, excluding `App/iStatsApp.swift`, `Resources`, `Assets.xcassets`) and `Sources/iStatsCore`. New files there are picked up automatically by `swift build` / `swift test`.
- `iStats.xcodeproj/project.pbxproj` (`objectVersion = 56`) uses explicit file references with no synchronized groups. **Every file added or deleted under `iStats/` or `Tests/iStatsTests` must also be added to / removed from `project.pbxproj`** (PBXBuildFile, PBXFileReference, group children, Sources build phase; for tests, the `iStatsTests` target). Files under `Sources/iStatsCore` and `Tests/iStatsCoreTests` do not need pbxproj edits.
- Build and test: `swift build --scratch-path /tmp/istats-build`, `swift test --scratch-path /tmp/istats-build`, `swift build -c release --scratch-path /tmp/istats-build`, `xcodebuild -scheme iStats -configuration Debug build`, `xcodebuild test -scheme iStats -destination 'platform=macOS'` (a second shared scheme `iStatsApp` also exists and earlier evidence cites it).
- macOS 13 deployment target, Swift 6 strict concurrency.
- Invariants (CLAUDE.md): no sysctl/Mach/IOKit/SMC on `@MainActor`; failures map to `Availability.unavailable(reason:)`; rates via `RateMath`; telemetry in memory only; fans read-only.

## 4. Commit policy

Each task 9.0 to 9.12 gets at least one commit with a meaningful message after its build and tests pass. Large tasks (9.1, 9.3, 9.7, 9.9, 9.10) are committed at natural sub-steps (each task file has a "Commit plan"). Never commit a broken build. Handoffs go to `docs/handoffs/09-9.x-{plan,exam,summary}.md`; `docs/progress.md` is the only status file.

## 5. Risks (phase level)

| Risk | Mitigation |
|---|---|
| Scope (13 tasks plus deferred 9F) | Stages ship independently; stop cleanly after any stage |
| Xcode project edits | Pure logic in `iStatsCore`; each task lists pbxproj edits explicitly |
| Preferences migration could wipe layout | Fixture tests, idempotent, versioned, unknown values kept |
| Nine strip buttons in 320 pt | Only enabled categories, 24 pt buttons, geometry test |
| macOS 13 floor | `NavigationSplitView` and `.formStyle(.grouped)` exist on 13; symbol availability test with `display` fallback for GPU |
| Name collisions | `AlertEvaluator` already exists (app target); `PanelGlance` already exists; `PopoverTab.overview` vs `PanelDestination.overview` |

## 6. Out of scope

A global hotkey; telemetry persistence (ADR 0006); WidgetKit or Notification Center widgets, localization, auto-update; per-process network or disk usage (no data source); a new app icon; **privileged fan control (9F) implementation**.
