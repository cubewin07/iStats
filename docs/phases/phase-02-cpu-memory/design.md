# Phase 2 — CPU & Memory — Design

The slice of the architecture this phase builds. See the top-level
[`design.md`](../../specs/design.md) for the complete design.

## API mapping for this phase

| Metric | Primary API | Notes / risk |
|--------|-------------|--------------|
| CPU total/per-core | Mach `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` | Compute deltas between samples for % |
| Load average | `sysctl` (`vm.loadavg`) | Straightforward |
| CPU frequency | `sysctl` (`hw.cpufrequency`*) | Often unavailable on Apple Silicon → mark `.unavailable` |
| Memory | Mach `host_statistics64(HOST_VM_INFO64)` + `sysctl hw.memsize` | Page size from `host_page_size` |
| Memory pressure | `DispatchSource` memory pressure / `sysctl` | Map to normal/warning/critical |
| Swap | `sysctl vm.swapusage` | Struct decode |

## Data model additions

```swift
struct CPUSample { let totalUsage: Double; let perCore: [Double]
                   let user: Double; let system: Double; let idle: Double }
struct MemorySample { let total, used, free, wired, compressed, cached, swapUsed: UInt64
                      let pressure: MemoryPressure }
enum MemoryPressure { case normal, warning, critical }
```

## Rate math (pure, property-tested)

- **CPU %**: `(deltaBusy / deltaTotal) * 100` per core, where busy/total come from
  cumulative tick counters between consecutive samples.
- Properties: result is always within `0...100`; with monotonic non-decreasing counters
  the math never produces negative values; total equals user + system + idle within
  rounding.

## Samplers

- `CPUSampler` — conforms to `Sampler`, reads tick counters via Mach, computes deltas
  against the previous reading it holds.
- `MemorySampler` — reads VM stats + `hw.memsize`; derives pressure level.

## Presentation

- Detail view renders CPU (aggregate + per-core) and memory with live rolling graphs fed
  from `MetricsStore`.
- Menu bar can be configured to show CPU or memory (Requirement 9.4).
- Memory pressure warning/critical is surfaced visibly (Requirement 2.4).

## Validation

Cross-check CPU % and memory figures against Activity Monitor and `top` per the
prerequisites/learning guide.
