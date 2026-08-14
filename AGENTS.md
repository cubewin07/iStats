# AGENTS.md — iStats

Instructions for every agent working in this repository. Role procedures live in [`docs/agents/`](docs/agents/). Domain how-tos live in [`.grok/skills/`](.grok/skills/). Public-skill install work is a separate ticket: [`docs/guides/skills-to-install.md`](docs/guides/skills-to-install.md).

---

## 1. What this is

**iStats** is a native macOS menu bar monitor (AppKit `NSStatusItem` + SwiftUI popover) inspired by iStat Menus. It will show live CPU, memory, thermals, fans, GPU, network, disk, battery, and power.

- Swift 6.0, macOS 13+, Apple Silicon first (Intel degrades via `.unavailable`).
- SPM library `iStatsCore` today. Xcode app target is Phase 1 work (`iStats.xcodeproj` does not exist yet).

---

## 2. Where we are

Status lives in **one** file: [`docs/progress.md`](docs/progress.md). Read it. Do not copy its tables into this file.

Phase folders and [`docs/specs/tasks.md`](docs/specs/tasks.md) are the work breakdown (what a task is). Leave their checkboxes alone. When a task finishes, update `docs/progress.md` only.

---

## 3. Target architecture

```
Hardware / kernel APIs
  (sysctl, Mach, IOKit, AppleSMC, IOPowerSources, getifaddrs)
        │
        ▼
Sampling layer     one Sampler per category, background only
        │
        ▼
iStatsCore         SampleScheduler, MetricsStore (RingBuffer), models, RateMath
        │
        ▼
Presentation       MenuBarController + SwiftUI popover / preferences
```

### Invariants

1. **No OS calls on the main thread.** `sysctl`, Mach, IOKit, SMC, `IOPowerSources` run only on scheduler-owned background work (ADR 0002).
2. **Degrade, do not crash.** Missing sensor, denied access, bad `kern_return_t` → `Availability.unavailable(reason:)`.
3. **Rates are pure.** Counters go through `RateMath` (zero elapsed and counter reset → 0, never a negative spike).
4. **No telemetry on disk or the network** (ADR 0006). Only user preferences persist.
5. **Non-sandboxed** for v1 (ADR 0005). Still handle a single denied read.
6. **Fans read-only** until ADR 0004's gates are all true.
7. **Docs stay true.** If you change behavior or architecture, update the matching file under `docs/`.

---

## 4. Roles

| Role | When | Writes Swift? | Instructions |
|------|------|---------------|--------------|
| **planner** | How to implement a phase/task | No | [`docs/agents/planner.md`](docs/agents/planner.md) |
| **examiner** | What exists vs the spec | No | [`docs/agents/examiner.md`](docs/agents/examiner.md) |
| **implementor** | Execute an accepted plan | Yes | [`docs/agents/implementor.md`](docs/agents/implementor.md) |
| **orchestrator** | Run the team; Herdr sibling panes if `HERDR_ENV=1` | Coordination only | [`docs/agents/orchestrator.md`](docs/agents/orchestrator.md) |

Handoffs: `docs/handoffs/<phase>-<task>-{exam,plan,summary}.md`.

Start a dedicated session with `grok --agent planner` (same for the other three names). Wrappers: `.grok/agents/`, `.grok/personas/`, `.claude/agents/`.

Default sequence for a phase task: examiner → planner → implementor. A single obvious file edit does not need the team.

**Orchestrator + Herdr:** if `HERDR_ENV=1`, read the herdr skill, split a **sibling** pane in the current tab, same cwd, `--no-focus`, start a named agent (`planner` / `examiner` / `implementor`) running `grok --agent <role>`. The live `herdr` binary is the syntax authority. If not inside Herdr, use in-process subagents (`explore` / `plan` / `general-purpose`) and say so. Never call `herdr` from outside Herdr.

---

## 5. Commands

This folder can fail SwiftPM's default `.build` database ("disk I/O error"). Always use the scratch path:

```bash
swift build --scratch-path /tmp/istats-build
swift test  --scratch-path /tmp/istats-build
swift test  --scratch-path /tmp/istats-build --filter RateMathTests
swift test  --scratch-path /tmp/istats-build --filter RingBufferTests
swift test  --scratch-path /tmp/istats-build --filter UnitsTests
swift build -c release --scratch-path /tmp/istats-build
```

After Phase 1 creates the Xcode project:

```bash
xcodebuild -scheme iStats -configuration Debug build
xcodebuild test -scheme iStats -destination 'platform=macOS'
```

Do not claim tests passed unless you ran them.

---

## 6. Layout

```
Package.swift
Sources/iStatsCore/          # pure domain (today)
Tests/iStatsCoreTests/
docs/progress.md             # only status file
docs/specs/                  # canonical requirements, design, tasks
docs/architecture/adr/       # 0001–0006
docs/guides/                 # build, learning, glossary, skills-to-install
docs/phases/                 # phase-00 … phase-06 (plans, not status)
docs/agents/                 # role instructions (source of truth)
docs/handoffs/               # exam / plan / summary files
.grok/agents/  .grok/personas/  .grok/skills/
.claude/agents/
```

Intended app tree (Phase 1+): `iStats/App`, `iStats/Sampling`, `iStats/UI` depending on `iStatsCore`.

---

## 7. Skills

**Already in this repo** (do not replace with a random download):

| Skill | Use when |
|-------|----------|
| `macos-system-apis` | Any sampler / Darwin interop |
| `applesmc-iokit-spi` | Phase 5 thermal, fan, GPU, ADR 0003/0004 |
| `swift-concurrency-patterns` | Scheduler, view models, main-thread boundaries |
| `metric-validation` | End of a metric phase, `report.md` |

**To download later:** follow [`docs/guides/skills-to-install.md`](docs/guides/skills-to-install.md). Evaluate with that rubric. Do not install TCC-bypass or iOS-only kits.

**Herdr:** required for the orchestrator's pane workflow. Skill at `~/.agents/skills/herdr/`. Confirm `herdr` is on `PATH` before spawning.

---

## 8. Phase protocol

1. Open [`docs/progress.md`](docs/progress.md). Implement the **Next task** there, not a later phase.
2. Read the matching task file under `docs/phases/` for steps and definition of done.
3. Phases 2–4 are independent after Phase 1. Phase 5 is last among metrics (highest risk). Phase 6 is polish.
4. Every phase ends with: app or package still builds, new pure logic tested, metrics checked against a reference tool, `report.md` updated, ADRs updated if a decision changed.
5. Mark the task done in `docs/progress.md` only when the implementor summary and test commands justify it. Do not tick plan checkboxes.

---

## 9. Definition of done (any implementation pass)

- Compiles with the scratch-path commands above.
- New pure functions have tests; `swift test --scratch-path /tmp/istats-build` is green.
- No main-thread system calls introduced.
- Failures surface as `.unavailable`, not crashes or magic zeros.
- Handoff summary written if a role was used.
- Docs/ADRs/report match what shipped.
