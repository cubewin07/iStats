import Foundation

/// A type-erased wrapper for any `Sampler` conforming type or sample closure.
public struct AnySampler: Sendable {
    /// The category of metrics this sampler produces.
    public let category: MetricCategory
    private let _sample: @Sendable () throws -> Sendable

    /// Wraps an existing `Sampler` instance.
    public init<S: Sampler>(_ sampler: S) {
        self.category = sampler.category
        self._sample = { try sampler.sample() }
    }

    /// Creates an `AnySampler` with an explicit category and sample closure.
    public init(category: MetricCategory, sample: @escaping @Sendable () throws -> Sendable) {
        self.category = category
        self._sample = sample
    }

    /// Reads current values from the wrapped sampler. Runs off the main thread.
    public func sample() throws -> Sendable {
        try _sample()
    }
}

/// A typed reading produced by the sampling layer across all metric categories.
public enum MetricReading: Sendable, Equatable {
    case cpu(Sample<CPUSample>)
    case memory(Sample<MemorySample>)
    case thermal(Sample<ThermalSample>)
    case fan(Sample<FanSample>)
    case gpu(Sample<GPUSample>)
    case network(Sample<NetworkSample>)
    case disk(Sample<DiskSample>)
    case power(Sample<PowerSample>)
    case unavailable(category: MetricCategory, reason: String, timestamp: Date)

    /// The metric category associated with this reading.
    public var category: MetricCategory {
        switch self {
        case .cpu: return .cpu
        case .memory: return .memory
        case .thermal: return .thermal
        case .fan: return .fan
        case .gpu: return .gpu
        case .network: return .network
        case .disk: return .disk
        case .power: return .power
        case .unavailable(let category, _, _): return category
        }
    }

    /// The timestamp when this reading was captured.
    public var timestamp: Date {
        switch self {
        case .cpu(let s): return s.timestamp
        case .memory(let s): return s.timestamp
        case .thermal(let s): return s.timestamp
        case .fan(let s): return s.timestamp
        case .gpu(let s): return s.timestamp
        case .network(let s): return s.timestamp
        case .disk(let s): return s.timestamp
        case .power(let s): return s.timestamp
        case .unavailable(_, _, let t): return t
        }
    }

    /// The availability status of this reading.
    public var availability: Availability {
        switch self {
        case .cpu(let s): return s.availability
        case .memory(let s): return s.availability
        case .thermal(let s): return s.availability
        case .fan(let s): return s.availability
        case .gpu(let s): return s.availability
        case .network(let s): return s.availability
        case .disk(let s): return s.availability
        case .power(let s): return s.availability
        case .unavailable(_, let reason, _): return .unavailable(reason: reason)
        }
    }

    /// Wraps a raw output value into the corresponding `MetricReading` case.
    public static func wrap(
        category: MetricCategory,
        value: Sendable,
        timestamp: Date = Date(),
        availability: Availability = .available
    ) -> MetricReading {
        switch category {
        case .cpu:
            if let cpu = value as? CPUSample {
                return .cpu(Sample(value: cpu, timestamp: timestamp, availability: availability))
            } else if let sample = value as? Sample<CPUSample> {
                return .cpu(sample)
            }
        case .memory:
            if let mem = value as? MemorySample {
                return .memory(Sample(value: mem, timestamp: timestamp, availability: availability))
            } else if let sample = value as? Sample<MemorySample> {
                return .memory(sample)
            }
        case .thermal:
            if let th = value as? ThermalSample {
                return .thermal(Sample(value: th, timestamp: timestamp, availability: availability))
            } else if let sample = value as? Sample<ThermalSample> {
                return .thermal(sample)
            }
        case .fan:
            if let fan = value as? FanSample {
                return .fan(Sample(value: fan, timestamp: timestamp, availability: availability))
            } else if let sample = value as? Sample<FanSample> {
                return .fan(sample)
            }
        case .gpu:
            if let gpu = value as? GPUSample {
                return .gpu(Sample(value: gpu, timestamp: timestamp, availability: availability))
            } else if let sample = value as? Sample<GPUSample> {
                return .gpu(sample)
            }
        case .network:
            if let net = value as? NetworkSample {
                return .network(Sample(value: net, timestamp: timestamp, availability: availability))
            } else if let sample = value as? Sample<NetworkSample> {
                return .network(sample)
            }
        case .disk:
            if let disk = value as? DiskSample {
                return .disk(Sample(value: disk, timestamp: timestamp, availability: availability))
            } else if let sample = value as? Sample<DiskSample> {
                return .disk(sample)
            }
        case .power:
            if let power = value as? PowerSample {
                return .power(Sample(value: power, timestamp: timestamp, availability: availability))
            } else if let sample = value as? Sample<PowerSample> {
                return .power(sample)
            }
        }
        return .unavailable(
            category: category,
            reason: "Unexpected sample output type: \(type(of: value))",
            timestamp: timestamp
        )
    }
}

