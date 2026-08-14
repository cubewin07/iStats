# iStats Documentation

Welcome to the iStats documentation hub. This directory contains the complete specifications, architectural design, developer guides, Architecture Decision Records (ADRs), and the phased delivery roadmap.

---

## Directory Organization

```
docs/
├── specs/                             # Canonical master specifications
│   ├── requirements.md                # System requirements (EARS format)
│   ├── design.md                      # Canonical system design & macOS API mappings
│   └── tasks.md                       # Master implementation tasks list
│
├── architecture/                      # System design, architecture & ADRs
│   ├── overview.md                    # Project overview, goals & mental model
│   ├── architecture.md                # Layered architecture, data flow & threading narration
│   ├── swift-app-structure-primer.md  # Swift/macOS app structure primer
│   └── adr/                           # Architecture Decision Records
│       ├── README.md                  # ADR index & status summary
│       └── 0001-0006-*.md             # Individual decision records
│
├── guides/                            # Developer guides & references
│   ├── build-and-run.md               # Local build, run, and debugging instructions
│   ├── glossary.md                    # macOS & OS kernel terminology glossary
│   └── prerequisites-and-learning.md  # Learning roadmap & metric validation guide
│
└── phases/                            # Phased implementation plan & per-phase specs
    ├── README.md                      # Master phase roadmap & dependency graph
    └── phase-00-documentation/ ... phase-06-polish-prefs/
        ├── requirements.md            # Phase-scoped requirements
        ├── design.md                  # Phase-scoped design slice
        ├── tasks.md                   # Phase summary checklist & learning focus
        ├── report.md                  # Completion report & reference validation log
        └── tasks/                     # Granular task specs (definition of done)
```

---

## Quick Navigation

| Section | Link | Description |
|---------|------|-------------|
| **Overview** | [`architecture/overview.md`](./architecture/overview.md) | What iStats is, who it's for, and core goals. **Start here.** |
| **Requirements** | [`specs/requirements.md`](./specs/requirements.md) | Master functional and non-functional requirements (EARS format). |
| **System Design** | [`specs/design.md`](./specs/design.md) | Canonical architecture, data flow, privilege model, and API mapping table. |
| **Architecture (Narrated)** | [`architecture/architecture.md`](./architecture/architecture.md) | Teaching-oriented narration of the layered design and threading model. |
| **Swift App Primer** | [`architecture/swift-app-structure-primer.md`](./architecture/swift-app-structure-primer.md) | Guide to Swift/macOS project structure and AppKit/SwiftUI patterns. |
| **ADRs** | [`architecture/adr/`](./architecture/adr/) | Architecture Decision Records (immutable log of key architectural choices). |
| **Learning Guide** | [`guides/prerequisites-and-learning.md`](./guides/prerequisites-and-learning.md) | Prerequisites and how to validate every metric against macOS reference tools. |
| **Build & Run** | [`guides/build-and-run.md`](./guides/build-and-run.md) | Instructions for building, running, and debugging iStats locally. |
| **Glossary** | [`guides/glossary.md`](./guides/glossary.md) | Definitions of macOS, BSD, Mach, IOKit, and SMC terms. |
| **Master Task List** | [`specs/tasks.md`](./specs/tasks.md) | Master checklist mapping all requirements to actionable tasks. |
| **Phase Plan** | [`phases/`](./phases/) | The 7-phase delivery roadmap, scoped phase specs, and report templates. |

---

## Suggested Reading Order

1. [`architecture/overview.md`](./architecture/overview.md) — High-level goals, mental model, and non-goals.
2. [`guides/prerequisites-and-learning.md`](./guides/prerequisites-and-learning.md) — Fundamental OS concepts and reference validation methodology.
3. [`architecture/architecture.md`](./architecture/architecture.md) — System layers, isolation boundaries, and threading.
4. [`specs/design.md`](./specs/design.md) & [`specs/requirements.md`](./specs/requirements.md) — Formal specifications and macOS API mapping.
5. [`phases/README.md`](./phases/README.md) — Phased roadmap from foundation to final polish.
6. Relevant [`architecture/adr/`](./architecture/adr/) records as you work on specific architectural decisions.
