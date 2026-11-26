import Foundation

/// Canonical identifier for every metric concept explained in panels, settings, and the glossary sheet (Phase 9, task 9.11).
public enum MetricTerm: String, CaseIterable, Hashable, Sendable, Codable, Identifiable {
    // CPU
    case cpuUsage = "cpu_usage"
    case loadAverage = "load_average"
    case peCores = "pe_cores"

    // Memory
    case memoryPressure = "memory_pressure"
    case swap = "swap"
    case compressed = "compressed"
    case wired = "wired"
    case activeInactivePages = "active_inactive_pages"

    // GPU
    case gpuEngines = "gpu_engines"
    case vramWorkingSet = "vram_working_set"

    // Thermal
    case thermalState = "thermal_state"
    case throttling = "throttling"

    // Fans
    case fanRpmRange = "fan_rpm_range"

    // Network
    case rssi = "rssi"
    case snr = "snr"

    // Disk
    case iops = "iops"
    case diskSpace = "disk_space"

    // Power / Battery
    case cycleCount = "cycle_count"
    case maxCapacity = "max_capacity"
    case batteryCharge = "battery_charge"

    public var id: String { rawValue }
}

/// Pure, offline explanation for a single metric term (ADR 0006 / ADR 0011).
public struct GlossaryEntry: Hashable, Sendable, Identifiable {
    public let key: MetricTerm
    public let category: MetricCategory
    public let title: String
    public let summary: String
    public let typical: String

    public var id: MetricTerm { key }
    /// Alias matching design doc naming (`meaning`).
    public var meaning: String { summary }
    /// Alias matching task doc naming (`learnMore`).
    public var learnMore: String { typical }

    public init(
        key: MetricTerm,
        category: MetricCategory,
        title: String,
        summary: String,
        typical: String
    ) {
        self.key = key
        self.category = category
        self.title = title
        self.summary = summary
        self.typical = typical
    }
}

/// Offline metric glossary registry used by `InfoButton` popovers and the `?` glossary sheet.
public enum MetricGlossary {
    /// Every term that must resolve to a valid, non-empty glossary entry.
    public static let requiredKeys: [MetricTerm] = MetricTerm.allCases

