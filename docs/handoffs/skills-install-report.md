# Skills install report

Date: 2026-08-14
Harness: Grok / Claude / Antigravity

## Accepted
- `xcode-build-fixer` — `avdlee/xcode-build-optimization-agent-skill` — Real Xcode build diagnostic and setting repair for Phase 1+ app target and SPM-in-Xcode integration. Scope: global.
- `axiom-macos` — `charleswiltgen/axiom` — macOS-specific AppKit (`NSStatusItem`, `NSHostingController`), menu bar, and macOS SwiftUI patterns. Scope: global.
- `swift-testing-pro` — `twostraws/swift-testing-agent-skill` — Swift 6 Swift Testing (`@Test`, `#expect`, `@Suite`, async testing) best practices and XCTest migration. Scope: global.

## Rejected
- `charleswiltgen/axiom@axiom-concurrency` / `avdlee/swift-concurrency-agent-skill@swift-concurrency` — Existing project skill `.grok/skills/swift-concurrency-patterns/` is authoritative and tailored to ADR 0002.
- `charleswiltgen/axiom@axiom-xcode-mcp` — Skipped as external Xcode MCP server setup is not currently requested.
- `michaelboeding/skills@add-to-xcode` — Not available in current repository distribution; repository contains unrelated generic utilities.
- `dpearson2699/swift-ios-skills@swift-codable` / `swiftui-uikit-interop` — iOS/UIKit-focused and redundant for macOS domain models.
- `margelo/react-native-skills@swift` — React Native focus, irrelevant to native Swift menu bar monitor.
- `itlearning/study-ios@swift-quiz` — Quiz/tutorial format, non-procedural.

## Deferred
- `grantiva/swift-assist@coverage` — Deferred until Phase 6 (Polish, Preferences & Performance).

## Verification
- `grok inspect`: OK. All 3 new skills discovered as user skills (`xcode-build-fixer`, `axiom-macos`, `swift-testing-pro`) alongside 4 in-repo project domain skills (`applesmc-iokit-spi`, `macos-system-apis`, `metric-validation`, `swift-concurrency-patterns`). No name collisions with project skills.
- `herdr`: Present (`/Users/letanthang/.local/bin/herdr` on PATH, skill at `~/.agents/skills/herdr/`).
