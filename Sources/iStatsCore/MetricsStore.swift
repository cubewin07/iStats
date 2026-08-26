import Foundation

/// An in-memory, fixed-capacity ring buffer store per metric category holding the
/// last N samples for live graph rendering and telemetry inspection (Requirement 10.2).
///
/// Telemetry is held strictly in memory and is never persisted to disk or sent over
/// the network (ADR 0006).
public struct MetricsStore: Sendable, Equatable {
    /// Default number of samples retained per category (e.g., 60 samples).
    public static let defaultCapacity: Int = 60

    private var buffers: [MetricCategory: RingBuffer<MetricReading>]
    public let defaultBufferCapacity: Int
    public let categoryCapacities: [MetricCategory: Int]

    /// Initializes a `MetricsStore` with a default capacity and optional per-category overrides.
    /// - Parameters:
    ///   - defaultCapacity: The capacity used for categories not explicitly overridden. Must be > 0.
    ///   - categoryCapacities: Optional per-category capacity overrides. All values must be > 0.
    public init(
        defaultCapacity: Int = MetricsStore.defaultCapacity,
        categoryCapacities: [MetricCategory: Int] = [:]
    ) {
        precondition(defaultCapacity > 0, "defaultCapacity must be > 0")
        for (category, cap) in categoryCapacities {
            precondition(cap > 0, "Capacity for \(category) must be > 0")
        }

        self.defaultBufferCapacity = defaultCapacity
        self.categoryCapacities = categoryCapacities

        var initialBuffers: [MetricCategory: RingBuffer<MetricReading>] = [:]
        for category in MetricCategory.allCases {
            let cap = categoryCapacities[category] ?? defaultCapacity
            initialBuffers[category] = RingBuffer<MetricReading>(capacity: cap)
        }
        self.buffers = initialBuffers
    }

    // MARK: - Appending Samples

    /// Appends a new reading into the corresponding category's ring buffer.
    /// If at capacity, evicts the oldest reading.
    public mutating func append(_ reading: MetricReading) {
        let category = reading.category
        if buffers[category] == nil {
            let cap = categoryCapacities[category] ?? defaultBufferCapacity
            buffers[category] = RingBuffer<MetricReading>(capacity: cap)
        }
        buffers[category]?.append(reading)
    }

    /// Appends multiple readings in chronological order.
    public mutating func append(_ readings: [MetricReading]) {
        for reading in readings {
            append(reading)
        }
    }

    /// Convenience method to wrap and append a raw value.
    public mutating func record(
        category: MetricCategory,
        value: Sendable,
        timestamp: Date = Date(),
        availability: Availability = .available
    ) {
        let reading = MetricReading.wrap(
            category: category,
            value: value,
            timestamp: timestamp,
            availability: availability
        )
        append(reading)
    }

    /// Convenience method to record an unavailable reading.
    public mutating func recordUnavailable(
        category: MetricCategory,
        reason: String,
        timestamp: Date = Date()
    ) {
        let reading = MetricReading.unavailable(
            category: category,
            reason: reason,
            timestamp: timestamp
        )
        append(reading)
    }

    // MARK: - Querying Readings

    /// Returns all readings for a category in chronological order (oldest first, newest last).
    public func readings(for category: MetricCategory) -> [MetricReading] {
        buffers[category]?.elements ?? []
    }

    /// Returns the most recent reading for a category, if any.
    public func latest(for category: MetricCategory) -> MetricReading? {
        buffers[category]?.latest
    }

    /// Returns the number of readings stored for a category.
    public func count(for category: MetricCategory) -> Int {
        buffers[category]?.count ?? 0
    }

    /// Returns the capacity of the ring buffer for a category.
    public func capacity(for category: MetricCategory) -> Int {
        buffers[category]?.capacity ?? (categoryCapacities[category] ?? defaultBufferCapacity)
    }

    /// Returns whether the buffer for a category is empty.
    public func isEmpty(for category: MetricCategory) -> Bool {
        buffers[category]?.isEmpty ?? true
    }

    /// Returns whether the buffer for a category is full (at capacity).
    public func isFull(for category: MetricCategory) -> Bool {
        buffers[category]?.isFull ?? false
    }

