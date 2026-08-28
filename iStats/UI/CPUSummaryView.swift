import SwiftUI
import iStatsCore

/// A comprehensive CPU metrics card view displaying aggregate utilization, live rolling history graph,
/// user/system/idle breakdown, load average, clock frequency, system uptime, and per-core distribution
/// (Requirements 10.1, 10.2, 10.3).
public struct CPUSummaryView: View {
    public let sample: CPUSample?
    public let history: [Sample<CPUSample>]
    @State private var isPerCoreExpanded: Bool = false

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
                    Text("CPU Activity History")
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
                        value: sample.frequencyHz != nil ? Units.formatFrequencyHz(sample.frequencyHz!, fractionDigits: 1) : "—",
                        detail: sample.frequencyHz != nil ? nil : "Dynamic",
                        icon: "bolt.badge.clock"
                    )

                    telemetryCard(
                        title: "Uptime",
                        value: uptimeString,
                        detail: nil,
                        icon: "clock.arrow.circlepath"
                    )
                }

                // Per-Core Utilization Section (Real iStat Rings & Cluster Breakdown)
                if !sample.perCore.isEmpty {
                    perCoreSection(sample: sample)
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

    // MARK: - Per-Core Section (Real iStat Style)

    private func perCoreSection(sample: CPUSample) -> some View {
        let perCore = sample.perCore
        let hasEandP = (sample.efficiencyCoreCount ?? 0) > 0 && (sample.performanceCoreCount ?? 0) > 0

        return VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPerCoreExpanded.toggle()
                }
            }) {
                HStack {
                    Text("Per-Core Breakdown (\(perCore.count) Cores)")
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
                // Row of Circular Ring Gauges
                if perCore.count <= 12 {
                    HStack(spacing: 5) {
                        ForEach(0..<perCore.count, id: \.self) { index in
                            CoreRingGauge(
                                usage: perCore[index],
                                coreType: sample.coreType(at: index),
                                index: index
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 17, maximum: 22), spacing: 5)], spacing: 6) {
                        ForEach(0..<perCore.count, id: \.self) { index in
                            CoreRingGauge(
                                usage: perCore[index],
                                coreType: sample.coreType(at: index),
                                index: index
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }

                // Cluster Utilization Rows
                VStack(spacing: 5) {
                    if hasEandP {
                        if let eUsage = sample.efficiencyUsage {
                            coreClusterRow(
                                title: "Efficiency Cores",
                                value: String(format: "%.0f%%", eUsage),
                                color: Color(red: 0.98, green: 0.28, blue: 0.60)
                            )
                        }
                        if let pUsage = sample.performanceUsage {
                            coreClusterRow(
                                title: "Performance Cores",
                                value: String(format: "%.0f%%", pUsage),
                                color: Color(red: 0.08, green: 0.52, blue: 1.0)
                            )
                        }
                    } else if let pUsage = sample.performanceUsage {
                        coreClusterRow(
                            title: "Performance Cores",
                            value: String(format: "%.0f%%", pUsage),
                            color: Color(red: 0.08, green: 0.52, blue: 1.0)
                        )
                    } else {
                        coreClusterRow(
                            title: "Cores (\(perCore.count))",
                            value: String(format: "%.0f%%", sample.totalUsage),
                            color: Color(red: 0.08, green: 0.52, blue: 1.0)
                        )
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    private func coreClusterRow(title: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)

            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
        }
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

/// A circular progress ring gauge for an individual CPU core.
struct CoreRingGauge: View {
    let usage: Double
    let coreType: CPUCoreType
    let index: Int

    private var coreColor: Color {
        switch coreType {
        case .efficiency:
            return Color(red: 0.98, green: 0.28, blue: 0.60)
        case .performance:
            return Color(red: 0.08, green: 0.52, blue: 1.0)
        case .standard:
            return Color(red: 0.08, green: 0.52, blue: 1.0)
        }
    }

    private var label: String {
        let typeName: String
        switch coreType {
        case .efficiency: typeName = "Efficiency"
        case .performance: typeName = "Performance"
        case .standard: typeName = "Standard"
        }
        return "Core \(index + 1) (\(typeName)): \(String(format: "%.0f%%", usage))"
    }

    var body: some View {
        let clamped = max(0.0, min(100.0, usage))
        let fraction = CGFloat(clamped / 100.0)

        ZStack {
            // Background Track
            Circle()
                .stroke(
                    coreColor.opacity(0.18),
                    style: StrokeStyle(lineWidth: 2.5)
                )

            // Progress Arc
            Circle()
                .trim(from: 0.0, to: fraction)
                .stroke(
                    coreColor,
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 17, height: 17)
        .help(label)
    }
}

