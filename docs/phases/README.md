# iStats — Master Phase Plan & Specifications

This directory contains the phased implementation plan and per-phase specification packages for iStats. Each phase is a self-contained increment that ends with a **runnable app**, passing tests, and a written **report**.

Phases are ordered so foundational, well-documented APIs come first and the riskiest, least-documented work (thermal/fan/GPU) comes later after building confidence.

## Phase Package Structure

Each phase folder is a self-contained module containing:
- `requirements.md` — The requirements (and acceptance criteria) satisfied by this phase, scoped from the master [`requirements.md`](../specs/requirements.md).
- `design.md` — The design slice for this phase, scoped from the master [`design.md`](../specs/design.md).
- `tasks.md` — The phase summary checklist, learning focus, and exit criteria.
- `report.md` — Completion report written at the end of the phase: what was built, what was learned, and metric validation against reference tools.
- `tasks/` — Individual task files (`X.Y-*.md`) stating exact implementation steps and definition of done for each subtask.

---

## Phase Map

| Phase | Folder | Theme | Key APIs | Risk | Exit criteria |
|-------|--------|-------|----------|------|---------------|
| **0** | [`phase-00-documentation`](./phase-00-documentation/) | Documentation & Learning Baseline | — | Low | Master specs, ADRs, prerequisites guide, and phase skeleton in place |
| **1** | [`phase-01-foundation`](./phase-01-foundation/) | App Foundation | AppKit, NSStatusItem, GCD | Low–Med | Menu bar app runs, scheduler + store + protocols in place, tests run |
| **2** | [`phase-02-cpu-memory`](./phase-02-cpu-memory/) | CPU & Memory | Mach host stats, sysctl | Med | CPU% and memory match Activity Monitor; graphs live |
| **3** | [`phase-03-network-disk`](./phase-03-network-disk/) | Network & Disk | getifaddrs, statfs, IOKit | Med | Throughput matches Activity Monitor; capacity matches `df` |
| **4** | [`phase-04-battery-power`](./phase-04-battery-power/) | Battery & Power | IOPowerSources, AppleSmartBattery | Med | Battery health matches `system_profiler`/`pmset` |
| **5** | [`phase-05-thermal-fan-gpu`](./phase-05-thermal-fan-gpu/) | Thermal, Fan & GPU | AppleSMC, IOKit, IOReport | **High** | Spike done; available sensors validated vs `powermetrics`; ADR 0003 finalized |
| **6** | [`phase-06-polish-prefs`](./phase-06-polish-prefs/) | Polish & Preferences | SwiftUI, SMAppService | Low–Med | All prefs persist; footprint measured; docs finalized |

---

## Dependency Flow

```
Phase 0 (docs) ──► Phase 1 (foundation) ──► Phase 2 (CPU/Mem)
                                              │
                         ┌────────────────────┼────────────────────┐
                         ▼                    ▼                    ▼
                   Phase 3 (Net/Disk)   Phase 4 (Battery)    (independent)
                         └────────────────────┴────────────────────┘
                                              │
                                              ▼
                                   Phase 5 (Thermal/Fan/GPU)  ← highest risk
                                              │
                                              ▼
                                   Phase 6 (Polish & Prefs)
```

Phases 2, 3, and 4 are largely independent after Phase 1 and could be reordered; the recommended order builds from most-documented to least.

---

## Definition of Done (Every Phase)

1. Code compiles and the app runs.
2. New pure domain logic has unit tests; all tests pass.
3. Each new metric is validated against its reference tool and the comparison is recorded in `report.md`.
4. Any new architectural decision is captured as or within an ADR in [`docs/architecture/adr/`](../architecture/adr/).
5. Relevant docs ([`architecture.md`](../architecture/architecture.md), [`prerequisites-and-learning.md`](../guides/prerequisites-and-learning.md)) are kept up to date.
