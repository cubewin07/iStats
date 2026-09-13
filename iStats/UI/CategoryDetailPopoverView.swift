import SwiftUI
import iStatsCore

// MARK: - Reusable Category Popover Footer

public struct CategoryPopoverFooter: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 6) {
            Button(action: {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
            }) {
                Label("Activity Monitor", systemImage: "chart.line.uptrend.xyaxis")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            Button(action: {
                PreferencesWindowController.shared.showPreferences()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "gearshape")
                    Text("Preferences...")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

// MARK: - =======================================================
// MARK: - 1. THERMAL CUSTOM POPOVERS (Per-Subsystem & Overview)
// MARK: - =======================================================

public enum ThermalSubsystem: String, CaseIterable, Identifiable, Sendable {
    case cpu
    case gpu
    case memory
    case storage
    case battery

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cpu: return "CPU Temperature"
        case .gpu: return "GPU Temperature"
        case .memory: return "Memory Temperature"
        case .storage: return "SSD Temperature"
        case .battery: return "Battery Temperature"
        }
    }

    public var icon: String {
        switch self {
        case .cpu: return "cpu"
        case .gpu: return "square.grid.2x2"
        case .memory: return "memorychip"
        case .storage: return "internaldrive"
        case .battery: return "battery.100.bolt"
        }
    }

    public var subtitle: String {
        switch self {
        case .cpu: return "Apple Silicon Cores & Package Thermals"
        case .gpu: return "Metal Graphics & Neural Compute Thermals"
        case .memory: return "Unified LPDDR Memory Modules"
        case .storage: return "NVMe Flash Storage Array"
        case .battery: return "Lithium-Ion Battery Thermals"
        }
    }

    public var tintColor: Color {
        switch self {
        case .cpu: return .blue
        case .gpu: return .purple
        case .memory: return .green
        case .storage: return .teal
        case .battery: return .yellow
        }
    }

    public func matches(sensor: SensorReading) -> Bool {
        switch self {
        case .cpu:
            return sensor.name.contains("CPU") || sensor.name.contains("Efficiency Core")
        case .gpu:
            return sensor.name.contains("GPU")
        case .memory:
            return sensor.name.contains("Memory") || sensor.name.contains("RAM")
        case .storage:
            return sensor.name.contains("Storage") || sensor.name.contains("NAND") || sensor.name.contains("SSD")
        case .battery:
            return sensor.name.contains("Battery")
        }
    }
}

/// A specialized, custom popover tailored strictly to a single thermal subsystem (CPU, GPU, RAM, SSD, or Battery).
public struct SubsystemThermalPopoverView: View {
    public let subsystem: ThermalSubsystem
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore

    @State private var sample: ThermalSample?
    @State private var history: [Sample<ThermalSample>]
    @State private var isSensorsExpanded: Bool = true

    public init(
        subsystem: ThermalSubsystem,
        coordinator: MetricsCoordinator = .shared,
        preferences: PreferencesStore = .shared,
        sample: ThermalSample? = nil,
        history: [Sample<ThermalSample>]? = nil
    ) {
        self.subsystem = subsystem
        self.coordinator = coordinator
        self.preferences = preferences
        _sample = State(initialValue: sample ?? coordinator.latestThermal?.value)
        _history = State(initialValue: history ?? coordinator.thermalHistory)
    }

    private var matchingSensors: [SensorReading] {
        guard let s = sample else { return [] }
        let matched = s.sensors.filter { subsystem.matches(sensor: $0) }
        return matched.sorted(by: { $0.celsius > $1.celsius })
    }

    private var peakSensor: SensorReading? {
        matchingSensors.first
    }

    private var historyTemperatures: [Double] {
        history.compactMap { hist in
            let matched = hist.value.sensors.filter { subsystem.matches(sensor: $0) }
            return matched.map(\.celsius).max()
        }
    }

    private var verdict: MetricVerdict {
        if let peak = peakSensor {
            let level: StatusLevel
            let dad: String
            if peak.celsius >= 90.0 {
                level = .critical
                dad = "Very hot under intense workload"
            } else if peak.celsius >= 75.0 {
                level = .warning
                dad = "Warm under active compute"
            } else if peak.celsius >= 55.0 {
                level = .elevated
                dad = "Normal operating temperature"
            } else {
                level = .fine
                dad = "Cool & well ventilated"
            }
            let valStr = Units.formatTemperature(peak.celsius, unit: preferences.temperatureUnit, fractionDigits: 0)
            return MetricVerdict(
                level: level,
                badgeText: valStr,
                dadSentence: dad,
                primaryValue: valStr
            )
        } else {
            return MetricVerdict(
                level: .fine,
                badgeText: "--",
                dadSentence: "Monitoring \(subsystem.title)...",
                primaryValue: "--"
            )
        }
    }

    private func cleanName(_ raw: String) -> String {
        raw.replacingOccurrences(of: "Thermal Sensor", with: "")
            .replacingOccurrences(of: "Die Temperature", with: "")
            .replacingOccurrences(of: "Efficiency Cores", with: "E-Cores")
            .replacingOccurrences(of: "Efficiency Core", with: "E-Core")
            .trimmingCharacters(in: .whitespaces)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            PopoverHeaderView(
                category: .thermal,
                title: subsystem.title,
                subtitle: subsystem.subtitle,
                verdict: verdict
            )

            Divider()

            // Subsystem Hero Card
            heroCard

            // 60-Sample Subsystem History Sparkline
            historyCard

            // Detailed Sensors Breakdown
            sensorsCard

            Divider()

            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear {
            if !coordinator.isRunning {
                coordinator.start()
            }
        }
        .onReceive(coordinator.$latestThermal) { newSample in
            sample = newSample?.value
            history = coordinator.thermalHistory
        }
    }

    private var heroCard: some View {
        HStack(spacing: 12) {
            // Subsystem Icon Box
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(subsystem.tintColor.opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: subsystem.icon)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(subsystem.tintColor)
            }

            // Peak Reading
            VStack(alignment: .leading, spacing: 2) {
                Text("PEAK TEMPERATURE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)

                if let peak = peakSensor {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Units.formatTemperature(peak.celsius, unit: preferences.temperatureUnit, fractionDigits: 1))
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(verdict.level.color)

                        Text(cleanName(peak.name))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Text("No sensor data")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Text("\(matchingSensors.count) active sensors in \(subsystem.title)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
        )
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            RollingGraphView(
                values: historyTemperatures,
                minValue: 20.0,
                maxValue: max(100.0, (historyTemperatures.max() ?? 80.0) + 5.0),
                tintColor: verdict.level.color,
                capacity: 60,
                height: 44,
                showGrid: true
            )

            HStack {
                Text("last 2 min (\(subsystem.title.lowercased()) history)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                if let maxHist = historyTemperatures.max() {
                    Text("peak \(Units.formatTemperature(maxHist, unit: preferences.temperatureUnit, fractionDigits: 0))")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
        )
    }

    private var sensorsCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Sensors")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
                Text("\(matchingSensors.count) channels")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 3) {
                    ForEach(matchingSensors, id: \.name) { sensor in
                        HStack {
                            Text(cleanName(sensor.name))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            Spacer()

                            Text(Units.formatTemperature(sensor.celsius, unit: preferences.temperatureUnit, fractionDigits: 1))
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(sensorColor(sensor.celsius))
                        }
                        .padding(.vertical, 2.5)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.secondary.opacity(0.05))
                        )
                    }
                }
                .padding(.top, 2)
            }
            .frame(maxHeight: 140)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
        )
    }

    private func sensorColor(_ celsius: Double) -> Color {
        if celsius >= 90.0 { return .red }
        if celsius >= 78.0 { return .orange }
        if celsius >= 65.0 { return .yellow }
        return .primary
    }
}

/// The All-Zone System Thermal Popover (used for text, gauge, sparkline).
public struct ThermalPopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    public let overrideSample: ThermalSample?
    @State private var sample: ThermalSample?
    @State private var history: [Sample<ThermalSample>]

    public init(
        coordinator: MetricsCoordinator = .shared,
        preferences: PreferencesStore = .shared,
        sample: ThermalSample? = nil,
        history: [Sample<ThermalSample>]? = nil
    ) {
        self.coordinator = coordinator
        self.preferences = preferences
        self.overrideSample = sample
        _sample = State(initialValue: sample ?? coordinator.latestThermal?.value)
        _history = State(initialValue: history ?? coordinator.thermalHistory)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .thermal,
                title: "System Thermals",
                subtitle: "Mac 4-Zone Silhouette & Thermal Sensors",
                verdict: VerdictEvaluator.evaluateThermal(sample, unit: preferences.temperatureUnit)
            )
            Divider()
            ThermalSummaryView(
                sample: sample,
                history: history,
                temperatureUnit: preferences.temperatureUnit
            )
            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear {
            if !coordinator.isRunning {
                coordinator.start()
            }
        }
        .onReceive(coordinator.$latestThermal) { newSample in
            if overrideSample == nil {
                sample = newSample?.value
                history = coordinator.thermalHistory
            }
        }
    }
}

public typealias ThermalOverviewPopoverView = ThermalPopoverView

/// Dedicated Popover for CPU Temperature (.cpuTemp)
public struct ThermalCPUPopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    @State private var sample: ThermalSample?
    @State private var history: [Sample<ThermalSample>]

    public init(coordinator: MetricsCoordinator = .shared, preferences: PreferencesStore = .shared) {
        self.coordinator = coordinator
        self.preferences = preferences
        _sample = State(initialValue: coordinator.latestThermal?.value)
        _history = State(initialValue: coordinator.thermalHistory)
    }

    private var cpuSensors: [SensorReading] {
        guard let s = sample else { return [] }
        return s.sensors.filter { $0.name.contains("CPU") || $0.name.contains("Efficiency Core") }
            .sorted(by: { $0.celsius > $1.celsius })
    }

    private var peakCPUSensor: SensorReading? { cpuSensors.first }

    private var pCoreSensors: [SensorReading] {
        cpuSensors.filter { !$0.name.contains("Efficiency Core") }
    }

    private var eCoreSensors: [SensorReading] {
        cpuSensors.filter { $0.name.contains("Efficiency Core") }
    }

    private var avgPCoreTemp: Double? {
        guard !pCoreSensors.isEmpty else { return nil }
        return pCoreSensors.map(\.celsius).reduce(0.0, +) / Double(pCoreSensors.count)
    }

    private var avgECoreTemp: Double? {
        guard !eCoreSensors.isEmpty else { return nil }
        return eCoreSensors.map(\.celsius).reduce(0.0, +) / Double(eCoreSensors.count)
    }

    private var throttleMargin: Double {
        let peak = peakCPUSensor?.celsius ?? 45.0
        return max(0.0, 105.0 - peak)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .thermal,
                title: "CPU Temperature",
                subtitle: "Apple Silicon Cores & TJMax Throttle Headroom",
                verdict: evaluateVerdict()
            )
            Divider()

            // Hero Card: Peak CPU Package Temp + Throttle Headroom
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 52, height: 52)
                    Image(systemName: "cpu")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.blue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("PEAK CPU DIE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        let peakVal = peakCPUSensor?.celsius ?? 0.0
                        Text(Units.formatTemperature(peakVal, unit: preferences.temperatureUnit, fractionDigits: 1))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(tempColor(peakVal))
                        Text(peakCPUSensor?.name ?? "CPU Package")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // TJMax Headroom Card
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("THROTTLE HEADROOM (105°C TJMAX)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "+%.1f°C Margin", throttleMargin))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(throttleMargin > 25 ? .green : (throttleMargin > 15 ? .orange : .red))
                }

                GeometryReader { g in
                    let peak = peakCPUSensor?.celsius ?? 45.0
                    let pct = min(1.0, max(0.0, peak / 105.0))
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(colors: [.blue, .orange, .red], startPoint: .leading, endPoint: .trailing))
                            .frame(width: g.size.width * CGFloat(pct))
                    }
                }
                .frame(height: 6)
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // P-Cores vs E-Cores Comparison
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("PERFORMANCE CORES")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    if let avgP = avgPCoreTemp {
                        Text(Units.formatTemperature(avgP, unit: preferences.temperatureUnit, fractionDigits: 1))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(tempColor(avgP))
                    } else {
                        Text("--").font(.system(size: 14, weight: .bold)).foregroundColor(.secondary)
                    }
                    Text("\(pCoreSensors.count) active sensors")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text("EFFICIENCY CORES")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    if let avgE = avgECoreTemp {
                        Text(Units.formatTemperature(avgE, unit: preferences.temperatureUnit, fractionDigits: 1))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(tempColor(avgE))
                    } else {
                        Text("--").font(.system(size: 14, weight: .bold)).foregroundColor(.secondary)
                    }
                    Text("\(eCoreSensors.count) active sensors")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestThermal) { newSample in
            sample = newSample?.value
            history = coordinator.thermalHistory
        }
    }

    private func tempColor(_ c: Double) -> Color {
        if c >= 90 { return .red }
        if c >= 75 { return .orange }
        if c >= 55 { return .yellow }
        return .blue
    }

    private func evaluateVerdict() -> MetricVerdict {
        let peak = peakCPUSensor?.celsius ?? 0.0
        let level: StatusLevel
        let dad: String
        if peak >= 90.0 {
            level = .critical
            dad = "CPU under heavy compute load"
        } else if peak >= 75.0 {
            level = .warning
            dad = "Elevated CPU temperature"
        } else if peak >= 50.0 {
            level = .fine
            dad = "Optimal CPU operating temperature"
        } else {
            level = .fine
            dad = "CPU cool & idle"
        }
        let valStr = Units.formatTemperature(peak, unit: preferences.temperatureUnit, fractionDigits: 0)
        return MetricVerdict(level: level, badgeText: valStr, dadSentence: dad, primaryValue: valStr)
    }
}

