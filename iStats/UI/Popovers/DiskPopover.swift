import SwiftUI
import iStatsCore

/// Purpose-driven Disk popover (ADR 0008, Task 7.4g).
/// Structure: Overview · Volumes · History.
/// Answers: "How much free disk space do I have? Is disk I/O thrashing?"
public struct DiskPopover: View {
    @State public var selectedTab: PopoverTab
    @ObservedObject public var coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore

    public init(
        initialTab: PopoverTab = .overview,
        coordinator: MetricsCoordinator = .shared,
        preferences: PreferencesStore = .shared
    ) {
        self._selectedTab = State(initialValue: initialTab)
        self.coordinator = coordinator
        self.preferences = preferences
    }

    private var sample: DiskSample? {
        coordinator.latestDisk?.value
    }

    private var verdict: MetricVerdict {
        VerdictEvaluator.evaluateDisk(sample, standard: preferences.byteUnitStandard)
    }

    public var body: some View {
        PopoverScaffold(
            category: .disk,
            verdict: verdict,
            tabs: [.overview, .detail, .history],
            selectedTab: $selectedTab,
            isLoading: coordinator.latestDisk == nil,
            unavailableReason: coordinator.categoryAvailability[.disk]?.unavailableReason,
            preferences: preferences,
            coordinator: coordinator
        ) {
            switch selectedTab {
            case .overview:
                overviewTab
            case .detail:
                volumesTab
            case .history:
                HistoryTab(category: .disk, coordinator: coordinator, preferences: preferences)
            }
        }
    }

    // MARK: - Overview Tab

    @ViewBuilder
    private var overviewTab: some View {
        if let disk = sample {
            let primary = disk.volumes.first(where: { $0.mountPoint == "/" }) ?? disk.volumes.first
            let std = preferences.byteUnitStandard
            let freeBytes = primary?.free ?? 0
            let totalBytes = primary?.total ?? 1
            let usedBytes = primary?.used ?? 0
            let usedPct = totalBytes > 0 ? (Double(usedBytes) / Double(totalBytes)) * 100.0 : 0.0

            let readBytes = disk.io?.bytesReadPerSec ?? 0.0
            let writeBytes = disk.io?.bytesWrittenPerSec ?? 0.0
            let readOps = disk.io?.readOpsPerSec ?? 0.0
            let writeOps = disk.io?.writeOpsPerSec ?? 0.0

            VStack(alignment: .leading, spacing: Tokens.md) {
                // Free Space Hero Metric + Mirrored Duplex Sparkline
                HStack(alignment: .top, spacing: Tokens.md) {
                    HeroMetric(
                        primaryValue: Units.formatBytes(freeBytes, standard: std),
                        unit: "free",
                        contextLine: "of \(Units.formatBytes(totalBytes, standard: std)) · \(String(format: "%.0f%%", usedPct)) used"
                    )
                    .frame(width: 140, alignment: .leading)

                    let readHistory = coordinator.diskHistory.map { $0.value.io?.bytesReadPerSec ?? 0.0 }
                    let writeHistory = coordinator.diskHistory.map { $0.value.io?.bytesWrittenPerSec ?? 0.0 }
                    TrendChart(
                        mode: .mirrored(
                            top: readHistory,
                            bottom: writeHistory,
                            topColor: CategoryPalette.disk,
                            bottomColor: Color.orange.opacity(0.85),
                            topLabel: "R",
                            bottomLabel: "W"
                        ),
                        height: 52,
                        sampleIntervalSeconds: preferences.refreshInterval
                    )
                    .frame(maxWidth: .infinity)
                }

                // Storage Capacity Bar
                SegmentedBar(segments: [
                    .init(value: Double(usedBytes), color: CategoryPalette.disk, label: "Used"),
                    .init(value: Double(freeBytes), color: Color.secondary.opacity(0.25), label: "Free")
                ])

                // 2x2 I/O Grid (Throughput & IOPS)
                StatGrid(columns: 2) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Disk Read Rate").font(Tokens.bodyLabel).foregroundColor(.secondary)
                        Text(Units.formatDiskRate(readBytes, standard: std)).font(Tokens.monoValue)
                    }
                    .padding(8)
                    .cardBackground()

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Disk Write Rate").font(Tokens.bodyLabel).foregroundColor(.secondary)
                        Text(Units.formatDiskRate(writeBytes, standard: std)).font(Tokens.monoValue)
                    }
                    .padding(8)
                    .cardBackground()

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Read IOPS").font(Tokens.bodyLabel).foregroundColor(.secondary)
                        Text(String(format: "%.0f ops/s", readOps)).font(Tokens.monoValue)
                    }
                    .padding(8)
                    .cardBackground()

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Write IOPS").font(Tokens.bodyLabel).foregroundColor(.secondary)
                        Text(String(format: "%.0f ops/s", writeOps)).font(Tokens.monoValue)
                    }
                    .padding(8)
                    .cardBackground()
                }
            }
        }
    }

    // MARK: - Volumes Tab

    @ViewBuilder
    private var volumesTab: some View {
        if let disk = sample {
            let std = preferences.byteUnitStandard
            let vols = disk.volumes.sorted(by: { ($0.mountPoint == "/") ? true : ($1.mountPoint == "/" ? false : $0.name < $1.name) })

            VStack(alignment: .leading, spacing: Tokens.sm) {
                HStack {
                    Text("Mounted Volumes (\(vols.count))")
                        .font(Tokens.sectionTitle)
                        .foregroundColor(.secondary)
                    Spacer()
                }

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(vols, id: \.mountPoint) { vol in
                            let ratio = vol.total > 0 ? (Double(vol.used) / Double(vol.total)) * 100.0 : 0.0

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(vol.name)
                                            .font(.system(size: 11.5, weight: .semibold))
                                            .foregroundColor(.primary)

                                        Text(vol.mountPoint)
                                            .font(.system(size: 9.5))
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 1) {
                                        Text("\(Units.formatBytes(vol.free, standard: std)) free")
                                            .font(Tokens.monoValue)
                                            .foregroundColor(.primary)

                                        Text("of \(Units.formatBytes(vol.total, standard: std))")
                                            .font(.system(size: 9.5))
                                            .foregroundColor(.secondary)
                                    }
                                }

                                SegmentedBar(segments: [
                                    .init(value: Double(vol.used), color: CategoryPalette.disk, label: "Used"),
                                    .init(value: Double(vol.free), color: Color.secondary.opacity(0.2), label: "Free")
                                ])
                            }
                            .padding(8)
                            .cardBackground()
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
    }
}
