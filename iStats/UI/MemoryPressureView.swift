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
        case .normal:
            return .green
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }

    private var badgeIcon: String {
        switch pressure {
        case .normal:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .critical:
            return "exclamationmark.octagon.fill"
        }
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: badgeIcon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(badgeColor)

            Text(pressure.displayName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(badgeColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(badgeColor.opacity(0.15))
        )
        .overlay(
            Capsule()
                .stroke(badgeColor.opacity(0.35), lineWidth: 1)
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
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: pressure == .critical ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(pressure == .critical ? .red : .orange)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(pressure == .critical ? "Critical Memory Pressure" : "Memory Pressure Warning")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(pressure == .critical ? .red : .orange)

                    Text(pressure == .critical
                         ? "System memory is exhausted. Performance may be severely degraded."
                         : "System memory is under heavy pressure. Compression and swapping active.")
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(pressure == .critical ? Color.red.opacity(0.12) : Color.orange.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(pressure == .critical ? Color.red.opacity(0.35) : Color.orange.opacity(0.35), lineWidth: 1)
            )
        }
    }
}

/// Memory statistics summary section for the detail popover.
public struct MemorySummaryView: View {
    public let sample: MemorySample?

    public init(sample: MemorySample?) {
        self.sample = sample
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section Header with Pressure Badge
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "memorychip")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.accentColor)
                    Text("Memory")
                        .font(.system(size: 13, weight: .bold))
                }

                Spacer()

                if let sample {
                    MemoryPressureBadgeView(pressure: sample.pressure)
                }
            }

            if let sample {
                // Warning / Critical Alert Banner if elevated
                MemoryPressureAlertBanner(pressure: sample.pressure)

                // Used / Total Gauge Bar
                let usedRatio = sample.total > 0 ? min(1.0, Double(sample.used) / Double(sample.total)) : 0.0
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(gaugeColor(ratio: usedRatio, pressure: sample.pressure))
                                .frame(width: max(0, geo.size.width * CGFloat(usedRatio)), height: 8)
                        }
                    }
                    .frame(height: 8)

                    HStack {
                        Text("\(Units.formatBytes(sample.used)) used of \(Units.formatBytes(sample.total))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)

                        Spacer()

                        Text(String(format: "%.1f%%", usedRatio * 100.0))
                            .font(.system(size: 11, weight: .bold))
                    }
                }

                // Breakdown Grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    metricItem(label: "Wired", value: Units.formatBytes(sample.wired))
                    metricItem(label: "Compressed", value: Units.formatBytes(sample.compressed))
                    metricItem(label: "Cached Files", value: Units.formatBytes(sample.cached))
                    metricItem(label: "Swap Used", value: Units.formatBytes(sample.swapUsed))
                }
                .padding(.top, 2)
            } else {
                Text("Waiting for memory sample...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
    }

    private func gaugeColor(ratio: Double, pressure: MemoryPressure) -> Color {
        switch pressure {
        case .critical:
            return .red
        case .warning:
            return .orange
        case .normal:
            if ratio > 0.9 { return .orange }
            return .blue
        }
    }

    private func metricItem(label: String, value: String) -> some View {
        HStack {
            Text(label + ":")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .medium))
        }
    }
}
