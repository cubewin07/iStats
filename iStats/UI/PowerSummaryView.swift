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
            if let sample = sample {
                if sample.hasBattery {
                    // Battery Present View
                    batteryPresentSection(sample: sample)
                } else {
                    // Desktop Mac / AC-only View
                    noBatterySection(sample: sample)
                }
            } else {
                Text("Waiting for power telemetry...")
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

    // MARK: - Battery Present Section

    private func batteryPresentSection(sample: PowerSample) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Hero Battery Card
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(powerSourceLabel(sample: sample))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)

                    if let charge = sample.charge {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(String(format: "%.0f", charge))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(chargeColor(for: charge, state: sample.state))

                            Text("%")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(chargeColor(for: charge, state: sample.state))

                            if sample.state == .charging {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.green)
                            }
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    if let state = sample.state {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(chargeColor(for: sample.charge, state: state))
                                .frame(width: 5, height: 5)
                            Text(stateDisplayName(state))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(chargeColor(for: sample.charge, state: state))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(chargeColor(for: sample.charge, state: state).opacity(0.12))
                        .clipShape(Capsule())
                    }

                    if let time = sample.timeRemaining {
                        Text(formatTimeRemaining(time, state: sample.state))
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Charge Level Gauge Bar
            if let charge = sample.charge {
                let ratio = min(1.0, max(0.0, charge / 100.0))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.18))
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: [chargeColor(for: charge, state: sample.state).opacity(0.8), chargeColor(for: charge, state: sample.state)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, geo.size.width * CGFloat(ratio)), height: 6)
                    }
                }
                .frame(height: 6)
            }

            // Power Draw Rolling Graph
            if !historyPowerDraw.isEmpty || sample.powerDrawWatts != nil {
                powerDrawGraphSection()
            }

            // Power Draw & Adapter Wattage Tiles
            HStack(spacing: 8) {
                if let draw = sample.powerDrawWatts {
                    telemetryTile(
                        title: "Power Draw",
                        value: String(format: "%.1f W", draw),
                        color: .orange,
                        icon: "bolt.fill"
                    )
                }

                if let adapter = sample.adapterWatts {
                    telemetryTile(
                        title: "Power Adapter",
                        value: String(format: "%.0f W", adapter),
                        color: .green,
                        icon: "powerplug.fill"
                    )
                }
            }

            // Battery Health & Longevity Section
            if hasHealthMetrics(sample) {
                batteryHealthSection(sample: sample)
            }
        }
    }

    // MARK: - No Battery Section (Desktop Mac)

    private func noBatterySection(sample: PowerSample) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "powerplug.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.green)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Desktop Mac (AC Powered)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.primary)
                    Text("Connected to power supply. No internal battery present.")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.secondary.opacity(0.06))
            )

            // Wattage tiles if available
            HStack(spacing: 8) {
                if let draw = sample.powerDrawWatts {
                    telemetryTile(
                        title: "System Power Draw",
                        value: String(format: "%.1f W", draw),
                        color: .orange,
                        icon: "bolt.fill"
                    )
                }

                if let adapter = sample.adapterWatts {
                    telemetryTile(
                        title: "Power Supply",
                        value: String(format: "%.0f W", adapter),
                        color: .green,
                        icon: "powerplug.fill"
                    )
                }
            }

            if historyPowerDraw.count >= 2 {
                powerDrawGraphSection()
            }
        }
    }

    // MARK: - Power Draw Graph Section

    private func powerDrawGraphSection() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            RollingGraphView(
                values: historyPowerDraw,
                minValue: 0.0,
                maxValue: peakPowerDraw,
                tintColor: .orange,
                capacity: 60,
                height: 44,
                showGrid: true
            )

            HStack {
                Text("60s Power Consumption")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "Peak: %.1f W", peakPowerDraw))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Battery Health Section

    private func batteryHealthSection(sample: PowerSample) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHealthExpanded.toggle()
                }
            }) {
                HStack {
                    Text("Battery Health & Capacity")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.primary)
                    Spacer()
                    if let condition = sample.condition {
                        Text(condition)
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(condition == "Normal" ? .green : .red)
                    }
                    Image(systemName: isHealthExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isHealthExpanded {
                VStack(spacing: 5) {
                    if let curMax = sample.currentMaxCapacity, let design = sample.designCapacity, design > 0 {
                        let healthPercent = (Double(curMax) / Double(design)) * 100.0
                        healthRow(
                            title: "Maximum Capacity",
                            value: String(format: "%.1f%% (%d / %d mAh)", healthPercent, curMax, design),
                            valueColor: healthPercent >= 80 ? .green : .orange
                        )
                    } else if let curMax = sample.currentMaxCapacity {
                        healthRow(title: "Maximum Capacity", value: "\(curMax) mAh")
                    }

                    if let cycles = sample.cycleCount {
                        healthRow(title: "Cycle Count", value: "\(cycles) cycles")
                    }

                    if let condition = sample.condition {
                        healthRow(title: "Condition", value: condition, valueColor: condition == "Normal" ? .green : .red)
                    }
                }
                .padding(7)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.06))
                )
                .transition(.opacity)
            }
        }
        .padding(.top, 2)
    }

    private func healthRow(title: String, value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 9.5))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(valueColor)
        }
    }

    private func telemetryTile(title: String, value: String, color: Color, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 8.5))
                    .foregroundColor(.secondary)

                Text(value)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.06))
        )
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func powerSourceLabel(sample: PowerSample) -> String {
        if sample.state == .charging || sample.state == .acConnected || sample.state == .charged {
            if let watts = sample.adapterWatts {
                return "Power Adapter (\(Int(watts))W)"
            }
            return "Power Adapter Connected"
        }
        return "Battery Power"
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
        case .charged: return "Fully Charged"
        case .acConnected: return "AC Power"
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
            return "\(timeStr) until full"
        } else {
            return "\(timeStr) remaining"
        }
    }

    private func hasHealthMetrics(_ sample: PowerSample) -> Bool {
        sample.cycleCount != nil || sample.condition != nil || sample.currentMaxCapacity != nil || sample.designCapacity != nil
    }
}

