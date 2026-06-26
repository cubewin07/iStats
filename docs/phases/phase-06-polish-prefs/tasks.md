# Phase 6 — Polish, Preferences & Performance

**Goal:** Finish configurability, launch-at-login, performance tuning, and finalize all docs.

**Maps to Kiro spec task:** 6 (sub-tasks 6.1–6.5)

## Tasks
- [ ] Preferences: enable/disable each category; configurable menu bar content; unit options (°C/°F, bytes/bits, IEC/SI).
- [ ] Launch at login via `SMAppService`; Dock-icon toggle.
- [ ] Persist all preferences across launches.
- [ ] Performance pass: confirm sampling off main thread; measure iStats' own CPU at default interval; verify interval scaling reduces footprint.
- [ ] Finalize all docs/ADRs; write `report.md` and project README.

## Learning focus
- `SMAppService` registration for login items.
- Measuring your own app's footprint (and the observer effect on a monitor).
- SwiftUI preferences patterns and persistence.

## Validation
- Change each preference, restart, confirm it persisted.
- Measure iStats CPU at default interval (target: low single digits); confirm a longer interval lowers it.

## Exit criteria
- All v1 requirements met; footprint acceptable; docs/ADRs/reports complete.
