import SwiftUI
import AppKit
import iStatsCore

/// Dedicated Disk Instrument Panel (Task 8.8g / ADR 0009 / Blueprint §6.7).
/// Features the signature Storage Bar + I/O Waveform, boot volume free display,
/// 14 pt SplitCapsule storage breakdown, live IOPS counters, and mounted volumes inspector.
public struct DiskPanel: View {
    public let initialTab: PopoverTab
    public let rememberLastTab: Bool
    public let focusSource: MetricSource?

    @ObservedObject public var coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore

    @State private var selectedTab: PopoverTab
    @State private var hoveredVolumePoint: String? = nil

    public init(
        initialTab: PopoverTab = .overview,
        rememberLastTab: Bool = true,
        focusSource: MetricSource? = nil,
        coordinator: MetricsCoordinator = .shared,
        preferences: PreferencesStore = .shared
    ) {
        self.initialTab = initialTab
        self.rememberLastTab = rememberLastTab
        self.focusSource = focusSource
        self.coordinator = coordinator
        self.preferences = preferences
        let supported = PopoverTab.supportedTabs(for: .disk)
        let resolved = supported.contains(initialTab) ? initialTab : .overview
        self._selectedTab = State(initialValue: resolved)
    }

    private var sample: DiskSample? {
        coordinator.latestDisk?.value
    }

    private var bootVolume: VolumeCapacity? {
        guard let s = sample else { return nil }
        return s.volumes.first(where: { $0.mountPoint == "/" })
            ?? s.volumes.max(by: { $0.total < $1.total })
    }

    public var body: some View {
        let glance = deriveGlance(sample: sample)
        let (status, ribbon) = deriveStatusAndRibbon(sample: sample)
        let availability = coordinator.categoryAvailability[.disk]
        let isLoading = (availability == nil && !coordinator.isSamplingPaused)

        PanelScaffold(
            category: .disk,
            glance: glance,
            status: status,
            ribbon: ribbon,
            pages: PopoverTab.supportedTabs(for: .disk),
            selection: $selectedTab,
            availability: availability,
            isLoading: isLoading,
            isPaused: coordinator.isSamplingPaused,
            onTogglePause: {
                coordinator.toggleSamplingPaused()
            },
            onPinToggle: {
                PanelController.shared.togglePin(for: .disk)
            },
            isPinned: PanelController.shared.isPinned(for: .disk)
        ) { tab in
            switch tab {
            case .overview:
                nowPage(sample: sample)
            case .detail:
                volumesPage(sample: sample)
            case .history:
                HistoryPage(category: .disk, coordinator: coordinator, preferences: preferences)
            }
        }
        .onChange(of: selectedTab) { newTab in
            if rememberLastTab {
                preferences.setLastSelectedTab(newTab, for: .disk)
            }
        }
    }

    // MARK: - Glance Derivation

    private func deriveGlance(sample: DiskSample?) -> PanelGlance {
        let std = preferences.byteUnitStandard
        let boot = bootVolume

        let (displayVal, displayUnit, formatStr) = formatFreeSpace(boot?.free ?? 0, standard: std)
        let headline = deriveHeadline(boot: boot, std: std)

        let readHistory = coordinator.diskHistory.map { $0.value.io?.bytesReadPerSec ?? 0.0 }
        let writeHistory = coordinator.diskHistory.map { $0.value.io?.bytesWrittenPerSec ?? 0.0 }

        let insight = InsightEngine.best(
            series: readHistory,
            interval: preferences.refreshInterval,
            unit: .bytesPerSecond
        )?.text

        let chartMode = LiveChartMode.mirrored(
            top: readHistory,
            bottom: writeHistory,
            topColor: CategoryPalette.color(for: .disk),
            bottomColor: CategoryPalette.Series.diskWrite,
            topLabel: "R",
            bottomLabel: "W"
        )

        return PanelGlance(
            value: displayVal,
            format: formatStr,
            unit: displayUnit,
            headline: headline,
            insight: insight,
            chartMode: chartMode,
            chartHeight: 56,
            scrubFormat: { Units.formatDiskRate($0, standard: std) }
        )
    }

    private func formatFreeSpace(_ bytes: UInt64, standard: Units.ByteUnitStandard) -> (Double, String, String) {
        let base: Double = standard == .si ? 1000.0 : 1024.0
        let suffixes = standard == .si ? ["B", "KB", "MB", "GB", "TB", "PB"] : ["B", "KiB", "MiB", "GiB", "TiB", "PiB"]
        var val = Double(bytes)
        var idx = 0
        while val >= base && idx < suffixes.count - 1 {
            val /= base
            idx += 1
        }
        let formatStr = (idx > 0 && val < 10.0) ? "%.1f" : "%.0f"
        return (val, "\(suffixes[idx]) free", formatStr)
    }

