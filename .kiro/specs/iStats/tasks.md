# iStats — Implementation Plan

Tasks are grouped by the phases defined in the design. Each phase ends with a runnable app and a written `report.md`. Documentation deliverables (ADRs, docs, prerequisites/learning guide) are explicit tasks, not afterthoughts.

---

## Phase 0 — Documentation scaffolding & learning baseline

- [ ] 0. Set up project + documentation skeleton
  - [ ] 0.1 Create the `iStats/` folder structure (App/Core/Sampling/UI/Resources, iStatsTests, docs/) as in the design
    - _Requirements: 14.2, 14.3_
  - [ ] 0.2 Write `docs/prerequisites-and-learning.md`: OS concepts and macOS frameworks (sysctl, Mach host stats, IOKit, SMC, IOPowerSources), plus a per-metric "validate against reference tool" checklist (Activity Monitor, `top`, `df`, `pmset`, `powermetrics`)
    - _Requirements: 14.4, 14.5_
  - [ ] 0.3 Write the docs set: `overview.md`, `architecture.md`, `build-and-run.md`, `glossary.md`
    - _Requirements: 14.2_
  - [ ] 0.4 Write `docs/phases/phase-plan.md` (whole-project skeleton + phase index) and create per-phase `tasks.md`/`report.md` stubs
    - _Requirements: 14.3_
  - [ ] 0.5 Author initial ADRs 0001 (stack), 0002 (threading), 0006 (privacy/no persistence)
    - _Requirements: 14.1, 13.3_

---

## Phase 1 — Foundation (runnable menu bar app)

- [ ] 1. Create the Xcode app target and menu bar shell
  - [ ] 1.1 Create Swift app target; set `LSUIElement` so it runs without a Dock icon (configurable later)
    - _Requirements: 9.1, 9.5_
  - [ ] 1.2 Install an `NSStatusItem` (MenuBarController) showing a placeholder; click opens an empty detail popover
    - _Requirements: 9.1, 9.3_
  - [ ] 1.3 Define core protocols and value types: `Sampler`, `Sample<T>`, `Availability`, `MetricCategory`
    - _Requirements: 1.5, 12.3_
  - [ ] 1.4 Implement `SampleScheduler` (background queue, per-category interval, publishes to main actor) with per-sampler error isolation
    - _Requirements: 12.1, 12.3, 12.4_
  - [ ] 1.5 Implement `MetricsStore` rolling ring buffer (pure) + unit tests for capacity/eviction
    - _Requirements: 10.2_
  - [ ] 1.6 Preferences shell (SwiftUI) with persisted settings store; wire interval bounds
    - _Requirements: 11.2, 11.4_
  - [ ] 1.7 Write `phase-01` report
    - _Requirements: 14.3_

---

## Phase 2 — CPU & Memory

- [ ] 2. Implement CPU and memory sampling
  - [ ] 2.1 `CPUSampler` via Mach `host_processor_info`; compute total + per-core %, user/system/idle from tick deltas
    - _Requirements: 1.1, 1.2, 1.4_
  - [ ] 2.2 Load average via `sysctl vm.loadavg`; CPU frequency where available else `.unavailable`
    - _Requirements: 1.3, 1.5_
  - [ ] 2.3 Pure unit/property tests for CPU % math from synthetic counters (monotonic, 0–100% bounds)
    - _Requirements: 1.1, 12.1_
  - [ ] 2.4 `MemorySampler` via `host_statistics64(HOST_VM_INFO64)` + `sysctl hw.memsize`; used/free/wired/compressed/cached/swap
    - _Requirements: 2.1, 2.3_
  - [ ] 2.5 Memory pressure level (normal/warning/critical) and surface it in UI
    - _Requirements: 2.2, 2.4_
  - [ ] 2.6 Render CPU + memory in detail view with live rolling graphs; allow choosing CPU/mem for the menu bar
    - _Requirements: 9.4, 10.1, 10.2, 10.3_
  - [ ] 2.7 Validate values vs Activity Monitor / `top`; write `phase-02` report
    - _Requirements: 14.5, 14.3_

