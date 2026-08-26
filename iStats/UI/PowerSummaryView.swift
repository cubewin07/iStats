import SwiftUI
import iStatsCore

/// A comprehensive Battery and Power metrics view displaying live charge capacity, charging state,
/// time remaining, health (cycle count, condition, capacity), instantaneous power draw, adapter wattage,
/// and graceful handling of machines with no internal battery (Requirements 8.1, 8.2, 8.3, 8.4, 10.1).
public struct PowerSummaryView: View {
    public let sample: PowerSample?
    public let history: [Sample<PowerSample>]

    @State private var isHealthExpanded: Bool = true

    public init(
        sample: PowerSample? = nil,
        history: [Sample<PowerSample>] = []
    ) {
        self.sample = sample
        self.history = history
    }

    /// History values of instantaneous power draw in Watts.
    private var historyPowerDraw: [Double] {
        history.compactMap { $0.value.powerDrawWatts }
    }

    private var currentPowerDraw: Double {
        sample?.powerDrawWatts ?? 0.0
    }

    private var peakPowerDraw: Double {
        let maxHist = historyPowerDraw.max() ?? 0.0
        return max(maxHist, currentPowerDraw, 1.0)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Category Icon, Name, Live Status
            HStack {
                Label {
                    Text(headerTitle)
                        .font(.headline)
                        .fontWeight(.semibold)
                } icon: {
                    Image(systemName: headerIcon)
                        .foregroundColor(headerIconColor)
                }

                Spacer()

                if let sample = sample {
                    if sample.hasBattery {
                        HStack(spacing: 6) {
                            if let charge = sample.charge {
                                Text(String(format: "%.0f%%", charge))
                                    .font(.system(.body, design: .monospaced))
                                    .fontWeight(.bold)
                                    .foregroundColor(chargeColor(for: charge, state: sample.state))
                            }
                            if let state = sample.state {
                                Text("(\(stateDisplayName(state)))")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        // Desktop Mac / No battery present (Requirement 8.4)
                        Text("AC Powered")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Sampling...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            if let sample = sample {
                if sample.hasBattery {
                    // Battery Present Section (Requirements 8.1, 8.2, 8.3)
                    batteryPresentSection(sample: sample)
                } else {
                    // No Battery Present Section (Requirement 8.4)
                    noBatterySection(sample: sample)
                }
            } else {
                Text("Waiting for power sample...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Battery Present Section

    private func batteryPresentSection(sample: PowerSample) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Charge Gauge
            if let charge = sample.charge {
                let ratio = min(1.0, max(0.0, charge / 100.0))
                VStack(alignment: .leading, spacing: 3) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(chargeColor(for: charge, state: sample.state))
                                .frame(width: max(0, geo.size.width * CGFloat(ratio)), height: 6)
                        }
                    }
                    .frame(height: 6)

                    HStack {
                        Text(String(format: "%.1f%% remaining", charge))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)

                        Spacer()

                        if let time = sample.timeRemaining {
                            Text(formatTimeRemaining(time, state: sample.state))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Power Draw Rolling Graph (if wattage history available, Requirement 8.3)
            if !historyPowerDraw.isEmpty || sample.powerDrawWatts != nil {
                powerDrawGraphSection(sample: sample)
            }

            // Power & Adapter Badges
            let hasWattageInfo = sample.powerDrawWatts != nil || sample.adapterWatts != nil
            if hasWattageInfo {
                HStack(spacing: 12) {
                    if let draw = sample.powerDrawWatts {
                        metricBadge(
                            title: "Power Draw",
                            value: String(format: "%.1f W", draw),
                            color: .orange
                        )
                    }
                    if let adapter = sample.adapterWatts {
                        metricBadge(
                            title: "Adapter",
                            value: String(format: "%.0f W", adapter),
                            color: .green
                        )
                    }
                }
                .padding(.top, 2)
            }

            // Battery Health Section (Requirement 8.2)
            if hasHealthMetrics(sample) {
                batteryHealthSection(sample: sample)
            }
        }
    }

    // MARK: - No Battery Section (Requirement 8.4)

    private func noBatterySection(sample: PowerSample) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "powerplug")
                    .font(.system(size: 14))
                    .foregroundColor(.green)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Desktop Mac (AC Powered)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                    Text("No internal battery installed. Battery metrics not applicable.")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.06))
            )

            // Wattage if exposed by hardware
            if let draw = sample.powerDrawWatts {
                HStack(spacing: 12) {
                    metricBadge(
                        title: "System Power Draw",
                        value: String(format: "%.1f W", draw),
                        color: .orange
                    )
                    if let adapter = sample.adapterWatts {
                        metricBadge(
                            title: "Power Supply",
                            value: String(format: "%.0f W", adapter),
                            color: .green
                        )
                    }
                }
                .padding(.top, 2)

                if !historyPowerDraw.isEmpty {
                    powerDrawGraphSection(sample: sample)
                }
            }
        }
    }