/// A central background scheduler that periodically executes registered samplers
/// on background tasks, isolates errors and timeouts per category, and publishes
/// results to downstream consumers (ADR 0002, Requirements 12.1, 12.3, 12.4).
public actor SampleScheduler {
    public typealias SampleHandler = @Sendable (MetricReading) -> Void
    public typealias MainActorSampleHandler = @Sendable @MainActor (MetricReading) -> Void

    // MARK: - Cadence Key
    private struct CadenceKey: Hashable, Sendable {
        let milliseconds: Int
        var seconds: TimeInterval { Double(milliseconds) / 1000.0 }

        init(_ seconds: TimeInterval) {
            self.milliseconds = max(1, Int((seconds * 1000.0).rounded()))
        }
    }

    private var samplers: [MetricCategory: AnySampler] = [:]
    private var intervals: [MetricCategory: TimeInterval] = [:]
    private var enabledCategories: Set<MetricCategory> = Set(MetricCategory.allCases)
    private var defaultInterval: TimeInterval
    private var timeBudget: TimeInterval
    private var cadenceTasks: [CadenceKey: Task<Void, Never>] = [:]
    private var continuations: [UUID: AsyncStream<MetricReading>.Continuation] = [:]

    /// Configurable timer coalescing tolerance ratio (default: 0.15, meaning 15% leeway).
    public private(set) var toleranceRatio: Double = 0.15

    /// Optional general callback invoked when a sample reading is published.
    public var onSample: SampleHandler?

    /// Optional `@MainActor` callback invoked on the main thread when a reading is published.
    public var onMainActorSample: MainActorSampleHandler?

    /// Whether the scheduler is currently running periodic sampling.
    public private(set) var isRunning: Bool = false

    /// Creates a new `SampleScheduler`.
    /// - Parameters:
    ///   - defaultInterval: The default sampling interval in seconds (default: 2.0).
    ///   - timeBudget: The maximum execution duration allowed per sampler before timing out (default: 2.0).
    ///   - toleranceRatio: The timer tolerance ratio for sleep coalescing (default: 0.15).
    ///   - onSample: Optional callback for reading updates.
    ///   - onMainActorSample: Optional `@MainActor` callback for reading updates.
    public init(
        defaultInterval: TimeInterval = 2.0,
        timeBudget: TimeInterval = 2.0,
        toleranceRatio: Double = 0.15,
        onSample: SampleHandler? = nil,
        onMainActorSample: MainActorSampleHandler? = nil
    ) {
        self.defaultInterval = max(defaultInterval, 0.001)
        self.timeBudget = max(timeBudget, 0.001)
        self.toleranceRatio = max(0.0, min(0.5, toleranceRatio))
        self.onSample = onSample
        self.onMainActorSample = onMainActorSample
    }

    /// Sets the general onSample callback.
    public func setOnSample(_ handler: SampleHandler?) {
        self.onSample = handler
    }

    /// Sets the MainActor onSample callback.
    public func setOnMainActorSample(_ handler: MainActorSampleHandler?) {
        self.onMainActorSample = handler
    }

    /// Sets the timer coalescing tolerance ratio (clamped to 0.0...0.5).
    public func setToleranceRatio(_ ratio: Double) {
        self.toleranceRatio = max(0.0, min(0.5, ratio))
    }

    deinit {
        for task in cadenceTasks.values {
            task.cancel()
        }
        for continuation in continuations.values {
            continuation.finish()
        }
    }

    /// An `AsyncStream` delivering all live sampled metrics as they are produced.
    nonisolated public var stream: AsyncStream<MetricReading> {
        AsyncStream { continuation in
            let id = UUID()
            Task {
                await self.addContinuation(id: id, continuation: continuation)
            }
            continuation.onTermination = { @Sendable _ in
                Task {
                    await self.removeContinuation(id: id)
                }
            }
        }
    }

    private func addContinuation(id: UUID, continuation: AsyncStream<MetricReading>.Continuation) {
        continuations[id] = continuation
    }

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    // MARK: - Registration & Configuration

    /// Registers a concrete `Sampler`.
    public func register<S: Sampler>(_ sampler: S) {
        register(AnySampler(sampler))
    }

    /// Registers a type-erased `AnySampler`.
    public func register(_ sampler: AnySampler) {
        samplers[sampler.category] = sampler
        if isRunning && isEnabled(category: sampler.category) {
            syncCadenceLoops()
        }
    }

    /// Unregisters the sampler for the given category.
    public func unregister(category: MetricCategory) {
        samplers.removeValue(forKey: category)
        if isRunning {
            syncCadenceLoops()
        }
    }

    /// Returns whether a sampler is registered for the specified category.
    public func isRegistered(category: MetricCategory) -> Bool {
        samplers[category] != nil
    }

    /// Returns the list of all registered metric categories.
    public func registeredCategories() -> [MetricCategory] {
        Array(samplers.keys)
    }

    /// Enables or disables sampling for a specific metric category.
    public func setEnabled(category: MetricCategory, isEnabled: Bool) {
        if isEnabled {
            enabledCategories.insert(category)
        } else {
            enabledCategories.remove(category)
        }
        if isRunning {
            syncCadenceLoops()
        }
    }

    /// Returns whether the given category is enabled for sampling.
    public func isEnabled(category: MetricCategory) -> Bool {
        enabledCategories.contains(category)
    }

    /// Sets the sampling interval for a specific category.
    public func setInterval(category: MetricCategory, interval: TimeInterval) {
        intervals[category] = max(interval, 0.001)
        if isRunning {
            syncCadenceLoops()
        }
    }

    /// Gets the configured sampling interval for a specific category (or default).
    public func interval(for category: MetricCategory) -> TimeInterval {
        intervals[category] ?? defaultInterval
    }

    /// Sets the default sampling interval applied to categories without an explicit override.
    public func setDefaultInterval(_ interval: TimeInterval) {
        self.defaultInterval = max(interval, 0.001)
        if isRunning {
            syncCadenceLoops()
        }
    }

    /// Sets the timeout time budget for sampler executions.
    public func setTimeBudget(_ budget: TimeInterval) {
        self.timeBudget = max(budget, 0.001)
    }

    /// Gets the current time budget.
    public func getTimeBudget() -> TimeInterval {
        timeBudget
    }

    // MARK: - Lifecycle

    /// Starts periodic background sampling for all registered and enabled categories.
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        syncCadenceLoops()
    }

    /// Stops periodic sampling across all categories and cancels background tasks.
    public func stop() {
        guard isRunning else { return }
        isRunning = false
        for task in cadenceTasks.values {
            task.cancel()
        }
        cadenceTasks.removeAll()
    }

    // MARK: - Direct Sampling

    /// Triggers an immediate one-off sample for the given category, isolated from the periodic loop.
    public func sampleOnce(category: MetricCategory) async -> MetricReading? {
        guard let sampler = samplers[category] else { return nil }
        return await sampleWithTimeout(sampler: sampler, timeout: timeBudget)
    }

    /// Triggers immediate one-off samples for all registered and enabled categories.
    public func sampleAll() async -> [MetricReading] {
        var readings: [MetricReading] = []
        for category in MetricCategory.allCases {
            if let sampler = samplers[category], isEnabled(category: category) {
                let reading = await sampleWithTimeout(sampler: sampler, timeout: timeBudget)
                readings.append(reading)
            }
        }
        return readings
    }

    // MARK: - Internal Sampling & Batched Cadence Loops

    private func syncCadenceLoops() {
        guard isRunning else {
            for task in cadenceTasks.values { task.cancel() }
            cadenceTasks.removeAll()
            return
        }

        var neededCadences: Set<CadenceKey> = []
        for category in samplers.keys where isEnabled(category: category) {
            let intv = interval(for: category)
            neededCadences.insert(CadenceKey(intv))
        }

        for (cadence, task) in cadenceTasks where !neededCadences.contains(cadence) {
            task.cancel()
            cadenceTasks.removeValue(forKey: cadence)
        }

        for cadence in neededCadences where cadenceTasks[cadence] == nil {
            startCadenceLoop(for: cadence)
        }
    }

    private func activeCategories(for cadence: CadenceKey) -> [MetricCategory] {
        samplers.keys.filter { category in
            isEnabled(category: category) && CadenceKey(interval(for: category)) == cadence
        }
    }

    private func startCadenceLoop(for cadence: CadenceKey) {
        cadenceTasks[cadence]?.cancel()
        let intervalSeconds = cadence.seconds

        // Explicitly set .utility QoS to ensure tasks execute on Efficiency cores
        cadenceTasks[cadence] = Task(priority: .utility) { [weak self] in
            let clock = ContinuousClock()
            var nextTick = clock.now

            while !Task.isCancelled {
                guard let self = self else { break }

                let categories = await self.activeCategories(for: cadence)
                guard !categories.isEmpty else { break }

                // Batch dispatch all active categories concurrently on utility priority
                await withTaskGroup(of: Void.self) { group in
                    for category in categories {
                        guard let sampler = await self.samplers[category] else { continue }
                        group.addTask {
                            let timeout = await self.timeBudget
                            let reading = await self.sampleWithTimeout(sampler: sampler, timeout: timeout)
                            await self.publish(reading)
                        }
                    }
                }

                // Compute next tick & leeway
                nextTick = nextTick + .milliseconds(cadence.milliseconds)
                let now = clock.now
                if nextTick <= now {
                    nextTick = now + .milliseconds(cadence.milliseconds)
                }

                let ratio = await self.toleranceRatio
                let toleranceSeconds = max(0.005, min(0.5, intervalSeconds * ratio))
                let toleranceDuration = Duration.milliseconds(Int(toleranceSeconds * 1000.0))

                do {
                    try await clock.sleep(until: nextTick, tolerance: toleranceDuration)
                } catch {
                    break
                }
            }
        }
    }

    private func sampleWithTimeout(sampler: AnySampler, timeout: TimeInterval) async -> MetricReading {
        let category = sampler.category
        let timestamp = Date()
        let budgetNanos = UInt64(timeout * 1_000_000_000)

        do {
            let output = try await withThrowingTaskGroup(of: Sendable.self) { group in
                group.addTask {
                    try sampler.sample()
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: budgetNanos)
                    throw SamplerError.timedOut
                }

                guard let firstResult = try await group.next() else {
                    throw SamplerError.systemCallFailed("No result returned from sampler")
                }
                group.cancelAll()
                return firstResult
            }
            return MetricReading.wrap(category: category, value: output, timestamp: timestamp)
        } catch let error as SamplerError {
            let reason: String
            switch error {
            case .unsupported(let msg):
                reason = "Unsupported: \(msg)"
            case .systemCallFailed(let msg):
                reason = "System call failed: \(msg)"
            case .timedOut:
                reason = "Sample timed out after \(timeout)s"
            }
            return .unavailable(category: category, reason: reason, timestamp: timestamp)
        } catch {
            return .unavailable(category: category, reason: error.localizedDescription, timestamp: timestamp)
        }
    }

    private func publish(_ reading: MetricReading) {
        for continuation in continuations.values {
            continuation.yield(reading)
        }
        if let onSample = self.onSample {
            onSample(reading)
        }
        if let onMainActorSample = self.onMainActorSample {
            Task { @MainActor in
                onMainActorSample(reading)
            }
        }
    }
}
