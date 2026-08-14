# Phase 6 — Polish, Preferences & Performance — Design

The slice of the architecture this phase finalizes. See the top-level
[`design.md`](../../specs/design.md) for the complete design.

## Preferences (full)

Building on the Phase 1 preferences shell:

- **Category toggles:** enable/disable each `MetricCategory`; disabled categories are not
  scheduled (also lowers footprint).
- **Menu bar content:** choose which metric(s) render in the `NSStatusItem`.
- **Unit options:** °C/°F, bytes vs bits, IEC vs SI byte units — all via the pure unit
  converters introduced earlier.
- **Persistence:** all preferences persisted across launches (settings store).

## System integration

- **Launch at login:** `SMAppService` registration toggled from preferences (Req 11.4/11.5).
- **Dock icon toggle:** flip `LSUIElement`/activation policy at runtime (Req 9.5).

## Performance pass

- Confirm all sampling runs off the main thread (Req 12.1).
- Measure iStats' own CPU at the default interval; target low single-digit percent on the
  target hardware (Req 12.2).
- Verify increasing the interval reduces sampling frequency and footprint (Req 12.4).
- Disabled categories incur no scheduling cost.

## Documentation finalization

- Finalize all ADRs (0001–0006) and the docs set (`overview`, `architecture`,
  `build-and-run`, `glossary`, `prerequisites-and-learning`).
- Write `docs/phases/phase-06-polish-prefs/report.md` and the project `README.md`.
