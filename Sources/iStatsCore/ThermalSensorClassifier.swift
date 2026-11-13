import Foundation

/// Specific hardware subcomponents tracked within the Temperature category.
public enum MetricSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case peak
    case cpu
    case gpu
    case memory
    case ssd
    case battery

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .peak: return "Peak System"
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return "Memory"
        case .ssd: return "Storage"
        case .battery: return "Battery"
        }
    }

    public var shortLabel: String {
        switch self {
        case .peak: return "TMP"
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return "MEM"
        case .ssd: return "SSD"
        case .battery: return "BAT"
        }
    }

    public var symbolName: String {
        switch self {
        case .peak: return "thermometer.medium"
        case .cpu: return "cpu"
        case .gpu: return "square.3.layers.3d"
        case .memory: return "memorychip"
        case .ssd: return "internaldrive"
        case .battery: return "battery.100percent.bolt"
        }
    }
}

/// Pure utility classifying hardware sensors into standard `MetricSource` groups.
public enum ThermalSensorClassifier {
    /// Classifies a raw sensor reading by its hardware channel name.
    public static func classify(_ sensor: SensorReading) -> MetricSource? {
        let name = sensor.name
        if name.contains("Peak") {
            return .peak
        }
        if name.contains("CPU")
            || name.contains("Efficiency Core")
            || name.contains("Performance Core")
            || name.contains("Package") {
            return .cpu
        }
        if name.contains("GPU") {
            return .gpu
        }
        if name.contains("Memory") || name.contains("RAM") {
            return .memory
        }
        if name.contains("Storage") || name.contains("NAND") || name.contains("SSD") {
            return .ssd
        }
        if name.contains("Battery") {
            return .battery
        }
        return nil
    }

    /// Returns all sensor readings in a thermal sample matching the given source.
    public static func sensors(in sample: ThermalSample, for source: MetricSource) -> [SensorReading] {
        switch source {
        case .peak:
            return sample.sensors
        case .cpu, .gpu, .memory, .ssd, .battery:
            return sample.sensors.filter { classify($0) == source }
        }
    }

    /// Extracts the peak temperature in Celsius for a given hardware source.
    public static func peakCelsius(in sample: ThermalSample, for source: MetricSource) -> Double? {
        let matching = sensors(in: sample, for: source)
        guard !matching.isEmpty else {
            return nil
        }
        return matching.map(\.celsius).max()
    }
}
