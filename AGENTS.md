# AGENTS.md — Agent Specification for iStats

This document provides context, architectural constraints, and instructions for AI agents working in this repository.

---

## 1. Project Overview

**iStats** is a native macOS system monitoring application (menu bar + detail popover) inspired by iStat Menus. It surfaces live, detailed telemetry: CPU, memory, thermals, fans, GPU, network, disk, battery, and power.

- **Language / Platform**: Swift 6.0, macOS 13.0+ (Ventura or later).
- **UI Frameworks**: AppKit (`NSStatusItem`, `NSStatusBar`) + SwiftUI.
- **Hardware Target**: Primary target is Apple Silicon MacBooks (with graceful degradation for Intel where supported).
- **Core Repository**: Swift Package Manager (`Package.swift`) for `iStatsCore` + Xcode App Target (`iStats.xcodeproj` / `iStats/App`).

---

## 2. Architectural Principles & Invariants

```
Hardware / Kernel APIs
  │   (sysctl, Mach host_statistics, IOKit, AppleSMC, IOPowerSources, getifaddrs)
  ▼
Sampling Layer  ── One Sampler per category (background queues only)
  │   (catches errors, returns typed Sample<T>, never crashes)
  ▼
Domain Core (iStatsCore) ── SampleScheduler, MetricsStore (RingBuffer), Models, Pure Math
  │   (100% pure Swift, testable without hardware)
  ▼
Presentation ── MenuBarController (NSStatusItem) + SwiftUI Popover Views & Preferences
```

### Critical Rules for Agents:

1. **OS Call Isolation**: NEVER make system calls (`sysctl`, `host_statistics`, `IORegistryEntryCreateCFProperty`, SMC reads) on `@MainActor` or the UI thread. All sampling runs on background queues managed by `SampleScheduler`.
2. **Resilience & Graceful Degradation**: A missing sensor, permission denial, or unsupported hardware key MUST NOT crash the app. Always wrap failures in `Availability.unavailable(reason:)`.
3. **Pure Rate Math & Delta Handling**: Counters (CPU ticks, network bytes) are cumulative. Always compute rates via pure delta functions with counter-rollover and reset protection (see `RateMath.swift`).
4. **Privacy / No Telemetry Persistence**: Live metrics are held strictly in in-memory fixed-capacity ring buffers (`RingBuffer.swift`). Never write telemetry to disk or remote endpoints (ADR 0006). Only user preferences are persisted.
5. **Documentation Integrity**: When implementing features or changing architecture, keep the relevant files in `docs/` (specs, ADRs, phase reports) synchronized.

---

## 3. Essential Developer Commands

```bash
# Build the core library
swift build

# Run all unit tests
swift test

# Run a specific test suite
swift test --filter RateMathTests
swift test --filter RingBufferTests
swift test --filter UnitsTests

# Check for warnings or formatting
swift build -c release
```

---

## 4. Repository Structure

```
iStats/
├── Package.swift                      # SPM package configuration
├── Sources/
│   └── iStatsCore/                    # Pure domain models, ring buffer, rate math, protocols
├── Tests/
│   └── iStatsCoreTests/               # Unit and property tests for domain logic
├── docs/                              # Project documentation hub
│   ├── README.md                      # Documentation index
│   ├── specs/                         # Canonical requirements (EARS), design, master tasks
│   │   ├── requirements.md
│   │   ├── design.md
│   │   └── tasks.md
│   ├── architecture/                  # Architecture narration, overview, primer, and ADRs
│   │   ├── overview.md
│   │   ├── architecture.md
│   │   ├── swift-app-structure-primer.md
│   │   └── adr/                       # ADR 0001–0006
│   ├── guides/                        # Build & run, glossary, prerequisites & learning
│   │   ├── build-and-run.md
│   │   ├── glossary.md
│   │   └── prerequisites-and-learning.md
│   └── phases/                        # 7-phase delivery roadmap and per-phase specs
│       ├── README.md
│       └── phase-00-... to phase-06-...
└── README.md                          # Root repo introduction
```

---

## 5. Suggested Skills & Tooling for Future Agents

When further customizing or extending agent capabilities in this codespace, consider adding the following skills:

1. **`macos-system-apis`**: Reference guide for Mach kernel calls (`mach_host`), BSD `sysctl`, `IOKit` registry traversal, and `IOPowerSources`.
2. **`applesmc-iokit-spi`**: Helper and documentation for Apple Silicon SMC keys, IOReport channels, and thermal sensor discovery.
3. **`swift-concurrency-patterns`**: Best practices for `AsyncStream`, actor isolation, `@MainActor` publishers, and GCD timer schedulers.
4. **`metric-validation-suite`**: Automated CLI scripts comparing iStats sampler outputs against ground-truth reference tools (`top`, `df`, `pmset`, `powermetrics`).
