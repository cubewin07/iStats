import SwiftUI
import iStatsCore

/// A comprehensive CPU metrics card view displaying aggregate utilization, live rolling history graph,
/// user/system/idle breakdown, load average, clock frequency, system uptime, and per-core distribution
/// (Requirements 10.1, 10.2, 10.3).
public struct CPUSummaryView: View {
    public let sample: CPUSample?
    public let history: [Sample<CPUSample>]
    @State private var isPerCoreExpanded: Bool = true

    public init(sample: CPUSample? = nil, history: [Sample<CPUSample>] = []) {
        self.sample = sample
        self.history = history
    }

    private var historyPercentages: [Double] {
        history.map { $0.value.totalUsage }
    }

    private var uptimeString: String {
        Units.formatUptime(ProcessInfo.processInfo.systemUptime)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Hero Metric Row: Icon, Title, Aggregate Percentage & Chips
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Total Utilization")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)

                    if let sample = sample {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(String(format: "%.1f", sample.totalUsage))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(usageColor(for: sample.totalUsage))

                            Text("%")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(usageColor(for: sample.totalUsage))
                        }
                    } else {
                        Text("Sampling...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if let sample = sample {
                    // Mini breakdown pills
                    VStack(alignment: .trailing, spacing: 3) {
                        breakdownChip(label: "User", value: String(format: "%.1f%%", sample.user), color: .blue)
                        breakdownChip(label: "Sys", value: String(format: "%.1f%%", sample.system), color: .orange)
                        breakdownChip(label: "Idle", value: String(format: "%.1f%%", sample.idle), color: .secondary)
                    }
                }
            }

            // Usage Breakdown Bar
            if let sample = sample {
                breakdownBar(sample: sample)
            }

            // Rolling 60s History Graph
            VStack(alignment: .leading, spacing: 4) {
                RollingGraphView(
                    values: historyPercentages,
                    minValue: 0.0,
                    maxValue: 100.0,
                    tintColor: .blue,
                    capacity: 60,
                    height: 44,
                    showGrid: true
                )

                HStack {
                    Text("60s CPU Activity")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    if let sample = sample {
                        let peak = historyPercentages.max() ?? sample.totalUsage
                        Text(String(format: "Peak: %.1f%%", peak))
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }

            if let sample = sample {
                // System Telemetry Tiles (Load Avg, Frequency / Model, Uptime)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    telemetryCard(
                        title: "Load Avg",
                        value: sample.loadAverage != nil ? String(format: "%.2f", sample.loadAverage!.oneMinute) : "N/A",
                        detail: sample.loadAverage != nil ? String(format: "5m: %.2f", sample.loadAverage!.fiveMinute) : nil,
                        icon: "gauge.medium"
                    )

                    telemetryCard(
                        title: "Clock",
                        value: sample.frequencyHz != nil ? Units.formatFrequencyHz(sample.frequencyHz!, fractionDigits: 1) : "Dynamic",
                        detail: sample.frequencyHz != nil ? nil : "Apple Silicon",
                        icon: "bolt.badge.clock"
                    )

                    telemetryCard(
                        title: "Uptime",
                        value: uptimeString,
                        detail: nil,
                        icon: "clock.arrow.circlepath"
                    )
                }

                // Per-Core Utilization Section
                if !sample.perCore.isEmpty {
                    perCoreSection(perCore: sample.perCore)
                }
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

    // MARK: - Breakdown Bar

    private func breakdownBar(sample: CPUSample) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let userWidth = max(0, width * CGFloat(sample.user / 100.0))
            let sysWidth = max(0, width * CGFloat(sample.system / 100.0))
            let idleWidth = max(0, width - userWidth - sysWidth)

            HStack(spacing: 1.5) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.blue)
                    .frame(width: max(0, userWidth - 1))

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.orange)
                    .frame(width: max(0, sysWidth - 1))

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: max(0, idleWidth))
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: 5)
    }

    private func breakdownChip(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)

            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)

            Text(value)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
        }
    }

    // MARK: - Telemetry Card Tile

    private func telemetryCard(title: String, value: String, detail: String?, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)

            if let detail = detail {
                Text(detail)
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    // MARK: - Per-Core Section

    private func perCoreSection(perCore: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPerCoreExpanded.toggle()
                }
            }) {
                HStack {
                    Text("Cores (\(perCore.count))")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: isPerCoreExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isPerCoreExpanded {
                let columns = [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ]

                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(0..<perCore.count, id: \.self) { index in
                        let coreUsage = perCore[index]
                        HStack(spacing: 4) {
                            Text(String(format: "C%d", index))
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 22, alignment: .leading)

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.secondary.opacity(0.15))
                                        .frame(height: 4)

                                    Capsule()
                                        .fill(usageColor(for: coreUsage))
                                        .frame(width: max(2, geo.size.width * CGFloat(min(max(coreUsage, 0), 100) / 100.0)), height: 4)
                                }
                            }
                            .frame(height: 4)

                            Text(String(format: "%2.0f%%", coreUsage))
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 26, alignment: .trailing)
                        }
                        .padding(.vertical, 1)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Helpers

    private func usageColor(for usage: Double) -> Color {
        if usage >= 85.0 {
            return .red
        } else if usage >= 60.0 {
            return .orange
        } else {
            return .blue
        }
    }
}