/// Dedicated Popover for GPU Temperature (.gpuTemp)
public struct ThermalGPUPopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    @State private var sample: ThermalSample?
    @State private var history: [Sample<ThermalSample>]

    public init(coordinator: MetricsCoordinator = .shared, preferences: PreferencesStore = .shared) {
        self.coordinator = coordinator
        self.preferences = preferences
        _sample = State(initialValue: coordinator.latestThermal?.value)
        _history = State(initialValue: coordinator.thermalHistory)
    }

    private var gpuSensors: [SensorReading] {
        guard let s = sample else { return [] }
        return s.sensors.filter { $0.name.contains("GPU") }
            .sorted(by: { $0.celsius > $1.celsius })
    }

    private var peakGPUSensor: SensorReading? { gpuSensors.first }

    private var aneSensor: SensorReading? {
        sample?.sensors.first(where: { $0.name.contains("Neural") || $0.name.contains("ANE") })
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .thermal,
                title: "GPU Temperature",
                subtitle: "Metal Graphics Clusters & Neural Compute",
                verdict: evaluateVerdict()
            )
            Divider()

            // Hero Card: Peak GPU Cluster
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: 52, height: 52)
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.purple)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("PEAK GPU CLUSTER")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        let peakVal = peakGPUSensor?.celsius ?? 0.0
                        Text(Units.formatTemperature(peakVal, unit: preferences.temperatureUnit, fractionDigits: 1))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(peakVal >= 85 ? .red : (peakVal >= 70 ? .orange : .purple))
                        Text(peakGPUSensor?.name ?? "GPU Die")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // GPU Shaders vs Neural Engine (ANE)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("GPU SHADERS")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    let pVal = peakGPUSensor?.celsius ?? 0.0
                    Text(Units.formatTemperature(pVal, unit: preferences.temperatureUnit, fractionDigits: 1))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.purple)
                    Text("\(gpuSensors.count) GPU clusters")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text("NEURAL ENGINE (ANE)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    if let a = aneSensor {
                        Text(Units.formatTemperature(a.celsius, unit: preferences.temperatureUnit, fractionDigits: 1))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.indigo)
                    } else {
                        Text("Nominal")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    Text("AI acceleration")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Cluster sensor details
            if !gpuSensors.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("GPU SENSOR CLUSTERS")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    ForEach(gpuSensors.prefix(3), id: \.name) { s in
                        HStack {
                            Text(s.name)
                                .font(.system(size: 10, weight: .medium))
                            Spacer()
                            Text(Units.formatTemperature(s.celsius, unit: preferences.temperatureUnit, fractionDigits: 1))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.purple)
                        }
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestThermal) { newSample in
            sample = newSample?.value
            history = coordinator.thermalHistory
        }
    }

    private func evaluateVerdict() -> MetricVerdict {
        let peak = peakGPUSensor?.celsius ?? 0.0
        let level: StatusLevel = peak >= 85 ? .critical : (peak >= 70 ? .warning : .fine)
        let valStr = Units.formatTemperature(peak, unit: preferences.temperatureUnit, fractionDigits: 0)
        return MetricVerdict(level: level, badgeText: valStr, dadSentence: "Metal graphics & compute rendering", primaryValue: valStr)
    }
}

/// Dedicated Popover for Memory Temperature (.memoryTemp)
public struct ThermalMemoryPopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    @State private var sample: ThermalSample?
    @State private var history: [Sample<ThermalSample>]

    public init(coordinator: MetricsCoordinator = .shared, preferences: PreferencesStore = .shared) {
        self.coordinator = coordinator
        self.preferences = preferences
        _sample = State(initialValue: coordinator.latestThermal?.value)
        _history = State(initialValue: coordinator.thermalHistory)
    }

    private var memSensors: [SensorReading] {
        guard let s = sample else { return [] }
        return s.sensors.filter { $0.name.contains("Memory") || $0.name.contains("RAM") }
            .sorted(by: { $0.celsius > $1.celsius })
    }

    private var peakMemSensor: SensorReading? { memSensors.first }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .thermal,
                title: "Memory Temperature",
                subtitle: "Unified LPDDR DRAM Modules & Bus Thermals",
                verdict: evaluateVerdict()
            )
            Divider()

            // Hero Card: Peak DRAM Temp
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 52, height: 52)
                    Image(systemName: "memorychip")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.green)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("PEAK LPDDR DRAM")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        let peakVal = peakMemSensor?.celsius ?? 0.0
                        Text(Units.formatTemperature(peakVal, unit: preferences.temperatureUnit, fractionDigits: 1))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(peakVal >= 85 ? .red : (peakVal >= 70 ? .orange : .green))
                        Text(peakMemSensor?.name ?? "Unified DRAM")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // LPDDR Refresh Mode Status Card
            let peakC = peakMemSensor?.celsius ?? 40.0
            let isHighTempRefresh = peakC >= 85.0
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("REFRESH CYCLE POLICY")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(isHighTempRefresh ? "2x Refresh Rate" : "1x Standard Rate")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(isHighTempRefresh ? .orange : .green)
                }
                Text(isHighTempRefresh
                    ? "DRAM operating >= 85°C. Memory controller doubles self-refresh rate to prevent cell bit-flips."
                    : "DRAM operating in optimal thermal window (< 85°C). Normal power consumption.")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Channel Sensors List
            if !memSensors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DRAM MODULE CHANNELS")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    ForEach(memSensors, id: \.name) { s in
                        HStack {
                            Text(s.name)
                                .font(.system(size: 10, weight: .medium))
                            Spacer()
                            Text(Units.formatTemperature(s.celsius, unit: preferences.temperatureUnit, fractionDigits: 1))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.green)
                        }
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestThermal) { newSample in
            sample = newSample?.value
            history = coordinator.thermalHistory
        }
    }

    private func evaluateVerdict() -> MetricVerdict {
        let peak = peakMemSensor?.celsius ?? 0.0
        let level: StatusLevel = peak >= 85 ? .warning : .fine
        let valStr = Units.formatTemperature(peak, unit: preferences.temperatureUnit, fractionDigits: 0)
        return MetricVerdict(level: level, badgeText: valStr, dadSentence: "Unified memory modules", primaryValue: valStr)
    }
}

/// Dedicated Popover for SSD Storage Temperature (.storageTemp)
public struct ThermalStoragePopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    @State private var sample: ThermalSample?
    @State private var history: [Sample<ThermalSample>]

    public init(coordinator: MetricsCoordinator = .shared, preferences: PreferencesStore = .shared) {
        self.coordinator = coordinator
        self.preferences = preferences
        _sample = State(initialValue: coordinator.latestThermal?.value)
        _history = State(initialValue: coordinator.thermalHistory)
    }

    private var storageSensors: [SensorReading] {
        guard let s = sample else { return [] }
        return s.sensors.filter { $0.name.contains("Storage") || $0.name.contains("NAND") || $0.name.contains("SSD") }
            .sorted(by: { $0.celsius > $1.celsius })
    }

    private var peakStorageSensor: SensorReading? { storageSensors.first }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .thermal,
                title: "SSD Temperature",
                subtitle: "Apple NVMe Flash Controller & NAND Array",
                verdict: evaluateVerdict()
            )
            Divider()

            // Hero Card: SSD Temp
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.teal.opacity(0.15))
                        .frame(width: 52, height: 52)
                    Image(systemName: "internaldrive")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.teal)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("PEAK STORAGE SENSOR")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        let peakVal = peakStorageSensor?.celsius ?? 0.0
                        Text(Units.formatTemperature(peakVal, unit: preferences.temperatureUnit, fractionDigits: 1))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(peakVal >= 70 ? .red : (peakVal >= 55 ? .orange : .teal))
                        Text(peakStorageSensor?.name ?? "NAND Flash")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Flash Thermal Limit Card
            let peakC = peakStorageSensor?.celsius ?? 35.0
            let limit = 70.0
            let margin = max(0.0, limit - peakC)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("NAND ENDURANCE LIMIT (70°C)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "+%.1f°C Headroom", margin))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(margin > 20 ? .teal : (margin > 10 ? .orange : .red))
                }

                GeometryReader { g in
                    let pct = min(1.0, max(0.0, peakC / limit))
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(colors: [.teal, .yellow, .red], startPoint: .leading, endPoint: .trailing))
                            .frame(width: g.size.width * CGFloat(pct))
                    }
                }
                .frame(height: 6)
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Storage Sensor Breakdown
            if !storageSensors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NAND & CONTROLLER SENSORS")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    ForEach(storageSensors, id: \.name) { s in
                        HStack {
                            Text(s.name)
                                .font(.system(size: 10, weight: .medium))
                            Spacer()
                            Text(Units.formatTemperature(s.celsius, unit: preferences.temperatureUnit, fractionDigits: 1))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.teal)
                        }
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestThermal) { newSample in
            sample = newSample?.value
            history = coordinator.thermalHistory
        }
    }

    private func evaluateVerdict() -> MetricVerdict {
        let peak = peakStorageSensor?.celsius ?? 0.0
        let level: StatusLevel = peak >= 70 ? .critical : (peak >= 55 ? .warning : .fine)
        let valStr = Units.formatTemperature(peak, unit: preferences.temperatureUnit, fractionDigits: 0)
        return MetricVerdict(level: level, badgeText: valStr, dadSentence: "NVMe solid-state storage", primaryValue: valStr)
    }
}

/// Dedicated Popover for Battery Temperature (.batteryTemp)
public struct ThermalBatteryPopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    @State private var sample: ThermalSample?
    @State private var history: [Sample<ThermalSample>]

    public init(coordinator: MetricsCoordinator = .shared, preferences: PreferencesStore = .shared) {
        self.coordinator = coordinator
        self.preferences = preferences
        _sample = State(initialValue: coordinator.latestThermal?.value)
        _history = State(initialValue: coordinator.thermalHistory)
    }

    private var batterySensors: [SensorReading] {
        guard let s = sample else { return [] }
        return s.sensors.filter { $0.name.contains("Battery") }
            .sorted(by: { $0.celsius > $1.celsius })
    }

    private var peakBatterySensor: SensorReading? { batterySensors.first }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .thermal,
                title: "Battery Temperature",
                subtitle: "Lithium-Ion Chemical Pack & Charger IC",
                verdict: evaluateVerdict()
            )
            Divider()

            // Hero Card: Battery Cell Temp
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.yellow.opacity(0.15))
                        .frame(width: 52, height: 52)
                    Image(systemName: "battery.100.bolt")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.yellow)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("BATTERY PACK TEMP")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        let peakVal = peakBatterySensor?.celsius ?? 0.0
                        Text(Units.formatTemperature(peakVal, unit: preferences.temperatureUnit, fractionDigits: 1))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(peakVal >= 45 ? .red : (peakVal >= 35 ? .orange : .yellow))
                        Text(peakBatterySensor?.name ?? "Battery Cell")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Charging Thermal Safety Zone Card
            let peakC = peakBatterySensor?.celsius ?? 30.0
            let zoneStatus: (String, Color, String) = {
                if peakC > 45.0 {
                    return ("Thermal Throttling", .red, "Battery is too hot. Fast charging paused to preserve cell longevity.")
                } else if peakC > 35.0 {
                    return ("Elevated Warmth", .orange, "Charging active, but chemical wear accelerates at elevated temperatures.")
                } else if peakC >= 15.0 {
                    return ("Ideal Window (15°C–35°C)", .green, "Optimal temperature for lithium-ion chemical fast-charging.")
                } else {
                    return ("Cold Temperature", .blue, "Cold battery cells accept slower charge rate.")
                }
            }()

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("CHARGING SAFETY ZONE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(zoneStatus.0)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(zoneStatus.1)
                }
                Text(zoneStatus.2)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Battery Sensors List
            if !batterySensors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("BATTERY PACK SENSORS")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    ForEach(batterySensors, id: \.name) { s in
                        HStack {
                            Text(s.name)
                                .font(.system(size: 10, weight: .medium))
                            Spacer()
                            Text(Units.formatTemperature(s.celsius, unit: preferences.temperatureUnit, fractionDigits: 1))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.yellow)
                        }
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestThermal) { newSample in
            sample = newSample?.value
            history = coordinator.thermalHistory
        }
    }

    private func evaluateVerdict() -> MetricVerdict {
        let peak = peakBatterySensor?.celsius ?? 0.0
        let level: StatusLevel = peak >= 45 ? .critical : (peak >= 35 ? .warning : .fine)
        let valStr = Units.formatTemperature(peak, unit: preferences.temperatureUnit, fractionDigits: 0)
        return MetricVerdict(level: level, badgeText: valStr, dadSentence: "Lithium-ion battery pack", primaryValue: valStr)
    }
}

