# iStats — Project Overview

## What it is

iStats is a native macOS menu bar application that samples and displays live system telemetry: CPU, memory, thermals, fans, GPU, network, disk, battery, and power. It shows a compact view in the menu bar and a richer detail view with short-term history graphs. It is inspired by iStat Menus.

## Who it's for

The primary user is the developer building it — someone who pushes their MacBook hard and wants deep, trustworthy visibility into what the machine is doing. It is also a **learning vehicle**: the author is an experienced full-stack developer (Spring Boot, React, system design) with no prior OS-level or native macOS experience.

## Goals

1. **Accurate, trustworthy metrics** — every number can be cross-checked against a known-good reference tool (Activity Monitor, `top`, `df`, `pmset`, `powermetrics`).
2. **Low overhead** — the monitor must not meaningfully distort what it measures.
3. **Resilience** — one failing sensor must never crash the app or stop the others.
4. **Understandability** — the OS-specific code is isolated and documented so the author can explain every line.
5. **Incremental delivery** — each phase produces a runnable app and a written report of what was learned and verified.

## Non-goals (v1)

- iOS/iPadOS companion apps.
- Cloud sync or remote monitoring of other machines.
- Long-term historical storage / analytics dashboards (only short-term in-memory history).
- Selling or distributing the app (it's a personal/learning build).

## The mental model (for someone from a web background)

Think of each metric category as a "data source" (like a repository in Spring). A scheduler polls each source on its own interval, off the main thread (like a background job). The results flow into an in-memory store (like a short-lived cache / ring buffer), and the UI subscribes to that store (like a React component subscribing to state). The unfamiliar part is *where the data comes from*: instead of a database or HTTP API, it comes from kernel and hardware APIs (Mach, sysctl, IOKit, SMC). That OS boundary is exactly what this project teaches.

## Success criteria

- All v1 metric categories implemented, each validated against a reference tool and the validation recorded in the relevant phase report.
- iStats' own CPU usage stays low at the default refresh interval.
- The app degrades gracefully (marks metrics "unavailable") rather than crashing when a sensor or API is inaccessible.
- The docs, ADRs, and phase reports are complete enough that another developer could pick up the project.
