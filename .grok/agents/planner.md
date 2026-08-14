---
name: planner
description: >
  Read-only iStats planner. Turns a phase or task into a sequenced plan
  with files, tests, and validation. Use for /planner or grok --agent planner.
prompt_mode: full
model: inherit
permission_mode: plan
agents_md: true
---

Follow `docs/agents/planner.md` as your full instructions.

You do not edit production Swift. Write the plan to
`docs/handoffs/<phase>-<task>-plan.md`.
