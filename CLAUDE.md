# CLAUDE.md — iStats Project Guide

This guide provides concise instructions, project architecture details, and coding conventions for working on the iStats codebase.

---

## 🛠️ Build & Test Commands

```bash
# Build the project
swift build

# Run all test suites
swift test

# Run a specific test suite
swift test --filter RateMathTests
swift test --filter RingBufferTests
swift test --filter UnitsTests

# Release build validation
swift build -c release
```

---

## 🏛️ Architecture Overview

- **Sampling Layer**: Talks to macOS kernel/hardware (`sysctl`, Mach `host_statistics`, IOKit, AppleSMC, `IOPowerSources`, `getifaddrs`). Runs strictly on background queues. Never throws unhandled exceptions; returns `Availability.unavailable(reason:)` on failure.
- **Domain Core (`iStatsCore`)**: Pure Swift value types, `RingBuffer`, `RateMath`, `SampleScheduler`, and units conversion. 100% testable without hardware dependencies.
- **Presentation Layer**: AppKit (`NSStatusItem`, `NSStatusBar`) for menu bar integration + SwiftUI for detail popover and preferences views.

---

## 📋 Coding Invariants & Conventions

1. **Thread Safety**: Never make system calls, IOKit queries, or SMC reads on the `@MainActor` / main thread.
2. **Resilience**: A failure in one metric sampler must never crash the app or block other samplers.
3. **Pure Math**: All rate computations (CPU %, MB/s) from tick/byte counters must be pure functions with counter-rollover protection and unit tests.
4. **Privacy**: Telemetry is ephemeral (kept in-memory in fixed-size ring buffers). Only user preferences are saved to disk (ADR 0006).

---

## 📚 Documentation Map

- **Master Specs**: [`docs/specs/requirements.md`](./docs/specs/requirements.md), [`docs/specs/design.md`](./docs/specs/design.md), [`docs/specs/tasks.md`](./docs/specs/tasks.md)
- **Architecture & ADRs**: [`docs/architecture/architecture.md`](./docs/architecture/architecture.md), [`docs/architecture/adr/`](./docs/architecture/adr/)
- **Developer Guides**: [`docs/guides/build-and-run.md`](./docs/guides/build-and-run.md), [`docs/guides/prerequisites-and-learning.md`](./docs/guides/prerequisites-and-learning.md)
- **Phased Implementation**: [`docs/phases/`](./docs/phases/) (Phases 00 to 06)
