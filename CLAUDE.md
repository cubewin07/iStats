# CLAUDE.md — iStats

Native macOS menu bar monitor (Swift 6, AppKit + SwiftUI). Learning project. Full agent contract: [`AGENTS.md`](./AGENTS.md). Roles: [`docs/agents/`](./docs/agents/).

## Where we are

[`docs/progress.md`](./docs/progress.md) is the only status file. Read it before planning or implementing. Do not copy its tables here. Phase plans under `docs/phases/` say what to build; leave their checkboxes alone.

## Commands

Scratch path is required on this machine (SwiftPM `.build` hits disk I/O errors in-tree):

| Command | Purpose |
|---------|---------|
| `swift build --scratch-path /tmp/istats-build` | Build `iStatsCore` |
| `swift test --scratch-path /tmp/istats-build` | All package tests |
| `swift test --scratch-path /tmp/istats-build --filter RateMathTests` | One suite |
| `swift build -c release --scratch-path /tmp/istats-build` | Release check |

After Phase 1: `xcodebuild -scheme iStats -configuration Debug build`.

## Architecture (target)

Hardware APIs → Sampling (background, one `Sampler` per category) → `iStatsCore` (scheduler, ring buffers, pure math) → AppKit status item + SwiftUI popover.

Today only the pure core exists under `Sources/iStatsCore/`.

## Roles

`planner` / `examiner` / `implementor` / `orchestrator` — instructions in `docs/agents/<role>.md`. Handoffs in `docs/handoffs/`. Start with `grok --agent <role>`. Orchestrator: if `HERDR_ENV=1`, split a sibling Herdr pane and start `grok --agent <role>`; otherwise in-process subagents. Do not call `herdr` from outside Herdr.

## Invariants

- No `sysctl` / Mach / IOKit / SMC on `@MainActor`.
- Failures → `Availability.unavailable(reason:)`.
- Rates via `RateMath` (reset → 0).
- Telemetry in-memory only (ADR 0006). Preferences may persist.
- Fans read-only until ADR 0004 is satisfied.

## Skills

In-repo: `macos-system-apis`, `applesmc-iokit-spi`, `swift-concurrency-patterns`, `metric-validation`. Install extras only via [`docs/guides/skills-to-install.md`](./docs/guides/skills-to-install.md).

## Docs map

- Progress: `docs/progress.md` (status only)
- Specs: `docs/specs/{requirements,design,tasks}.md`
- ADRs: `docs/architecture/adr/`
- Phases: `docs/phases/`
- Learning / validation: `docs/guides/prerequisites-and-learning.md`
- Build: `docs/guides/build-and-run.md`

## Gotchas

- Trust `docs/progress.md` **On disk**, not the design wish-list, for which types exist.
- `powermetrics` / `top` / `pmset` are validation references, not production data sources.
