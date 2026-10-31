import Foundation

/// A lightweight timestamped scalar data point for extended history trend charts (Task 7.6).
public struct ScalarPoint: Sendable, Equatable, Codable {
    public let timestamp: Date
    public let value: Double

    public init(timestamp: Date = Date(), value: Double) {
        self.timestamp = timestamp
        self.value = value
    }
}

/// Identifiers for chartable scalar series retained across extended time horizons (1m / 5m / 15m).
public enum ScalarSeriesKey: String, CaseIterable, Identifiable, Sendable, Codable {
    case cpuUser
    case cpuSystem
    case memoryUsedPercent
    case gpuUtilization
    case thermalPeakCelsius
    case fanMaxRPM
    case networkInBytesPerSec
    case networkOutBytesPerSec
    case diskReadBytesPerSec
    case diskWriteBytesPerSec
    case powerWatts

    public var id: String { rawValue }
}

/// An in-memory, fixed-capacity ring buffer store per metric category holding the
/// last N samples for live graph rendering and telemetry inspection (Requirement 10.2).
///
/// Telemetry is held strictly in memory and is never persisted to disk or sent over
/// the network (ADR 0006).
public struct MetricsStore: Sendable, Equatable {
    /// Default number of samples retained per category (e.g., 60 samples).
    public static let defaultCapacity: Int = 60

    /// Extended number of samples retained for lightweight scalar series buffers (900 samples = 15m @ 1s).
    public static let defaultScalarCapacity: Int = 900

    private var buffers: [MetricCategory: RingBuffer<MetricReading>]
    private var scalarBuffers: [ScalarSeriesKey: RingBuffer<ScalarPoint>]
    public let defaultBufferCapacity: Int
    public let categoryCapacities: [MetricCategory: Int]
    public let scalarCapacity: Int

    /// Initializes a `MetricsStore` with a default capacity and optional per-category overrides.
    /// - Parameters:
    ///   - defaultCapacity: The capacity used for categories not explicitly overridden. Must be > 0.
    ///   - categoryCapacities: Optional per-category capacity overrides. All values must be > 0.
    ///   - scalarCapacity: The capacity for extended scalar buffers (default 900). Must be > 0.
    public init(
        defaultCapacity: Int = MetricsStore.defaultCapacity,
        categoryCapacities: [MetricCategory: Int] = [:],
        scalarCapacity: Int = MetricsStore.defaultScalarCapacity
    ) {
        precondition(defaultCapacity > 0, "defaultCapacity must be > 0")
        precondition(scalarCapacity > 0, "scalarCapacity must be > 0")
        for (category, cap) in categoryCapacities {
            precondition(cap > 0, "Capacity for \(category) must be > 0")
        }

        self.defaultBufferCapacity = defaultCapacity
        self.categoryCapacities = categoryCapacities
        self.scalarCapacity = scalarCapacity

        var initialBuffers: [MetricCategory: RingBuffer<MetricReading>] = [:]
        for category in MetricCategory.allCases {
            let cap = categoryCapacities[category] ?? defaultCapacity
            initialBuffers[category] = RingBuffer<MetricReading>(capacity: cap)
        }
        self.buffers = initialBuffers

        var initialScalars: [ScalarSeriesKey: RingBuffer<ScalarPoint>] = [:]
        for key in ScalarSeriesKey.allCases {
            initialScalars[key] = RingBuffer<ScalarPoint>(capacity: scalarCapacity)
        }
        self.scalarBuffers = initialScalars
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
        recordScalarPoints(for: reading)
    }

