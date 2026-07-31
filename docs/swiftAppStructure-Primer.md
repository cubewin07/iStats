# Swift App Structure — A Primer for iStats

Written for someone coming from Java/Spring Boot, C#, and TS/React. The goal isn't to teach Swift syntax line by line — it's to give you the mental map so nothing in the repo (or in Xcode) feels alien.

---

## 1. The unit of organization: **Package → Targets → Sources**, not classes-in-folders

In Spring Boot, your build unit is the Maven/Gradle module, described by `pom.xml`/`build.gradle`. In Swift, that's **Swift Package Manager (SPM)**, described by `Package.swift` — which is itself executable Swift code, not XML/YAML. Your repo's file is a good example:

```swift
let package = Package(
    name: "iStats",
    platforms: [.macOS(.v13)],       // minimum OS version, like a <java.version> tag
    products: [
        .library(name: "iStatsCore", targets: ["iStatsCore"])   // what this package *exposes*
    ],
    targets: [
        .target(name: "iStatsCore"),                             // the actual code
        .testTarget(name: "iStatsCoreTests", dependencies: ["iStatsCore"])  // tests, depends on the target
    ]
)
```

Mental mapping:

| Spring Boot / Maven | Swift Package Manager |
|---|---|
| `pom.xml` | `Package.swift` |
| Maven module | **target** |
| a `.jar` you publish | **product** (library or executable) |
| `src/main/java` | `Sources/<TargetName>/` |
| `src/test/java` | `Tests/<TargetNameTests>/` |
| Maven dependency | `.package(url: ...)` + listing it in a target's `dependencies` |

**Key idea**: a "target" is not a class or a file — it's a compilation unit. Each folder under `Sources/` with a matching name in `Package.swift` becomes one. `iStatsCore` is your domain/business-logic target; the (not-yet-created) menu bar app is meant to be a *separate* target/project that depends on it. That's exactly the "core library + thin UI shell" pattern you already use when you separate a Spring Boot service layer from a controller layer — just enforced at the compiler level here instead of by convention.

---

## 2. Where "main" is — and why there are three different answers

This trips up almost everyone coming from Java, where `public static void main` is unambiguous. Swift has three different entry-point conventions depending on what kind of target you're building:

- **A plain script/CLI target**: a file literally named `main.swift` — top-level code in that file just *runs*, no function wrapper needed.
- **A modern app target (SwiftUI, iOS 14+/macOS 11+)**: no `main.swift` at all. Instead, one `struct` is annotated `@main` and conforms to the `App` protocol:
  ```swift
  @main
  struct iStatsApp: App {
      var body: some Scene {
          MenuBarExtra("iStats", systemImage: "gauge") {
              ContentView()
          }
      }
  }
  ```
  This is what you'll write for the menu bar app. `@main` tells the compiler "start here," similar in spirit to Spring Boot's `@SpringBootApplication` marking the class with `main()`.
- **Older AppKit apps**: an `AppDelegate` class implementing lifecycle callbacks (`applicationDidFinishLaunching`, etc.), wired via a storyboard or `NSApplicationMain`. You likely won't need this for a menu-bar utility — `MenuBarExtra` (SwiftUI) is the modern, much simpler way to do exactly what iStats needs.

Since `iStatsCore` is a library target (no `products: .executable`), it *shouldn't* have a `main.swift` — libraries never do, same as a Spring `-core` module has no `main()`.

---

## 3. The four building blocks, and how they differ from Java

You know OOP already, so this is mostly "what's different," not "what is a class."

**`struct` vs `class` — this is the big one.** Structs are *value types* (copied on assignment/passing), classes are *reference types* (shared, like every Java object). Swift code defaults to `struct` unless you specifically need reference semantics (shared mutable state, identity, inheritance). SwiftUI views are structs. Your data models are usually structs. This is the opposite instinct from Java, where everything non-primitive is a reference by default — expect to reach for `class` far less often than you would in Java.

**`protocol` ≈ Java `interface`**, but more powerful: protocols can supply default implementations directly (`extension SomeProtocol { func foo() { ... } }`), and structs/enums can conform to them too, not just classes. This is closer to a mix of Java interfaces + default methods + a bit of what traits/mixins give you in other languages.

