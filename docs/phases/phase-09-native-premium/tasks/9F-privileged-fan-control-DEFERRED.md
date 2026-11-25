# Task 9F — Privileged Fan Control (DEFERRED, learning first)

**Status: DEFERRED. Not part of the Phase 9 exit criteria.** ADR 0004 (fans read-only) remains in force. Nothing here may be implemented until the spike below is done and an ADR 0012 is written and accepted. This is a learning exercise first.

## Intent
Decide whether writing fan speeds is feasible and safe for a personal, non-App-Store tool, and if so how (privileged helper vs. alternatives).

## Current code
- Read-only fan sampling via SMC (`applesmc-iokit-spi` skill, `docs/guides/prerequisites-and-learning.md`); `iStats/UI/Panels/FanPanel.swift` has no write affordances.
- ADR 0004 defines the conditions for control; CLAUDE.md invariant: "Fans read-only until ADR 0004 is satisfied."

## Spike questions
1. Do Apple Silicon Macs on the current macOS accept `F0Tg`/`FS!` style writes at all, and what does the SMC return when not privileged?
2. What is the minimum privilege boundary: `SMJobBless`/`SMAppService` daemon with a signed XPC helper vs. a one-shot root tool? What signing and notarization does each require?
3. What safety floor is enforceable (never below firmware minimum, automatic restore on exit, crash, sleep, and thermal emergency)?
4. How does thermal management firmware react (does it override within seconds)? Is there measurable benefit?
5. What is the failure and uninstall story (helper removal, stale daemon after app update)?

## Go / no-go
Go only if: writes work and are reversible; a watchdog restores automatic mode on any helper or app exit; benefit is measurable on the learner's own Mac; the risk analysis is written. Otherwise no-go: keep ADR 0004, record findings.

## Outline (only after go)
- **9F.1** Spike notebook and findings doc (`docs/guides/`), no app code.
- **9F.2** ADR 0012 (privilege model, safety floor, watchdog), accepted before code.
- **9F.3** Helper + XPC protocol, signed, with automatic-restore watchdog; unit tests with a fake SMC.
- **9F.4** UI (explicit opt-in, curve editor limits, always-visible "automatic" restore) and verification report.

## Files
None until 9F.2. No Swift edits in Phase 9.

## Tests
Spike notes only. Later phases: fake-SMC unit tests, watchdog tests.

## Validation commands
None (docs/learning).

## Acceptance criteria
This file stays marked DEFERRED; Phase 9 closes without it.

## Risks
Hardware damage or instability from bad writes; signing and privilege escalation surface; breakage on macOS updates.

## Out of scope
Everything, for Phase 9.

## Commit plan
None in Phase 9.
