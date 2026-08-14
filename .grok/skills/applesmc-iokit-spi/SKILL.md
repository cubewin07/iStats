---
name: applesmc-iokit-spi
description: >
  Apple Silicon / Intel SMC keys, IOReport thermal channels, and fan read
  posture for iStats. Use in Phase 5, thermal/fan/GPU spikes, ADR 0003/0004
  work, or when the user mentions SMC, IOReport, fans, thermals, or powermetrics.
---

# AppleSMC / IOReport (iStats)

Status today: **ADR 0003 is Proposed**. Do not treat any key list as stable. A Phase 5 spike on the **target Mac** must record what actually works, then ADR 0003 becomes Accepted with those findings.

## Posture

1. Spike first. No production `ThermalSampler` / `FanSampler` until the spike notes which source returned real values.
2. Data source is **pluggable**: try SMC keys; if absent, try IOReport / HID energy sensors for what they can provide.
3. Partial coverage is success. Missing sensors are `.unavailable(reason:)`.
4. Fans are **read-only** unless ADR 0004's gates are all true: spike says control is safe, user opt-in, privileged helper exists, values stay within hardware min/max.
5. Never shell out to `sudo powermetrics` as the live sampler. Use it only as a reference (`metric-validation`).
6. All reads stay off the main thread. SMC/IOKit can stall — the scheduler time budget must apply.

## Spike checklist (write into Phase 5 report + ADR 0003)

On the machine being developed:

- Discover the `AppleSMC` IOKit service. List readable 4-char keys if a key dump is possible.
- Record, for each intended metric: key or IOReport channel, raw type, decoded unit, whether it matched `powermetrics`.
- Classic Intel-era names (`TC0P`, `FNum`, `F0Ac`, `F0Mn`, `F0Mx`) are **hints**, not a contract. Apple Silicon often uses different or no keys.
- GPU: `IOAccelerator` / `AGXAccelerator` properties — same rule, record what exists.
- Note anything that required root. Production code must not require root for read-only display.

## Implementation rules (after the spike)

- One place owns key/channel tables (not copied into views).
- Decode in the sampler; emit `SensorReading` / `FanReading` already in °C and RPM.
- Never write an SMC key unless fan-control work is explicitly in scope and ADR 0004 is satisfied.
- Do not persist discovered keys as telemetry. A static table in source + the ADR is fine.

## Rejected approaches

- Parsing `powermetrics` stdout in the always-on loop.
- Hard-coding a blog post's key list without verifying this Mac.
- Assuming Intel keys exist on Apple Silicon.
