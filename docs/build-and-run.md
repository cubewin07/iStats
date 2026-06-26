# iStats — Build & Run

> The Xcode project is created in Phase 1. Until then this document describes the intended setup; update the specifics once the project exists.

## Prerequisites

- macOS (current major version recommended). Primary target: Apple Silicon.
- Xcode (latest stable) with Command Line Tools installed: `xcode-select --install`.
- A signing identity is not required for local development (run unsigned / your own Mac).

## Project layout

```
iStats/
├── iStats/            # app target source
│   ├── App/           # entry point, MenuBarController, AppDelegate
│   ├── Core/          # SampleScheduler, MetricsStore, models, math (pure)
│   ├── Sampling/      # one Sampler per metric category
│   ├── UI/            # detail view, graphs, preferences
│   └── Resources/     # Info.plist, assets
└── iStatsTests/       # unit tests for Core
```

## Build & run

1. Open the project in Xcode (`iStats.xcodeproj` or the workspace).
2. Select the `iStats` scheme.
3. Run (⌘R). The app appears in the menu bar (no Dock icon when `LSUIElement` is set).

CLI alternative (once a scheme exists):
```
xcodebuild -scheme iStats -configuration Debug build
```

## Running tests

- In Xcode: ⌘U.
- CLI:
```
xcodebuild test -scheme iStats -destination 'platform=macOS'
```
The `Core` tests run without hardware. Sampler integration tests require running on a real Mac.

## Permissions during development

- Most metrics need no special permission.
- Thermal/fan/power (Phase 5) and some IOKit reads may require additional access; the app must degrade gracefully if not granted. See `adr/0005-sandbox-and-entitlements.md`.
- For development, the app runs **non-sandboxed** (many sensors are blocked under App Sandbox). This tradeoff is recorded in ADR 0005.

## Debugging tips

- Use `os_log` / `Logger` for structured logs; filter in Console.app.
- To compare against references quickly: keep Activity Monitor open and a Terminal with `top -l 1`, `vm_stat`, `pmset -g batt` handy.
