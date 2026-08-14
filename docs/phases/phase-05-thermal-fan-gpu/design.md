# Phase 5 — Thermal, Fan & GPU — Design

The slice of the architecture this phase builds. See the top-level
[`design.md`](../../specs/design.md) for the complete design.

> **Highest design risk.** Thermal/fan/power-via-SMC is the least documented and most
> fragile area, especially on Apple Silicon. SMC keys differ across hardware. The design
> always allows `.unavailable` and never blocks other metrics on a failed read here.

## API mapping for this phase

| Metric | Primary API | Notes / risk |
|--------|-------------|--------------|
| Temperatures | AppleSMC via IOKit (SMC keys) **or** IOReport/IOHID energy sensors | Keys differ by hardware → ADR 0003 |
| Fans | AppleSMC keys (FNum, F0Ac, …) | Control likely needs privileged helper → default read-only |
| GPU | IOKit (`IOAccelerator`/`AGXAccelerator`) performance stats | Keys vary by GPU; mark `.unavailable` when absent |

## ADRs authored in this phase

- **0003 — Thermal/fan data source:** decide AppleSMC keys vs IOReport on the target
  hardware, after a spike.
- **0004 — Privilege & fan control:** read-only by default; fan control only via a
  privileged helper (`SMAppService`/launchd) and opt-in; never silent escalation.
- **0005 — Sandbox & entitlements:** non-sandboxed for development; document the sandbox
  tradeoffs and graceful degradation when access is denied.

## Data model additions

```swift
struct ThermalSample { let sensors: [SensorReading]; let pressure: ThermalPressure? }
struct SensorReading { let name: String; let celsius: Double }
struct FanSample { let fans: [FanReading] }
struct FanReading { let name: String; let rpm: Int; let minRPM: Int?; let maxRPM: Int? }
struct GPUSample { let utilization: Double?; let memoryUsed: UInt64?
                   let tempCelsius: Double?; let powerWatts: Double? }
```

## Samplers

- `ThermalSampler` — reads available sensors, assigns human-readable names, reports °C
  (°F option via converter), and thermal pressure where exposed; `.unavailable` otherwise.
- `FanSampler` — RPM + min/max bounds, read-only.
- `GPUSampler` — utilization, memory, temp/power where available; `.unavailable` otherwise.

## Resilience

Every read in this phase is wrapped so a missing/blocked SMC key or GPU stat degrades to
`.unavailable` without crashing or stopping the other samplers (Requirement 3.3, 5.3,
13.1).

## Validation

Cross-check temperatures, fan RPM, and GPU stats against `sudo powermetrics`.