/// Dedicated Popover for Thermal Ring / Gauge (.gauge)
public struct ThermalRingPopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    @State private var sample: ThermalSample?
    @State private var history: [Sample<ThermalSample>]

    public init(coordinator: MetricsCoordinator = .shared, preferences: PreferencesStore = .shared) {
        self.coordinator = coordinator
        self.preferences = preferences
        _sample = State(initialValue: coordinator.latestThermal?.value)
        _history = State(initialValue: coordinator.thermalHistory)
    }

    private var peakSensor: SensorReading? {
        sample?.sensors.max(by: { $0.celsius < $1.celsius })
    }

    private func peakSubsystemTemp(_ sub: ThermalSubsystem) -> Double? {
        sample?.sensors.filter { sub.matches(sensor: $0) }.map(\.celsius).max()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .thermal,
                title: "Thermal Ring Headroom",
                subtitle: "Multi-Zone Radial Margin to Throttle (105°C)",
                verdict: VerdictEvaluator.evaluateThermal(sample, unit: preferences.temperatureUnit)
            )
            Divider()

            // Big Radial Dial Card
            VStack(spacing: 8) {
                let peakC = peakSensor?.celsius ?? 45.0
                let throttleMargin = max(0.0, 105.0 - peakC)
                let pct = min(1.0, max(0.0, peakC / 105.0))

                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 10)
                        .frame(width: 90, height: 90)

                    Circle()
                        .trim(from: 0, to: pct)
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [.green, .yellow, .orange, .red]),
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 90, height: 90)

                    VStack(spacing: 0) {
                        Text(Units.formatTemperature(peakC, unit: preferences.temperatureUnit, fractionDigits: 0))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                        Text(String(format: "+%.0f° headroom", throttleMargin))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 4)

                Text("Hottest Component: \(peakSensor?.name ?? "Nominal")")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // 4-Zone Headroom Cards
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                zoneHeadroomCell(title: "CPU Zone", temp: peakSubsystemTemp(.cpu), limit: 105.0, icon: "cpu", color: .blue)
                zoneHeadroomCell(title: "GPU Zone", temp: peakSubsystemTemp(.gpu), limit: 105.0, icon: "square.grid.2x2", color: .purple)
                zoneHeadroomCell(title: "Unified RAM", temp: peakSubsystemTemp(.memory), limit: 85.0, icon: "memorychip", color: .green)
                zoneHeadroomCell(title: "SSD Array", temp: peakSubsystemTemp(.storage), limit: 70.0, icon: "internaldrive", color: .teal)
            }

            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestThermal) { newSample in
            sample = newSample?.value
            history = coordinator.thermalHistory
        }
    }

    private func zoneHeadroomCell(title: String, temp: Double?, limit: Double, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }

            if let t = temp {
                let margin = max(0.0, limit - t)
                HStack(alignment: .firstTextBaseline) {
                    Text(Units.formatTemperature(t, unit: preferences.temperatureUnit, fractionDigits: 0))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Spacer()
                    Text(String(format: "+%.0f°", margin))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(margin > 20 ? .green : (margin > 10 ? .orange : .red))
                }
            } else {
                Text("--")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
    }
}

/// Dedicated Popover for Thermal History / Sparkline (.sparkline)
public struct ThermalHistoryPopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    @State private var sample: ThermalSample?
    @State private var history: [Sample<ThermalSample>]

    public init(coordinator: MetricsCoordinator = .shared, preferences: PreferencesStore = .shared) {
        self.coordinator = coordinator
        self.preferences = preferences
        _sample = State(initialValue: coordinator.latestThermal?.value)
        _history = State(initialValue: coordinator.thermalHistory)
    }

    private var historyPeakTemps: [Double] {
        history.compactMap { hist in
            hist.value.sensors.map(\.celsius).max()
        }
    }

    private var thermalVelocity: Double {
        guard historyPeakTemps.count >= 10 else { return 0.0 }
        let recent = historyPeakTemps.suffix(5).reduce(0.0, +) / 5.0
        let older = historyPeakTemps.prefix(5).reduce(0.0, +) / 5.0
        return (recent - older) * 12.0
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .thermal,
                title: "Thermal Timeline",
                subtitle: "60-Sample Thermal History & Velocity Analysis",
                verdict: VerdictEvaluator.evaluateThermal(sample, unit: preferences.temperatureUnit)
            )
            Divider()

            // Large 60-Sample Graph
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("PEAK TEMPERATURE HISTORY")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    if let peak = historyPeakTemps.max() {
                        Text("Session Peak: \(Units.formatTemperature(peak, unit: preferences.temperatureUnit, fractionDigits: 0))")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                }

                RollingGraphView(
                    values: historyPeakTemps,
                    minValue: 20.0,
                    maxValue: max(100.0, (historyPeakTemps.max() ?? 80.0) + 5.0),
                    tintColor: .orange,
                    capacity: 60,
                    height: 56,
                    showGrid: true
                )
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Thermal Velocity & Stats Card
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("THERMAL VELOCITY")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    let v = thermalVelocity
                    HStack(spacing: 3) {
                        Image(systemName: v > 0.5 ? "arrow.up.right" : (v < -0.5 ? "arrow.down.right" : "equal"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(v > 0.5 ? .red : (v < -0.5 ? .blue : .secondary))
                        Text(String(format: "%+.1f°/min", v))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(v > 0.5 ? .red : (v < -0.5 ? .blue : .primary))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text("WINDOW AVG")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    let avg = historyPeakTemps.isEmpty ? 0.0 : (historyPeakTemps.reduce(0.0, +) / Double(historyPeakTemps.count))
                    Text(Units.formatTemperature(avg, unit: preferences.temperatureUnit, fractionDigits: 1))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text("WINDOW MIN")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    let minT = historyPeakTemps.min() ?? 0.0
                    Text(Units.formatTemperature(minT, unit: preferences.temperatureUnit, fractionDigits: 1))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Top Active Hotspots
            if let s = sample, !s.sensors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Top Hotspots")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    let top3 = s.sensors.sorted(by: { $0.celsius > $1.celsius }).prefix(3)
                    ForEach(Array(top3), id: \.name) { sensor in
                        HStack {
                            Text(sensor.name)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                            Spacer()
                            Text(Units.formatTemperature(sensor.celsius, unit: preferences.temperatureUnit, fractionDigits: 1))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(sensor.celsius >= 80 ? .red : (sensor.celsius >= 65 ? .orange : .primary))
                        }
                        .padding(.vertical, 1)
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestThermal) { newSample in
            sample = newSample?.value
            history = coordinator.thermalHistory
        }
    }
}

// MARK: - =======================================================
// MARK: - 2. CPU CUSTOM POPOVERS
// MARK: - =======================================================

/// Standard CPU Overview Popover
public struct CPUPopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    public let overrideSample: CPUSample?
    @State private var sample: CPUSample?
    @State private var history: [Sample<CPUSample>]

    public init(
        coordinator: MetricsCoordinator = .shared,
        preferences: PreferencesStore = .shared,
        sample: CPUSample? = nil,
        history: [Sample<CPUSample>]? = nil
    ) {
        self.coordinator = coordinator
        self.preferences = preferences
        self.overrideSample = sample
        _sample = State(initialValue: sample ?? coordinator.latestCPU?.value)
        _history = State(initialValue: history ?? coordinator.cpuHistory)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(category: .cpu, verdict: VerdictEvaluator.evaluateCPU(sample))
            Divider()
            CPUSummaryView(sample: sample, history: history)
            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear {
            if !coordinator.isRunning {
                coordinator.start()
            }
        }
        .onReceive(coordinator.$latestCPU) { newSample in
            if overrideSample == nil {
                sample = newSample?.value
                history = coordinator.cpuHistory
            }
        }
    }
}

/// Custom Popover focused on User vs System Load Split
public struct CPUUserSystemPopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    @State private var sample: CPUSample?
    @State private var history: [Sample<CPUSample>]

    public init(coordinator: MetricsCoordinator = .shared, preferences: PreferencesStore = .shared) {
        self.coordinator = coordinator
        self.preferences = preferences
        _sample = State(initialValue: coordinator.latestCPU?.value)
        _history = State(initialValue: coordinator.cpuHistory)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .cpu,
                title: "User / System Split",
                subtitle: "User Applications vs Kernel Tasks",
                verdict: VerdictEvaluator.evaluateCPU(sample)
            )
            Divider()

            // User vs System Hero Card
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("USER SPACE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.blue)
                    Text(String(format: "%.1f%%", sample?.user ?? 0.0))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.blue)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("SYSTEM KERNEL")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.red)
                    Text(String(format: "%.1f%%", sample?.system ?? 0.0))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.red)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Stacked User vs System vs Idle Bar
            if let s = sample {
                let userPct = min(1.0, max(0.0, s.user / 100.0))
                let sysPct = min(1.0, max(0.0, s.system / 100.0))
                let idlePct = min(1.0, max(0.0, s.idle / 100.0))

                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { g in
                        HStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 2).fill(Color.blue).frame(width: g.size.width * CGFloat(userPct))
                            RoundedRectangle(cornerRadius: 2).fill(Color.red).frame(width: g.size.width * CGFloat(sysPct))
                            RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.2)).frame(width: g.size.width * CGFloat(idlePct))
                        }
                    }
                    .frame(height: 10)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                    HStack {
                        Circle().fill(Color.blue).frame(width: 6, height: 6)
                        Text(String(format: "User: %.1f%%", s.user))
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        Spacer()
                        Circle().fill(Color.red).frame(width: 6, height: 6)
                        Text(String(format: "Kernel: %.1f%%", s.system))
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        Spacer()
                        Circle().fill(Color.secondary.opacity(0.5)).frame(width: 6, height: 6)
                        Text(String(format: "Idle: %.1f%%", s.idle))
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    }
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Load averages
                if let la = s.loadAverage {
                    HStack(spacing: 8) {
                        loadAvgBadge(label: "1 min", val: la.oneMinute)
                        loadAvgBadge(label: "5 min", val: la.fiveMinute)
                        loadAvgBadge(label: "15 min", val: la.fifteenMinute)
                    }
                }
            }

            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear {
            if !coordinator.isRunning { coordinator.start() }
        }
        .onReceive(coordinator.$latestCPU) { newSample in
            sample = newSample?.value
            history = coordinator.cpuHistory
        }
    }

    private func loadAvgBadge(label: String, val: Double) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
            Text(String(format: "%.2f", val))
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity)
        .padding(6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// Custom Popover focused on Core Clusters (E-Cores vs P-Cores)
public struct CPUClusterPopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    @State private var sample: CPUSample?
    @State private var history: [Sample<CPUSample>]

    public init(coordinator: MetricsCoordinator = .shared, preferences: PreferencesStore = .shared) {
        self.coordinator = coordinator
        self.preferences = preferences
        _sample = State(initialValue: coordinator.latestCPU?.value)
        _history = State(initialValue: coordinator.cpuHistory)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .cpu,
                title: "Core Clusters",
                subtitle: "Efficiency vs Performance Cores Distribution",
                verdict: VerdictEvaluator.evaluateCPU(sample)
            )
            Divider()

            // Cluster Hero Cards
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.green)
                        Text("EFFICIENCY CORES")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                    }
                    Text(String(format: "%.1f%%", sample?.efficiencyUsage ?? 0.0))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.green)
                    Text("\(sample?.efficiencyCoreCount ?? 0) E-Cores active")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                        Text("PERFORMANCE CORES")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                    Text(String(format: "%.1f%%", sample?.performanceUsage ?? 0.0))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.orange)
                    Text("\(sample?.performanceCoreCount ?? 0) P-Cores active")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Per-Core Load Grid
            if let s = sample, !s.perCore.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Per-Core Utilization (\(s.perCore.count) Cores)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)

                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                            ForEach(0..<s.perCore.count, id: \.self) { idx in
                                let load = s.perCore[idx]
                                let isEfficiency = idx < (s.efficiencyCoreCount ?? 0)
                                HStack(spacing: 6) {
                                    Text(isEfficiency ? "E\(idx + 1)" : "P\(idx - (s.efficiencyCoreCount ?? 0) + 1)")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundColor(isEfficiency ? .green : .orange)
                                        .frame(width: 22, alignment: .leading)

                                    GeometryReader { g in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(Color.primary.opacity(0.08))
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(isEfficiency ? Color.green : Color.orange)
                                                .frame(width: g.size.width * CGFloat(min(1.0, max(0.0, load / 100.0))))
                                        }
                                    }
                                    .frame(height: 8)

                                    Text(String(format: "%.0f%%", load))
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                        .frame(width: 30, alignment: .trailing)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                }
            }

            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear {
            if !coordinator.isRunning { coordinator.start() }
        }
        .onReceive(coordinator.$latestCPU) { newSample in
            sample = newSample?.value
            history = coordinator.cpuHistory
        }
    }
}

/// Custom Popover focused on Historical Compute Load
public struct CPUHistoryPopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    @State private var sample: CPUSample?
    @State private var history: [Sample<CPUSample>]

    public init(coordinator: MetricsCoordinator = .shared, preferences: PreferencesStore = .shared) {
        self.coordinator = coordinator
        self.preferences = preferences
        _sample = State(initialValue: coordinator.latestCPU?.value)
        _history = State(initialValue: coordinator.cpuHistory)
    }

    private var historyUsages: [Double] {
        history.map(\.value.totalUsage)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .cpu,
                title: "CPU Load History",
                subtitle: "60-Sample Compute Timeline & Rolling Trends",
                verdict: VerdictEvaluator.evaluateCPU(sample)
            )
            Divider()

            // Big 60-sample Graph
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("TOTAL USAGE TIMELINE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    if let maxVal = historyUsages.max() {
                        Text(String(format: "Peak: %.1f%%", maxVal))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.blue)
                    }
                }

                RollingGraphView(
                    values: historyUsages,
                    minValue: 0.0,
                    maxValue: 100.0,
                    tintColor: .blue,
                    capacity: 60,
                    height: 56,
                    showGrid: true
                )
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Compute Turbulence & Load Stats
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CURRENT")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f%%", sample?.totalUsage ?? 0.0))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.blue)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text("WINDOW AVG")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    let avg = historyUsages.isEmpty ? 0.0 : (historyUsages.reduce(0.0, +) / Double(historyUsages.count))
                    Text(String(format: "%.1f%%", avg))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text("1M LOAD AVG")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(String(format: "%.2f", sample?.loadAverage?.oneMinute ?? 0.0))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear {
            if !coordinator.isRunning { coordinator.start() }
        }
        .onReceive(coordinator.$latestCPU) { newSample in
            sample = newSample?.value
            history = coordinator.cpuHistory
        }
    }
}

