# Phase 3 — Network & Disk

**Goal:** Network throughput and disk capacity/I/O, validated against Activity Monitor and `df`.

**Maps to Kiro spec task:** 3 (sub-tasks 3.1–3.6)

## Tasks
- [ ] `NetworkSampler` via `getifaddrs`/`if_data`; per-interface + aggregate up/down + session totals.
- [ ] Rate math from byte deltas; handle counter reset (never negative) — property tested.
- [ ] `DiskSampler` capacity (total/used/free) per mounted volume via `statfs`; react to volume add/remove.
- [ ] Disk I/O via IOKit block storage statistics (`.unavailable` if not accessible).
- [ ] Network/disk in detail view; unit option bytes vs bits for network.
- [ ] Validate vs Activity Monitor (network) and `df`; write `report.md`.

## Learning focus
- `getifaddrs` and per-interface counters; aggregating interfaces.
- Why counters reset and how to clamp negative deltas to zero.
- `statfs` capacity semantics; volume mount/unmount notifications.

## Validation
- Start a large download; compare iStats throughput to Activity Monitor → Network.
- `netstat -ib` sampled twice for byte deltas.
- `df -h` vs iStats capacity per volume.

## Exit criteria
- Throughput tracks references; capacity matches `df`; counter-reset test passes.
