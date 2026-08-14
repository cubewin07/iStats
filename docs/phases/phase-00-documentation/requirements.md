# Phase 0 — Documentation Scaffolding & Learning Baseline — Requirements

## Goal of this phase

Establish the documentation, learning, and planning foundation **before** any feature
code is written, so the project teaches as it is built and every later phase has a place
to record what was learned and how it was validated.

> Scope note: this phase satisfies the documentation/learning deliverables and the
> privacy posture. Feature requirements (CPU, memory, etc.) are addressed in later phases.

## Requirements covered by this phase

### Requirement 14: Learning and documentation deliverables

**User Story:** As a developer learning OS-level macOS development, I want the project to
teach me as it's built, so that I can understand, validate, and extend the code with
confidence.

#### Acceptance Criteria

1. WHEN the project is planned THEN iStats SHALL include Architecture Decision Records
   (ADRs) capturing key technical choices (frameworks per metric, threading model,
   privilege model, persistence, etc.).
2. WHEN the project is planned THEN iStats SHALL include a general documentation set
   (project overview, architecture, build/run instructions, glossary).
3. WHEN the project is planned THEN iStats SHALL include a phased delivery plan with a
   skeleton for the whole project, AND each phase SHALL have its own report and task list.
4. WHEN the project is planned THEN iStats SHALL include a dedicated prerequisites/"what I
   need to learn" document covering relevant OS concepts and macOS frameworks (sysctl,
   Mach host stats, IOKit, SMC, IOReport/powermetrics concepts, SwiftUI/AppKit menu bar
   patterns) and how to validate each category of metric against a known-good reference
   (Activity Monitor, `top`, `powermetrics`, etc.).
5. WHERE a metric is implemented THEN the documentation SHALL describe how to verify its
   correctness against a reference tool.

### Requirement 13.3: Privacy posture (planning-time decision)

#### Acceptance Criteria

1. WHEN handling sensor/system data THEN iStats SHALL keep all data local and SHALL NOT
   transmit it off the machine. (Captured here as ADR 0006 so the no-persistence/privacy
   stance is fixed before any sampler is built.)

## Definition of done for Phase 0

- Folder structure exists as specified in the design.
- Prerequisites/learning guide, core docs set, phase plan, and initial ADRs are written.
- No telemetry persistence design decision is recorded.
