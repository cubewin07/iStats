# Phase 3 — Network & Disk — Requirements

## Goal of this phase

Add network throughput (per-interface + aggregate up/down, session totals, robust rate
math) and disk capacity/I-O for mounted volumes. Surface both in the detail view with a
bytes-vs-bits unit option for network. Validate against Activity Monitor (network) and
`df`.

## Requirements covered by this phase

### Requirement 6: Network monitoring

**User Story:** As a power user, I want to see network throughput, so that I can tell what
is using my bandwidth.

#### Acceptance Criteria

1. WHEN the app samples network THEN iStats SHALL report current upload and download
   throughput.
2. WHEN multiple interfaces are present THEN iStats SHALL report throughput per interface
   and an aggregate.
3. WHEN the app samples network THEN iStats SHALL report cumulative bytes sent/received for
   the session.
4. WHEN computing throughput THEN iStats SHALL derive rates from byte deltas between
   consecutive samples and handle counter resets without producing negative or absurd
   values.

### Requirement 7: Disk monitoring

**User Story:** As a power user, I want disk capacity and I/O, so that I can see storage
usage and disk activity.

#### Acceptance Criteria

1. WHEN the app samples disk THEN iStats SHALL report total, used, and free capacity for
   mounted volumes.
2. WHERE available, iStats SHALL report disk read/write throughput (I/O).
3. WHEN a volume is added or removed THEN iStats SHALL update the list of monitored volumes
   accordingly.

### Requirement 10.1 / 11.3: Presentation & units

#### Acceptance Criteria

1. WHEN the detail view is open THEN iStats SHALL display network and disk with current
   values (10.1).
2. WHERE the user opens preferences, iStats SHALL allow choosing bytes vs bits for network
   (11.3).

## Definition of done for Phase 3

- Network sampler reports per-interface + aggregate throughput and session totals.
- Rate math handles counter resets (never negative/absurd), property-tested.
- Disk sampler reports capacity per volume and reacts to volume add/remove.
- Disk I/O reported where accessible, else `.unavailable`.
- Network/disk render in the detail view; bytes/bits option available.
- Phase 3 report written, validated vs Activity Monitor / `df`.
