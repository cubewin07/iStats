# Phase 4 — Battery & Power

**Goal:** Battery state, health, and power draw, validated against `pmset` and `system_profiler`.

**Maps to Kiro spec task:** 4 (sub-tasks 4.1–4.5)

## Tasks
- [ ] `PowerSampler` battery charge/state/time-remaining via `IOPowerSources`.
- [ ] Battery health (cycle count, condition, design vs current max capacity) via `AppleSmartBattery` IORegistry entry.
- [ ] Instantaneous power draw / wattage + adapter power where exposed.
- [ ] Handle no-battery case (hide / not-applicable).
- [ ] Validate vs `pmset -g batt` / `system_profiler`; write `report.md`.

## Learning focus
- IOKit IORegistry traversal; reading `AppleSmartBattery` properties.
- `IOPowerSources` API shape.
- Where wattage comes from (SMC/IOReport) and its caveats.

## Validation
- `pmset -g batt` (charge %, charging state).
- `system_profiler SPPowerDataType` (cycle count, condition, capacities).
- `sudo powermetrics --samplers cpu_power,gpu_power` for power draw sanity.

## Exit criteria
- Charge/state/health match references; no-battery case handled.
