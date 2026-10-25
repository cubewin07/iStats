import Foundation
import Combine
import IOKit.ps
import iStatsCore

/// A central `@MainActor` coordinator bridging background sampling from `SampleScheduler`
/// into the in-memory `MetricsStore` and publishing live updates to SwiftUI views and the menu bar
/// (Requirements 9.2, 9.4, 10.1, 10.2, 10.3, 12.1, ADR 0002).
@MainActor
public final class MetricsCoordinator: ObservableObject {
    // MARK: - Singleton

    /// Shared singleton coordinator instance for the application.
    public static let shared = MetricsCoordinator()

    // MARK: - Storage & Scheduler

    public let scheduler: SampleScheduler
    private let preferencesStore: PreferencesStore
    private let lowPowerModeProvider: @Sendable () -> Bool
    private var userOverrodeLowPowerPause: Bool = false
    private var cancellables = Set<AnyCancellable>()
    private var startTask: Task<Void, Never>?
    private var streamTask: Task<Void, Never>?
    nonisolated(unsafe) private var powerRunLoopSource: CFRunLoopSource?

    // MARK: - Published State

    /// In-memory ring buffer store holding live telemetry history.
    public private(set) var store: MetricsStore

    /// The latest available CPU sample.
    @Published public private(set) var latestCPU: Sample<CPUSample>?

    /// The latest available Memory sample.
    @Published public private(set) var latestMemory: Sample<MemorySample>?

    /// The latest available Network sample.
    @Published public private(set) var latestNetwork: Sample<NetworkSample>?

    /// The latest available Disk sample.
    @Published public private(set) var latestDisk: Sample<DiskSample>?

    /// The latest available Power sample.
    @Published public private(set) var latestPower: Sample<PowerSample>?

    /// The latest available Thermal sample.
    @Published public private(set) var latestThermal: Sample<ThermalSample>?

    /// The latest available Fan sample.
    @Published public private(set) var latestFan: Sample<FanSample>?

    /// The latest available GPU sample.
    @Published public private(set) var latestGPU: Sample<GPUSample>?

    /// Rolling chronological history of CPU samples queried on-demand from backing store.
    public var cpuHistory: [Sample<CPUSample>] { store.cpuHistory() }

    /// Rolling chronological history of Memory samples queried on-demand from backing store.
    public var memoryHistory: [Sample<MemorySample>] { store.memoryHistory() }

    /// Rolling chronological history of Network samples queried on-demand from backing store.
    public var networkHistory: [Sample<NetworkSample>] { store.networkHistory() }

    /// Rolling chronological history of Disk samples queried on-demand from backing store.
    public var diskHistory: [Sample<DiskSample>] { store.diskHistory() }

    /// Rolling chronological history of Power samples queried on-demand from backing store.
    public var powerHistory: [Sample<PowerSample>] { store.powerHistory() }

    /// Rolling chronological history of Thermal samples queried on-demand from backing store.
    public var thermalHistory: [Sample<ThermalSample>] { store.thermalHistory() }

    /// Rolling chronological history of Fan samples queried on-demand from backing store.
    public var fanHistory: [Sample<FanSample>] { store.fanHistory() }

    /// Rolling chronological history of GPU samples queried on-demand from backing store.
    public var gpuHistory: [Sample<GPUSample>] { store.gpuHistory() }

    /// Live availability status per metric category.
    @Published public private(set) var categoryAvailability: [MetricCategory: Availability] = [:]

    /// Whether the coordinator is actively sampling.
    @Published public private(set) var isRunning: Bool = false

    /// Whether macOS Low Power Mode (Battery Saving Mode) is currently active (Issue #12).
    @Published public private(set) var isLowPowerModeActive: Bool = false

    /// Whether sampling was automatically paused due to macOS Low Power Mode (Issue #12).
    @Published public private(set) var isAutoPausedByLowPowerMode: Bool = false

    // MARK: - Performance Instrumentation (Stage 4 Energy Optimization)

