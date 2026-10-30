import SwiftUI
import iStatsCore

/// A Disk metrics card view:
/// 1. Boot volume Storage Reservoir Tank + Large free space hero
/// 2. Live Read/Write speed cards + 60-sample I/O sparkline
/// 3. Collapsible diagnostics (IOPS, additional mounted backup/external volumes).
public struct DiskSummaryView: View {
    public let sample: DiskSample?
    public let history: [Sample<DiskSample>]
    public let byteStandard: Units.ByteUnitStandard
    public let refreshInterval: TimeInterval

    @State private var isVolumesExpanded: Bool = false

    public init(
        sample: DiskSample? = nil,
        history: [Sample<DiskSample>] = [],
        byteStandard: Units.ByteUnitStandard = .iec,
        refreshInterval: TimeInterval = 2.0
    ) {
        self.sample = sample
        self.history = history
        self.byteStandard = byteStandard
        self.refreshInterval = refreshInterval
    }

    private var verdict: MetricVerdict {
        VerdictEvaluator.evaluateDisk(sample, standard: byteStandard)
    }

    private var bootVolume: VolumeCapacity? {
        sample?.volumes.first(where: { $0.mountPoint == "/" }) ?? sample?.volumes.first
    }

    private var historyReadRates: [Double] {
        history.map { $0.value.io?.bytesReadPerSec ?? 0.0 }
    }

    private var historyWriteRates: [Double] {
        history.map { $0.value.io?.bytesWrittenPerSec ?? 0.0 }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // MARK: - Boot Volume Capacity Hero
            HStack(alignment: .center, spacing: 14) {
                // Live Storage Tank Illustration
                DiskStorageTankIllustrationView(
                    sample: sample,
                    byteStandard: byteStandard,
                    width: 38,
                    height: 64
                )

                // High-Readability Capacity Metrics
                VStack(alignment: .leading, spacing: 3) {
                    if let vol = bootVolume {
                        // Large Free Space Hero
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(Units.formatBytes(vol.free, standard: byteStandard, fractionDigits: 0))
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)

                            Text("free")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                        }

                        // Used of Total & Used %
                        let usedPct = vol.total > 0 ? (Double(vol.used) / Double(vol.total)) * 100.0 : 0.0
                        Text("Used \(Units.formatBytes(vol.used, standard: byteStandard, fractionDigits: 0)) of \(Units.formatBytes(vol.total, standard: byteStandard, fractionDigits: 0)) (\(String(format: "%.0f%%", usedPct)))")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)

                        // Volume Name & Mount
                        Text("\(vol.name) · \(vol.mountPoint)")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.85))
                    } else {
                        Text("Sampling storage...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }

            // MARK: - Live I/O Activity Cards (Read & Write)
            if let io = sample?.io {
                HStack(spacing: 8) {
                    ioRateCard(title: "Read", rate: io.bytesReadPerSec, icon: "arrow.down", color: .cyan)
                    ioRateCard(title: "Write", rate: io.bytesWrittenPerSec, icon: "arrow.up", color: .orange)
                }

                // 60-Sample Dual Read/Write Sparkline
                VStack(alignment: .leading, spacing: 4) {
                    DualTraceRollingGraphView(
                        primaryValues: historyReadRates,
                        secondaryValues: historyWriteRates,
                        primaryColor: .cyan,
                        secondaryColor: .orange,
                        primaryLabel: "Read",
                        secondaryLabel: "Write",
                        height: 40,
                        capacity: 60
                    )

                    HStack {
                        HStack(spacing: 8) {
                            HStack(spacing: 3) {
                                Circle().fill(Color.cyan).frame(width: 5, height: 5)
                                Text("Read")
                                    .font(.system(size: 8.5, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            HStack(spacing: 3) {
                                Circle().fill(Color.orange).frame(width: 5, height: 5)
                                Text("Write")
                                    .font(.system(size: 8.5, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            Text("· last \(Units.formatHistoryDuration(sampleCount: 60, interval: refreshInterval))")
                                .font(.system(size: 8.5, weight: .medium))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        let peakR = historyReadRates.max() ?? 0
                        let peakW = historyWriteRates.max() ?? 0
                        HStack(spacing: 5) {
                            Text("Peak:")
                                .font(.system(size: 8.5, weight: .medium))
                                .foregroundColor(.secondary)
                            Text("R:" + Units.formatDiskRate(peakR, standard: byteStandard))
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundColor(.cyan)
                            Text("W:" + Units.formatDiskRate(peakW, standard: byteStandard))
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }

            // MARK: - Collapsible Diagnostics (All Mounted Volumes & IOPS)
            if let sample = sample, !sample.volumes.isEmpty {
                CollapsibleSection(
                    title: "Volumes",
                    count: sample.volumes.count,
                    isExpanded: $isVolumesExpanded
                ) {
                    diagnosticsContent(sample: sample)
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
        )
    }

    // MARK: - I/O Rate Card

    private func ioRateCard(title: String, rate: Double, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 0.5) {
                Text(title)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundColor(.secondary)

                Text(Units.formatBytes(UInt64(max(0, rate)), standard: byteStandard, fractionDigits: 1) + "/s")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.05))
        )
    }

    // MARK: - Diagnostics Content

    @ViewBuilder
    private func diagnosticsContent(sample: DiskSample) -> some View {
        VStack(spacing: 4) {
            // IOPS Read / Write
            if let io = sample.io {
                HStack {
                    Text("I/O Operations")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(String(format: "Read: %.0f IOPS · Write: %.0f IOPS", io.readOpsPerSec, io.writeOpsPerSec))
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 6)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.04)))
            }

            // All Mounted Volumes (Click to open in Finder)
            ScrollView(.vertical, showsIndicators: sample.volumes.count > 4) {
                VStack(spacing: 4) {
                    ForEach(sample.volumes, id: \.mountPoint) { vol in
                        Button(action: {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: vol.mountPoint)
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "internaldrive")
                                            .font(.system(size: 8, weight: .semibold))
                                            .foregroundColor(.cyan)
                                        Text(vol.name)
                                            .font(.system(size: 9.5, weight: .medium))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                    }

                                    Text(vol.mountPoint)
                                        .font(.system(size: 8, weight: .regular, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                let usedPct = vol.total > 0 ? (Double(vol.used) / Double(vol.total)) * 100.0 : 0.0
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text("\(Units.formatBytes(vol.free, standard: byteStandard)) free")
                                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.primary)

                                    Text("of \(Units.formatBytes(vol.total, standard: byteStandard)) (\(String(format: "%.0f%%", usedPct)))")
                                        .font(.system(size: 8, weight: .regular))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 3)
                            .padding(.horizontal, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.secondary.opacity(0.04))
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Click to open \(vol.name) in Finder")
                    }
                }
            }
            .frame(maxHeight: min(CGFloat(sample.volumes.count) * 36 + 8, 180))
        }
        .padding(.top, 4)
    }
}
