# Phase 8 — Premium Panel Redesign — Requirements

## Goal of this phase

Replace the Phase 7 popover presentation with a **premium, instrument-grade panel experience**: a custom glass panel shell, a tuned design language, living charts, motion, and a distinct signature instrument per category. All of it keeps the existing data model, real-data-only rule, and app invariants.

## Requirement 11: Premium category panels

**User story:** As a user, I want each iStats panel to feel like a well-crafted native instrument: calm when my Mac is healthy, alive while open, and precise when I look closer.

### R8.1 Shell & window
1. WHEN a menu bar item is clicked THEN iStats SHALL open a borderless, arrowless panel anchored 6 pt below the item, horizontally centred on it and clamped to the screen's `visibleFrame` with 8 pt margins.
2. The panel SHALL use Liquid Glass on macOS 26+ and a vibrant `NSVisualEffectView` material on macOS 13–15, with 16 pt continuous corners and a system shadow.
3. The panel SHALL close on outside click, `Esc`, app deactivation, or clicking the same item again, unless it is pinned.
4. WHILE a panel is open, hovering another iStats item SHALL swap to that item's panel without a full close/open cycle.
5. WHEN the user pins a panel THEN it SHALL become a movable floating window that survives outside clicks until it is un-pinned or closed.
6. The panel SHALL be 352 pt wide, size its height to content with animation, and cap at 560 pt. The Overview page SHALL NOT scroll.

### R8.2 Design language
1. All panel UI SHALL use the Phase 8 tokens (`Instrument.Type`, `Space`, `Radius`, `Surface`, `Motion`) and SHALL NOT use stock SwiftUI colour literals (`.blue`, `.mint`, …) for identity or series.
2. Category colours SHALL come from asset-catalog colour sets with light, dark and high-contrast variants.
3. Status colour SHALL appear only at `.elevated` or higher. No "Fine" badge is rendered.
4. Numerals SHALL use SF Pro tabular digits. SF Mono is limited to identifiers.
5. Text-on-tint combinations SHALL meet WCAG AA (4.5:1), verified by a unit test.

### R8.3 Motion
1. Numeric values SHALL animate digit transitions on macOS 14+ and crossfade on macOS 13.
2. Live charts SHALL glide between samples over the refresh interval and show a live head indicator.
3. All continuous animation SHALL stop when the panel is hidden and SHALL respect Reduce Motion, Low Power Mode, and paused sampling.

### R8.4 Content
1. Each category SHALL provide a signature instrument as specified in `design.md §6`. No two categories share the same body layout.
2. Each panel SHALL show at most one insight line, derived from in-memory history by tested pure functions (`InsightEngine`).
3. Every rendered value SHALL map to a `Models.swift` field or a unit-tested pure derivation. A missing field hides its row rather than showing a placeholder.
4. Copy SHALL be short and numeric. The legacy `dadSentence` copy SHALL be replaced by `headline` strings from a single tested table.

### R8.5 Interaction & accessibility
1. Keyboard: `⌘1–3`, `←/→`, `Esc`, `⌘C` (hovered value), `⌘,`, `⌘P`, `Space` SHALL work while the panel is key.
2. Every instrument SHALL expose a meaningful VoiceOver label/value. Charts SHALL expose a summary ("CPU, last minute, min 4 %, max 92 %, now 34 %").
3. Panels SHALL remain legible with Increase Contrast and Reduce Transparency (opaque fallback surface).

### R8.6 Performance & invariants
1. Opening a panel SHALL show its first frame within 100 ms of the click (hosting views pre-warmed).
2. With one panel open at a 1 s refresh, total app CPU SHALL stay ≤ 3 % on the reference Apple Silicon Mac. With panels closed, it SHALL not regress from the Phase 7 baseline.
3. No system calls SHALL be added on the main thread (ADR 0002). Per-process sampling runs on scheduler-owned background work.
4. No new telemetry SHALL be persisted (ADR 0006). Only the UI preferences (pin position, last page) may persist.
5. The SPM package and app SHALL build and all tests SHALL pass with the scratch-path commands in `AGENTS.md §5`.

## Out of scope
- Menu bar widget glyph redesign (only palette values flow through).
- Preferences window redesign (a candidate for a later phase).
- Fan control (ADR 0004 gates unchanged).
- Any persisted history or cloud features.

