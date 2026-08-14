# iStats

A native macOS system monitoring app (menu bar + detail view) inspired by iStat Menus. Built with Swift + SwiftUI/AppKit. This is a learning project for understanding macOS at the OS level.

Tracks: CPU, memory, thermals, fans, GPU, network, disk, battery, and power.

## Documentation & Specifications

All specifications, architectural designs, guides, and implementation plans live under [`docs/`](./docs/):

- **Master Specifications**:
  - [`docs/specs/requirements.md`](./docs/specs/requirements.md) — What the app must do (EARS format)
  - [`docs/specs/design.md`](./docs/specs/design.md) — System architecture, macOS API map per metric, threading, and privilege model
  - [`docs/specs/tasks.md`](./docs/specs/tasks.md) — Master implementation task list
- **Architecture & ADRs**:
  - [`docs/architecture/overview.md`](./docs/architecture/overview.md) — Project overview, mental model, and goals
  - [`docs/architecture/architecture.md`](./docs/architecture/architecture.md) — Layered architecture narration
  - [`docs/architecture/adr/`](./docs/architecture/adr/) — Architecture Decision Records
- **Developer Guides**:
  - [`docs/guides/build-and-run.md`](./docs/guides/build-and-run.md) — Local build & run instructions
  - [`docs/guides/prerequisites-and-learning.md`](./docs/guides/prerequisites-and-learning.md) — OS concepts & metric validation guide
  - [`docs/guides/glossary.md`](./docs/guides/glossary.md) — macOS OS/kernel glossary
- **Phased Implementation**:
  - [`docs/phases/`](./docs/phases/) — 7-phase delivery roadmap, scoped phase specs, and validation reports

## Repo

Remote: https://github.com/cubewin07/iStats.git