    public static let allEntries: [GlossaryEntry] = [
        // MARK: CPU
        GlossaryEntry(
            key: .cpuUsage,
            category: .cpu,
            title: "CPU Utilization",
            summary: "Percentage of total processor capacity spent running apps (User) and macOS kernel tasks (System) versus sitting Idle.",
            typical: "5–25% at rest or browsing; sustained 85%+ triggers alerts when enabled."
        ),
        GlossaryEntry(
            key: .loadAverage,
            category: .cpu,
            title: "Load Average",
            summary: "Average number of runnable or uninterruptible processes waiting for CPU or I/O over the last 1, 5, and 15 minutes.",
            typical: "Healthy when below your logical core count. Sustained values above core count mean tasks are queuing."
        ),
        GlossaryEntry(
            key: .peCores,
            category: .cpu,
            title: "Performance & Efficiency Cores",
            summary: "Apple Silicon splits work between high-speed P-cores for demanding tasks and power-saving E-cores for background work.",
            typical: "E-cores stay active during light use; P-cores ramp up for builds, renders, or heavy apps."
        ),

        // MARK: Memory
        GlossaryEntry(
            key: .memoryPressure,
            category: .memory,
            title: "Memory Pressure",
            summary: "macOS's signal of how hard the virtual memory system is working to satisfy RAM requests, factoring in free, compressed, and swap activity.",
            typical: "Normal (green) is healthy. Warning (amber) means macOS is compressing heavily; Critical (red) causes slowdowns."
        ),
        GlossaryEntry(
            key: .swap,
            category: .memory,
            title: "Swap Memory",
            summary: "Disk space on your SSD temporarily used by macOS to hold memory pages that could not stay in physical RAM.",
            typical: "0 B to a few hundred MiB is normal. Multi-gigabyte swap growth with high pressure indicates RAM contention."
        ),
        GlossaryEntry(
            key: .compressed,
            category: .memory,
            title: "Compressed Memory",
            summary: "Inactive RAM pages shrunk in place by macOS so more data fits in physical memory without writing to SSD swap.",
            typical: "0.5–4 GiB is common under multitasking; large compressed memory with Warning pressure precedes swapping."
        ),
        GlossaryEntry(
            key: .wired,
            category: .memory,
            title: "Wired Memory",
            summary: "Memory locked in physical RAM by the macOS kernel and drivers that cannot be compressed or paged out to disk.",
            typical: "Usually 1.5–4 GiB depending on macOS version, kernel extensions, and integrated GPU allocations."
        ),
        GlossaryEntry(
            key: .activeInactivePages,
            category: .memory,
            title: "Active & Inactive Pages",
            summary: "Active pages were recently accessed by running apps; Inactive pages hold recent data kept cached for fast reuse if needed again.",
            typical: "macOS reclaims Inactive pages automatically before resorting to swap."
        ),

        // MARK: GPU
        GlossaryEntry(
            key: .gpuEngines,
            category: .gpu,
            title: "GPU Engines",
            summary: "Device shows overall GPU busyness, while Renderer (fragment/compute shaders) and Tiler (geometry binning) track Apple GPU pipeline stages.",
            typical: "Below 25% during desktop compositing; spikes during graphics, Metal compute, or video work."
        ),
        GlossaryEntry(
            key: .vramWorkingSet,
            category: .gpu,
            title: "VRAM Working Set",
            summary: "Graphics memory currently allocated by Metal apps compared against the system's recommended maximum GPU budget.",
            typical: "Staying under 75% of recommended max keeps frame times smooth without memory paging."
        ),

        // MARK: Thermal
        GlossaryEntry(
            key: .thermalState,
            category: .thermal,
            title: "Thermal Pressure State",
            summary: "macOS's system-wide thermal classification (Nominal, Fair, Serious, Critical) combining die temperatures and cooling headroom.",
            typical: "Nominal under everyday workloads; Fair during sustained bursts; Serious or Critical indicates thermal limits."
        ),
        GlossaryEntry(
            key: .throttling,
            category: .thermal,
            title: "Thermal Throttling",
            summary: "Automatic reduction of CPU or GPU clock speeds by macOS when cooling cannot keep silicon within safe temperature limits.",
            typical: "Does not occur at Nominal or Fair thermal states; begins at Serious or Critical thermal pressure."
        ),

        // MARK: Fans
        GlossaryEntry(
            key: .fanRpmRange,
            category: .fan,
            title: "Fan RPM & Speed Range",
            summary: "Live revolutions per minute plotted between each fan's hardware minimum and maximum speeds managed by macOS.",
            typical: "Fans often idle at minimum RPM (or 0 RPM on Macs with zero-RPM mode) and ramp smoothly under sustained heat."
        ),

        // MARK: Network
        GlossaryEntry(
            key: .rssi,
            category: .network,
            title: "RSSI (Signal Strength)",
            summary: "Received Signal Strength Indicator measured in dBm; values closer to 0 mean a stronger Wi-Fi signal.",
            typical: "-30 to -60 dBm is strong; -60 to -75 dBm is fair; below -80 dBm often causes drops or slow speeds."
        ),
        GlossaryEntry(
            key: .snr,
            category: .network,
            title: "SNR (Signal-to-Noise Ratio)",
            summary: "Margin in decibels (dB) between your Wi-Fi signal (RSSI) and background radio interference (Noise Floor).",
            typical: "25 dB or higher gives fast, reliable links; 15–25 dB is usable; below 15 dB degrades throughput."
        ),

        // MARK: Disk
        GlossaryEntry(
            key: .iops,
            category: .disk,
            title: "IOPS (I/O Operations/s)",
            summary: "Number of individual read or write storage requests completed per second, alongside raw MB/s throughput.",
            typical: "Tens of IOPS when idle; thousands to tens of thousands during builds, indexing, or large transfers."
        ),
        GlossaryEntry(
            key: .diskSpace,
            category: .disk,
            title: "Disk Space & Purgeable Storage",
            summary: "Percentage of volume capacity occupied by files. Keeping free headroom prevents swap stalls and APFS snapshot pressure.",
            typical: "Keep at least 10–15% free space on the boot volume for smooth macOS operation and updates."
        ),

        // MARK: Power
        GlossaryEntry(
            key: .cycleCount,
            category: .power,
            title: "Battery Cycle Count",
            summary: "Total cumulative full-charge equivalents (100% discharged and recharged, across one or more partial sessions).",
            typical: "Modern MacBook batteries are rated for up to 1,000 cycles before reaching ~80% of original capacity."
        ),
        GlossaryEntry(
            key: .maxCapacity,
            category: .power,
            title: "Maximum Battery Capacity",
            summary: "Current full-charge capacity compared with the battery's original factory design capacity in milliamp-hours (mAh).",
            typical: "80–100% is normal for a healthy battery; below 80% may show a Service Recommended notice."
        ),
        GlossaryEntry(
            key: .batteryCharge,
            category: .power,
            title: "Battery Charge Level",
            summary: "Current percentage of battery energy remaining relative to its current maximum capacity.",
            typical: "Low-battery alerts usually trigger at 15–20%; Optimized Battery Charging may pause at 80% on AC."
        )
    ]

    private static let entriesByKey: [MetricTerm: GlossaryEntry] = {
        Dictionary(uniqueKeysWithValues: allEntries.map { ($0.key, $0) })
    }()

    /// Looks up the glossary entry for a typed `MetricTerm`.
    public static func entry(for term: MetricTerm) -> GlossaryEntry {
        if let found = entriesByKey[term] {
            return found
        }
        preconditionFailure("Missing MetricGlossary entry for \(term.rawValue)")
    }

    /// Looks up a glossary entry by raw string key, returning `nil` for unknown keys.
    public static func entry(forKey key: String) -> GlossaryEntry? {
        guard let term = MetricTerm(rawValue: key) else { return nil }
        return entry(for: term)
    }

    /// Returns all glossary entries associated with `category`, preserving canonical order.
    public static func entries(for category: MetricCategory) -> [GlossaryEntry] {
        allEntries.filter { $0.category == category }
    }

    /// Returns the relevant glossary entries for a panel destination (the category's entries,
    /// or all enabled categories' entries when viewing Overview).
    public static func entries(
        for destination: PanelDestination,
        enabledCategories: Set<MetricCategory> = Set(MetricCategory.allCases)
    ) -> [GlossaryEntry] {
        switch destination {
        case .category(let category):
            return entries(for: category)
        case .overview:
            return MetricCategory.allCases
                .filter { enabledCategories.contains($0) }
                .flatMap { entries(for: $0) }
        }
    }
}
