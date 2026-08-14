# ADR 0002 — Threading and scheduling model

**Status:** Accepted

## Context
Some system reads (notably SMC/IOKit) can be slow or occasionally stall. The menu bar UI must stay responsive, the app's own footprint must stay low, and a failure in one sensor must not affect others (Requirements 12.1–12.4).

## Decision
Use a central **`SampleScheduler`** that runs samplers on a **background queue / Swift concurrency tasks**, one timer per metric category (categories may have different intervals). Each `sampler.sample()` call is wrapped in error handling and a time budget; results are published to the **`@MainActor`** layer via `AsyncStream`/`@Published`. The UI thread never performs a system call.

## Options considered
- **Central background scheduler with per-sampler isolation (chosen)** — clean separation, easy to throttle, resilient.
- **One timer on the main thread calling all samplers** — simplest, but a slow read freezes the UI; rejected.
- **A thread per sampler** — more isolation but heavier and harder to coordinate; unnecessary for this workload.

## Consequences
- Predictable, low CPU usage; intervals can scale to reduce footprint (Requirement 12.4).
- A hung/erroring sampler is contained and reported as `.unavailable` (Requirement 12.3).
- Requires discipline marshalling results back to the main actor; concurrency bugs are the main risk and are mitigated with value types and tests.
