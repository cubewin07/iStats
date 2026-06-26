# iStats — Master Phase Plan (the skeleton)

This is the whole-project skeleton. Each phase is a self-contained increment that ends with a **runnable app** and a written **report**. Phases are ordered so foundational, well-documented APIs come first and the riskiest, least-documented work (thermal/fan/GPU) comes last, after you've built confidence.

Each phase folder contains:
- `tasks.md` — the concrete checklist for that phase (mirrors the Kiro spec tasks, with learning notes).
- `report.md` — written at the end: what was built, what was learned, and how each metric was validated against a reference tool.

## Phase map

| Phase | Theme | Key APIs | Risk | Exit criteria |
|-------|-------|----------|------|---------------|
| [0](phase-00-foundation-docs/tasks.md) | Docs & learning baseline | — | Low | Docs, ADRs, prerequisites guide, phase skeleton all exist |
| [1](phase-01-app-foundation/tasks.md) | App foundation | AppKit, NSStatusItem, GCD | Low–Med | Menu bar app runs, scheduler + store + protocols in place, tests run |
| [2](phase-02-cpu-memory/tasks.md) | CPU & Memory | Mach host stats, sysctl | Med | CPU% and memory match Activity Monitor; graphs live |
| [3](phase-03-network-disk/tasks.md) | Network & Disk | getifaddrs, statfs, IOKit | Med | Throughput matches Activity Monitor; capacity matches `df` |
| [4](phase-04-battery-power/tasks.md) | Battery & Power | IOPowerSources, AppleSmartBattery | Med | Battery health matches `system_profiler`/`pmset` |
| [5](phase-05-thermal-fan-gpu/tasks.md) | Thermal, Fan & GPU | AppleSMC, IOKit, IOReport | **High** | Spike done; available sensors validated vs `powermetrics`; ADR 0003 finalized |
| [6](phase-06-polish-prefs/tasks.md) | Polish & Preferences | SwiftUI, SMAppService | Low–Med | All prefs persist; footprint measured; docs finalized |

## Dependency flow

```
Phase 0 (docs) ──► Phase 1 (foundation) ──► Phase 2 (CPU/Mem)
                                              │
                         ┌────────────────────┼────────────────────┐
                         ▼                     ▼                    ▼
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

## Definition of Done (every phase)

1. Code compiles and the app runs.
2. New pure logic has unit tests; they pass.
3. Each new metric is validated against its reference tool and the comparison is recorded in `report.md`.
4. Any new decision is captured as/within an ADR.
5. Relevant docs (`architecture.md`, `prerequisites-and-learning.md`) are updated.

## How to use this with Kiro

The executable task list is `.kiro/specs/iStats/tasks.md`. These phase files are the richer, human-facing companion. When you finish a phase via Kiro, fill in that phase's `report.md` here.
