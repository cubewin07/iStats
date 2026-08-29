import SwiftUI
import iStatsCore

/// Live 4-zone Mac heat map silhouette illustration (CPU, GPU, RAM, SSD/Enclosure).
/// Maps temperatures to subsystem medians with a ~100 °C scale to prevent single hot sensor alarms.
public struct ThermalHeatMapIllustrationView: View {
    public let sample: ThermalSample?
    public let temperatureUnit: Units.TemperatureUnit
    public let size: CGSize
    public let showLabels: Bool

    public init(
        sample: ThermalSample?,
        temperatureUnit: Units.TemperatureUnit = .celsius,
        size: CGSize = CGSize(width: 144, height: 82),
        showLabels: Bool = true
    ) {
        self.sample = sample
        self.temperatureUnit = temperatureUnit
        self.size = size
        self.showLabels = showLabels
    }

    public var body: some View {
        ZStack {
            // Mac Unibody Silhouette Container
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .controlBackgroundColor).opacity(0.85),
                            Color(nsColor: .windowBackgroundColor).opacity(0.95)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.15), radius: 2.5, x: 0, y: 1)

            // 4 Heat Zones (2x2 Grid)
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    zoneTile(title: "CPU", temp: cpuMedianTemp)
                    zoneTile(title: "GPU", temp: gpuMedianTemp)
                }
                HStack(spacing: 4) {
                    zoneTile(title: "RAM", temp: ramMedianTemp)
                    zoneTile(title: "SSD", temp: ssdMedianTemp)
                }
            }
            .padding(5)
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: - Zone Calculation (Medians)

    private var cpuMedianTemp: Double {
        calculateMedian(for: ["CPU", "Package", "SoC", "Core", "Cluster A", "Cluster B"]) ?? 50.0
    }

    private var gpuMedianTemp: Double {
        calculateMedian(for: ["GPU"]) ?? (cpuMedianTemp * 0.95)
    }

    private var ramMedianTemp: Double {
        calculateMedian(for: ["Memory", "RAM", "Module"]) ?? (cpuMedianTemp * 0.9)
    }

    private var ssdMedianTemp: Double {
        calculateMedian(for: ["Flash", "NAND", "SSD", "Storage", "Battery", "Palm"]) ?? 42.0
    }

    private func calculateMedian(for keywords: [String]) -> Double? {
        guard let sensors = sample?.sensors, !sensors.isEmpty else { return nil }
        let matches = sensors.filter { sensor in
            keywords.contains { kw in sensor.name.localizedCaseInsensitiveContains(kw) }
        }
        guard !matches.isEmpty else { return nil }
        let temps = matches.map(\.celsius).sorted()
        let mid = temps.count / 2
        return temps.count % 2 == 0 ? (temps[mid - 1] + temps[mid]) / 2.0 : temps[mid]
    }

    // MARK: - Zone Tile

    private func zoneTile(title: String, temp: Double) -> some View {
        let color = zoneColor(for: temp)

        return ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(
                    LinearGradient(
                        colors: [
                            color.opacity(0.22),
                            color.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(color.opacity(0.45), lineWidth: 0.75)
                )

            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: size.width > 100 ? 10 : 8.5, weight: .bold, design: .rounded))
                    .foregroundColor(color)

                if showLabels {
                    Text(Units.formatTemperature(temp, unit: temperatureUnit, fractionDigits: 0))
                        .font(.system(size: size.width > 100 ? 11 : 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func zoneColor(for celsius: Double) -> Color {
        if celsius >= 95.0 {
            return .red
        } else if celsius >= 80.0 {
            return .orange
        } else if celsius >= 65.0 {
            return .yellow
        } else {
            return .green
        }
    }
}
