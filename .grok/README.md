# `.grok/` — project harness files

| Path | Role |
|------|------|
| `agents/` | Session agents (`grok --agent planner` …). Bodies point at `docs/agents/`. |
| `personas/` | Subagent overlays. `instructions_file` points at `docs/agents/`. |
| `skills/` | Domain skills for this repo (macOS APIs, SMC, concurrency, validation). |

Do not duplicate procedure here. Edit `docs/agents/` or the skill `SKILL.md`.
