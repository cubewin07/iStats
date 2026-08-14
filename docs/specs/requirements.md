# iStats — Requirements

## Introduction

iStats is a native macOS system monitoring application inspired by iStat Menus. It lives in the menu bar and surfaces live, detailed telemetry about the machine — CPU, memory, thermals, fans, GPU, network, disk, battery, and power — with a compact menu bar presentation and a richer detail view.

This is a learning project. The owner is an experienced full-stack developer (Spring Boot, React, some system design) with **no prior OS-level or native macOS experience**. Therefore the system must be understandable and thoroughly documented: Architecture Decision Records (ADRs), general docs, a phased delivery plan with per-phase reports and tasks, and a dedicated prerequisites/"what I need to learn" guide are first-class deliverables alongside the code.

**Tech stack:** Swift + SwiftUI/AppKit, native macOS. Target hardware is an Apple Silicon MacBook (must also degrade gracefully on Intel where reasonable).

**Out of scope for v1:** iOS/iPadOS companion apps, cloud sync, historical long-term storage/analytics dashboards, and remote monitoring of other machines.

---

## Glossary

- **SMC** — System Management Controller; source of many temperature/fan/power sensors.
- **IOKit** — Apple framework for talking to device drivers and hardware.
- **sysctl** — BSD interface for reading kernel state (CPU, memory, load).
- **Mach** — The kernel layer exposing host statistics (`host_statistics`, processor info).
- **Menu bar extra** — The status item shown in the macOS menu bar.
- **Sampler** — A component that reads one category of metrics at a configured interval.
- **Sample** — One timestamped reading from a sampler.

---

## Requirements

### Requirement 1: CPU monitoring

**User Story:** As a power user, I want to see CPU usage and load in real time, so that I can tell when the machine is under heavy load and which behavior caused it.

#### Acceptance Criteria

1. WHEN the app is running THEN iStats SHALL sample total CPU utilization at the configured refresh interval.
2. WHEN the app samples the CPU THEN iStats SHALL report per-core utilization in addition to the aggregate.
3. WHERE the hardware exposes it, iStats SHALL report CPU frequency and the system load average (1/5/15 minute).
4. WHEN displaying CPU utilization THEN iStats SHALL distinguish user, system, and idle time.
5. IF a CPU metric is unavailable on the current hardware THEN iStats SHALL mark that metric as "unavailable" rather than displaying a misleading zero.

### Requirement 2: Memory monitoring

**User Story:** As a power user, I want detailed memory information, so that I can understand memory pressure and swap behavior when I run heavy workloads.

#### Acceptance Criteria

1. WHEN the app samples memory THEN iStats SHALL report used, free, active, inactive, wired, and cached/compressed memory.
2. WHEN the app samples memory THEN iStats SHALL report swap used and the macOS memory pressure level (normal/warning/critical).
3. WHEN total physical memory is queried THEN iStats SHALL report it accurately for the host.
4. WHEN memory pressure transitions to warning or critical THEN iStats SHALL surface that state visibly in the UI.

### Requirement 3: Thermal / temperature monitoring

**User Story:** As a power user, I want to read temperature sensors, so that I can see how hot the machine gets under load.

#### Acceptance Criteria

1. WHERE temperature sensors are accessible, iStats SHALL read available thermal sensors (e.g., CPU, GPU, and other SMC-exposed sensors).
2. WHEN reading temperatures THEN iStats SHALL label each sensor with a human-readable name and report values in °C (with a user option for °F).
3. IF temperature sensors are not accessible on the current OS/hardware/entitlement configuration THEN iStats SHALL clearly indicate that thermal data is unavailable and SHALL NOT crash or block other metrics.
4. WHERE the OS exposes it, iStats SHALL report the system thermal pressure/state.

### Requirement 4: Fan monitoring (and control where feasible)

**User Story:** As a power user, I want to see fan speeds and, if possible, control them, so that I can manage cooling during sustained load.

#### Acceptance Criteria

1. WHERE fan sensors are accessible, iStats SHALL report current RPM for each fan.
2. WHERE the hardware exposes them, iStats SHALL report minimum and maximum RPM bounds per fan.
3. IF fan control is technically and safely feasible on the target hardware THEN iStats SHALL allow setting fan speed within hardware-reported bounds; OTHERWISE iStats SHALL present fans as read-only.
4. WHEN fan control is not supported THEN iStats SHALL clearly communicate that fans are read-only and explain why.

### Requirement 5: GPU monitoring

**User Story:** As a power user, I want GPU utilization and related stats, so that I can see graphics/compute load.

#### Acceptance Criteria

1. WHERE the hardware exposes it, iStats SHALL report GPU utilization.
2. WHERE available, iStats SHALL report GPU memory usage and GPU-related temperature/power.
3. IF GPU metrics are unavailable THEN iStats SHALL mark them unavailable without affecting other metrics.

### Requirement 6: Network monitoring

**User Story:** As a power user, I want to see network throughput, so that I can tell what is using my bandwidth.

#### Acceptance Criteria

1. WHEN the app samples network THEN iStats SHALL report current upload and download throughput.
2. WHEN multiple interfaces are present THEN iStats SHALL report throughput per interface and an aggregate.
3. WHEN the app samples network THEN iStats SHALL report cumulative bytes sent/received for the session.
4. WHEN computing throughput THEN iStats SHALL derive rates from byte deltas between consecutive samples and handle counter resets without producing negative or absurd values.

### Requirement 7: Disk monitoring

**User Story:** As a power user, I want disk capacity and I/O, so that I can see storage usage and disk activity.

#### Acceptance Criteria