    private func deriveHeadline(boot: VolumeCapacity?, std: Units.ByteUnitStandard) -> String {
        guard let boot = boot, boot.total > 0 else { return "No volume information" }
        let totalStr = Units.formatBytes(boot.total, standard: std)
        let usedPct = Int(round(Double(boot.used) / Double(boot.total) * 100.0))
        return "of \(totalStr) · \(usedPct)% used"
    }

    private func deriveStatusAndRibbon(sample: DiskSample?) -> (StatusLevel, String?) {
        guard let boot = bootVolume, boot.total > 0 else { return (.fine, nil) }
        let usedPct = Double(boot.used) / Double(boot.total) * 100.0
        let level = StatusThresholds.disk(usedPercent: usedPct)

        switch level {
        case .critical:
            return (.critical, "Disk space critically low: free up space immediately")
        case .warning:
            return (.warning, "Disk space low: \(Int(round(usedPct)))% used")
        case .elevated:
            return (.elevated, "Disk space running low: \(Int(round(usedPct)))% used")
        case .fine:
            return (.fine, nil)
        }
    }

    // MARK: - Now Page (Overview)

    @ViewBuilder
    private func nowPage(sample: DiskSample?) -> some View {
        if let s = sample, let boot = bootVolume {
            let std = preferences.byteUnitStandard

            VStack(alignment: .leading, spacing: Instrument.Space.m) {
                // Storage Bar Module
                storageBarModule(volume: boot, std: std)

                // I/O Throughput & Activity Module
                if let io = s.io {
                    Module(eyebrow: "Live Throughput & IOPS") {
                        VStack(spacing: 6) {
                            let readRate = Units.formatCompactRate(io.bytesReadPerSec, standard: std)
                            let readIOPS = Int(round(io.readOpsPerSec))
                            MetricRow(
                                label: "Disk Read",
                                valueText: "\(readRate)  ·  \(readIOPS) IOPS",
                                sparklineColor: CategoryPalette.color(for: .disk),
                                isCopyable: true
                            )

                            let writeRate = Units.formatCompactRate(io.bytesWrittenPerSec, standard: std)
                            let writeIOPS = Int(round(io.writeOpsPerSec))
                            MetricRow(
                                label: "Disk Write",
                                valueText: "\(writeRate)  ·  \(writeIOPS) IOPS",
                                sparklineColor: CategoryPalette.Series.diskWrite,
                                isCopyable: true
                            )
                        }
                    }
                }
            }
        } else {
            InsetEmptyState(
                systemImage: "internaldrive",
                title: "No Disk Data",
                reason: "Disk storage and I/O metrics are currently unavailable."
            )
        }
    }

    // MARK: - Storage Bar Module