    // MARK: - Power Draw Graph Section

    private func powerDrawGraphSection(sample: PowerSample) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            RollingGraphView(
                values: historyPowerDraw.isEmpty ? (sample.powerDrawWatts != nil ? [sample.powerDrawWatts!] : []) : historyPowerDraw,
                minValue: 0.0,
                maxValue: peakPowerDraw,
                tintColor: .orange,
                capacity: 60,
                height: 48,
                showGrid: true
            )

            HStack {
                Text("60s power draw")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "Peak: %.1f W", peakPowerDraw))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Battery Health Section

    private func batteryHealthSection(sample: PowerSample) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHealthExpanded.toggle()
                }
            }) {
                HStack {
                    Text("Battery Health")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    if let condition = sample.condition {
                        Text(condition)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(condition == "Normal" ? .green : .red)
                    }
                    Image(systemName: isHealthExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isHealthExpanded {
                VStack(spacing: 6) {
                    if let cycles = sample.cycleCount {
                        healthRow(title: "Cycle Count", value: "\(cycles) cycles")
                    }

                    if let condition = sample.condition {
                        healthRow(title: "Condition", value: condition, valueColor: condition == "Normal" ? .green : .red)
                    }

                    if let curMax = sample.currentMaxCapacity, let design = sample.designCapacity, design > 0 {
                        let healthPercent = (Double(curMax) / Double(design)) * 100.0
                        healthRow(
                            title: "Maximum Capacity",
                            value: String(format: "%.1f%% (%d / %d mAh)", healthPercent, curMax, design)
                        )
                    } else if let curMax = sample.currentMaxCapacity {
                        healthRow(title: "Maximum Capacity", value: "\(curMax) mAh")
                    }
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.06))
                )
                .transition(.opacity)
            }
        }
        .padding(.top, 4)
    }

    private func healthRow(title: String, value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .fontWeight(.medium)
                .foregroundColor(valueColor)
        }
    }

    // MARK: - Helpers

    private var headerTitle: String {
        guard let sample = sample else { return "Power" }
        return sample.hasBattery ? "Battery & Power" : "Power"
    }

    private var headerIcon: String {
        guard let sample = sample else { return "bolt.fill" }
        if !sample.hasBattery {
            return "powerplug.fill"
        }
        return batteryIcon(charge: sample.charge, state: sample.state)
    }

    private var headerIconColor: Color {
        guard let sample = sample else { return .green }
        if !sample.hasBattery {
            return .secondary
        }
        return chargeColor(for: sample.charge, state: sample.state)
    }

    private func batteryIcon(charge: Double?, state: BatteryState?) -> String {
        guard let charge = charge else { return "battery.100" }
        let isCharging = state == .charging
        if isCharging {
            if charge >= 90 { return "battery.100.bolt" }
            if charge >= 70 { return "battery.75.bolt" }
            if charge >= 45 { return "battery.50.bolt" }
            if charge >= 20 { return "battery.25.bolt" }
            return "battery.0.bolt"
        } else {
            if charge >= 90 { return "battery.100" }
            if charge >= 70 { return "battery.75" }
            if charge >= 45 { return "battery.50" }
            if charge >= 20 { return "battery.25" }
            return "battery.0"
        }
    }

    private func chargeColor(for charge: Double?, state: BatteryState?) -> Color {
        guard let charge = charge else { return .green }
        if state == .charging {
            return .green
        }
        if charge <= 10.0 {
            return .red
        } else if charge <= 20.0 {
            return .orange
        } else {
            return .green
        }
    }

    private func stateDisplayName(_ state: BatteryState) -> String {
        switch state {
        case .charging: return "Charging"
        case .discharging: return "Discharging"
        case .charged: return "Charged"
        case .acConnected: return "AC Connected"
        case .unknown: return "Unknown"
        }
    }

    private func formatTimeRemaining(_ seconds: TimeInterval, state: BatteryState?) -> String {
        let totalMinutes = Int(seconds) / 60
        let timeStr: String
        if totalMinutes < 60 {
            timeStr = "\(totalMinutes)m"
        } else {
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            timeStr = minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        }

        if state == .charging {
            return "\(timeStr) to full"
        } else {
            return "\(timeStr) left"
        }
    }

    private func hasHealthMetrics(_ sample: PowerSample) -> Bool {
        sample.cycleCount != nil || sample.condition != nil || sample.currentMaxCapacity != nil || sample.designCapacity != nil
    }

    private func metricBadge(title: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(title):")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
