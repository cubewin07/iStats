# Skills to install — playbook for a follow-up agent

This file is a **job ticket**, not a catalog dump. Another agent should search, evaluate, and install. Do not treat the candidate list as an order to install everything.

Canonical project rules live in [`AGENTS.md`](../../AGENTS.md). Role behavior lives in [`docs/agents/`](../agents/). Domain knowledge that does not exist as a trustworthy public skill is already in [`.grok/skills/`](../../.grok/skills/).

---

## 1. Your job

1. Read this file and [`AGENTS.md`](../../AGENTS.md).
2. Inventory what is already installed (section 4).
3. Search for public skills that fill the **gaps** in section 2.
4. Score each candidate with the rubric in section 3.
5. Install only skills that pass. Skip or record a "rejected" note for the rest.
6. Verify discovery (section 8). Write a short install report at the bottom of this file or in `docs/handoffs/skills-install-report.md`.

Do **not** recreate the project skills under `.grok/skills/`. Those are already the source of truth for macOS sampling, SMC, Swift concurrency, and metric validation.

---

## 2. Capability gaps this repo actually has

iStats is a **native macOS 13+ menu bar app** (AppKit + SwiftUI, Swift 6, Apple Silicon first). Today it is a Swift package with pure `iStatsCore` types and tests. There is **no Xcode app target, no sampler implementations, no scheduler, no UI**.

| Need | Why it matters here | Prefer | Do not prefer |
|------|---------------------|--------|----------------|
| Xcode / `xcodebuild` diagnosis | Phase 1 creates the app target, `LSUIElement`, signing, schemes | Skills that fix real Xcode build logs, schemes, SPM-in-Xcode | iOS-only templates, UIKit storyboard generators |
| Swift 6 / SwiftUI / AppKit on **Mac** | Menu bar item, popover, preferences window | AppKit `NSStatusItem`, SwiftUI-in-AppKit hosting, `@MainActor` | iOS navigation stacks, UIKit, React Native "swift" packs |
| Swift concurrency that matches ADR 0002 | Background sampling, publish to main actor | `Sendable` value types, actors, GCD timers, isolation | "just use MainActor everywhere" |
| Swift testing / XCTest | Pure math and ring-buffer tests already exist | XCTest on SPM + later `xcodebuild test` | Jest/Playwright, iOS UI tests as the default |
| Git commit / review hygiene | Multi-agent building | Conventional commits, review checklists | Changelog generators for libraries we do not publish |
| Herdr pane control | Orchestrator must spawn sibling agents | The official Herdr skill + live `herdr` CLI | Generic "tmux helper" skills that do not speak Herdr JSON |

There is **no good public skill** for Mach `host_statistics`, `sysctl`, IOKit registry walks, `IOPowerSources`, or AppleSMC keys. Do not keep searching for those. Use the project skills:

- `.grok/skills/macos-system-apis/`
- `.grok/skills/applesmc-iokit-spi/`
- `.grok/skills/swift-concurrency-patterns/`
- `.grok/skills/metric-validation/`

---

## 3. Evaluation rubric (must pass before install)

Score each candidate. **Install only if it is Accept or Accept-with-notes.**

| Criterion | Accept | Reject |
|-----------|--------|--------|
| **Fit** | Teaches a task we will do in Phases 1–6 (Xcode app, SwiftUI/AppKit, concurrency, tests, review) | iOS product kits, Codable tutorials, quizzes, sales/CRM, icon generators |
| **Platform** | macOS / Swift / Xcode | UIKit-first, React Native, web frontend as the main payload |
| **Invariants** | Does not tell agents to call `sysctl` / IOKit / SMC on the main thread; does not persist telemetry | Contradicts ADR 0002 or ADR 0006 |
| **Trust** | Known author, or repo with real history and a readable `SKILL.md` | Unknown author, <100 installs, **and** a vague or copy-pasted body |
| **Installs** | ≥1k is a plus, not a requirement | <100 needs a strong author **or** you read the whole skill and it is clearly correct |
| **Recency** | Updated for Swift 5.9+ / Xcode 15+ | Last useful content is Swift 4 / storyboards |
| **Shape** | Procedural steps, real commands, failure modes | Marketing page, "you are an expert" with no procedure |
| **Safety** | No privilege escalation, no TCC bypass, no "disable SIP" | Anything named like security-bypass, jailbreak, TCC smash |
| **Harness** | Standard `SKILL.md` frontmatter (`name`, `description`) | Only works inside one proprietary agent with no portable file |
| **Duplication** | Adds something our project skills do not already cover | Restates `RateMath` / ring buffer / "don't crash on missing sensors" |

**Hard rejects (do not install):**

- `yaklang/hack-skills@macos-security-bypass` and clones
- Skills whose job is to hide from TCC, inject into other processes, or unsigned kernel work
- Skills that want to log live metrics to disk or a remote endpoint

**Install counts are a hint, not a verdict.** A 5-install Swift-concurrency skill from a careful author can beat a 2k-install Codable skill we will never use.

---

## 4. Already present — do not reinstall

Confirm with `grok inspect` and by listing these paths.

