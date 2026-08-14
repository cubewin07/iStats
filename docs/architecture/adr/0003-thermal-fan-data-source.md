# ADR 0003 — Thermal/fan/power data source

**Status:** Proposed (to be confirmed by a spike in Phase 5)

## Context
Temperature, fan, and some power metrics historically come from the **SMC** via IOKit, using undocumented 4-character keys (e.g., `TC0P`, `F0Ac`). On **Apple Silicon** many classic SMC keys differ, are absent, or are replaced by data exposed through **IOReport** / surfaced by Apple's `powermetrics` tool. There is no stable public API. This is the highest-risk area of the project.

## Decision (provisional)
Treat the data source as **pluggable**. Implement an SMC-key reader first; if keys are unavailable on the target hardware, fall back to an IOReport-based approach for the metrics it can provide. Run a **spike in Phase 5** on the actual target Mac to discover which keys/sources work, then finalize this ADR with the concrete findings (which keys map to which sensors).

## Options considered
- **AppleSMC key reads** — works on many Macs, well-trodden on Intel; fragile and partial on Apple Silicon.
- **IOReport** — closer to what `powermetrics` uses for power/thermal on Apple Silicon; less documented, more complex.
- **Shelling out to `powermetrics`** — accurate but requires root and spawning a process; rejected for a always-on monitor, though useful as a validation reference.

## Consequences
- Thermal/fan/GPU metrics may be partially `.unavailable` depending on hardware; the UI must handle this gracefully (Requirement 3.3).
- The spike's findings (concrete keys/sources per sensor) become essential documentation in the Phase 5 report.
- This ADR will be updated to **Accepted** with specifics once the spike completes.
