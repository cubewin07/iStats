# Phase 4 — Battery & Power — Design

The slice of the architecture this phase builds. See the top-level
[`design.md`](../../design.md) for the complete design.

## API mapping for this phase

| Metric | Primary API | Notes / risk |
|--------|-------------|--------------|
| Charge / state / time remaining | `IOPowerSources` | No special entitlement needed |
| Battery health (cycles, condition, capacity) | `AppleSmartBattery` IOKit registry | Read registry properties |
| Power draw / wattage, adapter power | SMC power keys / IOReport | May be `.unavailable` on some hardware |
| No-battery case | `IOPowerSources` returns no internal battery | Hide / mark not-applicable |

## Data model additions

```swift
struct PowerSample {
    let hasBattery: Bool
    let charge: Double?            // 0...100
    let state: BatteryState?       // charging / discharging / charged
    let timeRemaining: TimeInterval?
    let cycleCount: Int?
    let condition: String?
    let designCapacity: Int?
    let currentMaxCapacity: Int?
    let powerDrawWatts: Double?    // .unavailable -> nil
    let adapterWatts: Double?
}
```

## Sampler

- `PowerSampler` — reads `IOPowerSources` for charge/state/time, the `AppleSmartBattery`
  registry for health, and SMC/IOReport for wattage where exposed.
- When no internal battery exists, sets `hasBattery = false`; the UI hides or marks battery
  metrics not-applicable (Requirement 8.4).
- Any unexposed field degrades to `nil` / `.unavailable` rather than a misleading zero.

## Validation

Cross-check charge, state, time-remaining, and health against `pmset -g batt` and System
Information.
