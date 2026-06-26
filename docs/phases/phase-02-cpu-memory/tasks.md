# Phase 2 — CPU & Memory

**Goal:** Real CPU and memory metrics, displayed live with rolling graphs, validated against Activity Monitor / `top`.

**Maps to Kiro spec task:** 2 (sub-tasks 2.1–2.7)

## Tasks
- [ ] `CPUSampler` via Mach `host_processor_info`; total + per-core %, user/system/idle from tick deltas.
- [ ] Load average via `sysctl vm.loadavg`; CPU frequency where available else `.unavailable`.
- [ ] Pure unit/property tests for CPU % math from synthetic counters (0–100% bounds, monotonic counters).
- [ ] `MemorySampler` via `host_statistics64(HOST_VM_INFO64)` + `sysctl hw.memsize`.
- [ ] Memory pressure level (normal/warning/critical) surfaced in UI.
- [ ] Render CPU + memory in detail view with live graphs; allow choosing what shows in the menu bar.
- [ ] Validate vs Activity Monitor / `top`; write `report.md`.

## Learning focus
- Mach host/processor info; the structure of CPU tick counters.
- Page size and converting page counts to bytes; macOS memory accounting (wired/active/compressed).
- The counters→rate computation in practice.

## Validation
- `top -l 2` second sample CPU vs iStats (within reason).
- Activity Monitor Memory tab: Memory Used, Swap, Pressure vs iStats.
- `vm_stat` and `sysctl vm.swapusage` cross-check.

## Exit criteria
- CPU and memory values track the references under idle and load.
- CPU math unit tests pass, including edge cases (counter wrap/reset).