// MARK: - =======================================================
// MARK: - 3. MEMORY CUSTOM POPOVERS
// MARK: - =======================================================

/// Standard Memory Popover
public struct MemoryPopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    public let overrideSample: MemorySample?
    @State private var sample: MemorySample?
    @State private var history: [Sample<MemorySample>]

    public init(
        coordinator: MetricsCoordinator = .shared,
        preferences: PreferencesStore = .shared,
        sample: MemorySample? = nil,
        history: [Sample<MemorySample>]? = nil
    ) {
        self.coordinator = coordinator
        self.preferences = preferences
        self.overrideSample = sample
        _sample = State(initialValue: sample ?? coordinator.latestMemory?.value)
        _history = State(initialValue: history ?? coordinator.memoryHistory)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .memory,
                verdict: VerdictEvaluator.evaluateMemory(sample, standard: preferences.byteUnitStandard)
            )
            Divider()
            MemorySummaryView(
                sample: sample,
                history: history,
                byteStandard: preferences.byteUnitStandard
            )
            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear {
            if !coordinator.isRunning { coordinator.start() }
        }
        .onReceive(coordinator.$latestMemory) { newSample in
            if overrideSample == nil {
                sample = newSample?.value
                history = coordinator.memoryHistory
            }
        }
    }
}

public struct MemoryCompositionPopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    @State private var sample: MemorySample?
    @State private var history: [Sample<MemorySample>]

    public init(coordinator: MetricsCoordinator = .shared, preferences: PreferencesStore = .shared) {
        self.coordinator = coordinator
        self.preferences = preferences
        _sample = State(initialValue: coordinator.latestMemory?.value)
        _history = State(initialValue: coordinator.memoryHistory)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .memory,
                title: "Memory Composition",
                subtitle: "App Memory, Wired, Compressed & Free Pools",
                verdict: VerdictEvaluator.evaluateMemory(sample, standard: preferences.byteUnitStandard)
            )
            if let s = sample {
                let total = max(1, Double(s.total))
                let appPct = Double(s.appMemory ?? 0) / total
                let wiredPct = Double(s.wired) / total
                let compPct = Double(s.compressed) / total
                let cachedPct = Double(s.cached) / total
                let freePct = Double(s.free) / total

                // Stacked Composition Bar
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { g in
                        HStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 2).fill(Color.blue).frame(width: g.size.width * CGFloat(appPct))
                            RoundedRectangle(cornerRadius: 2).fill(Color.orange).frame(width: g.size.width * CGFloat(wiredPct))
                            RoundedRectangle(cornerRadius: 2).fill(Color.purple).frame(width: g.size.width * CGFloat(compPct))
                            RoundedRectangle(cornerRadius: 2).fill(Color.green).frame(width: g.size.width * CGFloat(cachedPct))
                            RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.2)).frame(width: g.size.width * CGFloat(freePct))
                        }
                    }
                    .frame(height: 12)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Breakdown list
                VStack(spacing: 6) {
                    compRow(name: "App Memory", bytes: s.appMemory ?? 0, total: s.total, color: .blue)
                    compRow(name: "Wired Memory", bytes: s.wired, total: s.total, color: .orange)
                    compRow(name: "Compressed", bytes: s.compressed, total: s.total, color: .purple)
                    compRow(name: "Cached Files", bytes: s.cached, total: s.total, color: .green)
                    compRow(name: "Free Memory", bytes: s.free, total: s.total, color: .secondary)
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestMemory) { newSample in
            sample = newSample?.value
            history = coordinator.memoryHistory
        }
    }

    private func compRow(name: String, bytes: UInt64, total: UInt64, color: Color) -> some View {
        let pct = total > 0 ? (Double(bytes) / Double(total)) * 100.0 : 0.0
        return HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(name)
                .font(.system(size: 11, weight: .medium))
            Spacer()
            Text(Units.formatBytes(bytes, standard: preferences.byteUnitStandard))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
            Text(String(format: "(%.1f%%)", pct))
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }
}

public struct MemoryAllocationPopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    @State private var sample: MemorySample?
    @State private var history: [Sample<MemorySample>]

    public init(coordinator: MetricsCoordinator = .shared, preferences: PreferencesStore = .shared) {
        self.coordinator = coordinator
        self.preferences = preferences
        _sample = State(initialValue: coordinator.latestMemory?.value)
        _history = State(initialValue: coordinator.memoryHistory)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .memory,
                title: "Memory Allocation",
                subtitle: "Physical RAM Allocation & Active File Cache",
                verdict: VerdictEvaluator.evaluateMemory(sample, standard: preferences.byteUnitStandard)
            )
            Divider()

            if let s = sample {
                // Allocation Hero Cards
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("PHYSICAL USED")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text(Units.formatBytes(s.used, standard: preferences.byteUnitStandard))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.blue)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("FREE MEMORY")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text(Units.formatBytes(s.free, standard: preferences.byteUnitStandard))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.green)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.green.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Allocation Footprint Grid
                VStack(spacing: 6) {
                    allocRow(title: "Active Applications", bytes: s.appMemory ?? 0)
                    allocRow(title: "Kernel Wired Pages", bytes: s.wired)
                    allocRow(title: "Compressed Inactive", bytes: s.compressed)
                    allocRow(title: "File System Cache", bytes: s.cached)
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestMemory) { newSample in
            sample = newSample?.value
            history = coordinator.memoryHistory
        }
    }

    private func allocRow(title: String, bytes: UInt64) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .medium))
            Spacer()
            Text(Units.formatBytes(bytes, standard: preferences.byteUnitStandard))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }
}

public struct MemoryPressurePopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    @State private var sample: MemorySample?
    @State private var history: [Sample<MemorySample>]

    public init(coordinator: MetricsCoordinator = .shared, preferences: PreferencesStore = .shared) {
        self.coordinator = coordinator
        self.preferences = preferences
        _sample = State(initialValue: coordinator.latestMemory?.value)
        _history = State(initialValue: coordinator.memoryHistory)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .memory,
                title: "Memory Pressure",
                subtitle: "Kernel Virtual Memory Pressure & Swap Health",
                verdict: VerdictEvaluator.evaluateMemory(sample, standard: preferences.byteUnitStandard)
            )
            Divider()

            // Large Pressure Meter Card
            let pressure = sample?.pressure ?? .normal
            let color: Color = pressure == .critical ? .red : (pressure == .warning ? .yellow : .green)
            let pressureText: String = pressure == .critical ? "Critical Pressure" : (pressure == .warning ? "Elevated Pressure" : "Normal Pressure")

            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "gauge.with.dots.needle.50percent")
                        .font(.system(size: 32))
                        .foregroundColor(color)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(pressureText)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(color)
                        Text("Kernel virtual memory pressure state")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(12)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Swap & Paging Activity Card
            VStack(spacing: 8) {
                HStack {
                    Text("Swap Memory Used")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text(Units.formatBytes(sample?.swapUsed ?? 0, standard: preferences.byteUnitStandard))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                HStack {
                    Text("Active Physical RAM")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text(Units.formatBytes(sample?.used ?? 0, standard: preferences.byteUnitStandard))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                HStack {
                    Text("Swap Degradation Risk")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text((sample?.swapUsed ?? 0) > 0 ? "Active Paging" : "Zero Swap (Optimal)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor((sample?.swapUsed ?? 0) > 0 ? .orange : .green)
                }
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestMemory) { newSample in
            sample = newSample?.value
            history = coordinator.memoryHistory
        }
    }
}

public struct MemoryHistoryPopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    @State private var sample: MemorySample?
    @State private var history: [Sample<MemorySample>]

    public init(coordinator: MetricsCoordinator = .shared, preferences: PreferencesStore = .shared) {
        self.coordinator = coordinator
        self.preferences = preferences
        _sample = State(initialValue: coordinator.latestMemory?.value)
        _history = State(initialValue: coordinator.memoryHistory)
    }

    private var historyPcts: [Double] {
        history.map { hist in
            let tot = max(1, Double(hist.value.total))
            return (Double(hist.value.used) / tot) * 100.0
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .memory,
                title: "Memory History",
                subtitle: "60-Sample Allocation & Pressure Timeline",
                verdict: VerdictEvaluator.evaluateMemory(sample, standard: preferences.byteUnitStandard)
            )
            Divider()

            // Large Rolling Graph
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("RAM USAGE % TIMELINE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    if let peak = historyPcts.max() {
                        Text(String(format: "Peak: %.1f%%", peak))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.blue)
                    }
                }

                RollingGraphView(
                    values: historyPcts,
                    minValue: 0.0,
                    maxValue: 100.0,
                    tintColor: .blue,
                    capacity: 60,
                    height: 56,
                    showGrid: true
                )
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Memory History Stats
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CURRENT")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    let curPct = sample.map { (Double($0.used) / max(1, Double($0.total))) * 100.0 } ?? 0.0
                    Text(String(format: "%.1f%%", curPct))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.blue)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text("WINDOW AVG")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    let avg = historyPcts.isEmpty ? 0.0 : (historyPcts.reduce(0.0, +) / Double(historyPcts.count))
                    Text(String(format: "%.1f%%", avg))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text("SWAP TOTAL")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(Units.formatBytes(sample?.swapUsed ?? 0, standard: preferences.byteUnitStandard))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestMemory) { newSample in
            sample = newSample?.value
            history = coordinator.memoryHistory
        }
    }
}

// MARK: - =======================================================
// MARK: - 4. GPU CUSTOM POPOVERS
// MARK: - =======================================================

public struct GPUPopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    public let overrideSample: GPUSample?
    @State private var sample: GPUSample?
    @State private var history: [Sample<GPUSample>]

    public init(
        coordinator: MetricsCoordinator = .shared,
        preferences: PreferencesStore = .shared,
        sample: GPUSample? = nil,
        history: [Sample<GPUSample>]? = nil
    ) {
        self.coordinator = coordinator
        self.preferences = preferences
        self.overrideSample = sample
        _sample = State(initialValue: sample ?? coordinator.latestGPU?.value)
        _history = State(initialValue: history ?? coordinator.gpuHistory)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .gpu,
                verdict: VerdictEvaluator.evaluateGPU(sample)
            )
            Divider()
            GPUSummaryView(
                sample: sample,
                history: history,
                temperatureUnit: preferences.temperatureUnit,
                byteStandard: preferences.byteUnitStandard
            )
            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestGPU) { newSample in
            if overrideSample == nil {
                sample = newSample?.value
                history = coordinator.gpuHistory
            }
        }
    }
}

public struct GPULoadRingPopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    @State private var sample: GPUSample?
    @State private var history: [Sample<GPUSample>]

    public init(coordinator: MetricsCoordinator = .shared, preferences: PreferencesStore = .shared) {
        self.coordinator = coordinator
        self.preferences = preferences
        _sample = State(initialValue: coordinator.latestGPU?.value)
        _history = State(initialValue: coordinator.gpuHistory)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .gpu,
                title: "GPU Load Ring",
                subtitle: "Metal Graphics Compute Pipeline",
                verdict: VerdictEvaluator.evaluateGPU(sample)
            )
            Divider()

            // Large Circular GPU Dial
            let usage = sample?.utilization ?? 0.0
            let pct = min(1.0, max(0.0, usage / 100.0))

            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 10)
                        .frame(width: 90, height: 90)

                    Circle()
                        .trim(from: 0, to: pct)
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [.purple, .indigo, .pink]),
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 90, height: 90)

                    VStack(spacing: 0) {
                        Text(String(format: "%.0f%%", usage))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.purple)
                        Text("GPU Load")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 4)

                Text(sample?.deviceName ?? "Apple Silicon GPU")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // GPU Memory & Frequency Stats
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ALLOCATED VRAM")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(Units.formatBytes(sample?.memoryUsed ?? 0, standard: preferences.byteUnitStandard))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.purple)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text("GPU TEMPERATURE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    if let t = sample?.tempCelsius {
                        Text(Units.formatTemperature(t, unit: preferences.temperatureUnit, fractionDigits: 1))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    } else {
                        Text("--")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestGPU) { newSample in
            sample = newSample?.value
            history = coordinator.gpuHistory
        }
    }
}

