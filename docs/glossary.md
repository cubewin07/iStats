# iStats — Glossary

Plain-language definitions of every term used in the project. Aimed at a developer new to OS-level macOS work.

| Term | Definition |
|------|------------|
| **AppKit** | Apple's older, powerful UI framework for macOS. Used here for the menu bar status item. |
| **SwiftUI** | Apple's modern declarative UI framework. Used here for the detail view and preferences. |
| **NSStatusItem** | The object representing your app's icon/text in the menu bar. |
| **NSStatusBar** | The system menu bar that hosts status items. |
| **LSUIElement** | An Info.plist flag that makes the app run without a Dock icon or main window — typical for menu bar apps. |
| **Menu bar extra** | Apple's term for a status item shown in the menu bar. |
| **Kernel** | The core of the OS that manages hardware and processes. User apps ask it for system info. |
| **User space** | Where normal apps run, isolated from direct hardware access. |
| **syscall** | A request from user space into the kernel for a privileged operation or data. |
| **sysctl** | A BSD interface (and command) to read/write kernel state by key, e.g. `hw.memsize`. |
| **Mach** | The microkernel layer in macOS exposing low-level calls like `host_statistics`. |
| **host_statistics / host_processor_info** | Mach calls returning system-wide VM and per-CPU tick counters. |
| **host_page_size** | The size of a memory page; needed to convert page counts to bytes. |
| **IOKit** | The framework for communicating with device drivers through the IORegistry. |
| **IORegistry** | A live tree of devices/drivers you can query (e.g., for battery info). |
| **SMC (System Management Controller)** | A microcontroller exposing sensor "keys" for temperature, fans, and power. |
| **SMC key** | A 4-character code (e.g., `TC0P`, `F0Ac`) identifying a sensor value. Largely undocumented. |
| **IOPowerSources** | An IOKit API for battery/power-source information. |
| **AppleSmartBattery** | An IORegistry entry exposing detailed battery health (cycle count, capacities). |
| **IOReport / powermetrics** | Lower-level/Apple-tool approaches to power and thermal data, relevant on Apple Silicon. |
| **getifaddrs** | A BSD function listing network interfaces and their byte counters. |
| **if_data** | A struct (from `getifaddrs`) holding per-interface counters like bytes in/out. |
| **statfs** | A BSD call returning filesystem capacity for a mounted volume. |
| **Counter** | A value that only increases (e.g., total bytes sent). Rates are computed from differences between counter samples. |
| **Rate** | A per-second value derived from two counter samples and the time between them. |
| **Memory pressure** | macOS's signal (normal/warning/critical) of how stressed memory is. |
| **Sampler** | An iStats component that reads one category of metrics. |
| **Sample** | One timestamped reading from a sampler. |
| **SampleScheduler** | The component that triggers samplers on intervals and isolates failures. |
| **MetricsStore** | The in-memory ring buffer holding recent samples for graphs. |
| **Ring buffer** | A fixed-size buffer that overwrites the oldest entry when full. |
| **@MainActor** | A Swift concurrency annotation marking code that must run on the main (UI) thread. |
| **GCD (Grand Central Dispatch)** | Apple's API for running work on background queues. |
| **AsyncStream** | A Swift concurrency type for delivering a sequence of values over time. |
| **kern_return_t** | The result code returned by Mach/IOKit calls; must be checked for success. |
| **App Sandbox** | A macOS security feature restricting what an app can access; can block sensors. |
| **TCC** | Transparency, Consent & Control — the system that gates sensitive permissions. |
| **SMAppService** | Modern API to register an app to launch at login. |
| **ADR** | Architecture Decision Record — a short document capturing one significant decision. |
