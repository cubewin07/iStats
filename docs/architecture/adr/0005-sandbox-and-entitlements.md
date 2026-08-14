# ADR 0005 — App Sandbox and entitlements

**Status:** Accepted

## Context
The **App Sandbox** restricts access to many system resources. Several sensors and IOKit/SMC reads are blocked or unreliable under the sandbox. iStats is a personal/learning app run locally, not distributed through the App Store (Requirement 13.1).

## Decision
Develop and run **non-sandboxed**. Request only the access actually needed. Document, per metric, whether it would survive sandboxing, so the tradeoff is explicit if distribution is ever reconsidered.

## Options considered
- **Non-sandboxed (chosen)** — full access to sensors; appropriate for a local personal tool.
- **Sandboxed** — required for App Store distribution, but blocks much of the app's purpose; rejected for v1.

## Consequences
- iStats cannot be distributed via the Mac App Store as-is.
- Maximum metric coverage during development.
- If distribution is ever desired, a follow-up ADR must catalog which metrics break under the sandbox and what entitlements/helpers would be needed.
- Graceful degradation is still required: if a specific read is denied, mark it `.unavailable` rather than crashing (Requirement 13.1).
