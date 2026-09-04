import SwiftUI
import iStatsCore

/// Authentic iStat Menus style GPU metrics view featuring:
/// 1. Hardware Specs Header (Chip model, Core count pill, Unified Memory badge)
/// 2. Live Silicon Die + Interactive Core Matrix Cluster (glowing active cores)
/// 3. Dual Engine Pipeline Gauges (Renderer 3D/Compute vs Tiler TBDR)
/// 4. Graphics Memory (VRAM) Allocation Bar (In Use vs Allocated vs Shared Pool)
/// 5. 60-sample utilization history sparkline
/// 6. Collapsible Diagnostics (Connected Displays, Thermals, Power, Driver Stability).
public struct GPUSummaryView: View {
    public let sample: GPUSample?
    public let history: [Sample<GPUSample>]
    public let temperatureUnit: Units.TemperatureUnit
    public let byteStandard: Units.ByteUnitStandard

    @State private var isDetailsExpanded: Bool = false

    public init(
        sample: GPUSample? = nil,
        history: [Sample<GPUSample>] = [],
        temperatureUnit: Units.TemperatureUnit = .celsius,
        byteStandard: Units.ByteUnitStandard = .iec
    ) {
        self.sample = sample
        self.history = history
        self.temperatureUnit = temperatureUnit
        self.byteStandard = byteStandard
    }

    private var verdict: MetricVerdict {
        VerdictEvaluator.evaluateGPU(sample)
    }

    private var historyPercentages: [Double] {
        history.compactMap { $0.value.utilization }
    }

    private let purpleAccent = Color.purple
    private let indigoAccent = Color.indigo

