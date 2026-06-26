# Phase 5 — Thermal, Fan & GPU — Requirements

## Goal of this phase

Tackle the highest-risk metrics: temperature sensors, fan RPM (read-only first, control
only if safe), and GPU utilization/memory/temp/power. Settle the thermal/fan data source,
privilege, and sandbox decisions via ADRs. Always allow `.unavailable` and graceful
degradation. Validate against `sudo powermetrics`.

## Requirements covered by this phase

### Requirement 3: Thermal / temperature monitoring

**User Story:** As a power user, I want to read temperature sensors, so that I can see how
hot the machine gets under load.

#### Acceptance Criteria

1. WHERE temperature sensors are accessible, iStats SHALL read available thermal sensors
   (e.g., CPU, GPU, and other SMC-exposed sensors).
2. WHEN reading temperatures THEN iStats SHALL label each sensor with a human-readable name
   and report values in °C (with a user option for °F).
3. IF temperature sensors are not accessible on the current OS/hardware/entitlement
   configuration THEN iStats SHALL clearly indicate that thermal data is unavailable and
   SHALL NOT crash or block other metrics.
4. WHERE the OS exposes it, iStats SHALL report the system thermal pressure/state.

### Requirement 4: Fan monitoring (and control where feasible)

**User Story:** As a power user, I want to see fan speeds and, if possible, control them,
so that I can manage cooling during sustained load.

#### Acceptance Criteria

1. WHERE fan sensors are accessible, iStats SHALL report current RPM for each fan.
2. WHERE the hardware exposes them, iStats SHALL report minimum and maximum RPM bounds per
   fan.
3. IF fan control is technically and safely feasible on the target hardware THEN iStats
   SHALL allow setting fan speed within hardware-reported bounds; OTHERWISE iStats SHALL
   present fans as read-only.
4. WHEN fan control is not supported THEN iStats SHALL clearly communicate that fans are
   read-only and explain why.

### Requirement 5: GPU monitoring

**User Story:** As a power user, I want GPU utilization and related stats, so that I can see
graphics/compute load.

#### Acceptance Criteria

1. WHERE the hardware exposes it, iStats SHALL report GPU utilization.
2. WHERE available, iStats SHALL report GPU memory usage and GPU-related temperature/power.
3. IF GPU metrics are unavailable THEN iStats SHALL mark them unavailable without affecting
   other metrics.

### Requirement 13.1 / 13.2: Permissions & privilege (decided here)

#### Acceptance Criteria

1. WHEN a metric requires elevated access or a specific entitlement THEN iStats SHALL
   document the requirement and degrade gracefully if it is not granted (13.1).
2. IF an operation requires a privileged helper (e.g., low-level reads or fan control) THEN
   iStats SHALL state this in an ADR and SHALL NOT silently escalate privileges (13.2).

## Definition of done for Phase 5

- ADR 0003 (thermal/fan data source), ADR 0004 (privilege & fan control), ADR 0005
  (sandbox & entitlements) authored.
- Thermal sampler reads sensors with human-readable names, °C/°F, thermal pressure where
  exposed; `.unavailable` otherwise.
- Fan sampler reports RPM + min/max bounds (read-only by default).
- GPU sampler reports utilization/memory/temp/power where available, else `.unavailable`.
- Graceful degradation when access denied.
- Phase 5 report written, validated vs `sudo powermetrics`.