    /// Subscript to access readings for a category.
    public subscript(category: MetricCategory) -> [MetricReading] {
        readings(for: category)
    }

    /// Total number of stored readings across all categories.
    public var totalCount: Int {
        buffers.values.reduce(0) { $0 + $1.count }
    }

    /// All categories that currently contain at least one reading.
    public var activeCategories: [MetricCategory] {
        MetricCategory.allCases.filter { count(for: $0) > 0 }
    }

    // MARK: - Typed Extractors

    /// The latest available CPU sample, if present.
    public func latestCPU() -> Sample<CPUSample>? {
        guard case .cpu(let s) = latest(for: .cpu) else { return nil }
        return s
    }

    /// The latest available Memory sample, if present.
    public func latestMemory() -> Sample<MemorySample>? {
        guard case .memory(let s) = latest(for: .memory) else { return nil }
        return s
    }

    /// The latest available Thermal sample, if present.
    public func latestThermal() -> Sample<ThermalSample>? {
        guard case .thermal(let s) = latest(for: .thermal) else { return nil }
        return s
    }

    /// The latest available Fan sample, if present.
    public func latestFan() -> Sample<FanSample>? {
        guard case .fan(let s) = latest(for: .fan) else { return nil }
        return s
    }

    /// The latest available GPU sample, if present.
    public func latestGPU() -> Sample<GPUSample>? {
        guard case .gpu(let s) = latest(for: .gpu) else { return nil }
        return s
    }

    /// The latest available Network sample, if present.
    public func latestNetwork() -> Sample<NetworkSample>? {
        guard case .network(let s) = latest(for: .network) else { return nil }
        return s
    }

    /// The latest available Disk sample, if present.
    public func latestDisk() -> Sample<DiskSample>? {
        guard case .disk(let s) = latest(for: .disk) else { return nil }
        return s
    }

    /// The latest available Power sample, if present.
    public func latestPower() -> Sample<PowerSample>? {
        guard case .power(let s) = latest(for: .power) else { return nil }
        return s
    }

    /// All valid CPU samples currently in history, in chronological order.
    public func cpuHistory() -> [Sample<CPUSample>] {
        readings(for: .cpu).compactMap {
            if case .cpu(let s) = $0 { return s }
            return nil
        }
    }

    /// All valid Memory samples currently in history, in chronological order.
    public func memoryHistory() -> [Sample<MemorySample>] {
        readings(for: .memory).compactMap {
            if case .memory(let s) = $0 { return s }
            return nil
        }
    }

    /// All valid Thermal samples currently in history, in chronological order.
    public func thermalHistory() -> [Sample<ThermalSample>] {
        readings(for: .thermal).compactMap {
            if case .thermal(let s) = $0 { return s }
            return nil
        }
    }

    /// All valid Fan samples currently in history, in chronological order.
    public func fanHistory() -> [Sample<FanSample>] {
        readings(for: .fan).compactMap {
            if case .fan(let s) = $0 { return s }
            return nil
        }
    }

    /// All valid GPU samples currently in history, in chronological order.
    public func gpuHistory() -> [Sample<GPUSample>] {
        readings(for: .gpu).compactMap {
            if case .gpu(let s) = $0 { return s }
            return nil
        }
    }

    /// All valid Network samples currently in history, in chronological order.
    public func networkHistory() -> [Sample<NetworkSample>] {
        readings(for: .network).compactMap {
            if case .network(let s) = $0 { return s }
            return nil
        }
    }

    /// All valid Disk samples currently in history, in chronological order.
    public func diskHistory() -> [Sample<DiskSample>] {
        readings(for: .disk).compactMap {
            if case .disk(let s) = $0 { return s }
            return nil
        }
    }

    /// All valid Power samples currently in history, in chronological order.
    public func powerHistory() -> [Sample<PowerSample>] {
        readings(for: .power).compactMap {
            if case .power(let s) = $0 { return s }
            return nil
        }
    }

    // MARK: - Resetting & Clearing

    /// Clears all readings stored for a specific category.
    public mutating func clear(category: MetricCategory) {
        buffers[category]?.clear()
    }

    /// Clears all readings across all categories.
    public mutating func clearAll() {
        for category in MetricCategory.allCases {
            buffers[category]?.clear()
        }
    }
}
