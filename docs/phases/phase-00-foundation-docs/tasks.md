# Phase 0 — Documentation & Learning Baseline

**Goal:** Establish all the supporting documentation so the build is guided and the learning is captured from day one.

**Maps to Kiro spec task:** 0 (and sub-tasks 0.1–0.5)

## Tasks

- [ ] Create the `iStats/` source folder structure (App/Core/Sampling/UI/Resources, iStatsTests).
- [ ] Write `docs/prerequisites-and-learning.md` (done — keep updating per phase).
- [ ] Write the docs set: `overview.md`, `architecture.md`, `build-and-run.md`, `glossary.md` (done).
- [ ] Write `docs/phases/phase-plan.md` and create per-phase folders (done).
- [ ] Author ADRs 0001, 0002, 0006 (done); stub 0003, 0004, 0005.

## Learning focus
- Orient yourself: read `overview.md` → `prerequisites-and-learning.md` (Part 1) → `architecture.md`.
- Understand the counters-vs-rates concept before writing any sampler.

## Exit criteria
- All planning docs exist and are internally consistent with the Kiro spec.
- You can explain, in one paragraph each, the four data sources (sysctl, Mach, IOKit, SMC).