| Skill / tool | Where | Action |
|--------------|--------|--------|
| `herdr` | `~/.agents/skills/herdr/` | Keep. Orchestrator depends on it. Confirm `herdr` is on `PATH`. |
| `find-skills` | `~/.agents/skills/find-skills/` | Keep. Use it to search. |
| `frontend-design` | `~/.grok/skills/` and `~/.agents/skills/` | Keep but **do not** use it as the visual system for the menu bar app unless the user asks for a distinctive UI pass. |
| Bundled Grok: `review`, `design`, `execute-plan`, `create-skill`, `create-workflow`, `writing-commit-messages` | `~/.grok/bundled/skills/` | Available. No install. |
| Claude plugin: `feature-dev`, `claude-md-improver`, `pr-review-toolkit` | Claude marketplace plugins | Available when that harness is in use. |
| Project domain skills | `.grok/skills/` in this repo | **Do not download replacements.** |

---

## 5. Search commands to run

Use the Skills CLI. Prefer leaderboard checks on https://skills.sh/ before installing.

```bash
npx skills find xcode
npx skills find swiftui
npx skills find appkit
npx skills find "swift concurrency"
npx skills find "swift testing"
npx skills find xcresult
```

Useful owner-scoped follow-ups if a pack looks promising:

```bash
npx skills find xcode --owner avdlee
npx skills find --owner charleswiltgen
```

If a search returns iOS-only or hack/bypass results, discard them and move on. Do not install "the closest match."

---

## 6. Candidates worth evaluating (not a shopping list)

These showed up in a 2026-04 skills.sh search. **Re-search before installing** — names and install counts move.

| Candidate | Why it might help | Likely phase | Starting bias |
|-----------|-------------------|--------------|---------------|
| `avdlee/xcode-build-optimization-agent-skill@xcode-build-fixer` (~3k installs) | Real Xcode build-log repair. Author is a known iOS/Mac educator. | 1+ | Evaluate first. Accept if the skill is about diagnosing `xcodebuild`, not generating toy iOS apps. |
| `charleswiltgen/axiom` pack (`axiom-xcode-debugging`, `axiom-xcode-mcp`, `axiom-synchronization`, `axiom-swiftui-containers-ref`, `axiom-build-performance`) | Serious Swift/Xcode tooling, not a tutorial farm. | 1, 2, 6 | Evaluate **per skill**. Take debugging / Xcode / concurrency-adjacent ones. Skip MCP setup unless the user wants that MCP server. |
| `michaelboeding/skills@add-to-xcode` (~25 installs) | Might help attach `iStatsCore` to a new app target. | 1 | Read the whole skill. Low installs → only accept if the steps match SPM + local Xcode. |
| `kmshdev/claude-swift-toolkit@swift-concurrency` (~5 installs) | Possible extra concurrency notes. | 1–2 | Default **reject** unless it is better than `.grok/skills/swift-concurrency-patterns/` and does not fight ADR 0002. |
| `grantiva/swift-assist@coverage` (~12 installs) | Coverage later, not now. | 6 | Defer. |
| `dpearson2699/swift-ios-skills@swift-codable` (~2.6k) | Popular, wrong problem. | — | Reject. We are not designing Codable APIs. |
| `margelo/react-native-skills@swift` | React Native. | — | Reject. |
| `itlearning/study-ios@swift-quiz` | Quiz. | — | Reject. |

Also consider (if search surfaces a clean match):

- A **SwiftUI macOS** skill that covers `NSHostingController`, popovers, and settings windows.
- An **XCTest / Swift Testing** skill that works with `swift test` (SPM) and later `xcodebuild test`.
- A **commit-message** skill only if the user is not already using the bundled one.

---

## 7. How to install what you accept

Global (user-level, all projects):

```bash
npx skills add <owner/repo@skill> -g -y
```

Project-only (this repo, committed if the team should share it):

```bash
npx skills add <owner/repo@skill> -y
```

Prefer **global** for generic Xcode/Swift hygiene. Prefer **project** only if the skill is tuned to this app and you want it versioned here.

After install:

```bash
npx skills check
grok inspect
```

Confirm the new skill appears and does not collide with a project skill of the same name. If it collides, rename or disable the public one — **project domain skills win**.

Herdr (already expected on this machine):

```bash
command -v herdr
test -f "$HOME/.agents/skills/herdr/SKILL.md" && echo "herdr skill present"
```

If `herdr` is missing, install it from the project's usual Herdr install path (see the Herdr skill / website). Do not invent a different multiplexer.

---

## 8. Verification

A skill is "installed" only when **all** of these are true:

1. `grok inspect` lists it (or Claude/Cursor inspect if that harness is the one in use).
2. The `SKILL.md` is on disk and readable.
3. You invoked it once (slash command or a one-line "follow this skill and summarize its first three steps") and the steps are sane for macOS.
4. Nothing in those steps tells an agent to sample hardware on the main thread or write telemetry to disk.

Record:

- skill name + source
- accept / reject / deferred
- one-line reason
- install scope (global / project) if accepted

---

## 9. What to write back

Create `docs/handoffs/skills-install-report.md` with:

```markdown
# Skills install report

Date:
Harness: Grok / Claude / both

## Accepted
- name — source — why

## Rejected
- name — source — why

## Deferred
- name — until which phase

## Verification
- grok inspect: ok / problems
- herdr: present / missing
```

Then stop. Do not start implementing iStats features as part of the install pass.
