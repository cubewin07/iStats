# Phase 0 — Documentation Scaffolding & Learning Baseline — Design

This phase produces no runtime code. It builds the **documentation architecture** that the
rest of the project depends on. See the top-level [`design.md`](../../design.md) for the
full picture; the slice below is what Phase 0 delivers.

## Project structure (skeleton to create)

```
iStats/
├── README.md
├── docs/
│   ├── overview.md
│   ├── architecture.md
│   ├── build-and-run.md
│   ├── glossary.md
│   ├── prerequisites-and-learning.md     # "what I need to learn" + how to validate each metric
│   ├── adr/
│   │   ├── 0001-language-and-ui-stack.md
│   │   ├── 0002-threading-and-scheduling-model.md
│   │   └── 0006-telemetry-privacy-no-persistence.md
│   └── phases/
│       ├── phase-plan.md                  # whole-project skeleton + phase index
│       └── phase-NN-*/{tasks.md,report.md}
├── iStats/            # app target (App/Core/Sampling/UI/Resources)
└── iStatsTests/       # unit tests for Core
```

## Documentation architecture

| Document | Purpose |
|----------|---------|
| `overview.md` | What iStats is, who it's for, scope and non-goals |
| `architecture.md` | Layered design (Sampling → Core → UI), threading model |
| `build-and-run.md` | How to build, run, and debug the app locally |
| `glossary.md` | SMC, IOKit, sysctl, Mach, sampler, sample, menu bar extra |
| `prerequisites-and-learning.md` | OS concepts + macOS frameworks to study, and a per-metric "validate against reference tool" checklist |
| `adr/000X-*.md` | One decision per file, in standard ADR format |
| `phases/phase-plan.md` | Whole-project skeleton + index of phases |

## ADRs authored in this phase

- **0001 — Language & UI stack:** Swift + SwiftUI/AppKit native (vs Tauri/Electron),
  chosen for OS learning and full API access.
- **0002 — Threading & scheduling model:** background `SampleScheduler` with per-sampler
  isolation; results published to the main actor.
- **0006 — Telemetry privacy / no persistence:** telemetry stays in-memory only;
  only preferences are persisted; data never leaves the device.

> ADRs 0003 (thermal/fan data source), 0004 (privilege & fan control), and 0005
> (sandbox & entitlements) are authored later, in the phases where those decisions
> become concrete (Phase 5).

## Validation-against-reference map (seed for the learning guide)

| Metric category | Reference tool to cross-check against |
|-----------------|----------------------------------------|
| CPU / load | Activity Monitor, `top` |
| Memory / pressure | Activity Monitor |
| Network throughput | Activity Monitor (Network tab) |
| Disk capacity | `df` |
| Battery / power | `pmset -g batt` |
| Thermal / fan / GPU | `sudo powermetrics` |
