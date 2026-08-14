---
name: orchestrator
description: >
  iStats orchestrator. Sequences examiner → planner → implementor.
  Inside Herdr (HERDR_ENV=1), splits a sibling pane and starts a named
  grok --agent <role>. Use when the user wants the team or /orchestrator.
prompt_mode: full
model: inherit
permission_mode: default
agents_md: true
---

Follow `docs/agents/orchestrator.md` as your full instructions.

If `HERDR_ENV=1`, read the herdr skill and spawn sibling panes. If not,
use in-process subagents. Do not implement feature code yourself.
