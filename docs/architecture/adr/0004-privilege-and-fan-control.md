# ADR 0004 — Privilege model and fan control

**Status:** Proposed

## Context
Reading most metrics needs no elevated privileges. **Writing** values — notably controlling fan speed — and some low-level reads may require a privileged helper (a `launchd` daemon installed via `SMAppService`). Fan control also carries thermal-safety risk if done incorrectly (Requirements 4.3, 13.2).

## Decision
Default posture is **read-only, no privilege escalation**. iStats ships without a privileged helper in early phases. Fan **control** is gated behind: (a) a confirmed-feasible-and-safe finding from the Phase 5 spike, (b) an explicit opt-in by the user, and (c) a separate privileged helper documented in its own ADR update. Fan speeds set by the user must stay within hardware-reported min/max bounds.

## Options considered
- **Read-only by default, opt-in privileged helper for control (chosen)** — safest; least surprising; aligns with least-privilege.
- **Always install a privileged helper** — rejected; unnecessary attack surface and complexity for a learning app.
- **No control ever** — simplest, but the user explicitly wants control "if feasible"; keep it possible but gated.

## Consequences
- Out of the box, fans are presented read-only with an explanation (Requirement 4.4).
- Enabling control is a deliberate, documented step with clear risk disclosure.
- No silent privilege escalation (Requirement 13.2).