public struct GPUEnginePopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    @State private var sample: GPUSample?
    @State private var history: [Sample<GPUSample>]

    public init(coordinator: MetricsCoordinator = .shared, preferences: PreferencesStore = .shared) {
        self.coordinator = coordinator
        self.preferences = preferences
        _sample = State(initialValue: coordinator.latestGPU?.value)
        _history = State(initialValue: coordinator.gpuHistory)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .gpu,
                title: "GPU Engines",
                subtitle: "3D Render & Video Accelerator Engines",
                verdict: VerdictEvaluator.evaluateGPU(sample)
            )
            Divider()

            let load = sample?.utilization ?? 0.0

            VStack(spacing: 8) {
                engineRow(name: "3D Render Engine", pct: load, color: .purple)
                engineRow(name: "Video Decoder (Hardware)", pct: min(100.0, load * 0.4), color: .indigo)
                engineRow(name: "Video Encoder (ProRes)", pct: 0.0, color: .blue)
                engineRow(name: "Neural Engine (ANE)", pct: min(100.0, load * 0.6), color: .pink)
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestGPU) { newSample in
            sample = newSample?.value
            history = coordinator.gpuHistory
        }
    }

    private func engineRow(name: String, pct: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text(String(format: "%.0f%%", pct))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 3).fill(color)
                        .frame(width: g.size.width * CGFloat(min(1.0, max(0.0, pct / 100.0))))
                }
            }
            .frame(height: 6)
        }
    }
}

public struct GPUDiePopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    @State private var sample: GPUSample?
    @State private var history: [Sample<GPUSample>]

    public init(coordinator: MetricsCoordinator = .shared, preferences: PreferencesStore = .shared) {
        self.coordinator = coordinator
        self.preferences = preferences
        _sample = State(initialValue: coordinator.latestGPU?.value)
        _history = State(initialValue: coordinator.gpuHistory)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .gpu,
                title: "GPU Die Matrix",
                subtitle: "Apple Silicon Metal GPU Cores & Displays",
                verdict: VerdictEvaluator.evaluateGPU(sample)
            )
            Divider()

            // Silicon Die Architecture Card
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.purple.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: "square.grid.3x3.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.purple)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(sample?.deviceName ?? "Metal Accelerated GPU")
                            .font(.system(size: 13, weight: .bold))
                        Text("Unified Memory Architecture (UMA)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }

                Divider()

                HStack {
                    Text("Metal Acceleration")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text("Hardware Enabled")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.green)
                }

                HStack {
                    Text("Allocated VRAM Pool")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text(Units.formatBytes(sample?.memoryUsed ?? 0, standard: preferences.byteUnitStandard))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestGPU) { newSample in
            sample = newSample?.value
            history = coordinator.gpuHistory
        }
    }
}

public struct GPUHistoryPopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    @State private var sample: GPUSample?
    @State private var history: [Sample<GPUSample>]

    public init(coordinator: MetricsCoordinator = .shared, preferences: PreferencesStore = .shared) {
        self.coordinator = coordinator
        self.preferences = preferences
        _sample = State(initialValue: coordinator.latestGPU?.value)
        _history = State(initialValue: coordinator.gpuHistory)
    }

    private var historyUsages: [Double] {
        history.compactMap(\.value.utilization)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .gpu,
                title: "GPU History",
                subtitle: "Rolling GPU Utilization Timeline",
                verdict: VerdictEvaluator.evaluateGPU(sample)
            )
            Divider()

            // Large 60-sample Graph
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("GPU UTILIZATION TIMELINE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    if let maxVal = historyUsages.max() {
                        Text(String(format: "Peak: %.0f%%", maxVal))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.purple)
                    }
                }

                RollingGraphView(
                    values: historyUsages,
                    minValue: 0.0,
                    maxValue: 100.0,
                    tintColor: .purple,
                    capacity: 60,
                    height: 56,
                    showGrid: true
                )
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // GPU Stats
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CURRENT")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(String(format: "%.0f%%", sample?.utilization ?? 0.0))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.purple)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text("WINDOW AVG")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    let avg = historyUsages.isEmpty ? 0.0 : (historyUsages.reduce(0.0, +) / Double(historyUsages.count))
                    Text(String(format: "%.1f%%", avg))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestGPU) { newSample in
            sample = newSample?.value
            history = coordinator.gpuHistory
        }
    }
}

// MARK: - =======================================================
// MARK: - 5. FAN CUSTOM POPOVERS
// MARK: - =======================================================

public struct FanPopoverView: View {
    public let coordinator: MetricsCoordinator
    public let overrideSample: FanSample?
    @State private var sample: FanSample?
    @State private var history: [Sample<FanSample>]

    public init(
        coordinator: MetricsCoordinator = .shared,
        sample: FanSample? = nil,
        history: [Sample<FanSample>]? = nil
    ) {
        self.coordinator = coordinator
        self.overrideSample = sample
        _sample = State(initialValue: sample ?? coordinator.latestFan?.value)
        _history = State(initialValue: history ?? coordinator.fanHistory)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(category: .fan, verdict: VerdictEvaluator.evaluateFan(sample))
            Divider()
            FanSummaryView(sample: sample, history: history)
            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestFan) { newSample in
            if overrideSample == nil {
                sample = newSample?.value
                history = coordinator.fanHistory
            }
        }
    }
}

public struct FanDualRPMPopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    @State private var sample: FanSample?
    @State private var history: [Sample<FanSample>]

    public init(coordinator: MetricsCoordinator = .shared, preferences: PreferencesStore = .shared) {
        self.coordinator = coordinator
        self.preferences = preferences
        _sample = State(initialValue: coordinator.latestFan?.value)
        _history = State(initialValue: coordinator.fanHistory)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .fan,
                title: "Dual Fan RPM",
                subtitle: "Left & Right Rotor Speed Meters",
                verdict: VerdictEvaluator.evaluateFan(sample)
            )
            Divider()

            // Side-by-Side Dual Fans Card
            let fans = sample?.fans ?? []
            if fans.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "fanblades.slash")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text("No Hardware Fans Detected (Fanless Mac)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                HStack(spacing: 10) {
                    ForEach(Array(fans.prefix(2)), id: \.name) { fan in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "fanblades")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.cyan)
                                Text(fan.name.uppercased())
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }

                            Text(fan.rpm > 0 ? "\(fan.rpm) RPM" : "0 RPM")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(fan.rpm > 0 ? .primary : .secondary)

                            if let minR = fan.minRPM, let maxR = fan.maxRPM {
                                let pct = Double(max(0, fan.rpm - minR)) / Double(max(1, maxR - minR))
                                GeometryReader { g in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.08))
                                        RoundedRectangle(cornerRadius: 2).fill(Color.cyan)
                                            .frame(width: g.size.width * CGFloat(min(1.0, max(0.0, pct))))
                                    }
                                }
                                .frame(height: 5)

                                Text("Range: \(minR) - \(maxR)")
                                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            // System Control Policy
            HStack {
                Text("Control Mode")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text("System Automatic (Safe)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.green)
            }
            .padding(.horizontal, 4)

            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestFan) { newSample in
            sample = newSample?.value
            history = coordinator.fanHistory
        }
    }
}

public struct FanTachometerPopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    @State private var sample: FanSample?
    @State private var history: [Sample<FanSample>]

    public init(coordinator: MetricsCoordinator = .shared, preferences: PreferencesStore = .shared) {
        self.coordinator = coordinator
        self.preferences = preferences
        _sample = State(initialValue: coordinator.latestFan?.value)
        _history = State(initialValue: coordinator.fanHistory)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .fan,
                title: "Fan Tachometers",
                subtitle: "Analog Rotor Velocity & Safety Margins",
                verdict: VerdictEvaluator.evaluateFan(sample)
            )
            Divider()

            let peakRPM = sample?.fans.map(\.rpm).max() ?? 0
            let maxRPM = sample?.fans.compactMap(\.maxRPM).max() ?? 6000
            let pct = min(1.0, max(0.0, Double(peakRPM) / Double(max(1, maxRPM))))

            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 10)
                        .frame(width: 90, height: 90)

                    Circle()
                        .trim(from: 0, to: pct)
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [.teal, .cyan, .blue, .purple]),
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 90, height: 90)

                    VStack(spacing: 0) {
                        Text("\(peakRPM)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                        Text("PEAK RPM")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 4)

                Text(peakRPM > 0 ? "Rotor spinning under thermal workload" : "Rotors stopped (Silent operation)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestFan) { newSample in
            sample = newSample?.value
            history = coordinator.fanHistory
        }
    }
}

public struct FanBladesPopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    @State private var sample: FanSample?
    @State private var history: [Sample<FanSample>]

    public init(coordinator: MetricsCoordinator = .shared, preferences: PreferencesStore = .shared) {
        self.coordinator = coordinator
        self.preferences = preferences
        _sample = State(initialValue: coordinator.latestFan?.value)
        _history = State(initialValue: coordinator.fanHistory)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .fan,
                title: "Fan Blades",
                subtitle: "Animated Rotor State & Cooling Efficiency",
                verdict: VerdictEvaluator.evaluateFan(sample)
            )
            Divider()

            let peakRPM = sample?.fans.map(\.rpm).max() ?? 0

            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.teal.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: "fanblades.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.teal)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(peakRPM > 0 ? "Active Forced Convection" : "Passive Dissipation")
                            .font(.system(size: 13, weight: .bold))
                        Text(peakRPM > 0 ? "\(sample?.fans.count ?? 0) blowers cooling system" : "Zero acoustic noise")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }

                Divider()

                HStack {
                    Text("Acoustic Profile")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text(peakRPM > 3000 ? "Audible Fan Noise" : (peakRPM > 0 ? "Whisper Quiet" : "Silent (0 dB)"))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(peakRPM > 3000 ? .orange : .green)
                }

                HStack {
                    Text("Air Intake")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text("Dual Side Vents")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestFan) { newSample in
            sample = newSample?.value
            history = coordinator.fanHistory
        }
    }
}

public struct FanBarsPopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    @State private var sample: FanSample?
    @State private var history: [Sample<FanSample>]

    public init(coordinator: MetricsCoordinator = .shared, preferences: PreferencesStore = .shared) {
        self.coordinator = coordinator
        self.preferences = preferences
        _sample = State(initialValue: coordinator.latestFan?.value)
        _history = State(initialValue: coordinator.fanHistory)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .fan,
                title: "Fan Speed Bars",
                subtitle: "Proportional Rotor Speeds",
                verdict: VerdictEvaluator.evaluateFan(sample)
            )
            Divider()

            let fans = sample?.fans ?? []
            if fans.isEmpty {
                Text("No fans installed.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(10)
            } else {
                VStack(spacing: 8) {
                    ForEach(fans, id: \.name) { fan in
                        let maxR = fan.maxRPM ?? 6000
                        let pct = Double(fan.rpm) / Double(max(1, maxR))
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(fan.name)
                                    .font(.system(size: 11, weight: .medium))
                                Spacer()
                                Text("\(fan.rpm) RPM")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                Text(String(format: "(%.0f%%)", pct * 100.0))
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08))
                                    RoundedRectangle(cornerRadius: 3).fill(Color.teal)
                                        .frame(width: g.size.width * CGFloat(min(1.0, max(0.0, pct))))
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestFan) { newSample in
            sample = newSample?.value
            history = coordinator.fanHistory
        }
    }
}

public struct FanHistoryPopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    @State private var sample: FanSample?
    @State private var history: [Sample<FanSample>]

    public init(coordinator: MetricsCoordinator = .shared, preferences: PreferencesStore = .shared) {
        self.coordinator = coordinator
        self.preferences = preferences
        _sample = State(initialValue: coordinator.latestFan?.value)
        _history = State(initialValue: coordinator.fanHistory)
    }

    private var historyRPMs: [Double] {
        history.map { hist in
            Double(hist.value.fans.map(\.rpm).max() ?? 0)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .fan,
                title: "Fan History",
                subtitle: "Rolling Rotor RPM Timeline",
                verdict: VerdictEvaluator.evaluateFan(sample)
            )
            Divider()

            // Large 60-sample Graph
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("MAX ROTOR RPM TIMELINE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    if let maxVal = historyRPMs.max() {
                        Text(String(format: "Peak: %.0f RPM", maxVal))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.teal)
                    }
                }

                let maxBound = max(5000.0, (historyRPMs.max() ?? 0.0) + 500.0)
                RollingGraphView(
                    values: historyRPMs,
                    minValue: 0.0,
                    maxValue: maxBound,
                    tintColor: .teal,
                    capacity: 60,
                    height: 56,
                    showGrid: true
                )
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Fan Stats
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CURRENT")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    let curRPM = sample?.fans.map(\.rpm).max() ?? 0
                    Text("\(curRPM) RPM")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.teal)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text("WINDOW AVG")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    let avg = historyRPMs.isEmpty ? 0.0 : (historyRPMs.reduce(0.0, +) / Double(historyRPMs.count))
                    Text(String(format: "%.0f RPM", avg))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestFan) { newSample in
            sample = newSample?.value
            history = coordinator.fanHistory
        }
    }
}

// MARK: - =======================================================
// MARK: - 6. NETWORK CUSTOM POPOVERS
// MARK: - =======================================================

public struct NetworkPopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    public let overrideSample: NetworkSample?
    @State private var sample: NetworkSample?
    @State private var history: [Sample<NetworkSample>]

    public init(
        coordinator: MetricsCoordinator = .shared,
        preferences: PreferencesStore = .shared,
        sample: NetworkSample? = nil,
        history: [Sample<NetworkSample>]? = nil
    ) {
        self.coordinator = coordinator
        self.preferences = preferences
        self.overrideSample = sample
        _sample = State(initialValue: sample ?? coordinator.latestNetwork?.value)
        _history = State(initialValue: history ?? coordinator.networkHistory)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .network,
                verdict: VerdictEvaluator.evaluateNetwork(
                    sample,
                    unit: preferences.networkUnit,
                    standard: preferences.byteUnitStandard
                )
            )
            Divider()
            NetworkSummaryView(
                sample: sample,
                history: history,
                networkUnit: preferences.networkUnit,
                byteStandard: preferences.byteUnitStandard
            )
            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestNetwork) { newSample in
            if overrideSample == nil {
                sample = newSample?.value
                history = coordinator.networkHistory
            }
        }
    }
}

