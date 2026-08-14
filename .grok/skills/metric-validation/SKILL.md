---
name: metric-validation
description: >
  Compare iStats readings to macOS reference tools and record the result
  in the phase report. Use at the end of a metric phase, when writing
  report.md, or when the user says validate, Activity Monitor, top,
  vm_stat, df, pmset, or powermetrics.
---

# Metric validation (iStats)

Trust comes from a side-by-side check, not from the sampler compiling. Procedure and per-metric commands live in `docs/guides/prerequisites-and-learning.md`. Write findings into that phase's `report.md`.

## Method

1. Run iStats (or print the sampler's values in a debug hook) next to the reference.
2. Apply a known load (tight loop, large copy, download, `yes > /dev/null`).
3. Confirm **direction and rough magnitude**, not bit-identical floats.
4. Record tool, command, iStats value, reference value, load applied, and whether it is acceptably close.
5. If the reference needs `sudo` (`powermetrics`), use it only for the report. Do not put sudo into the app.

## Reference map

| Category | Reference |
|----------|-----------|
| CPU % | Activity Monitor → CPU; `top -l 2` (use the **second** sample) |
| Load average | `uptime` |
| Memory / swap / pressure | Activity Monitor → Memory; `vm_stat`; `sysctl vm.swapusage` |
| Network B/s | Activity Monitor → Network; two samples of `netstat -ib` |
| Disk capacity | `df -h` |
| Disk I/O | Activity Monitor → Disk; `iostat` |
| Battery | `pmset -g batt`; `system_profiler SPPowerDataType` |
| Power / thermal / GPU | `sudo powermetrics` (and a known local sensor app if you trust one) |

## What "close enough" means

- Rates: same order of magnitude and the same movement under load. Brief disagreement on a 1s interval is normal.
- Percents: typically within a few points of Activity Monitor on a quiet machine; larger error under load is a bug until explained.
- Capacities (`df`, battery mAh): should match closely; mismatch usually means wrong units or the wrong volume/battery key.
- First sample after launch may be 0 (no delta yet). Do not fail validation on sample 1.

## Report section (copy into `docs/phases/phase-XX-*/report.md`)

```markdown
### Validation — <category>
- Machine:
- iStats build:
- Reference: <command or app>
- Load applied:
- iStats: ...
- Reference: ...
- Verdict: match / acceptable / fail (why)
```

## Do not

- Treat a green `swift test` as metric validation. Tests cover `RateMath` / `RingBuffer`, not this Mac's sensors.
- Change production code to match `powermetrics` by scraping it.
- Write the comparison numbers anywhere except the phase report (no telemetry logs on disk).
