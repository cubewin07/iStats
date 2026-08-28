import SwiftUI
import iStatsCore

/// Visual badge component displaying the current memory pressure level with distinct color-coding.
public struct MemoryPressureBadgeView: View {
    public let pressure: MemoryPressure

    public init(pressure: MemoryPressure) {
        self.pressure = pressure
    }

    private var badgeColor: Color {
        switch pressure {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private var badgeIcon: String {
        switch pressure {
        case .normal: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: badgeIcon)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(badgeColor)

            Text(pressure.displayName)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(badgeColor)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(
            Capsule()
                .fill(badgeColor.opacity(0.14))
        )
        .overlay(
            Capsule()
                .stroke(badgeColor.opacity(0.35), lineWidth: 0.75)
        )
    }
}

/// Prominent alert banner surfaced when memory pressure reaches warning or critical state (Requirement 2.4).
public struct MemoryPressureAlertBanner: View {
    public let pressure: MemoryPressure

    public init(pressure: MemoryPressure) {
        self.pressure = pressure
    }

    public var body: some View {
        if pressure.isElevated {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: pressure == .critical ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(pressure == .critical ? .red : .orange)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(pressure == .critical ? "Critical Memory Pressure" : "Memory Pressure Warning")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(pressure == .critical ? .red : .orange)

                    Text(pressure == .critical
                         ? "System memory is exhausted. Performance may be severely degraded."
                         : "System memory is under heavy pressure. Compression and swapping active.")
                        .font(.system(size: 10))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(pressure == .critical ? Color.red.opacity(0.12) : Color.orange.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(pressure == .critical ? Color.red.opacity(0.35) : Color.orange.opacity(0.35), lineWidth: 0.75)
            )
        }
    }
}

/// Memory statistics summary section for the detail popover.
public struct MemorySummaryView: View {
    public let sample: MemorySample?
    public let history: [Sample<MemorySample>]
    public let byteStandard: Units.ByteUnitStandard

    public init(
        sample: MemorySample?,
        history: [Sample<MemorySample>] = [],
        byteStandard: Units.ByteUnitStandard = .iec
    ) {
        self.sample = sample
        self.history = history
        self.byteStandard = byteStandard
    }

    private var historyPercentages: [Double] {
        history.map { s in
            s.value.total > 0 ? (Double(s.value.used) / Double(s.value.total)) * 100.0 : 0.0
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Hero Metric Row: Used RAM, Total RAM, Percentage, Pressure Badge
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Memory Usage")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)

                    if let sample = sample {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(Units.formatBytes(sample.used, standard: byteStandard, fractionDigits: 1))
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(pressureTextColor(sample.pressure))

                            Text("of \(Units.formatBytes(sample.total, standard: byteStandard, fractionDigits: 0))")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("Sampling...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if let sample = sample {
                    VStack(alignment: .trailing, spacing: 3) {
                        MemoryPressureBadgeView(pressure: sample.pressure)

                        let usedRatio = sample.total > 0 ? (Double(sample.used) / Double(sample.total)) * 100.0 : 0.0
                        Text(String(format: "%.1f%%", usedRatio))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                }
            }

            if let sample = sample {
                // Elevated alert banner if needed
                MemoryPressureAlertBanner(pressure: sample.pressure)

                // Memory Composition Multi-Segment Bar
                memoryCompositionBar(sample: sample)

                // Composition Chips Row
                HStack(spacing: 8) {
                    compositionChip(label: "App", color: .blue)
                    compositionChip(label: "Wired", color: .purple)
                    compositionChip(label: "Compressed", color: .orange)
                    compositionChip(label: "Cached", color: .teal)
                    compositionChip(label: "Free", color: .secondary.opacity(0.4))
                }
            }

            // Rolling 60s Memory History Graph
            VStack(alignment: .leading, spacing: 4) {
                RollingGraphView(
                    values: historyPercentages,
                    minValue: 0.0,
                    maxValue: 100.0,
                    tintColor: graphTintColor(for: sample?.pressure ?? .normal),
                    capacity: 60,
                    height: 44,
                    showGrid: true
                )

                HStack {
                    Text("Memory History")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    if let sample = sample {
                        let usedRatio = sample.total > 0 ? (Double(sample.used) / Double(sample.total)) * 100.0 : 0.0
                        Text(String(format: "Peak: %.1f%%", historyPercentages.max() ?? usedRatio))
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }

            if let sample = sample {
                // Breakdown Tiles Grid (App Memory, Wired, Compressed, Cached, Swap Used, Free)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    telemetryTile(
                        label: "App Memory",
                        value: Units.formatBytes(sample.appMemory ?? (sample.used >= (sample.wired + sample.compressed) ? sample.used - sample.wired - sample.compressed : sample.used), standard: byteStandard),
                        color: .blue
                    )

                    telemetryTile(
                        label: "Wired Memory",
                        value: Units.formatBytes(sample.wired, standard: byteStandard),
                        color: .purple
                    )

                    telemetryTile(
                        label: "Compressed",
                        value: Units.formatBytes(sample.compressed, standard: byteStandard),
                        color: .orange
                    )

                    telemetryTile(
                        label: "Cached Files",
                        value: Units.formatBytes(sample.cached, standard: byteStandard),
                        color: .teal
                    )

                    telemetryTile(
                        label: "Swap Used",
                        value: Units.formatBytes(sample.swapUsed, standard: byteStandard),
                        color: sample.swapUsed > 0 ? .orange : .secondary
                    )

                    telemetryTile(
                        label: "Free Memory",
                        value: Units.formatBytes(sample.free, standard: byteStandard),
                        color: .green
                    )
                }
            } else {
                Text("Waiting for memory sample...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
        )
    }

    // MARK: - Composition Bar

    private func memoryCompositionBar(sample: MemorySample) -> some View {
        GeometryReader { geo in
            let appBytes = Double(sample.appMemory ?? (sample.used >= (sample.wired + sample.compressed) ? sample.used - sample.wired - sample.compressed : sample.used))
            let wiredBytes = Double(sample.wired)
            let compressedBytes = Double(sample.compressed)
            let cachedBytes = Double(sample.cached)
            let freeBytes = Double(sample.free)
            let sum = max(1.0, appBytes + wiredBytes + compressedBytes + cachedBytes + freeBytes)

            let w = geo.size.width
            let appW = max(0, w * CGFloat(appBytes / sum))
            let wiredW = max(0, w * CGFloat(wiredBytes / sum))
            let compW = max(0, w * CGFloat(compressedBytes / sum))
            let cachedW = max(0, w * CGFloat(cachedBytes / sum))
            let freeW = max(0, w - appW - wiredW - compW - cachedW)

            HStack(spacing: 1.5) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.blue)
                    .frame(width: max(0, appW - 1))

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.purple)
                    .frame(width: max(0, wiredW - 1))

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.orange)
                    .frame(width: max(0, compW - 1))

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.teal)
                    .frame(width: max(0, cachedW - 1))

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: max(0, freeW))
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: 6)
    }

    private func compositionChip(label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Telemetry Tile

    private func telemetryTile(label: String, value: String, color: Color) -> some View {
        HStack {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    // MARK: - Helpers

    private func graphTintColor(for pressure: MemoryPressure) -> Color {
        switch pressure {
        case .critical: return .red
        case .warning: return .orange
        case .normal: return .green
        }
    }

    private func pressureTextColor(_ pressure: MemoryPressure) -> Color {
        switch pressure {
        case .critical: return .red
        case .warning: return .orange
        case .normal: return .primary
        }
    }
}