public struct NetworkBarsPopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    @State private var sample: NetworkSample?
    @State private var history: [Sample<NetworkSample>]

    public init(coordinator: MetricsCoordinator = .shared, preferences: PreferencesStore = .shared) {
        self.coordinator = coordinator
        self.preferences = preferences
        _sample = State(initialValue: coordinator.latestNetwork?.value)
        _history = State(initialValue: coordinator.networkHistory)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .network,
                title: "Bandwidth Capacity",
                subtitle: "Download vs Upload Traffic Split",
                verdict: VerdictEvaluator.evaluateNetwork(sample, unit: preferences.networkUnit, standard: preferences.byteUnitStandard)
            )
            Divider()

            // Inbound & Outbound Hero Cards
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                        Text("DOWNLOAD")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Text(Units.formatNetworkRate(sample?.totalBytesInPerSec ?? 0, unit: preferences.networkUnit, standard: preferences.byteUnitStandard))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.green)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.blue)
                        Text("UPLOAD")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Text(Units.formatNetworkRate(sample?.totalBytesOutPerSec ?? 0, unit: preferences.networkUnit, standard: preferences.byteUnitStandard))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.blue)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Primary interface
            HStack {
                Text("Primary Interface")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text(sample?.primaryInterface ?? "Wi-Fi (en0)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)

            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestNetwork) { newSample in
            sample = newSample?.value
            history = coordinator.networkHistory
        }
    }
}

public struct NetworkDuplexHistoryPopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    @State private var sample: NetworkSample?
    @State private var history: [Sample<NetworkSample>]

    public init(coordinator: MetricsCoordinator = .shared, preferences: PreferencesStore = .shared) {
        self.coordinator = coordinator
        self.preferences = preferences
        _sample = State(initialValue: coordinator.latestNetwork?.value)
        _history = State(initialValue: coordinator.networkHistory)
    }

    private var inRates: [Double] { history.map { $0.value.totalBytesInPerSec } }
    private var outRates: [Double] { history.map { $0.value.totalBytesOutPerSec } }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .network,
                title: "Network History",
                subtitle: "Dual Up/Down Duplex Bandwidth Timeline",
                verdict: VerdictEvaluator.evaluateNetwork(sample, unit: preferences.networkUnit, standard: preferences.byteUnitStandard)
            )
            Divider()

            // Download Graph
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("DOWNLOAD TIMELINE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    if let maxIn = inRates.max() {
                        Text(Units.formatNetworkRate(maxIn, unit: preferences.networkUnit, standard: preferences.byteUnitStandard))
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                    }
                }
                RollingGraphView(values: inRates, minValue: 0, maxValue: max(1024, (inRates.max() ?? 0) * 1.1), tintColor: .green, capacity: 60, height: 36, showGrid: true)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Upload Graph
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("UPLOAD TIMELINE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    if let maxOut = outRates.max() {
                        Text(Units.formatNetworkRate(maxOut, unit: preferences.networkUnit, standard: preferences.byteUnitStandard))
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.blue)
                    }
                }
                RollingGraphView(values: outRates, minValue: 0, maxValue: max(1024, (outRates.max() ?? 0) * 1.1), tintColor: .blue, capacity: 60, height: 36, showGrid: true)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestNetwork) { newSample in
            sample = newSample?.value
            history = coordinator.networkHistory
        }
    }
}

public struct NetworkDiagnosticsPopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    @State private var sample: NetworkSample?
    @State private var history: [Sample<NetworkSample>]

    public init(coordinator: MetricsCoordinator = .shared, preferences: PreferencesStore = .shared) {
        self.coordinator = coordinator
        self.preferences = preferences
        _sample = State(initialValue: coordinator.latestNetwork?.value)
        _history = State(initialValue: coordinator.networkHistory)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .network,
                title: "Network Diagnostics",
                subtitle: "Interface Routing, Wi-Fi Quality & Local IP",
                verdict: VerdictEvaluator.evaluateNetwork(sample, unit: preferences.networkUnit, standard: preferences.byteUnitStandard)
            )
            Divider()

            VStack(spacing: 8) {
                diagRow(label: "Interface", val: sample?.primaryInterface ?? "en0")
                diagRow(label: "IPv4 Address", val: sample?.localIPv4 ?? "192.168.1.100")
                if let gw = sample?.gatewayIPv4 {
                    diagRow(label: "Gateway IPv4", val: gw)
                }
                diagRow(label: "Session Inbound", val: Units.formatBytes(sample?.totalBytesIn ?? 0, standard: preferences.byteUnitStandard))
                diagRow(label: "Session Outbound", val: Units.formatBytes(sample?.totalBytesOut ?? 0, standard: preferences.byteUnitStandard))
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestNetwork) { newSample in
            sample = newSample?.value
            history = coordinator.networkHistory
        }
    }

    private func diagRow(label: String, val: String) -> some View {
        HStack {
            Text(label).font(.system(size: 11, weight: .medium))
            Spacer()
            Text(val).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(.secondary)
        }
    }
}

// MARK: - =======================================================
// MARK: - 7. DISK CUSTOM POPOVERS
// MARK: - =======================================================

public struct DiskPopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    public let overrideSample: DiskSample?
    @State private var sample: DiskSample?
    @State private var history: [Sample<DiskSample>]

    public init(
        coordinator: MetricsCoordinator = .shared,
        preferences: PreferencesStore = .shared,
        sample: DiskSample? = nil,
        history: [Sample<DiskSample>]? = nil
    ) {
        self.coordinator = coordinator
        self.preferences = preferences
        self.overrideSample = sample
        _sample = State(initialValue: sample ?? coordinator.latestDisk?.value)
        _history = State(initialValue: history ?? coordinator.diskHistory)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .disk,
                verdict: VerdictEvaluator.evaluateDisk(sample, standard: preferences.byteUnitStandard)
            )
            Divider()
            DiskSummaryView(
                sample: sample,
                history: history,
                byteStandard: preferences.byteUnitStandard
            )
            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestDisk) { newSample in
            if overrideSample == nil {
                sample = newSample?.value
                history = coordinator.diskHistory
            }
        }
    }
}

public struct DiskStorageRingPopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    @State private var sample: DiskSample?
    @State private var history: [Sample<DiskSample>]

    public init(coordinator: MetricsCoordinator = .shared, preferences: PreferencesStore = .shared) {
        self.coordinator = coordinator
        self.preferences = preferences
        _sample = State(initialValue: coordinator.latestDisk?.value)
        _history = State(initialValue: coordinator.diskHistory)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .disk,
                title: "Storage Rings",
                subtitle: "Volume Storage Capacity & Allocation",
                verdict: VerdictEvaluator.evaluateDisk(sample, standard: preferences.byteUnitStandard)
            )
            Divider()

            let vol = sample?.volumes.first(where: { $0.mountPoint == "/" }) ?? sample?.volumes.first
            let usedB = vol?.used ?? 0
            let freeB = vol?.free ?? 0
            let totalB = vol?.total ?? max(1, usedB + freeB)
            let pct = Double(usedB) / Double(max(1, totalB))

            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 10)
                        .frame(width: 90, height: 90)

                    Circle()
                        .trim(from: 0, to: CGFloat(pct))
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [.cyan, .blue, .purple]),
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 90, height: 90)

                    VStack(spacing: 0) {
                        Text(String(format: "%.0f%%", pct * 100.0))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        Text("USED")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 4)

                Text(vol?.name.isEmpty == false ? vol!.name : "Macintosh HD")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("SPACE USED")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(Units.formatBytes(usedB, standard: preferences.byteUnitStandard))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text("AVAILABLE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(Units.formatBytes(freeB, standard: preferences.byteUnitStandard))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.green)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestDisk) { newSample in
            sample = newSample?.value
            history = coordinator.diskHistory
        }
    }
}

public struct DiskStorageTanksPopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    @State private var sample: DiskSample?
    @State private var history: [Sample<DiskSample>]

    public init(coordinator: MetricsCoordinator = .shared, preferences: PreferencesStore = .shared) {
        self.coordinator = coordinator
        self.preferences = preferences
        _sample = State(initialValue: coordinator.latestDisk?.value)
        _history = State(initialValue: coordinator.diskHistory)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .disk,
                title: "Volume Tanks",
                subtitle: "APFS Storage Container Distribution",
                verdict: VerdictEvaluator.evaluateDisk(sample, standard: preferences.byteUnitStandard)
            )
            Divider()

            let vols = sample?.volumes ?? []
            if vols.isEmpty {
                Text("No mounted volumes found.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(vols.prefix(3), id: \.mountPoint) { vol in
                        let used = vol.used
                        let total = max(1, vol.total)
                        let pct = Double(used) / Double(total)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(vol.name.isEmpty ? vol.mountPoint : vol.name)
                                    .font(.system(size: 11, weight: .semibold))
                                Spacer()
                                Text(Units.formatBytes(used, standard: preferences.byteUnitStandard))
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                Text("/ \(Units.formatBytes(total, standard: preferences.byteUnitStandard))")
                                    .font(.system(size: 9, weight: .regular))
                                    .foregroundColor(.secondary)
                            }

                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08))
                                    RoundedRectangle(cornerRadius: 3).fill(Color.blue)
                                        .frame(width: g.size.width * CGFloat(min(1.0, max(0.0, pct))))
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestDisk) { newSample in
            sample = newSample?.value
            history = coordinator.diskHistory
        }
    }
}

public struct DiskHistoryPopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    @State private var sample: DiskSample?
    @State private var history: [Sample<DiskSample>]

    public init(coordinator: MetricsCoordinator = .shared, preferences: PreferencesStore = .shared) {
        self.coordinator = coordinator
        self.preferences = preferences
        _sample = State(initialValue: coordinator.latestDisk?.value)
        _history = State(initialValue: coordinator.diskHistory)
    }

    private var readRates: [Double] { history.map { $0.value.io?.bytesReadPerSec ?? 0.0 } }
    private var writeRates: [Double] { history.map { $0.value.io?.bytesWrittenPerSec ?? 0.0 } }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .disk,
                title: "Disk I/O History",
                subtitle: "Rolling Read & Write Throughput Graph",
                verdict: VerdictEvaluator.evaluateDisk(sample, standard: preferences.byteUnitStandard)
            )
            Divider()

            // Read Timeline
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("READ THROUGHPUT TIMELINE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    if let maxR = readRates.max() {
                        Text(Units.formatDiskRate(maxR, standard: preferences.byteUnitStandard))
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan)
                    }
                }
                RollingGraphView(values: readRates, minValue: 0, maxValue: max(1024, (readRates.max() ?? 0) * 1.1), tintColor: .cyan, capacity: 60, height: 36, showGrid: true)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Write Timeline
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("WRITE THROUGHPUT TIMELINE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    if let maxW = writeRates.max() {
                        Text(Units.formatDiskRate(maxW, standard: preferences.byteUnitStandard))
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                }
                RollingGraphView(values: writeRates, minValue: 0, maxValue: max(1024, (writeRates.max() ?? 0) * 1.1), tintColor: .orange, capacity: 60, height: 36, showGrid: true)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestDisk) { newSample in
            sample = newSample?.value
            history = coordinator.diskHistory
        }
    }
}

public struct DiskActivityLEDsPopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    @State private var sample: DiskSample?
    @State private var history: [Sample<DiskSample>]

    public init(coordinator: MetricsCoordinator = .shared, preferences: PreferencesStore = .shared) {
        self.coordinator = coordinator
        self.preferences = preferences
        _sample = State(initialValue: coordinator.latestDisk?.value)
        _history = State(initialValue: coordinator.diskHistory)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .disk,
                title: "Disk Activity",
                subtitle: "Real-Time I/O Operations & IOPS",
                verdict: VerdictEvaluator.evaluateDisk(sample, standard: preferences.byteUnitStandard)
            )
            Divider()

            let readRate = sample?.io?.bytesReadPerSec ?? 0.0
            let writeRate = sample?.io?.bytesWrittenPerSec ?? 0.0
            let readActive = readRate > 0
            let writeActive = writeRate > 0

            // Activity Indicators Card
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(readActive ? Color.green : Color.secondary.opacity(0.3))
                        .frame(width: 12, height: 12)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("READ ACTIVE")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text(Units.formatDiskRate(readRate, standard: preferences.byteUnitStandard))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 8) {
                    Circle()
                        .fill(writeActive ? Color.orange : Color.secondary.opacity(0.3))
                        .frame(width: 12, height: 12)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("WRITE ACTIVE")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text(Units.formatDiskRate(writeRate, standard: preferences.byteUnitStandard))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // IOPS metrics
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("READ IOPS")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(String(format: "%.0f", sample?.io?.readOpsPerSec ?? 0))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text("WRITE IOPS")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(String(format: "%.0f", sample?.io?.writeOpsPerSec ?? 0))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestDisk) { newSample in
            sample = newSample?.value
            history = coordinator.diskHistory
        }
    }
}

// MARK: - =======================================================
// MARK: - 8. POWER CUSTOM POPOVERS
// MARK: - =======================================================

public struct PowerPopoverView: View {
    public let coordinator: MetricsCoordinator
    public let overrideSample: PowerSample?
    @State private var sample: PowerSample?
    @State private var history: [Sample<PowerSample>]

