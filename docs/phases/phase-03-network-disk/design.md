# Phase 3 — Network & Disk — Design

The slice of the architecture this phase builds. See the top-level
[`design.md`](../../specs/design.md) for the complete design.

## API mapping for this phase

| Metric | Primary API | Notes / risk |
|--------|-------------|--------------|
| Network throughput | `getifaddrs` + `if_data` byte counters | Rate = Δbytes / Δtime; handle counter reset |
| Disk capacity | `statfs` per mounted volume | Enumerate volumes; react to add/remove |
| Disk I/O | IOKit (`IOBlockStorageDriver` statistics) | Mark `.unavailable` if not accessible |

## Data model additions

```swift
struct NetworkSample { let interfaces: [InterfaceThroughput] }   // up/down bytes/s + totals
struct InterfaceThroughput { let name: String; let upBytesPerSec, downBytesPerSec: Double
                             let totalUp, totalDown: UInt64 }
struct DiskSample { let volumes: [VolumeCapacity]; let io: DiskIO? } // io nil/unavailable
struct VolumeCapacity { let name: String; let total, used, free: UInt64 }
```

## Rate math (pure, property-tested)

- **Network rate**: `(bytesNow - bytesPrev) / (tNow - tPrev)`.
- If `bytesNow < bytesPrev` (counter reset / interface restart), treat the delta as 0 for
  that cycle — never negative, never absurd (Requirement 6.4).
- Properties: rate is never negative; a counter reset yields 0 not a huge spike.

## Samplers

- `NetworkSampler` — reads per-interface counters, computes per-interface and aggregate
  rates, tracks session totals.
- `DiskSampler` — enumerates mounted volumes via `statfs` for capacity; reads block storage
  stats for I/O where accessible, else `.unavailable`; reacts to volume add/remove.

## Presentation & units

- Network and disk shown in the detail view.
- Network unit option: bytes vs bits (Requirement 11.3) via the pure unit converters.

## Validation

Cross-check network throughput against Activity Monitor (Network tab) and disk capacity
against `df`.
