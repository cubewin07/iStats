# ADR 0006 — Telemetry privacy / no persistence

**Status:** Accepted

## Context
iStats reads detailed information about the machine. Some monitors offer history/export. The author's priority is privacy and simplicity (Requirement 13.3).

## Decision
All telemetry stays **on the device** and is held **in memory only** (a short rolling window in `MetricsStore` for graphs). iStats does **not** write telemetry to disk and does **not** transmit it anywhere. Only **user preferences** are persisted (UserDefaults/JSON).

## Options considered
- **In-memory only, preferences persisted (chosen)** — simplest, most private, fits v1's short-term-history goal.
- **Persist historical telemetry to disk** — enables long-term trends but adds storage, privacy, and schema concerns; deferred (it's a stated non-goal for v1).
- **Optional cloud sync** — explicit non-goal.

## Consequences
- History resets when the app restarts; acceptable for v1.
- No telemetry files to secure or leak.
- If long-term history is ever wanted, it needs a new ADR covering storage format, retention, and privacy.