    /// Count of times a batch of readings was ingested in a single pass.
    public private(set) var batchIngestionCount: Int = 0

    /// Count of times a single reading was ingested (legacy / direct path).
    public private(set) var singleIngestionCount: Int = 0

    /// Resets ingestion telemetry counters (primarily for tests).
    public func resetPerformanceCounters() {
        batchIngestionCount = 0
        singleIngestionCount = 0
    }

    // MARK: - Initialization

    /// Creates a new `MetricsCoordinator`.
    /// - Parameters:
    ///   - scheduler: The `SampleScheduler` actor instance.
    ///   - store: The initial `MetricsStore`.
    ///   - preferencesStore: The preferences store to synchronize with.
    ///   - lowPowerModeProvider: Optional closure returning whether macOS Low Power Mode is active.
    public init(
        scheduler: SampleScheduler = SampleScheduler(),
        store: MetricsStore = MetricsStore(),
        preferencesStore: PreferencesStore = .shared,
        lowPowerModeProvider: (@Sendable () -> Bool)? = nil
    ) {
        let provider = lowPowerModeProvider ?? { ProcessInfo.processInfo.isLowPowerModeEnabled }
        self.scheduler = scheduler
        self.store = store
        self.preferencesStore = preferencesStore
        self.lowPowerModeProvider = provider
        self.isLowPowerModeActive = false
        self.isAutoPausedByLowPowerMode = preferencesStore.isSamplingPaused && preferencesStore.isAutoPausedByLowPowerMode

        setupPreferencesObservation()
        setupLowPowerModeObservation()

        if lowPowerModeProvider != nil || preferencesStore === PreferencesStore.shared {
            evaluateLowPowerModeState()
        } else {
            self.isLowPowerModeActive = provider()
        }
    }

    deinit {
        startTask?.cancel()
        streamTask?.cancel()
        teardownPowerNotifications()
    }

    // MARK: - Lifecycle

    /// Whether background sampling is currently paused in preferences (Issue #12).
    public var isSamplingPaused: Bool {
        preferencesStore.isSamplingPaused
    }

    /// Pauses background sampling and updates the persisted preference (Issue #12).
    public func pauseSampling() {
        setSamplingPaused(true)
    }

    /// Resumes background sampling and updates the persisted preference (Issue #12).
    public func resumeSampling() {
        setSamplingPaused(false)
    }

    /// Updates the sampling pause state in preferences and synchronizes the scheduler lifecycle (Issue #12).
    public func setSamplingPaused(_ paused: Bool) {
        isAutoPausedByLowPowerMode = false
        if preferencesStore.isAutoPausedByLowPowerMode {
            preferencesStore.isAutoPausedByLowPowerMode = false
        }
        if !paused && lowPowerModeProvider() {
            userOverrodeLowPowerPause = true
        }
        if preferencesStore.isSamplingPaused != paused {
            preferencesStore.isSamplingPaused = paused
        }
        if paused {
            stop()
        } else {
            performStart()
        }
    }

    /// Toggles the sampling pause state (Issue #12).
    public func toggleSamplingPaused() {
        setSamplingPaused(!preferencesStore.isSamplingPaused)
    }

    /// Evaluates the current macOS Low Power Mode state and auto-pauses sampling if enabled
    /// and the user has not manually resumed sampling during the active Low Power Mode session (Issue #12).
    public func evaluateLowPowerModeState() {
        let currentLowPower = lowPowerModeProvider()
        let previousLowPower = isLowPowerModeActive
        if isLowPowerModeActive != currentLowPower {
            isLowPowerModeActive = currentLowPower
        }

        if currentLowPower {
            if !previousLowPower {
                userOverrodeLowPowerPause = false
            }
            if preferencesStore.autoPauseOnLowPowerMode && !userOverrodeLowPowerPause {
                pauseSamplingForLowPowerMode()
            }
        } else {
            userOverrodeLowPowerPause = false
        }
    }