---

## Phase 3 — Network & Disk

- [ ] 3. Implement network and disk sampling
  - [ ] 3.1 `NetworkSampler` via `getifaddrs`/`if_data`; per-interface + aggregate up/down throughput and session totals
    - _Requirements: 6.1, 6.2, 6.3_
  - [ ] 3.2 Rate math from byte deltas; handle counter reset (never negative/absurd) — property tested
    - _Requirements: 6.4_
  - [ ] 3.3 `DiskSampler` capacity (total/used/free) per mounted volume via `statfs`; react to volume add/remove
    - _Requirements: 7.1, 7.3_
  - [ ] 3.4 Disk I/O throughput via IOKit block storage statistics (mark `.unavailable` if not accessible)
    - _Requirements: 7.2_
  - [ ] 3.5 Network/disk in detail view; unit option bytes vs bits for network
    - _Requirements: 10.1, 11.3_
  - [ ] 3.6 Validate vs Activity Monitor (network) and `df`; write `phase-03` report
    - _Requirements: 14.5, 14.3_

---

## Phase 4 — Battery & Power

- [ ] 4. Implement battery and power sampling
  - [ ] 4.1 `PowerSampler` battery charge/state/time-remaining via `IOPowerSources`
    - _Requirements: 8.1_
  - [ ] 4.2 Battery health (cycle count, condition, design vs current max capacity) via `AppleSmartBattery` registry
    - _Requirements: 8.2_
  - [ ] 4.3 Instantaneous power draw / wattage + adapter power where exposed
    - _Requirements: 8.3_
  - [ ] 4.4 Handle no-battery case (hide / not-applicable)
    - _Requirements: 8.4_
  - [ ] 4.5 Validate vs `pmset -g batt` / system info; write `phase-04` report
    - _Requirements: 14.5, 14.3_

---

## Phase 5 — Thermal, Fan & GPU (highest risk)

- [ ] 5. Implement thermal, fan, and GPU sampling
  - [ ] 5.1 Spike + ADR 0003: decide thermal/fan/power data source (AppleSMC keys vs IOReport) on the target hardware
    - _Requirements: 3.1, 14.1_
  - [ ] 5.2 `ThermalSampler` reads available sensors, human-readable names, °C with °F option; `.unavailable` + thermal pressure where exposed
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 11.3_
  - [ ] 5.3 `FanSampler` RPM + min/max bounds (read-only)
    - _Requirements: 4.1, 4.2_
  - [ ] 5.4 ADR 0004 + (if feasible) opt-in fan control within bounds via privileged helper; otherwise present read-only with explanation
    - _Requirements: 4.3, 4.4, 13.2_
  - [ ] 5.5 `GPUSampler` utilization, memory, temp/power where available; `.unavailable` otherwise
    - _Requirements: 5.1, 5.2, 5.3_
  - [ ] 5.6 ADR 0005 sandbox/entitlements decision; ensure graceful degradation when access denied
    - _Requirements: 13.1, 13.2_
  - [ ] 5.7 Validate vs `sudo powermetrics`; write `phase-05` report
    - _Requirements: 14.5, 14.3_

---

## Phase 6 — Polish, preferences & performance

- [ ] 6. Finalize configuration and footprint
  - [ ] 6.1 Preferences: enable/disable each category; configurable menu bar content; unit options (°C/°F, bytes/bits, IEC/SI)
    - _Requirements: 11.1, 11.3, 9.4_
  - [ ] 6.2 Launch at login via `SMAppService`; Dock-icon toggle
    - _Requirements: 11.5, 9.5_
  - [ ] 6.3 Persist all preferences across launches
    - _Requirements: 11.4_
  - [ ] 6.4 Performance pass: confirm sampling off main thread, measure iStats' own CPU at default interval, verify interval scaling reduces footprint
    - _Requirements: 12.1, 12.2, 12.4_
  - [ ] 6.5 Finalize all docs/ADRs; write `phase-06` report and project README
    - _Requirements: 14.1, 14.2, 14.3_
