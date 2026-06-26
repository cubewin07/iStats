# iStats Documentation

This folder is the human-readable home for everything about how iStats is designed, planned, and learned. It is intentionally separate from the Kiro spec (`.kiro/specs/iStats/`) so the planning is easy to browse and manage on its own.

## How this folder is organized

| Folder / file | Purpose |
|---------------|---------|
| `overview.md` | What iStats is, who it's for, and the goals/non-goals. Start here. |
| `architecture.md` | The system design in prose + diagrams: layers, components, data flow, threading. |
| `build-and-run.md` | How to build, run, and debug the app locally. |
| `glossary.md` | Definitions of every OS/macOS term used in the project. |
| `prerequisites-and-learning.md` | **The learning guide.** What you need to understand before each phase, and how to validate every metric against a trusted reference tool. |
| `adr/` | Architecture Decision Records — one file per significant decision, with context, options, and consequences. |
| `phases/` | The phased delivery plan. `phase-plan.md` is the master skeleton; each `phase-XX-*/` folder has its own `tasks.md` and `report.md`. |

## Relationship to the Kiro spec

- `.kiro/specs/iStats/requirements.md` — the formal requirements (EARS).
- `.kiro/specs/iStats/design.md` — the canonical design; `architecture.md` here is the narrated, teaching-oriented version of it.
- `.kiro/specs/iStats/tasks.md` — the executable task list Kiro runs; `phases/` here is the richer, human-facing breakdown with learning notes and per-phase reports.

## Suggested reading order for a newcomer

1. `overview.md`
2. `prerequisites-and-learning.md` (sections for Phase 1–2)
3. `architecture.md`
4. `phases/phase-plan.md`
5. The relevant `adr/` entries as you reach each decision.