    private mutating func recordScalarPoints(for reading: MetricReading) {
        switch reading {
        case .cpu(let s):
            scalarBuffers[.cpuUser]?.append(ScalarPoint(timestamp: s.timestamp, value: s.value.user))
            scalarBuffers[.cpuSystem]?.append(ScalarPoint(timestamp: s.timestamp, value: s.value.system))
        case .memory(let s):
            if s.value.total > 0 {
                let ratio = (Double(s.value.used) / Double(s.value.total)) * 100.0
                scalarBuffers[.memoryUsedPercent]?.append(ScalarPoint(timestamp: s.timestamp, value: ratio))
            }
        case .gpu(let s):
            if let u = s.value.utilization {
                scalarBuffers[.gpuUtilization]?.append(ScalarPoint(timestamp: s.timestamp, value: u))
            }
        case .thermal(let s):
            if let peak = s.value.peakTemperatureCelsius {
                scalarBuffers[.thermalPeakCelsius]?.append(ScalarPoint(timestamp: s.timestamp, value: peak))
            }
        case .fan(let s):
            let maxRPM = Double(s.value.fans.map(\.rpm).max() ?? 0)
            scalarBuffers[.fanMaxRPM]?.append(ScalarPoint(timestamp: s.timestamp, value: maxRPM))
        case .network(let s):
            scalarBuffers[.networkInBytesPerSec]?.append(ScalarPoint(timestamp: s.timestamp, value: s.value.totalBytesInPerSec))
            scalarBuffers[.networkOutBytesPerSec]?.append(ScalarPoint(timestamp: s.timestamp, value: s.value.totalBytesOutPerSec))
        case .disk(let s):
            if let io = s.value.io {
                scalarBuffers[.diskReadBytesPerSec]?.append(ScalarPoint(timestamp: s.timestamp, value: io.bytesReadPerSec))
                scalarBuffers[.diskWriteBytesPerSec]?.append(ScalarPoint(timestamp: s.timestamp, value: io.bytesWrittenPerSec))
            }
        case .power(let s):
            if let draw = s.value.powerDrawWatts {
                scalarBuffers[.powerWatts]?.append(ScalarPoint(timestamp: s.timestamp, value: draw))
            } else if let charge = s.value.charge {
                scalarBuffers[.powerWatts]?.append(ScalarPoint(timestamp: s.timestamp, value: charge))
            }
        case .unavailable:
            break
        }
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

    /// Returns the availability status of the most recent reading for a category, if any.
    public func latestAvailability(for category: MetricCategory) -> Availability? {
        latest(for: category)?.availability
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

    // MARK: - Querying Scalar Trends (Task 7.6)

    /// Returns all timestamped points stored in the scalar buffer for a given series key.
    public func scalarPoints(for key: ScalarSeriesKey) -> [ScalarPoint] {
        scalarBuffers[key]?.elements ?? []
    }

    /// Returns the number of scalar points stored for a series key.
    public func scalarCount(for key: ScalarSeriesKey) -> Int {
        scalarBuffers[key]?.count ?? 0
    }

    /// Queries the scalar history for a given series key over a specified time window (duration in seconds),
    /// downsampled to at most `maxPoints` using spike-preserving bucket downsampling.
    public func scalarHistory(
        for key: ScalarSeriesKey,
        duration: TimeInterval? = nil,
        maxPoints: Int = 120
    ) -> [Double] {
        guard let buffer = scalarBuffers[key] else { return [] }
        let points = buffer.elements
        guard !points.isEmpty else { return [] }

        let filtered: [Double]
        if let duration = duration, duration > 0, let newest = points.last?.timestamp {
            let cutoff = newest.addingTimeInterval(-duration)
            filtered = points.filter { $0.timestamp > cutoff }.map(\.value)
        } else {
            filtered = points.map(\.value)
        }

        return Downsampler.downsampleSpikePreserving(filtered, targetCount: maxPoints)
    }

    // MARK: - Resetting & Clearing

    /// Clears all readings stored for a specific category.
    public mutating func clear(category: MetricCategory) {
        buffers[category]?.clear()
        switch category {
        case .cpu:
            scalarBuffers[.cpuUser]?.clear()
            scalarBuffers[.cpuSystem]?.clear()
        case .memory:
            scalarBuffers[.memoryUsedPercent]?.clear()
        case .gpu:
            scalarBuffers[.gpuUtilization]?.clear()
        case .thermal:
            scalarBuffers[.thermalPeakCelsius]?.clear()
        case .fan:
            scalarBuffers[.fanMaxRPM]?.clear()
        case .network:
            scalarBuffers[.networkInBytesPerSec]?.clear()
            scalarBuffers[.networkOutBytesPerSec]?.clear()
        case .disk:
            scalarBuffers[.diskReadBytesPerSec]?.clear()
            scalarBuffers[.diskWriteBytesPerSec]?.clear()
        case .power:
            scalarBuffers[.powerWatts]?.clear()
        }
    }

    /// Clears all readings across all categories.
    public mutating func clearAll() {
        for category in MetricCategory.allCases {
            buffers[category]?.clear()
        }
        for key in ScalarSeriesKey.allCases {
            scalarBuffers[key]?.clear()
        }
    }
}