    private func pauseSamplingForLowPowerMode() {
        isAutoPausedByLowPowerMode = true
        if !preferencesStore.isAutoPausedByLowPowerMode {
            preferencesStore.isAutoPausedByLowPowerMode = true
        }
        if !preferencesStore.isSamplingPaused {
            preferencesStore.isSamplingPaused = true
        }
        stop()
    }

    /// Registers standard samplers and begins periodic background sampling unless paused.
    public func start() {
        guard !preferencesStore.isSamplingPaused else { return }
        performStart()
    }

    private func performStart() {
        guard !isRunning else { return }
        isRunning = true

        startListeningToStream()
        setupPowerNotifications()

        let interval = preferencesStore.refreshInterval
        let enabledCategories = preferencesStore.enabledCategories
        let scheduler = self.scheduler

        startTask?.cancel()
        startTask = Task { [weak self] in
            if !(await scheduler.isRegistered(category: .cpu)) {
                await scheduler.register(CPUSampler())
            }
            if !(await scheduler.isRegistered(category: .memory)) {
                await scheduler.register(MemorySampler())
            }
            if !(await scheduler.isRegistered(category: .network)) {
                await scheduler.register(NetworkSampler())
            }
            if !(await scheduler.isRegistered(category: .disk)) {
                await scheduler.register(DiskSampler())
            }
            if !(await scheduler.isRegistered(category: .power)) {
                await scheduler.register(PowerSampler())
            }
            if !(await scheduler.isRegistered(category: .thermal)) {
                await scheduler.register(ThermalSampler())
            }
            if !(await scheduler.isRegistered(category: .fan)) {
                await scheduler.register(FanSampler())
            }
            if !(await scheduler.isRegistered(category: .gpu)) {
                await scheduler.register(GPUSampler())
            }
            await scheduler.setDefaultInterval(interval)

            for category in MetricCategory.allCases {
                let enabled = enabledCategories.contains(category)
                await scheduler.setEnabled(category: category, isEnabled: enabled)
            }

            guard !Task.isCancelled, let self = self, self.isRunning else {
                await scheduler.stop()
                return
            }
            await scheduler.start()
        }
    }

    /// Stops background sampling and stream observation.
    public func stop() {
        guard isRunning else { return }
        isRunning = false
        startTask?.cancel()
        startTask = nil
        streamTask?.cancel()
        streamTask = nil
        teardownPowerNotifications()

        let scheduler = self.scheduler
        Task {
            await scheduler.stop()
        }
    }

    // MARK: - Stream & Reading Processing

    private func startListeningToStream() {
        streamTask?.cancel()
        let batchStream = scheduler.batchStream

        streamTask = Task { [weak self] in
            for await batch in batchStream {
                guard !Task.isCancelled else { break }
                self?.handleReadings(batch)
            }
        }
    }

    /// Handles a batch of readings in a single atomic `@MainActor` pass, minimizing `@Published` churn.
    public func handleReadings(_ readings: [MetricReading]) {
        guard !readings.isEmpty else { return }
        batchIngestionCount += 1

        store.append(readings)

        var updatedAvailability = self.categoryAvailability
        var availabilityChanged = false
        var updatedCategories = Set<MetricCategory>()

        for reading in readings {
            if updatedAvailability[reading.category] != reading.availability {
                updatedAvailability[reading.category] = reading.availability
                availabilityChanged = true
            }
            updatedCategories.insert(reading.category)
        }

        if availabilityChanged {
            self.categoryAvailability = updatedAvailability
        }

        for category in updatedCategories {
            updateLatest(for: category)
        }
    }

    /// Handles a single reading from the sampling layer (backward compatibility).
    public func handleReading(_ reading: MetricReading) {
        singleIngestionCount += 1
        store.append(reading)
        if self.categoryAvailability[reading.category] != reading.availability {
            self.categoryAvailability[reading.category] = reading.availability
        }
        updateLatest(for: reading.category)
    }