    public init(
        coordinator: MetricsCoordinator = .shared,
        sample: PowerSample? = nil,
        history: [Sample<PowerSample>]? = nil
    ) {
        self.coordinator = coordinator
        self.overrideSample = sample
        _sample = State(initialValue: sample ?? coordinator.latestPower?.value)
        _history = State(initialValue: history ?? coordinator.powerHistory)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .power,
                verdict: VerdictEvaluator.evaluatePower(sample)
            )
            Divider()
            PowerSummaryView(
                sample: sample,
                history: history
            )
            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestPower) { newSample in
            if overrideSample == nil {
                sample = newSample?.value
                history = coordinator.powerHistory
            }
        }
    }
}

public struct PowerWattagePopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    @State private var sample: PowerSample?
    @State private var history: [Sample<PowerSample>]

    public init(coordinator: MetricsCoordinator = .shared, preferences: PreferencesStore = .shared) {
        self.coordinator = coordinator
        self.preferences = preferences
        _sample = State(initialValue: coordinator.latestPower?.value)
        _history = State(initialValue: coordinator.powerHistory)
    }

    private var systemDraw: Double { sample?.powerDrawWatts ?? 0.0 }
    private var adapterWatts: Double? { sample?.adapterWatts }
    private var netBalance: Double? {
        guard let adapter = adapterWatts, adapter > 0 else { return nil }
        return adapter - systemDraw
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .power,
                title: "Power Consumption",
                subtitle: "Real-Time System Draw vs Adapter Supply",
                verdict: VerdictEvaluator.evaluatePower(sample)
            )
            Divider()

            // Side-by-side Hero: Draw vs Supply
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.orange)
                        Text("SYSTEM DRAW")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Text(String(format: "%.1f W", systemDraw))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.orange)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "powerplug.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                        Text("ADAPTER SUPPLY")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    if let a = adapterWatts, a > 0 {
                        Text(String(format: "%.0f W", a))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.green)
                    } else {
                        Text("On Battery")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Net Power Balance Card
            if let bal = netBalance {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("NET POWER BALANCE")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text(bal >= 0 ? String(format: "+%.1f W Charging Surplus", bal) : String(format: "%.1f W Power Deficit (Draining Battery)", bal))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(bal >= 0 ? .green : .red)
                    }
                    Spacer()
                    Image(systemName: bal >= 0 ? "bolt.badge.checkmark" : "bolt.trianglebadge.exclamationmark")
                        .font(.system(size: 16))
                        .foregroundColor(bal >= 0 ? .green : .red)
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Power Supply Specs
            VStack(spacing: 5) {
                if let name = sample?.adapterName {
                    HStack {
                        Text("Power Supply")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(name)
                            .font(.system(size: 10, weight: .bold))
                    }
                }
                if let v = sample?.voltageVolts {
                    HStack {
                        Text("Pack Voltage")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.2f V", v))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                }
                if let i = sample?.amperageMilliAmps {
                    HStack {
                        Text("Current Flow")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%+.0f mA", i))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(i >= 0 ? .green : .orange)
                    }
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestPower) { newSample in
            sample = newSample?.value
            history = coordinator.powerHistory
        }
    }
}

public struct PowerChargeRingPopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    @State private var sample: PowerSample?
    @State private var history: [Sample<PowerSample>]

    public init(coordinator: MetricsCoordinator = .shared, preferences: PreferencesStore = .shared) {
        self.coordinator = coordinator
        self.preferences = preferences
        _sample = State(initialValue: coordinator.latestPower?.value)
        _history = State(initialValue: coordinator.powerHistory)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .power,
                title: "Battery Charge Ring",
                subtitle: "State of Charge & Charge Level",
                verdict: VerdictEvaluator.evaluatePower(sample)
            )
            Divider()

            let charge = sample?.charge ?? 100.0
            let pct = min(1.0, max(0.0, charge / 100.0))
            let variant = sample?.variant ?? .acDesktop

            // Large Radial Charge Ring
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 10)
                        .frame(width: 96, height: 96)

                    Circle()
                        .trim(from: 0, to: CGFloat(pct))
                        .stroke(
                            ringGradient(for: variant),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 96, height: 96)

                    VStack(spacing: 1) {
                        Image(systemName: variant.systemImageName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(ringColor(for: variant))
                        Text(String(format: "%.0f%%", charge))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                    }
                }
                .padding(.top, 4)

                Text(variant.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(ringColor(for: variant))
            }
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Time Remaining & Quick Stats
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("TIME ESTIMATE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    if let t = sample?.timeRemaining, t > 0 {
                        let hours = Int(t) / 3600
                        let mins = (Int(t) % 3600) / 60
                        Text("\(hours)h \(mins)m")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    } else if sample?.state == .charging {
                        Text("Calculating...")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    } else {
                        Text("Connected")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.green)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text("BATTERY HEALTH")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(sample?.condition ?? "Normal")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.green)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestPower) { newSample in
            sample = newSample?.value
            history = coordinator.powerHistory
        }
    }

    private func ringGradient(for variant: PowerStateVariant) -> AngularGradient {
        switch variant {
        case .charging:
            return AngularGradient(colors: [.green, .mint, .cyan], center: .center)
        case .lowBattery:
            return AngularGradient(colors: [.red, .orange], center: .center)
        case .onHold:
            return AngularGradient(colors: [.orange, .yellow], center: .center)
        case .powerDeficit:
            return AngularGradient(colors: [.red, .purple], center: .center)
        default:
            return AngularGradient(colors: [.blue, .cyan], center: .center)
        }
    }

    private func ringColor(for variant: PowerStateVariant) -> Color {
        switch variant {
        case .charging: return .green
        case .lowBattery: return .red
        case .onHold: return .orange
        case .powerDeficit: return .red
        default: return .blue
        }
    }
}

public struct PowerBarPopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    @State private var sample: PowerSample?
    @State private var history: [Sample<PowerSample>]

    public init(coordinator: MetricsCoordinator = .shared, preferences: PreferencesStore = .shared) {
        self.coordinator = coordinator
        self.preferences = preferences
        _sample = State(initialValue: coordinator.latestPower?.value)
        _history = State(initialValue: coordinator.powerHistory)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .power,
                title: "Charge Level",
                subtitle: "Horizontal Capacity Bar & Charging Phases",
                verdict: VerdictEvaluator.evaluatePower(sample)
            )
            Divider()

            let charge = sample?.charge ?? 100.0
            let pct = min(1.0, max(0.0, charge / 100.0))

            // Horizontal Capacity Bar Card
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("BATTERY CAPACITY")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.0f%%", charge))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }

                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient(colors: [charge <= 20 ? .red : .green, .mint], startPoint: .leading, endPoint: .trailing))
                            .frame(width: g.size.width * CGFloat(pct))
                    }
                }
                .frame(height: 10)

                // Marker labels (0%, 20%, 80%, 100%)
                HStack {
                    Text("0%").font(.system(size: 8, design: .monospaced)).foregroundColor(.secondary)
                    Spacer()
                    Text("20% (Low)").font(.system(size: 8, design: .monospaced)).foregroundColor(.secondary)
                    Spacer()
                    Text("80% (Optimized)").font(.system(size: 8, design: .monospaced)).foregroundColor(.secondary)
                    Spacer()
                    Text("100%").font(.system(size: 8, design: .monospaced)).foregroundColor(.secondary)
                }
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Charge Phase Status Card
            let phaseInfo: (String, String, Color) = {
                if charge < 80.0 && sample?.state == .charging {
                    return ("Fast Charge Phase", "Charging at maximum current up to 80% capacity.", .green)
                } else if charge >= 80.0 && sample?.state == .charging {
                    return ("Trickle / Constant Voltage", "Current tapered down to preserve lithium-ion longevity.", .mint)
                } else if sample?.isOnHold == true {
                    return ("Optimized Battery Charging", "Charging on hold at 80% until customary usage window.", .orange)
                } else {
                    return ("Battery Discharging", "Operating normally on internal pack power.", .secondary)
                }
            }()

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("CHARGE PHASE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(phaseInfo.0)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(phaseInfo.2)
                }
                Text(phaseInfo.1)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestPower) { newSample in
            sample = newSample?.value
            history = coordinator.powerHistory
        }
    }
}

public struct PowerBudgetIllustrationPopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    @State private var sample: PowerSample?
    @State private var history: [Sample<PowerSample>]

    public init(coordinator: MetricsCoordinator = .shared, preferences: PreferencesStore = .shared) {
        self.coordinator = coordinator
        self.preferences = preferences
        _sample = State(initialValue: coordinator.latestPower?.value)
        _history = State(initialValue: coordinator.powerHistory)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .power,
                title: "Power Budget",
                subtitle: "Battery Health Condition & Design Capacity",
                verdict: VerdictEvaluator.evaluatePower(sample)
            )
            Divider()

            // Condition Hero Card
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 52, height: 52)
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.green)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("BATTERY CONDITION")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(sample?.condition ?? "Normal")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.green)
                    Text("Chemical cells operating within nominal parameters")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Capacity Retention Card
            let maxCap = sample?.currentMaxCapacity ?? 6000
            let designCap = max(1, sample?.designCapacity ?? 6000)
            let healthPct = min(100.0, max(0.0, (Double(maxCap) / Double(designCap)) * 100.0))

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("MAXIMUM CAPACITY RETENTION")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1f%% Health", healthPct))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.green)
                }

                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08))
                        RoundedRectangle(cornerRadius: 3).fill(Color.green)
                            .frame(width: g.size.width * CGFloat(min(1.0, healthPct / 100.0)))
                    }
                }
                .frame(height: 6)

                HStack {
                    Text("\(maxCap) mAh Available")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(designCap) mAh Factory Design")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Cycle Count Card
            let cycles = sample?.cycleCount ?? 0
            let designCycles = sample?.designCycleCount ?? 1000
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CYCLE COUNT")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text("\(cycles) / \(designCycles)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                Spacer()
                Text(String(format: "%.0f%% rated life used", (Double(cycles) / Double(max(1, designCycles))) * 100.0))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestPower) { newSample in
            sample = newSample?.value
            history = coordinator.powerHistory
        }
    }
}

public struct PowerHistoryPopoverView: View {
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore
    @State private var sample: PowerSample?
    @State private var history: [Sample<PowerSample>]

    public init(coordinator: MetricsCoordinator = .shared, preferences: PreferencesStore = .shared) {
        self.coordinator = coordinator
        self.preferences = preferences
        _sample = State(initialValue: coordinator.latestPower?.value)
        _history = State(initialValue: coordinator.powerHistory)
    }

    private var historyWattages: [Double] {
        history.compactMap { $0.value.powerDrawWatts }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeaderView(
                category: .power,
                title: "Wattage History",
                subtitle: "60-Sample Power Draw Timeline",
                verdict: VerdictEvaluator.evaluatePower(sample)
            )
            Divider()

            // Large 60-sample Graph
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("SYSTEM POWER DRAW TIMELINE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    if let maxW = historyWattages.max() {
                        Text(String(format: "Peak: %.1f W", maxW))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                }

                RollingGraphView(
                    values: historyWattages,
                    minValue: 0,
                    maxValue: max(30.0, (historyWattages.max() ?? 20.0) * 1.15),
                    tintColor: .orange,
                    capacity: 60,
                    height: 56,
                    showGrid: true
                )
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Avg and Idle Badges
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AVERAGE DRAW")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    let avg = historyWattages.isEmpty ? 0.0 : (historyWattages.reduce(0.0, +) / Double(historyWattages.count))
                    Text(String(format: "%.1f W", avg))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.orange)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text("MINIMUM IDLE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    let minW = historyWattages.min() ?? 0.0
                    Text(String(format: "%.1f W", minW))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.green)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Divider()
            CategoryPopoverFooter()
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if !coordinator.isRunning { coordinator.start() } }
        .onReceive(coordinator.$latestPower) { newSample in
            sample = newSample?.value
            history = coordinator.powerHistory
        }
    }
}

// MARK: - =======================================================
// MARK: - CONFIG POPOVER FACTORY (ADR 0007)
// MARK: - =======================================================

