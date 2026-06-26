# ADR 0001 — Language and UI stack

**Status:** Accepted

## Context
iStats needs deep access to macOS system APIs (Mach, sysctl, IOKit, SMC) and a menu bar presence. The author is learning OS-level development and wants maximum access and educational value. Alternatives like Tauri (Rust + web) or Electron (Node + web) were considered.

## Decision
Build natively with **Swift**, using **AppKit** for the menu bar status item and **SwiftUI** for the detail view and preferences (with AppKit interop where needed).

## Options considered
- **Swift + SwiftUI/AppKit (chosen)** — full, first-class access to every system API; best learning value; idiomatic menu bar support.
- **Tauri (Rust + React)** — could reuse web UI skills, Rust for system access, but menu bar and many sensors need native bridging; adds a layer that obscures the OS learning.
- **Electron (Node + React)** — most familiar UI-wise, but heavyweight and poor at deep system access (temperature/sensors are impractical).

## Consequences
- Steeper learning curve (Swift + AppKit are new), accepted because learning is a goal.
- Direct access to all needed APIs; no cross-language bridging overhead.
- UI code is split between SwiftUI and AppKit; interop patterns must be learned (`NSHostingView`, `NSStatusItem`).
- Lowest runtime footprint of the three options, which matters for a monitor (Requirement 12).