    public var body: some View {
        VStack(spacing: 8) {
            // MARK: - 1. Top Card: Hardware Identification & Engines
            VStack(alignment: .leading, spacing: 8) {
                // Header: Device Name & Core Count Pill
                HStack(alignment: .center) {
                    HStack(spacing: 5) {
                        Image(systemName: "cpu")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(purpleAccent)

                        Text(sample?.deviceName ?? "Graphics Processor")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    // Core count badge (e.g. 16-Core GPU)
                    if let cores = sample?.coreCount {
                        Text("\(cores)-Core GPU")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundColor(purpleAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(purpleAccent.opacity(0.12))
                            .clipShape(Capsule())
                    } else if sample?.isUnifiedMemory == true {
                        Text("Unified Memory")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }

                // Hero Row: Die Illustration + Core Load + Quick Pills
                HStack(alignment: .center, spacing: 12) {
                    GPUDieIllustrationView(
                        sample: sample,
                        temperatureUnit: temperatureUnit,
                        byteStandard: byteStandard,
                        size: 58,
                        showPills: false
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        if let sample = sample {
                            if let util = sample.utilization {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(String(format: "%.0f%%", util))
                                        .font(.system(size: 24, weight: .bold, design: .rounded))
                                        .foregroundColor(.primary)

                                    Text("Core Load")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text("Graphics Active")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(purpleAccent)
                            }

                            // Quick metrics: Temp & Watts
                            HStack(spacing: 5) {
                                if let temp = sample.tempCelsius {
                                    statTag(icon: "thermometer.medium", text: Units.formatTemperature(temp, unit: temperatureUnit, fractionDigits: 0))
                                }
                                if let watts = sample.powerWatts {
                                    statTag(icon: "bolt.fill", text: String(format: "%.1f W", watts))
                                } else if sample.isUnifiedMemory == true {
                                    statTag(icon: "memorychip", text: "Unified")
                                }
                            }
                        } else {
                            Text("Sampling graphics telemetry...")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer(minLength: 0)
                }

                // Silicon Core Matrix Cluster (if core count is known)
                if let cores = sample?.coreCount, cores > 0 {
                    coreMatrixCluster(coreCount: cores, utilization: sample?.utilization ?? 0.0)
                }

                // Dual Engine Pipeline Breakdown (Renderer vs Tiler)
                if let sample = sample, (sample.rendererUtilization != nil || sample.tilerUtilization != nil) {
                    VStack(spacing: 4) {
                        if let render = sample.rendererUtilization {
                            pipelineProgressBar(
                                label: "3D Renderer / Compute",
                                value: render,
                                color: purpleAccent
                            )
                        }
                        if let tiler = sample.tilerUtilization {
                            pipelineProgressBar(
                                label: "TBDR Tiler Geometry",
                                value: tiler,
                                color: indigoAccent
                            )
                        }
                    }
                    .padding(.top, 2)
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

            // MARK: - 2. Middle Card: Graphics Memory (VRAM) Breakdown
            if let sample = sample, (sample.memoryUsed != nil || sample.allocatedMemory != nil) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "memorychip")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(purpleAccent)
                            Text("Graphics Memory")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.primary)
                        }

                        Spacer()

                        if let used = sample.memoryUsed {
                            Text("\(Units.formatBytes(used, standard: byteStandard)) In Use")
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                    }

                    // Multi-Segment VRAM Allocation Bar
                    vramAllocationBar(sample: sample)

                    // 3-Column Memory Legend
                    HStack {
                        if let used = sample.memoryUsed {
                            vramLegendItem(label: "In Use", value: Units.formatBytes(used, standard: byteStandard, fractionDigits: 1), dotColor: purpleAccent)
                        }
                        Spacer()
                        if let alloc = sample.allocatedMemory {
                            vramLegendItem(label: "Allocated", value: Units.formatBytes(alloc, standard: byteStandard, fractionDigits: 1), dotColor: indigoAccent.opacity(0.7))
                        }
                        Spacer()
                        if let maxPool = sample.recommendedMaxMemory {
                            vramLegendItem(label: "Max Pool", value: Units.formatBytes(maxPool, standard: byteStandard, fractionDigits: 1), dotColor: Color.secondary.opacity(0.4))
                        }
                    }
                    .padding(.top, 2)
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

            // MARK: - 3. 60-Sample History Sparkline
            if !historyPercentages.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    RollingGraphView(
                        values: historyPercentages,
                        minValue: 0.0,
                        maxValue: 100.0,
                        tintColor: purpleAccent,
                        capacity: 60,
                        height: 40,
                        showGrid: true
                    )

                    HStack {
                        Text("last 2 min")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)

                        Spacer()

                        if let maxHist = historyPercentages.max() {
                            Text(String(format: "peak %.0f%%", maxHist))
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 2)
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

            // MARK: - 4. Collapsible Hardware & Diagnostics
            if let sample = sample {
                CollapsibleSection(
                    title: "Hardware & Displays",
                    count: sample.displayCount,
                    isExpanded: $isDetailsExpanded
                ) {
                    diagnosticsContent(sample: sample)
                }
                .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Silicon Core Matrix Cluster

    private func coreMatrixCluster(coreCount: Int, utilization: Double) -> some View {
        let activeCount = Int(round((utilization / 100.0) * Double(coreCount)))
        let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: min(coreCount, 8))

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("GPU Cores")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(coreCount) Cores Active")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(purpleAccent)
            }

            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(0..<coreCount, id: \.self) { index in
                    let isActive = index < activeCount || (activeCount == 0 && utilization > 0 && index == 0)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            isActive
                                ? AnyShapeStyle(LinearGradient(colors: [purpleAccent, indigoAccent], startPoint: .top, endPoint: .bottom))
                                : AnyShapeStyle(Color.secondary.opacity(0.12))
                        )
                        .frame(height: 7)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .strokeBorder(isActive ? purpleAccent.opacity(0.6) : Color.primary.opacity(0.05), lineWidth: 0.5)
                        )
                        .shadow(color: isActive ? purpleAccent.opacity(0.4) : Color.clear, radius: 2)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Pipeline Progress Bar

    private func pipelineProgressBar(label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                Text(String(format: "%.0f%%", value))
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
            }

            GeometryReader { geo in
                let w = geo.size.width
                let progressWidth = max(0.0, min(w, w * CGFloat(value / 100.0)))

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.12))

                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: progressWidth)
                }
            }
            .frame(height: 4)
        }
    }

    // MARK: - VRAM Allocation Bar

    private func vramAllocationBar(sample: GPUSample) -> some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let maxWorkingSet = Double(sample.recommendedMaxMemory ?? (sample.allocatedMemory ?? 1))
            let allocBytes = Double(sample.allocatedMemory ?? sample.memoryUsed ?? 0)
            let usedBytes = Double(sample.memoryUsed ?? 0)

            let allocFraction = maxWorkingSet > 0 ? min(allocBytes / maxWorkingSet, 1.0) : 0.0
            let usedFraction = maxWorkingSet > 0 ? min(usedBytes / maxWorkingSet, 1.0) : 0.0

            let allocWidth = totalWidth * CGFloat(allocFraction)
            let usedWidth = totalWidth * CGFloat(usedFraction)

            ZStack(alignment: .leading) {
                // Background Track (Max Pool)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.12))

                // Allocated Track
                RoundedRectangle(cornerRadius: 3)
                    .fill(indigoAccent.opacity(0.4))
                    .frame(width: max(allocWidth, 2))

                // In Use Track
                RoundedRectangle(cornerRadius: 3)
                    .fill(purpleAccent)
                    .frame(width: max(usedWidth, 2))
            }
        }
        .frame(height: 6)
    }

    private func vramLegendItem(label: String, value: String, dotColor: Color) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(dotColor)
                .frame(width: 5, height: 5)
            VStack(alignment: .leading, spacing: 0.5) {
                Text(label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
            }
        }
    }

    // MARK: - Stat Tag

    private func statTag(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundColor(purpleAccent)
            Text(text)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(purpleAccent.opacity(0.10))
        )
    }

    // MARK: - Diagnostics Content

    @ViewBuilder
    private func diagnosticsContent(sample: GPUSample) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Connected Displays Section
            if let displays = sample.displayDescriptions, !displays.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "display.2")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(purpleAccent)
                        Text("Connected Displays (\(displays.count))")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.primary)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(displays, id: \.self) { desc in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 4, height: 4)
                                Text(desc)
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.05)))
            }

            // 2-Column Telemetry Tiles
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 5) {
                if let temp = sample.tempCelsius {
                    tile(label: "GPU Temperature", value: Units.formatTemperature(temp, unit: temperatureUnit, fractionDigits: 1), icon: "thermometer.medium")
                }
                if let watts = sample.powerWatts {
                    tile(label: "Instant Power", value: String(format: "%.1f W", watts), icon: "bolt.fill")
                } else if sample.isUnifiedMemory == true {
                    tile(label: "Architecture", value: "Apple Unified", icon: "memorychip")
                }
                if let rec = sample.recoveryCount {
                    tile(label: "Driver Health", value: rec == 0 ? "Normal (0 Err)" : "\(rec) Recoveries", icon: "checkmark.shield.fill")
                }
                if let cores = sample.coreCount {
                    tile(label: "Total Cores", value: "\(cores) Active", icon: "square.grid.2x2.fill")
                }
            }
        }
        .padding(.top, 4)
    }

    private func tile(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 8.5))
                .foregroundColor(purpleAccent)
            VStack(alignment: .leading, spacing: 0.5) {
                Text(label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
            }
            Spacer()
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.05)))
    }
}

