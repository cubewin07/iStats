# ADR 0004 — Privilege Model, Fan Control Policy & Read-Only Safety Posture

**Status:** Accepted (Settled in Phase 5)  
**Requirements:** 4.1, 4.2, 4.3, 4.4, 13.1, 13.2  
**Deciders:** Core Engineering Team  

---

## Context

A core capability of macOS hardware monitors is surfacing cooling and thermal dynamics. Modern Apple hardware (Intel and Apple Silicon M-series) employs sophisticated autonomous thermal management architectures built directly into hardware, Power Management Units (PMU), and firmware (AppleSMC). 

While unprivileged applications can safely query telemetry (such as actual RPM via `F0Ac`, minimum speed bounds via `F0Mn`, and maximum speed bounds via `F0Mx`) through IOKit user client connections (`AppleSMC`), modifying fan behavior (such as setting target speeds via `F0Tg` or forcing manual mode via `F0Md` / `FS! `) introduces significant privilege and safety considerations:

1. **Privilege Requirements on macOS:**
   - Reading SMC keys is permitted by the kernel for unprivileged user-space processes.
   - Writing to SMC control keys typically requires root privileges or a privileged helper daemon registered with `SMAppService` or `launchd`.
   - Silent privilege escalation is strictly prohibited by security design (Requirement 13.2).

2. **Thermal Safety & Hardware Longevity Risks:**
   - Apple Silicon SoCs (M1 through M4) utilize tightly coupled closed-loop thermal PID controllers that correlate dozens of temperature sensors (PMU dies, GPU clusters, battery, memory, SoC package) with fan RPM curves.
   - Manual fan speed overrides can override or fight the OS thermal management subsystem. Clamping fan speeds below required thermal thresholds during heavy workloads risks thermal throttling degradation, battery degradation, component stress, or emergency thermal shutdown.
   - Forcing fan speeds to continuous high RPMs increases mechanical bearing wear and acoustic noise.

3. **Security Attack Surface:**
   - Shipping a background privileged daemon (`launchd` / `SMAppService`) running as `root` requires a custom XPC interface.
   - Unauthenticated or insufficiently validated XPC endpoints in privileged helpers have historically been a major source of Local Privilege Escalation (LPE) CVEs in macOS third-party system utilities.
   - For a lightweight, transparent menu bar monitor, adding a root daemon creates disproportionate security risk.

---

## Options Considered

### Option 1: Automatic System Control (Strict Read-Only Posture) — **CHOSEN**
- Present all detected fans with live RPM, min/max RPM bounds, and speed gauge graphs.
- Do not write to AppleSMC; do not install or bundle a privileged root helper.
- Explicitly display "System Controlled" / "Automatic" status in the UI, accompanied by a clear explanation that macOS firmware automatically optimizes fan speeds for thermal safety and hardware protection (Requirements 4.3, 4.4).
- Model pure safety bounds and validation logic (`FanSafetyBounds`, `FanControlPolicy`) in `iStatsCore` to enforce `[minRPM, maxRPM]` constraints.

*Pros:*
- **Zero Attack Surface:** No root processes, no vulnerable XPC endpoints, zero attack surface.
- **Hardware Safety:** Complete protection against accidental thermal runaway, overheating, or hardware stress.
- **Zero Friction:** No administrative password prompts or installation steps for the user.
- **Full Compliance:** Completely satisfies Acceptance Criteria 4.3, 4.4, and 13.2.

*Cons:*
- Users cannot manually force higher fan speeds for pre-cooling before sustained tasks.

### Option 2: Install Privileged Helper Tool via `SMAppService`
- Bundle a separate `launchd` helper executable running as root, with an XPC communication layer and administrative authorization prompt on first enable.
- Expose manual fan sliders in Preferences.

*Pros:*
- Allows manual overrides for advanced power users.

*Cons:*
- **Substantial Security Complexity:** Requires secure code signing, audit of XPC message passing, and entitlement enforcement.
- **Thermal Hazard:** High risk of user error leading to inadequate cooling during intensive computational tasks.
- **Apple Silicon Disruption:** Overriding fan targets can conflict with dynamic PMU closed-loop thermal curves.
- **Violates Least-Privilege:** Exceeds the core mission of a non-invasive, lightweight menu bar monitor.

### Option 3: Direct Unprivileged SMC Writes
- Attempt unprivileged writes directly to `AppleSMC`.

*Pros:*
- None.

*Cons:*
- Rejected. Fails on macOS security sandbox and kernel access checks; unstable and unsafe.

---

## Decision

iStats adopts **Option 1: Strict Read-Only Monitoring with Zero Privilege Escalation**.

1. **Read-Only Telemetry:**
   - iStats continuously samples actual fan speeds (`F(i)Ac`) and hardware limits (`F(i)Mn`, `F(i)Mx`) via unprivileged IOKit reads.
   - No privileged helper daemon is installed or distributed.
   - No administrative credentials (`sudo` / `AuthorizationExecuteWithPrivileges`) are requested.

2. **Transparent User Communication (Requirement 4.4):**
   - The UI surfaces an informative **"System Controlled"** badge and an explanatory note in the detail view:
     > *"Fan speeds are automatically managed by macOS system firmware to protect thermal safety and hardware longevity."*
   - On fanless Macs (e.g. MacBook Air), the UI cleanly displays **"Passive Cooling"** without error states.

3. **Domain Safety Bounds (`iStatsCore`):**
   - Core domain models include `FanSafetyBounds` and `FanControlPolicy`.
   - Any target RPM calculations or mock simulations must strictly clamp within `[minRPM, maxRPM]`, preventing under-cooling (clamping below min) and motor wear (clamping above max).
   - Mode is formalized as `FanControlMode.systemAutomatic`.

---

## Consequences

- **Security Posture:** Zero privilege escalation, zero root attack surface, aligned with ADR 0005 (non-sandboxed but unprivileged) and ADR 0006 (privacy and no telemetry).
- **Thermal Reliability:** The macOS kernel and PMU retain unhindered authority over thermal throttling and cooling curves.
- **User Trust:** Users have full visibility into cooling metrics without worrying about background daemons or security degradation.
- **Traceability:** Fulfills Requirements 4.1, 4.2, 4.3, 4.4, 13.1, and 13.2.
