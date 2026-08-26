import Foundation
import Combine
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
    private var cancellables = Set<AnyCancellable>()
    private var streamTask: Task<Void, Never>?

    // MARK: - Published State

    /// In-memory ring buffer store holding live telemetry history.
    @Published public private(set) var store: MetricsStore

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

    /// Rolling chronological history of CPU samples.
    @Published public private(set) var cpuHistory: [Sample<CPUSample>] = []

    /// Rolling chronological history of Memory samples.
    @Published public private(set) var memoryHistory: [Sample<MemorySample>] = []

    /// Rolling chronological history of Network samples.
    @Published public private(set) var networkHistory: [Sample<NetworkSample>] = []

    /// Rolling chronological history of Disk samples.
    @Published public private(set) var diskHistory: [Sample<DiskSample>] = []

    /// Rolling chronological history of Power samples.
    @Published public private(set) var powerHistory: [Sample<PowerSample>] = []

    /// Rolling chronological history of Thermal samples.
    @Published public private(set) var thermalHistory: [Sample<ThermalSample>] = []

    /// Rolling chronological history of Fan samples.
    @Published public private(set) var fanHistory: [Sample<FanSample>] = []

    /// Whether the coordinator is actively sampling.
    @Published public private(set) var isRunning: Bool = false

    // MARK: - Initialization

    /// Creates a new `MetricsCoordinator`.
    /// - Parameters:
    ///   - scheduler: The `SampleScheduler` actor instance.
    ///   - store: The initial `MetricsStore`.
    ///   - preferencesStore: The preferences store to synchronize with.
    public init(
        scheduler: SampleScheduler = SampleScheduler(),
        store: MetricsStore = MetricsStore(),
        preferencesStore: PreferencesStore = .shared
    ) {
        self.scheduler = scheduler
        self.store = store
        self.preferencesStore = preferencesStore

        setupPreferencesObservation()
    }

    deinit {
        streamTask?.cancel()
    }

    // MARK: - Lifecycle

    /// Registers standard samplers and begins periodic background sampling.
    public func start() {
        guard !isRunning else { return }
        isRunning = true

        // Register default concrete samplers
        Task {
            await scheduler.register(CPUSampler())
            await scheduler.register(MemorySampler())
            await scheduler.register(NetworkSampler())
            await scheduler.register(DiskSampler())
            await scheduler.register(PowerSampler())
            await scheduler.register(ThermalSampler())
            await scheduler.register(FanSampler())
            await scheduler.setDefaultInterval(preferencesStore.refreshInterval)

            for category in MetricCategory.allCases {
                let enabled = preferencesStore.isCategoryEnabled(category)
                await scheduler.setEnabled(category: category, isEnabled: enabled)
            }

            await scheduler.start()
        }

        startListeningToStream()
    }

    /// Stops background sampling and stream observation.
    public func stop() {
        guard isRunning else { return }
        isRunning = false
        streamTask?.cancel()
        streamTask = nil

        Task {
            await scheduler.stop()
        }
    }

    // MARK: - Stream & Reading Processing

    private func startListeningToStream() {
        streamTask?.cancel()
        let stream = scheduler.stream

        streamTask = Task { [weak self] in
            for await reading in stream {
                guard !Task.isCancelled else { break }
                self?.handleReading(reading)
            }
        }
    }

    /// Handles a new reading from the sampling layer and updates published properties.
    public func handleReading(_ reading: MetricReading) {
        store.append(reading)

        switch reading.category {
        case .cpu:
            self.latestCPU = store.latestCPU()
            self.cpuHistory = store.cpuHistory()
        case .memory:
            self.latestMemory = store.latestMemory()
            self.memoryHistory = store.memoryHistory()
        case .network:
            self.latestNetwork = store.latestNetwork()
            self.networkHistory = store.networkHistory()
        case .disk:
            self.latestDisk = store.latestDisk()
            self.diskHistory = store.diskHistory()
        case .power:
            self.latestPower = store.latestPower()
            self.powerHistory = store.powerHistory()
        case .thermal:
            self.latestThermal = store.latestThermal()
            self.thermalHistory = store.thermalHistory()
        case .fan:
            self.latestFan = store.latestFan()
            self.fanHistory = store.fanHistory()
        default:
            break
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
    }
}