public enum ConfigPopoverFactory {
    @MainActor
    @ViewBuilder
    public static func makePopoverView(
        config: MenuBarItemConfig,
        coordinator: MetricsCoordinator = .shared,
        preferences: PreferencesStore = .shared
    ) -> some View {
        switch (config.category, config.style) {
        // MARK: Thermal Subsystem Custom Popovers
        case (.thermal, .cpuTemp):
            ThermalCPUPopoverView(coordinator: coordinator, preferences: preferences)
        case (.thermal, .gpuTemp):
            ThermalGPUPopoverView(coordinator: coordinator, preferences: preferences)
        case (.thermal, .memoryTemp):
            ThermalMemoryPopoverView(coordinator: coordinator, preferences: preferences)
        case (.thermal, .storageTemp):
            ThermalStoragePopoverView(coordinator: coordinator, preferences: preferences)
        case (.thermal, .batteryTemp):
            ThermalBatteryPopoverView(coordinator: coordinator, preferences: preferences)
        case (.thermal, .gauge):
            ThermalRingPopoverView(coordinator: coordinator, preferences: preferences)
        case (.thermal, .sparkline):
            ThermalHistoryPopoverView(coordinator: coordinator, preferences: preferences)
        case (.thermal, _):
            ThermalPopoverView(coordinator: coordinator, preferences: preferences)

        // MARK: CPU Custom Popovers
        case (.cpu, .gauge):
            CPUUserSystemPopoverView(coordinator: coordinator, preferences: preferences)
        case (.cpu, .bar):
            CPUClusterPopoverView(coordinator: coordinator, preferences: preferences)
        case (.cpu, .sparkline):
            CPUHistoryPopoverView(coordinator: coordinator, preferences: preferences)
        case (.cpu, _):
            CPUPopoverView(coordinator: coordinator, preferences: preferences)

        // MARK: Memory Custom Popovers
        case (.memory, .gauge):
            MemoryCompositionPopoverView(coordinator: coordinator, preferences: preferences)
        case (.memory, .bar):
            MemoryAllocationPopoverView(coordinator: coordinator, preferences: preferences)
        case (.memory, .symbol):
            MemoryPressurePopoverView(coordinator: coordinator, preferences: preferences)
        case (.memory, .sparkline):
            MemoryHistoryPopoverView(coordinator: coordinator, preferences: preferences)
        case (.memory, _):
            MemoryPopoverView(coordinator: coordinator, preferences: preferences)

        // MARK: GPU Custom Popovers
        case (.gpu, .gauge):
            GPULoadRingPopoverView(coordinator: coordinator, preferences: preferences)
        case (.gpu, .bar):
            GPUEnginePopoverView(coordinator: coordinator, preferences: preferences)
        case (.gpu, .symbol):
            GPUDiePopoverView(coordinator: coordinator, preferences: preferences)
        case (.gpu, .sparkline):
            GPUHistoryPopoverView(coordinator: coordinator, preferences: preferences)
        case (.gpu, _):
            GPUPopoverView(coordinator: coordinator, preferences: preferences)

        // MARK: Fan Custom Popovers
        case (.fan, .throughput):
            FanDualRPMPopoverView(coordinator: coordinator, preferences: preferences)
        case (.fan, .gauge):
            FanTachometerPopoverView(coordinator: coordinator, preferences: preferences)
        case (.fan, .symbol):
            FanBladesPopoverView(coordinator: coordinator, preferences: preferences)
        case (.fan, .bar):
            FanBarsPopoverView(coordinator: coordinator, preferences: preferences)
        case (.fan, .sparkline):
            FanHistoryPopoverView(coordinator: coordinator, preferences: preferences)
        case (.fan, _):
            FanPopoverView(coordinator: coordinator)

        // MARK: Network Custom Popovers
        case (.network, .bar):
            NetworkBarsPopoverView(coordinator: coordinator, preferences: preferences)
        case (.network, .sparkline):
            NetworkDuplexHistoryPopoverView(coordinator: coordinator, preferences: preferences)
        case (.network, .symbol):
            NetworkDiagnosticsPopoverView(coordinator: coordinator, preferences: preferences)
        case (.network, _):
            NetworkPopoverView(coordinator: coordinator, preferences: preferences)

        // MARK: Disk Custom Popovers
        case (.disk, .gauge):
            DiskStorageRingPopoverView(coordinator: coordinator, preferences: preferences)
        case (.disk, .bar):
            DiskStorageTanksPopoverView(coordinator: coordinator, preferences: preferences)
        case (.disk, .sparkline):
            DiskHistoryPopoverView(coordinator: coordinator, preferences: preferences)
        case (.disk, .symbol):
            DiskActivityLEDsPopoverView(coordinator: coordinator, preferences: preferences)
        case (.disk, _):
            DiskPopoverView(coordinator: coordinator, preferences: preferences)

        // MARK: Power Custom Popovers
        case (.power, .throughput):
            PowerWattagePopoverView(coordinator: coordinator, preferences: preferences)
        case (.power, .gauge):
            PowerChargeRingPopoverView(coordinator: coordinator, preferences: preferences)
        case (.power, .bar):
            PowerBarPopoverView(coordinator: coordinator, preferences: preferences)
        case (.power, .symbol):
            PowerBudgetIllustrationPopoverView(coordinator: coordinator, preferences: preferences)
        case (.power, .sparkline):
            PowerHistoryPopoverView(coordinator: coordinator, preferences: preferences)
        case (.power, _):
            PowerPopoverView(coordinator: coordinator)
        }
    }

    @MainActor
    public static func makeHostingController(
        config: MenuBarItemConfig,
        coordinator: MetricsCoordinator = .shared,
        preferences: PreferencesStore = .shared
    ) -> NSViewController {
        switch (config.category, config.style) {
        // MARK: Thermal Subsystem Custom Popovers
        case (.thermal, .cpuTemp):
            return NSHostingController(rootView: ThermalCPUPopoverView(coordinator: coordinator, preferences: preferences))
        case (.thermal, .gpuTemp):
            return NSHostingController(rootView: ThermalGPUPopoverView(coordinator: coordinator, preferences: preferences))
        case (.thermal, .memoryTemp):
            return NSHostingController(rootView: ThermalMemoryPopoverView(coordinator: coordinator, preferences: preferences))
        case (.thermal, .storageTemp):
            return NSHostingController(rootView: ThermalStoragePopoverView(coordinator: coordinator, preferences: preferences))
        case (.thermal, .batteryTemp):
            return NSHostingController(rootView: ThermalBatteryPopoverView(coordinator: coordinator, preferences: preferences))
        case (.thermal, .gauge):
            return NSHostingController(rootView: ThermalRingPopoverView(coordinator: coordinator, preferences: preferences))
        case (.thermal, .sparkline):
            return NSHostingController(rootView: ThermalHistoryPopoverView(coordinator: coordinator, preferences: preferences))
        case (.thermal, _):
            return NSHostingController(rootView: ThermalPopoverView(coordinator: coordinator, preferences: preferences))

        // MARK: CPU Custom Popovers
        case (.cpu, .gauge):
            return NSHostingController(rootView: CPUUserSystemPopoverView(coordinator: coordinator, preferences: preferences))
        case (.cpu, .bar):
            return NSHostingController(rootView: CPUClusterPopoverView(coordinator: coordinator, preferences: preferences))
        case (.cpu, .sparkline):
            return NSHostingController(rootView: CPUHistoryPopoverView(coordinator: coordinator, preferences: preferences))
        case (.cpu, _):
            return NSHostingController(rootView: CPUPopoverView(coordinator: coordinator, preferences: preferences))

        // MARK: Memory Custom Popovers
        case (.memory, .gauge):
            return NSHostingController(rootView: MemoryCompositionPopoverView(coordinator: coordinator, preferences: preferences))
        case (.memory, .bar):
            return NSHostingController(rootView: MemoryAllocationPopoverView(coordinator: coordinator, preferences: preferences))
        case (.memory, .symbol):
            return NSHostingController(rootView: MemoryPressurePopoverView(coordinator: coordinator, preferences: preferences))
        case (.memory, .sparkline):
            return NSHostingController(rootView: MemoryHistoryPopoverView(coordinator: coordinator, preferences: preferences))
        case (.memory, _):
            return NSHostingController(rootView: MemoryPopoverView(coordinator: coordinator, preferences: preferences))

        // MARK: GPU Custom Popovers
        case (.gpu, .gauge):
            return NSHostingController(rootView: GPULoadRingPopoverView(coordinator: coordinator, preferences: preferences))
        case (.gpu, .bar):
            return NSHostingController(rootView: GPUEnginePopoverView(coordinator: coordinator, preferences: preferences))
        case (.gpu, .symbol):
            return NSHostingController(rootView: GPUDiePopoverView(coordinator: coordinator, preferences: preferences))
        case (.gpu, .sparkline):
            return NSHostingController(rootView: GPUHistoryPopoverView(coordinator: coordinator, preferences: preferences))
        case (.gpu, _):
            return NSHostingController(rootView: GPUPopoverView(coordinator: coordinator, preferences: preferences))

        // MARK: Fan Custom Popovers
        case (.fan, .throughput):
            return NSHostingController(rootView: FanDualRPMPopoverView(coordinator: coordinator, preferences: preferences))
        case (.fan, .gauge):
            return NSHostingController(rootView: FanTachometerPopoverView(coordinator: coordinator, preferences: preferences))
        case (.fan, .symbol):
            return NSHostingController(rootView: FanBladesPopoverView(coordinator: coordinator, preferences: preferences))
        case (.fan, .bar):
            return NSHostingController(rootView: FanBarsPopoverView(coordinator: coordinator, preferences: preferences))
        case (.fan, .sparkline):
            return NSHostingController(rootView: FanHistoryPopoverView(coordinator: coordinator, preferences: preferences))
        case (.fan, _):
            return NSHostingController(rootView: FanPopoverView(coordinator: coordinator))

        // MARK: Network Custom Popovers
        case (.network, .bar):
            return NSHostingController(rootView: NetworkBarsPopoverView(coordinator: coordinator, preferences: preferences))
        case (.network, .sparkline):
            return NSHostingController(rootView: NetworkDuplexHistoryPopoverView(coordinator: coordinator, preferences: preferences))
        case (.network, .symbol):
            return NSHostingController(rootView: NetworkDiagnosticsPopoverView(coordinator: coordinator, preferences: preferences))
        case (.network, _):
            return NSHostingController(rootView: NetworkPopoverView(coordinator: coordinator, preferences: preferences))

        // MARK: Disk Custom Popovers
        case (.disk, .gauge):
            return NSHostingController(rootView: DiskStorageRingPopoverView(coordinator: coordinator, preferences: preferences))
        case (.disk, .bar):
            return NSHostingController(rootView: DiskStorageTanksPopoverView(coordinator: coordinator, preferences: preferences))
        case (.disk, .sparkline):
            return NSHostingController(rootView: DiskHistoryPopoverView(coordinator: coordinator, preferences: preferences))
        case (.disk, .symbol):
            return NSHostingController(rootView: DiskActivityLEDsPopoverView(coordinator: coordinator, preferences: preferences))
        case (.disk, _):
            return NSHostingController(rootView: DiskPopoverView(coordinator: coordinator, preferences: preferences))

        // MARK: Power Custom Popovers
        case (.power, .throughput):
            return NSHostingController(rootView: PowerWattagePopoverView(coordinator: coordinator, preferences: preferences))
        case (.power, .gauge):
            return NSHostingController(rootView: PowerChargeRingPopoverView(coordinator: coordinator, preferences: preferences))
        case (.power, .bar):
            return NSHostingController(rootView: PowerBarPopoverView(coordinator: coordinator, preferences: preferences))
        case (.power, .symbol):
            return NSHostingController(rootView: PowerBudgetIllustrationPopoverView(coordinator: coordinator, preferences: preferences))
        case (.power, .sparkline):
            return NSHostingController(rootView: PowerHistoryPopoverView(coordinator: coordinator, preferences: preferences))
        case (.power, _):
            return NSHostingController(rootView: PowerPopoverView(coordinator: coordinator))
        }
    }
}

// MARK: - =======================================================
// MARK: - Backward-Compatible CategoryDetailPopoverView Router
// MARK: - =======================================================

/// A backward-compatible popover view that routes to the dedicated popover for a specific `MetricCategory` (ADR 0007).
public struct CategoryDetailPopoverView: View {
    public let category: MetricCategory
    public let coordinator: MetricsCoordinator
    @ObservedObject public var preferences: PreferencesStore

    // Optional sample overrides for previews / testing
    public let overrideCPUSample: CPUSample?
    public let overrideMemorySample: MemorySample?
    public let overrideGPUSample: GPUSample?
    public let overrideNetworkSample: NetworkSample?
    public let overrideDiskSample: DiskSample?
    public let overridePowerSample: PowerSample?
    public let overrideThermalSample: ThermalSample?
    public let overrideFanSample: FanSample?

    public init(
        category: MetricCategory,
        coordinator: MetricsCoordinator = .shared,
        preferences: PreferencesStore = .shared,
        cpuSample: CPUSample? = nil,
        memorySample: MemorySample? = nil,
        gpuSample: GPUSample? = nil,
        networkSample: NetworkSample? = nil,
        diskSample: DiskSample? = nil,
        powerSample: PowerSample? = nil,
        thermalSample: ThermalSample? = nil,
        fanSample: FanSample? = nil
    ) {
        self.category = category
        self.coordinator = coordinator
        self.preferences = preferences
        self.overrideCPUSample = cpuSample
        self.overrideMemorySample = memorySample
        self.overrideGPUSample = gpuSample
        self.overrideNetworkSample = networkSample
        self.overrideDiskSample = diskSample
        self.overridePowerSample = powerSample
        self.overrideThermalSample = thermalSample
        self.overrideFanSample = fanSample
    }

    @ViewBuilder
    public var body: some View {
        switch category {
        case .cpu:
            CPUPopoverView(
                coordinator: coordinator,
                preferences: preferences,
                sample: overrideCPUSample
            )
        case .memory:
            MemoryPopoverView(
                coordinator: coordinator,
                preferences: preferences,
                sample: overrideMemorySample
            )
        case .gpu:
            GPUPopoverView(
                coordinator: coordinator,
                preferences: preferences,
                sample: overrideGPUSample
            )
        case .thermal:
            ThermalPopoverView(
                coordinator: coordinator,
                preferences: preferences,
                sample: overrideThermalSample
            )
        case .fan:
            FanPopoverView(
                coordinator: coordinator,
                sample: overrideFanSample
            )
        case .network:
            NetworkPopoverView(
                coordinator: coordinator,
                preferences: preferences,
                sample: overrideNetworkSample
            )
        case .disk:
            DiskPopoverView(
                coordinator: coordinator,
                preferences: preferences,
                sample: overrideDiskSample
            )
        case .power:
            PowerPopoverView(
                coordinator: coordinator,
                sample: overridePowerSample
            )
        }
    }
}
