# iStats agent roles

Four named roles share the building work. Instruction text lives **only** in this folder. Grok personas (`.grok/personas/`), Grok agents (`.grok/agents/`), and Claude agents (`.claude/agents/`) are thin wrappers that point here.

| Role | File | Writes code? | Default job |
|------|------|--------------|-------------|
| **Planner** | [`planner.md`](./planner.md) | No | Turn a phase/task into a concrete, sequenced plan |
| **Examiner** | [`examiner.md`](./examiner.md) | No | Map what exists, what the spec requires, and what is risky |
| **Implementor** | [`implementor.md`](./implementor.md) | Yes | Execute one plan slice; keep diffs small; prove with tests |
| **Orchestrator** | [`orchestrator.md`](./orchestrator.md) | Only coordination files | Split work, spawn sibling Herdr panes, merge results |

Use the names **planner**, **examiner**, **implementor**, **orchestrator**. Do not invent synonyms in pane names or handoff filenames.

---

## When to use which

```
User request
    │
    ▼
Orchestrator  ── decides whether the work needs a team or a single role
    │
    ├── Examiner   (unknown codebase area, "what is already here?")
    ├── Planner    (how should we implement this task/phase?)
    └── Implementor (the plan is accepted; write the code)
```

- One small, already-specified file change → skip the team; the current session may implement directly.
- A phase task (`1.4`, `2.1`, …) → examiner (if the area is unread) → planner → implementor.
- Several independent tasks after Phase 1 (for example CPU math tests vs a dummy sampler) → orchestrator may run sibling implementors, one task each.
- Never start implementor on thermal/fan/GPU (Phase 5) without an examiner spike and a planner that names the ADR outcome.

---

## Handoff files

Write working notes under [`docs/handoffs/`](../handoffs/):

```
docs/handoffs/<phase>-<task>-{exam,plan,summary}.md
```

Examples:

- `docs/handoffs/01-1.4-exam.md`
- `docs/handoffs/01-1.4-plan.md`
- `docs/handoffs/01-1.4-summary.md`

The next role **reads the previous file in full** before acting. Do not re-derive a plan from chat memory if a handoff file exists.

---

## Progress vs plan

- [`docs/progress.md`](../progress.md) — the only status file. Read it first. Update it when a task finishes.
- `docs/phases/` and `docs/specs/tasks.md` — what to build. Do not tick their checkboxes.

---

## Invariants every role obeys

These are restated so a spawned pane that only loaded this folder still cannot miss them. Detail lives in [`AGENTS.md`](../../AGENTS.md).

1. No `sysctl`, Mach, IOKit, SMC, or `IOPowerSources` on the main thread / `@MainActor`.
2. Sensor failure → `Availability.unavailable(reason:)`. Never crash the app.
3. Rates from counters go through `RateMath` (rollover / reset → 0, not a spike).
4. Live metrics stay in memory (`RingBuffer` / future `MetricsStore`). Only preferences persist.
5. Build/test with `--scratch-path /tmp/istats-build` on this machine.
6. Keep `docs/` in sync when behavior or architecture changes.

---

## How a session becomes a role

**Grok (same process):** `grok --agent planner` (or `examiner` / `implementor` / `orchestrator`). Definitions are in `.grok/agents/`.

**Grok subagent:** spawn `plan` or `explore` / `general-purpose` and tell it to follow the matching file in this folder. Project personas under `.grok/personas/` overlay the same instructions.

**Herdr sibling pane (orchestrator only, and only when `HERDR_ENV=1`):** split a pane, start a named agent, pass `grok --agent <role>`. See [`orchestrator.md`](./orchestrator.md).

**Claude Code:** project agents in `.claude/agents/` load the same files.
