---
name: swift-concurrency-patterns
description: >
  iStats threading model: SampleScheduler on background queues, Sendable
  samples, publish to @MainActor. Use when implementing the scheduler,
  view models, timers, AsyncStream, actors, or any code that might touch
  the main thread. ADR 0002.
---

# Swift concurrency (iStats)

ADR 0002 is accepted: one `SampleScheduler`, background work, per-sampler isolation, results hop to the main actor. UI never performs a system call.

## Layout

```
SampleScheduler  (not MainActor)
    │  timer per MetricCategory
    │  sample() off main, with time budget + catch
    ▼
Sample<T>  (Sendable value)
    ▼
MetricsStore / view models  (@MainActor)
    ▼
NSStatusItem + SwiftUI
```

## Rules

1. `Sampler.sample()` is synchronous and throwing today (`Sources/iStatsCore/Sampler.swift`). Call it from a background queue or unstructured task that is **not** `@MainActor`. Do not mark samplers `@MainActor`.
2. Types that cross threads are `Sendable`. Models already are. Do not add classes that mutate from two queues.
3. Publish with `AsyncStream` or `@Published` on a `@MainActor` type. The hop happens **after** the sample is a value type.
4. One failing or slow sampler cannot block the others: isolate each tick (separate task or `DispatchGroup` + timeout). Timeout → `SamplerError.timedOut` → `.unavailable`.
5. Intervals are per category and user-bounded (preferences). Changing the interval must change wake frequency (Requirement 12.4).
6. AppKit: create and mutate `NSStatusItem` on the main thread. Host SwiftUI with `NSHostingController` / `NSPopover` from the main thread. Feed them already-sampled values.

## Preferred shape (Phase 1)

- Scheduler owns enablement + interval config.
- Dummy sampler first, to prove: background call → main-actor publish → popover update.
- Tests for isolation and interval behavior should not need hardware (fake `Sampler`).

## Avoid

- `DispatchQueue.main.sync` from a sampler (deadlock risk).
- Starting IOKit / Mach work inside a SwiftUI `body` or `.onAppear` without hopping off main.
- A thread per sampler (rejected in ADR 0002).
- `@unchecked Sendable` to silence the compiler. Fix the type instead.

## UI split (ADR 0001)

- AppKit: `NSStatusItem`, popover chrome, `LSUIElement`.
- SwiftUI: detail graphs and preferences.
- View models stay `@MainActor` and dumb: they do not call Darwin.
