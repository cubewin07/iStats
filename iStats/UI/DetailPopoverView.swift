import SwiftUI
import iStatsCore

public struct DetailPopoverView: View {
    @ObservedObject public var coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore

    // Optional overrides for testing / previews
    private let overrideCPUSample: CPUSample?
    private let overrideMemorySample: MemorySample?
    private let overrideCPUHistory: [Sample<CPUSample>]?
    private let overrideMemoryHistory: [Sample<MemorySample>]?

    public init(
        coordinator: MetricsCoordinator = .shared,
        preferences: PreferencesStore = .shared,
        cpuSample: CPUSample? = nil,
        memorySample: MemorySample? = nil,
        cpuHistory: [Sample<CPUSample>]? = nil,
        memoryHistory: [Sample<MemorySample>]? = nil
    ) {
        self.coordinator = coordinator
        self.preferences = preferences
        self.overrideCPUSample = cpuSample
        self.overrideMemorySample = memorySample
        self.overrideCPUHistory = cpuHistory
        self.overrideMemoryHistory = memoryHistory
    }

    private var currentCPUSample: CPUSample? {
        overrideCPUSample ?? coordinator.latestCPU?.value
    }

    private var currentCPUHistory: [Sample<CPUSample>] {
        overrideCPUHistory ?? coordinator.cpuHistory
    }

    private var currentMemorySample: MemorySample? {
        overrideMemorySample ?? coordinator.latestMemory?.value
    }

    private var currentMemoryHistory: [Sample<MemorySample>] {
        overrideMemoryHistory ?? coordinator.memoryHistory
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text("iStats")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Text("v0.1.0")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 2)

            Divider()

            // Metrics Scroll Area
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    // CPU Monitoring Section (Requirements 10.1, 10.2, 10.3)
                    if preferences.isCategoryEnabled(.cpu) {
                        CPUSummaryView(
                            sample: currentCPUSample,
                            history: currentCPUHistory
                        )
                    }

                    // Memory Monitoring Section (Requirements 10.1, 10.2, 10.3)
                    if preferences.isCategoryEnabled(.memory) {
                        MemorySummaryView(
                            sample: currentMemorySample,
                            history: currentMemoryHistory
                        )
                    }
                }
            }
            .frame(maxHeight: 480)

            Divider()

            // Footer / Actions
            HStack {
                Text(statusFooterText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Preferences...") {
                    PreferencesWindowController.shared.showPreferences()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 330)
        .onAppear {
            if !coordinator.isRunning && overrideCPUSample == nil && overrideMemorySample == nil {
                coordinator.start()
            }
        }
    }

    private var statusFooterText: String {
        if let memory = currentMemorySample {
            return "Pressure: \(memory.pressure.displayName)"
        } else if coordinator.isRunning {
            return "Sampling..."
        } else {
            return "Status: Ready"
        }
    }
}
