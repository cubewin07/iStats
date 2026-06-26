# Phase 4 — Battery & Power — Requirements

## Goal of this phase

Add battery and power telemetry: charge/state/time-remaining, battery health (cycle count,
condition, design vs current capacity), instantaneous power draw/wattage and adapter power,
plus graceful handling of machines with no battery. Validate against `pmset -g batt`.

## Requirements covered by this phase

### Requirement 8: Battery and power monitoring

**User Story:** As a power user, I want battery health and power draw, so that I can
understand energy use and battery condition.

#### Acceptance Criteria

1. WHERE a battery is present, iStats SHALL report charge percentage, charging/discharging
   state, and time remaining when available.
2. WHERE available, iStats SHALL report battery health metrics: cycle count, condition, and
   design vs. current maximum capacity.
3. WHERE the hardware exposes it, iStats SHALL report instantaneous power draw / wattage
   (system and/or battery) and adapter power when plugged in.
4. WHEN no battery is present (e.g., desktop or unavailable) THEN iStats SHALL hide or mark
   battery metrics as not applicable.

## Definition of done for Phase 4

- Charge %, state, and time-remaining reported via `IOPowerSources`.
- Battery health (cycle count, condition, design vs current capacity) reported via the
  `AppleSmartBattery` registry.
- Power draw / wattage and adapter power reported where exposed.
- No-battery machines hide or mark battery metrics not-applicable.
- Phase 4 report written, validated vs `pmset -g batt`.