1. WHEN the app samples disk THEN iStats SHALL report total, used, and free capacity for mounted volumes.
2. WHERE available, iStats SHALL report disk read/write throughput (I/O).
3. WHEN a volume is added or removed THEN iStats SHALL update the list of monitored volumes accordingly.

### Requirement 8: Battery and power monitoring

**User Story:** As a power user, I want battery health and power draw, so that I can understand energy use and battery condition.

#### Acceptance Criteria

1. WHERE a battery is present, iStats SHALL report charge percentage, charging/discharging state, and time remaining when available.
2. WHERE available, iStats SHALL report battery health metrics: cycle count, condition, and design vs. current maximum capacity.
3. WHERE the hardware exposes it, iStats SHALL report instantaneous power draw / wattage (system and/or battery) and adapter power when plugged in.
4. WHEN no battery is present (e.g., desktop or unavailable) THEN iStats SHALL hide or mark battery metrics as not applicable.

### Requirement 9: Menu bar presentation

**User Story:** As a user, I want a compact menu bar display, so that I can glance at key metrics without opening a window.

#### Acceptance Criteria

1. WHEN the app launches THEN iStats SHALL install a menu bar status item.
2. WHEN metrics update THEN iStats SHALL update the menu bar display at the configured refresh interval without blocking the UI.
3. WHEN the user clicks the status item THEN iStats SHALL present a detail view (popover or window) with full metrics.
4. WHERE the user configures it, iStats SHALL allow choosing which metric(s) appear directly in the menu bar.
5. WHEN running as a menu bar app THEN iStats SHALL be able to run without a Dock icon (configurable).

### Requirement 10: Detailed metrics view

**User Story:** As a user, I want a detailed view with history graphs, so that I can see trends over the recent past, not just instantaneous values.

#### Acceptance Criteria

1. WHEN the user opens the detail view THEN iStats SHALL display all enabled metric categories with current values.
2. WHEN displaying a metric over time THEN iStats SHALL show a rolling short-term history graph (e.g., last N minutes held in memory).
3. WHEN the detail view is open THEN iStats SHALL refresh values live at the configured interval.

### Requirement 11: Configuration and preferences

**User Story:** As a user, I want to configure what's shown and how often, so that the app fits my workflow and resource budget.

#### Acceptance Criteria

1. WHERE the user opens preferences, iStats SHALL allow enabling/disabling each metric category.
2. WHERE the user opens preferences, iStats SHALL allow setting the refresh interval (with sane min/max bounds).
3. WHERE the user opens preferences, iStats SHALL allow choosing units (°C/°F, bytes vs. bits for network, etc.).
4. WHEN preferences change THEN iStats SHALL persist them across launches.
5. WHERE the user enables it, iStats SHALL support launch at login.

### Requirement 12: Performance and resource footprint

**User Story:** As a power user, I want the monitor itself to be lightweight, so that it doesn't distort the very measurements I'm trying to read.

#### Acceptance Criteria

1. WHEN sampling metrics THEN iStats SHALL perform reads off the main thread and publish results to the UI thread.
2. WHEN idle in the menu bar at the default interval THEN iStats SHALL keep its own CPU usage low (target: low single-digit percent on the target hardware).
3. WHEN a sampler fails or a sensor read errors THEN iStats SHALL isolate the failure to that sampler and continue updating the others.
4. WHEN the refresh interval is increased THEN iStats SHALL reduce sampling frequency accordingly to lower its footprint.

### Requirement 13: Permissions, entitlements, and security posture

**User Story:** As a user, I want clear handling of permissions, so that I know what access the app needs and why.

#### Acceptance Criteria

1. WHEN a metric requires elevated access or a specific entitlement THEN iStats SHALL document the requirement and degrade gracefully if it is not granted.
2. IF an operation requires a privileged helper (e.g., certain low-level reads or fan control) THEN iStats SHALL clearly state this as a design decision in an ADR and SHALL NOT silently escalate privileges.
3. WHEN handling sensor/system data THEN iStats SHALL keep all data local and SHALL NOT transmit it off the machine.

### Requirement 14: Learning and documentation deliverables

**User Story:** As a developer learning OS-level macOS development, I want the project to teach me as it's built, so that I can understand, validate, and extend the code with confidence.

#### Acceptance Criteria

1. WHEN the project is planned THEN iStats SHALL include Architecture Decision Records (ADRs) capturing key technical choices (frameworks per metric, threading model, privilege model, persistence, etc.).
2. WHEN the project is planned THEN iStats SHALL include a general documentation set (project overview, architecture, build/run instructions, glossary).
3. WHEN the project is planned THEN iStats SHALL include a phased delivery plan with a skeleton for the whole project, AND each phase SHALL have its own report and task list.
4. WHEN the project is planned THEN iStats SHALL include a dedicated prerequisites/"what I need to learn" document covering relevant OS concepts and macOS frameworks (sysctl, Mach host stats, IOKit, SMC, IOReport/powermetrics concepts, SwiftUI/AppKit menu bar patterns) and how to validate each category of metric against a known-good reference (Activity Monitor, `top`, `powermetrics`, etc.).
5. WHERE a metric is implemented THEN the documentation SHALL describe how to verify its correctness against a reference tool.

---

## Non-Functional Requirements

- **Platform:** macOS (target current major version; note minimum supported version as an ADR). Primary target Apple Silicon; graceful degradation on Intel where reasonable.
- **Language/UI:** Swift, SwiftUI for views with AppKit interop for the menu bar where needed.
- **Privacy:** All data stays on-device.
- **Reliability:** A failure in one sampler must not crash the app or stop other samplers.
- **Maintainability:** Clear separation between sampling (data acquisition), domain model, and presentation, to keep the OS-specific code isolated and testable.
- **Testability:** Pure computation (rate derivation, unit conversion, aggregation) must be unit-testable independent of hardware.