    @ViewBuilder
    private func storageBarModule(volume: VolumeCapacity, std: Units.ByteUnitStandard) -> some View {
        let usedPct = volume.total > 0 ? (Double(volume.used) / Double(volume.total) * 100.0) : 0.0

        Module(eyebrow: "\(volume.name) Storage") {
            VStack(alignment: .leading, spacing: Instrument.Space.s) {
                // 14 pt SplitCapsule
                SplitCapsule(
                    segments: [
                        CapsuleSegment(
                            value: Double(volume.used),
                            color: CategoryPalette.color(for: .disk),
                            label: "Used"
                        ),
                        CapsuleSegment(
                            value: Double(volume.free),
                            color: Color.secondary.opacity(0.18),
                            label: "Free"
                        )
                    ],
                    height: 14,
                    minVisibleWidth: 4,
                    gap: 1
                )

                // Tick labels: 0% / 50% / 100%
                HStack {
                    Text("0%")
                        .font(Instrument.Typography.micro)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("50%")
                        .font(Instrument.Typography.micro)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("100%")
                        .font(Instrument.Typography.micro)
                        .foregroundColor(.secondary)
                }

                // Breakdown rows
                VStack(spacing: 6) {
                    MetricRow(
                        label: "Used Space",
                        valueText: "\(Units.formatBytes(volume.used, standard: std)) (\(Int(round(usedPct)))%)",
                        isCopyable: true
                    )
                    MetricRow(
                        label: "Free Space",
                        valueText: Units.formatBytes(volume.free, standard: std),
                        isCopyable: true
                    )
                    MetricRow(
                        label: "Total Capacity",
                        valueText: Units.formatBytes(volume.total, standard: std),
                        isCopyable: true
                    )
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Volumes Detail Page

    @ViewBuilder
    private func volumesPage(sample: DiskSample?) -> some View {
        if let s = sample, !s.volumes.isEmpty {
            let std = preferences.byteUnitStandard

            VStack(alignment: .leading, spacing: Instrument.Space.m) {
                Module(eyebrow: "Mounted Volumes (\(s.volumes.count))") {
                    VStack(spacing: 12) {
                        ForEach(s.volumes, id: \.mountPoint) { vol in
                            volumeCard(vol: vol, std: std)
                        }
                    }
                }
            }
        } else {
            InsetEmptyState(
                systemImage: "internaldrive",
                title: "No Volumes Mounted",
                reason: "No mounted file system volumes detected."
            )
        }
    }

    @ViewBuilder
    private func volumeCard(vol: VolumeCapacity, std: Units.ByteUnitStandard) -> some View {
        let isHovered = (hoveredVolumePoint == vol.mountPoint)
        let isBoot = (vol.mountPoint == "/")

        VStack(alignment: .leading, spacing: 6) {
            // Header Row: Volume Name + Free of Total
            HStack {
                Image(systemName: isBoot ? "internaldrive.fill" : "externaldrive.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(CategoryPalette.color(for: .disk))

                Text(vol.name)
                    .font(Instrument.Typography.body)
                    .foregroundColor(.primary)

                Spacer()

                Text("\(Units.formatBytes(vol.free, standard: std)) free")
                    .font(Instrument.Typography.caption)
                    .foregroundColor(.secondary)
            }

            // Mini 6 pt Storage Bar
            SplitCapsule(
                segments: [
                    CapsuleSegment(
                        value: Double(vol.used),
                        color: CategoryPalette.color(for: .disk),
                        label: "Used"
                    ),
                    CapsuleSegment(
                        value: Double(vol.free),
                        color: Color.secondary.opacity(0.18),
                        label: "Free"
                    )
                ],
                height: 6,
                minVisibleWidth: 3,
                gap: 1
            )

            // Mount Point & Finder Action Row
            HStack {
                Text(vol.mountPoint)
                    .font(Instrument.Typography.mono)
                    .foregroundColor(.secondary)

                Spacer()

                if !isBoot {
                    Button {
                        let url = URL(fileURLWithPath: vol.mountPoint)
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        HStack(spacing: 4) {
                            Text("Show in Finder")
                                .font(Instrument.Typography.caption)
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(CategoryPalette.color(for: .disk))
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovered ? 1.0 : 0.8)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: Instrument.Radius.control, style: .continuous)
                .fill(Color.primary.opacity(isHovered ? 0.05 : 0.02))
        )
        .onHover { hovering in
            hoveredVolumePoint = hovering ? vol.mountPoint : nil
        }
    }
}

// MARK: - Previews

#if DEBUG
struct DiskPanel_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Single Volume
            DiskPanel(
                initialTab: .overview,
                coordinator: makeMockCoordinator(
                    sample: DiskSample(
                        volumes: [
                            VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 494_000_000_000, used: 280_000_000_000, free: 214_000_000_000)
                        ],
                        io: DiskIO(bytesReadPerSec: 14_500_000, bytesWrittenPerSec: 2_100_000, readOpsPerSec: 240, writeOpsPerSec: 85)
                    )
                )
            )
            .previewDisplayName("Single Volume")

            // Multiple Volumes incl. External
            DiskPanel(
                initialTab: .detail,
                coordinator: makeMockCoordinator(
                    sample: DiskSample(
                        volumes: [
                            VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 494_000_000_000, used: 280_000_000_000, free: 214_000_000_000),
                            VolumeCapacity(name: "SanDisk SSD", mountPoint: "/Volumes/SanDisk SSD", total: 1_000_000_000_000, used: 450_000_000_000, free: 550_000_000_000)
                        ],
                        io: DiskIO(bytesReadPerSec: 80_000_000, bytesWrittenPerSec: 45_000_000, readOpsPerSec: 1200, writeOpsPerSec: 650)
                    )
                )
            )
            .previewDisplayName("Multiple Volumes")

            // Low Free Space
            DiskPanel(
                initialTab: .overview,
                coordinator: makeMockCoordinator(
                    sample: DiskSample(
                        volumes: [
                            VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 500_000_000_000, used: 475_000_000_000, free: 25_000_000_000)
                        ],
                        io: DiskIO(bytesReadPerSec: 1_000_000, bytesWrittenPerSec: 500_000, readOpsPerSec: 10, writeOpsPerSec: 5)
                    )
                )
            )
            .previewDisplayName("Low Free Space")

            // No I/O Data
            DiskPanel(
                initialTab: .overview,
                coordinator: makeMockCoordinator(
                    sample: DiskSample(
                        volumes: [
                            VolumeCapacity(name: "Macintosh HD", mountPoint: "/", total: 500_000_000_000, used: 200_000_000_000, free: 300_000_000_000)
                        ],
                        io: nil
                    )
                )
            )
            .previewDisplayName("No I/O Data")
        }
        .padding()
        .background(Color.black)
    }

    private static func makeMockCoordinator(sample: DiskSample) -> MetricsCoordinator {
        let coordinator = MetricsCoordinator.shared
        coordinator.handleReading(.disk(Sample(value: sample)))
        return coordinator
    }
}
#endif
