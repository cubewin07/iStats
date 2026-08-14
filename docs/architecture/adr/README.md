# Architecture Decision Records (ADRs)

An ADR captures one significant decision: the context, the options considered, the choice, and the consequences. They are numbered and immutable — if a decision changes, add a new ADR that supersedes the old one rather than editing history.

## Format

Each ADR uses this structure:
- **Status** — Proposed / Accepted / Superseded by ADR-XXXX
- **Context** — the forces and constraints at play
- **Decision** — what we chose
- **Options considered** — alternatives and why they lost
- **Consequences** — the tradeoffs we now live with

## Index

| ADR | Title | Status |
|-----|-------|--------|
| [0001](0001-language-and-ui-stack.md) | Language and UI stack | Accepted |
| [0002](0002-threading-and-scheduling-model.md) | Threading and scheduling model | Accepted |
| [0003](0003-thermal-fan-data-source.md) | Thermal/fan/power data source | Proposed (spike-driven, Phase 5) |
| [0004](0004-privilege-and-fan-control.md) | Privilege model and fan control | Proposed |
| [0005](0005-sandbox-and-entitlements.md) | App Sandbox and entitlements | Accepted |
| [0006](0006-telemetry-privacy-no-persistence.md) | Telemetry privacy / no persistence | Accepted |
