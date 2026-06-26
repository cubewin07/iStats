# Phase 5 — Thermal, Fan & GPU (highest risk)

**Goal:** Read available thermal sensors, fan RPM, and GPU stats. Expect partial availability on Apple Silicon. This phase starts with a spike and finalizes ADR 0003.

**Maps to Kiro spec task:** 5 (sub-tasks 5.1–5.7)

## Tasks
- [ ] **Spike + ADR 0003:** decide thermal/fan/power data source (AppleSMC keys vs IOReport) on the target Mac; record which keys/sources actually work.
- [ ] `ThermalSampler`: available sensors, human-readable names, °C with °F option; `.unavailable` handling; thermal pressure where exposed.
- [ ] `FanSampler`: RPM + min/max bounds (read-only).
- [ ] ADR 0004 + (if feasible) opt-in fan control within bounds via privileged helper; otherwise present read-only with explanation.
- [ ] `GPUSampler`: utilization, memory, temp/power where available; `.unavailable` otherwise.
- [ ] ADR 0005 sandbox/entitlements check; ensure graceful degradation when access denied.
- [ ] Validate vs `sudo powermetrics`; write `report.md`.

## Learning focus
- IOKit service matching for `AppleSMC`; SMC key encoding (4-char codes, data types).
- Why Apple Silicon differs; what IOReport exposes.
- Thermal-safety reasoning before ever considering fan control.

## Validation
- `sudo powermetrics` (thermal pressure, GPU residency/power).
- Compare any temperature/fan readings to a tool you trust on this exact Mac model; record which SMC keys mapped to which sensors.

## Exit criteria
- Spike complete and ADR 0003 finalized with concrete findings.
- Whatever sensors are available are validated; unavailable ones are clearly marked, app stable.