    private func updateLatest(for category: MetricCategory) {
        switch category {
        case .cpu:
            self.latestCPU = store.latestCPU()
        case .memory:
            self.latestMemory = store.latestMemory()
        case .network:
            self.latestNetwork = store.latestNetwork()
        case .disk:
            self.latestDisk = store.latestDisk()
        case .power:
            self.latestPower = store.latestPower()
        case .thermal:
            self.latestThermal = store.latestThermal()
        case .fan:
            self.latestFan = store.latestFan()
        case .gpu:
            self.latestGPU = store.latestGPU()
        }
    }

    // MARK: - Preferences Synchronization

    private func setupPreferencesObservation() {
        preferencesStore.$refreshInterval
            .dropFirst()
            .sink { [weak self] newInterval in
                guard let self = self else { return }
                Task {
                    await self.scheduler.setDefaultInterval(newInterval)
                }
            }
            .store(in: &cancellables)

        preferencesStore.$enabledCategories
            .dropFirst()
            .sink { [weak self] enabledSet in
                guard let self = self else { return }
                Task {
                    for category in MetricCategory.allCases {
                        let isEnabled = enabledSet.contains(category)
                        await self.scheduler.setEnabled(category: category, isEnabled: isEnabled)
                    }
                }
            }
            .store(in: &cancellables)

        preferencesStore.$isSamplingPaused
            .dropFirst()
            .sink { [weak self] isPaused in
                guard let self = self else { return }
                if isPaused {
                    self.stop()
                } else {
                    self.isAutoPausedByLowPowerMode = false
                    if self.preferencesStore.isAutoPausedByLowPowerMode {
                        self.preferencesStore.isAutoPausedByLowPowerMode = false
                    }
                    if self.lowPowerModeProvider() {
                        self.userOverrodeLowPowerPause = true
                    }
                    self.performStart()
                }
            }
            .store(in: &cancellables)

        preferencesStore.$autoPauseOnLowPowerMode
            .dropFirst()
            .sink { [weak self] autoPauseEnabled in
                guard let self = self else { return }
                if autoPauseEnabled {
                    self.userOverrodeLowPowerPause = false
                    self.evaluateLowPowerModeState()
                } else {
                    let wasAutoPaused = self.isAutoPausedByLowPowerMode || self.preferencesStore.isAutoPausedByLowPowerMode
                    self.isAutoPausedByLowPowerMode = false
                    if self.preferencesStore.isAutoPausedByLowPowerMode {
                        self.preferencesStore.isAutoPausedByLowPowerMode = false
                    }
                    if wasAutoPaused && self.preferencesStore.isSamplingPaused {
                        self.resumeSampling()
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func setupLowPowerModeObservation() {
        NotificationCenter.default
            .publisher(for: Notification.Name.NSProcessInfoPowerStateDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.evaluateLowPowerModeState()
            }
            .store(in: &cancellables)
    }

    // MARK: - On-Demand & Event-Driven Sampling

    /// Triggers an immediate background sample for a specific category and updates published state.
    public func triggerImmediateSample(for category: MetricCategory) {
        guard !preferencesStore.isSamplingPaused else { return }
        Task { [weak self] in
            guard let self = self else { return }
            if let reading = await self.scheduler.sampleOnce(category: category) {
                self.handleReading(reading)
            }
        }
    }

    // MARK: - Power Source Notifications

    private func setupPowerNotifications() {
        guard powerRunLoopSource == nil else { return }

        let callback: IOPowerSourceCallbackType = { context in
            guard let context = context else { return }
            let coordinator = Unmanaged<MetricsCoordinator>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                coordinator.triggerImmediateSample(for: .power)
            }
        }

        let unmanagedSelf = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource(callback, unmanagedSelf)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            self.powerRunLoopSource = source
        }
    }

    nonisolated private func teardownPowerNotifications() {
        if let source = powerRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            CFRunLoopSourceInvalidate(source)
            self.powerRunLoopSource = nil
        }
    }
}
