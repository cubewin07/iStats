# iStats — Per-Phase Specifications

This folder breaks the iStats implementation plan into self-contained phases. Each
phase folder contains:

- `requirements.md` — the requirements (and acceptance criteria) that this phase satisfies,
  scoped down from the top-level [`requirements.md`](../requirements.md).
- `design.md` — the design slice relevant to this phase, scoped down from the top-level
  [`design.md`](../design.md).
- `tasks/` — one file per task. Each task file states **what to do** and the **goal**
  (definition of done) for that task. Task files do not repeat requirements or design;
  they reference the phase-level documents above.

The top-level [`requirements.md`](../requirements.md) and [`design.md`](../design.md)
remain the canonical, whole-project source of truth. These phase documents are derived
views that make each phase independently actionable.

## Phase index

| Phase | Folder | Theme |
|-------|--------|-------|
| 0 | [`phase-00-documentation`](./phase-00-documentation/) | Documentation scaffolding & learning baseline |
| 1 | [`phase-01-foundation`](./phase-01-foundation/) | Foundation — runnable menu bar app |
| 2 | [`phase-02-cpu-memory`](./phase-02-cpu-memory/) | CPU & Memory |
| 3 | [`phase-03-network-disk`](./phase-03-network-disk/) | Network & Disk |
| 4 | [`phase-04-battery-power`](./phase-04-battery-power/) | Battery & Power |
| 5 | [`phase-05-thermal-fan-gpu`](./phase-05-thermal-fan-gpu/) | Thermal, Fan & GPU (highest risk) |
| 6 | [`phase-06-polish-prefs`](./phase-06-polish-prefs/) | Polish, preferences & performance |