**`enum` is much stronger than Java/C# enums.** Swift enums can carry associated data per case:
```swift
enum SensorReading {
    case cpu(percent: Double)
    case memory(usedGB: Double, totalGB: Double)
    case error(String)
}
```
This is closer to Rust/Kotlin sealed classes than to a Java `enum`. You'll likely reach for this a lot in a stats-monitoring app to represent "one of several kinds of readings" cleanly.

**`Optional<T>` (written `T?`) is baked into the type system**, not bolted on like Java's `Optional<T>` class. `nil` can only be assigned to an optional type — you can't accidentally NPE a non-optional the way you can in Java/C#. The compiler forces you to unwrap (`if let`, `guard let`, `??`) before use. This eliminates a huge class of bugs you're used to defending against manually.

---

## 4. Access control — similar idea, slightly different defaults

You know `public`/`private`/`protected` from Java. Swift's spectrum:

| Keyword | Visible from |
|---|---|
| `open` | anywhere, and subclassable outside the module (classes only) |
| `public` | anywhere, but not subclassable outside the module |
| `internal` (**default**, no keyword needed) | anywhere within the same module/target |
| `fileprivate` | same file only |
| `private` | same declaration/scope only |

The default (`internal`) is roughly Java's package-private, but scoped to the whole target rather than a folder — since Swift doesn't use package namespaces the way Java does. This matters directly for you: anything in `iStatsCore` you want the future menu-bar app target to use **must be marked `public`**, or the other target won't see it — same failure mode as forgetting to export something from a Spring module, just enforced differently.

---

## 5. Testing: two frameworks exist — know which one you're looking at

Because `iStats` uses `swift-tools-version: 6.0`, it's likely using Apple's **new Swift Testing** framework rather than the older XCTest. They look different enough that it's worth knowing both on sight:

**Swift Testing (new, Swift 6+)**
```swift
import Testing
@testable import iStatsCore

@Test func cpuUsageNeverNegative() {
    let reading = SystemStats.currentCPU()
    #expect(reading >= 0)
}
```

**XCTest (older, still everywhere in tutorials/StackOverflow)**
```swift
import XCTest
@testable import iStatsCore

final class iStatsCoreTests: XCTestCase {
    func testCPUUsageNeverNegative() {
        let reading = SystemStats.currentCPU()
        XCTAssertGreaterThanOrEqual(reading, 0)
    }
}
```

Functionally equivalent to JUnit either way (`@Test`/`#expect` ≈ JUnit 5's `@Test`/`assertThat`; `XCTestCase` ≈ JUnit 4 style). `swift test` runs both kinds transparently, so you don't need to care which one at the CLI level — just recognize which style the existing `iStatsCoreTests` file uses before you add new tests, so you're consistent.

---

## 6. Putting it together: what "Sources/iStatsCore/*.swift" will actually contain

For a macOS system-stats app, expect the core library to end up organized roughly like:

```
Sources/iStatsCore/
├── Models/          // structs/enums representing CPU, RAM, disk, network readings
├── Providers/        // things that actually read system data (likely via C interop / IOKit / host_statistics)
├── Formatting/       // turning raw numbers into display strings
└── iStatsCore.swift  // or a namespace/facade type tying it together
```

The eventual app target (Xcode) would then be a thin layer:
```
iStatsApp/
├── iStatsApp.swift     // @main entry, MenuBarExtra scene
├── ContentView.swift    // SwiftUI view(s)
└── ViewModel.swift      // @Observable/ObservableObject bridging iStatsCore -> UI
```
— which is the same "core service + presentation layer" split you already default to, just with SwiftUI's `@Observable`/`ObservableObject` standing in for whatever you'd use for a ViewModel/DTO layer in a typical MVVM setup.

---

## Quick-reference cheat sheet

| You know this... | Swift equivalent |
|---|---|
| Maven/Gradle module | SPM target |
| `pom.xml` | `Package.swift` |
| `public static void main` | `@main struct X: App` (apps) or `main.swift` (scripts) |
| `interface` | `protocol` |
| Java `Optional<T>` | `T?` (built into the type system) |
| package-private | `internal` (the default) |
| JUnit `@Test` | `@Test` (Swift Testing) or `XCTestCase` method (XCTest) |
| everything is a reference | prefer `struct` (value type) unless you need identity/sharing → then `class` |

---

Once you're ready, the natural next step is creating the actual Xcode app target and wiring `iStatsCore` in as a local package dependency — happy to walk through that when you get there.