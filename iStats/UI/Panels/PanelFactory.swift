import SwiftUI
import AppKit
import iStatsCore

/// Factory for instantiating Instrument Panels (ADR 0009 / Task 8.6).
@MainActor
public enum PanelFactory {

    /// Instantiates the panel view for a given menu bar item configuration.
    @ViewBuilder
    public static func makePanelView(
        config: MenuBarItemConfig,
        coordinator: MetricsCoordinator = .shared,
        preferences: PreferencesStore = .shared
    ) -> some View {
        let popConfig = config.resolvedPopoverConfig
        let openingTab = (popConfig.rememberLastTab ? preferences.lastSelectedTab(for: config.category) : nil) ?? popConfig.openingTab
        let focusSource = config.source ?? popConfig.focusSource

        makeCategoryPanelView(
            category: config.category,
            initialTab: openingTab,
            rememberLastTab: popConfig.rememberLastTab,
            focusSource: focusSource,
            coordinator: coordinator,
            preferences: preferences
        )
    }

    /// Instantiates the panel view for a specific metric category.
    @ViewBuilder
    public static func makeCategoryPanelView(
        category: MetricCategory,
        initialTab: PopoverTab = .overview,
        rememberLastTab: Bool = true,
        focusSource: MetricSource? = nil,
        coordinator: MetricsCoordinator = .shared,
        preferences: PreferencesStore = .shared
    ) -> some View {
        switch category {
        case .cpu:
            CPUPanel(
                initialTab: initialTab,
                rememberLastTab: rememberLastTab,
                focusSource: focusSource,
                coordinator: coordinator,
                preferences: preferences
            )
        case .memory:
            MemoryPanel(
                initialTab: initialTab,
                rememberLastTab: rememberLastTab,
                focusSource: focusSource,
                coordinator: coordinator,
                preferences: preferences
            )
        case .gpu:
            GPUPanel(
                initialTab: initialTab,
                rememberLastTab: rememberLastTab,
                focusSource: focusSource,
                coordinator: coordinator,
                preferences: preferences
            )
        case .thermal:
            TemperaturePanel(
                initialTab: initialTab,
                rememberLastTab: rememberLastTab,
                focusSource: focusSource,
                coordinator: coordinator,
                preferences: preferences
            )
        case .fan:
            FanPanel(
                initialTab: initialTab,
                rememberLastTab: rememberLastTab,
                focusSource: focusSource,
                coordinator: coordinator,
                preferences: preferences
            )
        case .network:
            NetworkPanel(
                initialTab: initialTab,
                rememberLastTab: rememberLastTab,
                focusSource: focusSource,
                coordinator: coordinator,
                preferences: preferences
            )
        case .disk:
            DiskPanel(
                initialTab: initialTab,
                rememberLastTab: rememberLastTab,
                focusSource: focusSource,
                coordinator: coordinator,
                preferences: preferences
            )
        case .power:
            PowerPanel(
                initialTab: initialTab,
                rememberLastTab: rememberLastTab,
                focusSource: focusSource,
                coordinator: coordinator,
                preferences: preferences
            )
        }
    }
}

/// The fallback panel view shown when no widgets are currently active in the menu bar.
public struct NoWidgetsActiveView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: Instrument.Space.l) {
            Image(systemName: "menubar.rectangle")
                .font(.system(size: 28))
                .foregroundColor(.secondary)

            VStack(spacing: Instrument.Space.xs) {
                Text("No Widgets Active")
                    .font(Instrument.Typography.title)
                Text("Enable metrics to display them in your menu bar.")
                    .font(Instrument.Typography.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Open Preferences...") {
                PreferencesWindowController.shared.showPreferences()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(Instrument.Space.xxl)
        .frame(width: Instrument.Size.panelWidth)
    }
}

#if DEBUG

/// Load profile for the synthetic 1 Hz gallery stream (Task 8.5.9).
public enum InstrumentGalleryLoadMode: String, CaseIterable, Identifiable, Sendable {
    case steady = "Steady"
    case spike10x = "10× Spike"

    public var id: String { rawValue }
}

/// Synthetic 1 Hz timestamped telemetry generator driving `InstrumentGalleryPreview`
/// without touching OS sampling APIs or shared `UserDefaults`.
@MainActor
public final class InstrumentGalleryTelemetryDriver: ObservableObject {
    public let defaultsSuiteName: String
    public let preferences: PreferencesStore
    public let coordinator: MetricsCoordinator

    @Published public var loadMode: InstrumentGalleryLoadMode = .steady
    @Published public var lateJitterEnabled: Bool = false
    @Published public var isStreaming: Bool = true
    @Published public private(set) var tickCount: Int = 0
    @Published public private(set) var lastSampleDate: Date
    @Published public private(set) var lastSleepGapSeconds: TimeInterval = 0

    private var loopTask: Task<Void, Never>?
    private var syntheticClock: Date

    public init(referenceDate: Date = Date(), seedSampleCount: Int = 75) {
        let suite = "com.istats.instrument-gallery.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suite)!
        ud.removePersistentDomain(forName: suite)
        self.defaultsSuiteName = suite
        let prefs = PreferencesStore(userDefaults: ud)
        prefs.refreshInterval = 1.0
        self.preferences = prefs
        self.coordinator = MetricsCoordinator(
            preferencesStore: prefs,
            lowPowerModeProvider: { false }
        )
        self.syntheticClock = referenceDate
        self.lastSampleDate = referenceDate

        if seedSampleCount > 0 {
            seedHistory(count: seedSampleCount, endingAt: referenceDate)
        }
    }

    deinit {
        loopTask?.cancel()
        UserDefaults(suiteName: defaultsSuiteName)?.removePersistentDomain(forName: defaultsSuiteName)
    }

    /// Starts the 1 Hz synthetic telemetry loop if not already running.
    public func start() {
        isStreaming = true
        guard loopTask == nil else { return }
        loopTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let self, self.isStreaming else { continue }
                self.stepTick()
            }
        }
    }

    /// Stops the 1 Hz synthetic telemetry loop.
    public func stop() {
        isStreaming = false
        loopTask?.cancel()
        loopTask = nil
    }

    /// Seeds `count` 1 Hz samples across all 8 metric categories ending at `endingAt`.
    public func seedHistory(count: Int, endingAt endDate: Date = Date()) {
        guard count > 0 else { return }
        var batch: [MetricReading] = []
        batch.reserveCapacity(count * 8)

        let startDate = endDate.addingTimeInterval(-Double(count - 1))
        for i in 0..<count {
            let ts = startDate.addingTimeInterval(Double(i))
            batch.append(contentsOf: makeReadings(at: ts, step: i, isSpike: false))
        }
        coordinator.handleReadings(batch)
        coordinator.updateProcessesForTesting(makeProcesses(step: count - 1, isSpike: false))
        syntheticClock = endDate
        lastSampleDate = endDate
        tickCount = count
    }

    /// Advances the synthetic stream by 1 second, optionally injecting +60 ms late jitter
    /// and/or 10× spike telemetry.
    public func stepTick() {
        syntheticClock = syntheticClock.addingTimeInterval(1.0)
        // +60 ms late sample jitter tests A1 monotonic edge follower (zero backward snap).
        let jitterOffset: TimeInterval = (lateJitterEnabled && tickCount.isMultiple(of: 2)) ? 0.060 : 0.0
        let sampleDate = syntheticClock.addingTimeInterval(jitterOffset)
        let isSpike = (loadMode == .spike10x)

        coordinator.handleReadings(makeReadings(at: sampleDate, step: tickCount, isSpike: isSpike))
        coordinator.updateProcessesForTesting(makeProcesses(step: tickCount, isSpike: isSpike))
        lastSampleDate = sampleDate
        tickCount += 1
    }

    /// Simulates a macOS wake-from-sleep gap (`15 s` default) to verify clean `ChartTimeline` edge snapping.
    public func injectSleepGap(seconds: TimeInterval = 15.0) {
        syntheticClock = syntheticClock.addingTimeInterval(seconds)
        lastSleepGapSeconds = seconds
        let isSpike = (loadMode == .spike10x)
        coordinator.handleReadings(makeReadings(at: syntheticClock, step: tickCount, isSpike: isSpike))
        coordinator.updateProcessesForTesting(makeProcesses(step: tickCount, isSpike: isSpike))
        lastSampleDate = syntheticClock
        tickCount += 1
    }

    /// Synchronizes coordinator pause state for `.frozen` motion inspection.
    public func setFrozen(_ frozen: Bool) {
        if coordinator.isSamplingPaused != frozen {
            coordinator.setSamplingPaused(frozen)
        }
    }

    private func makeReadings(at timestamp: Date, step: Int, isSpike: Bool) -> [MetricReading] {
        let phase = Double(step) * 0.28
        let wave = 0.5 + 0.5 * sin(phase)
        let spikeFactor = isSpike ? 10.0 : 1.0

        // 1. CPU (4 E-cores + 6 P-cores)
        let cpuUser = min(82.0, (14.0 + 10.0 * wave) * (isSpike ? 3.2 : 1.0))
        let cpuSys = min(16.0, (4.0 + 3.0 * cos(phase * 0.7)) * (isSpike ? 2.1 : 1.0))
        let cpuTotal = min(100.0, cpuUser + cpuSys)
        let perCore = (0..<10).map { core -> Double in
            let isE = core < 4
            let base = isE ? cpuTotal * 0.55 : cpuTotal * 1.15
            let offset = Double((core * 7 + step) % 11) - 5.0
            return min(100.0, max(2.0, base + offset))
        }
        let cpuSample = CPUSample(
            totalUsage: cpuTotal,
            perCore: perCore,
            user: cpuUser,
            system: cpuSys,
            idle: max(0.0, 100.0 - cpuTotal),
            loadAverage: LoadAverage(
                oneMinute: isSpike ? 11.4 : 2.15 + 0.35 * wave,
                fiveMinute: isSpike ? 6.2 : 1.92,
                fifteenMinute: 1.68
            ),
            frequencyHz: isSpike ? 3_520_000_000 : 2_640_000_000,
            efficiencyCoreCount: 4,
            performanceCoreCount: 6
        )

        // 2. Memory (16 GiB unified)
        let gib: UInt64 = 1_073_741_824
        let totalMem: UInt64 = 16 * gib
        let appExtra: Double = isSpike ? Double(4 * gib) : (Double(gib) * wave * 0.6)
        let appMem: UInt64 = UInt64(Double(6 * gib) + appExtra)
        let wiredMem: UInt64 = UInt64(2.4 * Double(gib))
        let compressedGiB: Double = isSpike ? 2.6 : 1.1
        let compressedMem: UInt64 = UInt64(compressedGiB * Double(gib))
        let cachedMem: UInt64 = UInt64(2.1 * Double(gib))
        let usedMem: UInt64 = min(totalMem - gib, appMem + wiredMem + compressedMem)
        let freeMem: UInt64 = totalMem > usedMem ? (totalMem - usedMem) : 0
        let swapUsedBytes: UInt64 = isSpike ? 1_450_000_000 : 256_000_000
        let swapTotalBytes: UInt64 = 2_048_000_000
        let activeMem: UInt64 = appMem / 2
        let inactiveMem: UInt64 = appMem - activeMem
        let memSample = MemorySample(
            total: totalMem,
            used: usedMem,
            free: freeMem,
            wired: wiredMem,
            compressed: compressedMem,
            cached: cachedMem,
            swapUsed: swapUsedBytes,
            pressure: isSpike ? .warning : .normal,
            appMemory: appMem,
            active: activeMem,
            inactive: inactiveMem,
            swapTotal: swapTotalBytes,
            swapFree: swapTotalBytes - swapUsedBytes
        )

        // 3. GPU
        let gpuUtil = min(98.0, (12.0 + 10.0 * wave) * (isSpike ? 4.5 : 1.0))
        let gpuSample = GPUSample(
            utilization: gpuUtil,
            memoryUsed: UInt64(isSpike ? 3_800_000_000 : 1_100_000_000),
            tempCelsius: isSpike ? 78.0 : 48.0 + 3.0 * wave,
            powerWatts: isSpike ? 26.5 : 4.2 + 1.5 * wave,
            coreCount: 16,
            deviceName: "Apple M3 Pro",
            allocatedMemory: UInt64(isSpike ? 3_800_000_000 : 1_100_000_000),
            recommendedMaxMemory: 18 * gib,
            rendererUtilization: min(100.0, gpuUtil * 0.92),
            tilerUtilization: min(100.0, gpuUtil * 0.68),
            isUnifiedMemory: true,
            displayCount: 1,
            displayDescriptions: ["Built-in Liquid Retina XDR"],
            recoveryCount: 0,
            supportsRaytracing: true,
            metalFeatureSet: "Metal 3"
        )

        // 4. Thermal
        let thermalBump = isSpike ? 26.0 : 0.0
        let thermalSample = ThermalSample(
            sensors: [
                SensorReading(name: "CPU Performance Core 1", celsius: 52.0 + 4.0 * wave + thermalBump),
                SensorReading(name: "GPU Cluster 1", celsius: 48.0 + 3.0 * wave + thermalBump * 0.8),
                SensorReading(name: "Memory Proximity", celsius: 41.0 + 2.0 * wave + thermalBump * 0.4),
                SensorReading(name: "Storage NAND", celsius: 36.0 + 1.0 * wave),
                SensorReading(name: "Battery Sensor 1", celsius: 31.0 + 0.5 * wave)
            ],
            pressure: isSpike ? .serious : .nominal
        )

        // 5. Fan
        let fanRPM = Int(round((1450.0 + 200.0 * wave) * (isSpike ? 3.2 : 1.0)))
        let fanSample = FanSample(
            fans: [
                FanReading(name: "Left Fan", rpm: min(5800, fanRPM), minRPM: 1200, maxRPM: 5800),
                FanReading(name: "Right Fan", rpm: min(6000, fanRPM + 80), minRPM: 1200, maxRPM: 6000)
            ]
        )

        // 6. Network (steady ~1.2 MB/s down, 280 KB/s up; 10× spike tests ChartScale spring & 3s hysteresis)
        let netDown = (1_100_000.0 + 350_000.0 * wave) * spikeFactor
        let netUp = (240_000.0 + 90_000.0 * cos(phase * 0.9)) * spikeFactor
        let netSample = NetworkSample(
            interfaces: [
                InterfaceThroughput(
                    interfaceName: "en0",
                    bytesInPerSec: max(0.0, netDown),
                    bytesOutPerSec: max(0.0, netUp),
                    totalBytesIn: UInt64(420_000_000 + step * 1_200_000),
                    totalBytesOut: UInt64(85_000_000 + step * 250_000),
                    ipv4Address: "192.168.1.42",
                    type: .wifi
                )
            ],
            primaryInterface: "en0",
            primaryType: .wifi,
            localIPv4: "192.168.1.42",
            gatewayIPv4: "192.168.1.1",
            primaryDNS: "1.1.1.1",
            wifiDetails: WiFiLinkTelemetry(
                ssid: "InstrumentLab-5G",
                rssi: -52,
                noise: -92,
                txRate: 866.0,
                channel: 36,
                band: "5 GHz"
            )
        )

        // 7. Disk (steady ~14 MB/s read, 4 MB/s write; 10× spike -> 140 MB/s read)
        let diskRead = (14_000_000.0 + 4_500_000.0 * wave) * spikeFactor
        let diskWrite = (3_800_000.0 + 1_200_000.0 * cos(phase)) * spikeFactor
        let diskSample = DiskSample(
            volumes: [
                VolumeCapacity(
                    name: "Macintosh HD",
                    mountPoint: "/",
                    total: 1_000_000_000_000,
                    used: 480_000_000_000,
                    free: 520_000_000_000
                )
            ],
            io: DiskIO(
                bytesReadPerSec: max(0.0, diskRead),
                bytesWrittenPerSec: max(0.0, diskWrite),
                readOpsPerSec: (180.0 + 40.0 * wave) * spikeFactor,
                writeOpsPerSec: (65.0 + 20.0 * wave) * spikeFactor
            )
        )

        // 8. Power (watts-only scalar chart; steady ~11 W, 10× spike -> ~48 W capped)
        let watts = min(68.0, (10.5 + 2.5 * wave) * (isSpike ? 4.2 : 1.0))
        let powerSample = PowerSample(
            hasBattery: true,
            charge: 84.0,
            state: .charging,
            timeRemaining: 2100,
            cycleCount: 94,
            condition: "Normal",
            designCapacity: 5100,
            currentMaxCapacity: 4960,
            powerDrawWatts: watts,
            adapterWatts: 96.0,
            voltageVolts: 12.2,
            amperageMilliAmps: isSpike ? 3900.0 : 1450.0,
            designCycleCount: 1000,
            adapterName: "Apple 96W USB-C"
        )

        return [
            .cpu(Sample(value: cpuSample, timestamp: timestamp)),
            .memory(Sample(value: memSample, timestamp: timestamp)),
            .gpu(Sample(value: gpuSample, timestamp: timestamp)),
            .thermal(Sample(value: thermalSample, timestamp: timestamp)),
            .fan(Sample(value: fanSample, timestamp: timestamp)),
            .network(Sample(value: netSample, timestamp: timestamp)),
            .disk(Sample(value: diskSample, timestamp: timestamp)),
            .power(Sample(value: powerSample, timestamp: timestamp))
        ]
    }

    private func makeProcesses(step: Int, isSpike: Bool) -> ProcessSample {
        let boost = isSpike ? 3.0 : 1.0
        let xcodeCPU = (28.0 + Double(step % 9)) * boost
        let swiftCPU = (14.0 + Double((step + 3) % 7)) * boost
        let windowCPU = 8.4 + Double(step % 3)

        let topCPU = [
            ProcessInfoItem(pid: 401, name: "Xcode", bundleID: "com.apple.dt.Xcode", cpuPercent: xcodeCPU, memoryBytes: 2_800_000_000),
            ProcessInfoItem(pid: 402, name: "swift-frontend", bundleID: nil, cpuPercent: swiftCPU, memoryBytes: 1_150_000_000),
            ProcessInfoItem(pid: 403, name: "WindowServer", bundleID: nil, cpuPercent: windowCPU, memoryBytes: 640_000_000)
        ].sorted { $0.cpuPercent > $1.cpuPercent }

        let topMem = topCPU.sorted { $0.memoryBytes > $1.memoryBytes }
        return ProcessSample(topCPU: topCPU, topMemory: topMem, skippedCount: 0)
    }
}

/// Interactive `#if DEBUG` Instrument Gallery Preview (Task 8.5.9) displaying all 8 Instrument
/// panels side-by-side under synthetic 1 Hz telemetry with live toggles for 10× scale spikes,
/// +60 ms late sample jitter, 15 s wake-from-sleep gaps, Light/Dark appearance, and `MotionPolicy`.
public struct InstrumentGalleryPreview: View {
    @StateObject private var driver: InstrumentGalleryTelemetryDriver
    @State private var appearanceScheme: ColorScheme = .dark
    @State private var selectedMotionPolicy: MotionPolicy = .full
    @State private var selectedTab: PopoverTab = .overview

    public init(driver: InstrumentGalleryTelemetryDriver = InstrumentGalleryTelemetryDriver()) {
        self._driver = StateObject(wrappedValue: driver)
    }

    public var body: some View {
        VStack(spacing: 0) {
            controlsBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Instrument.Space.xl) {
                    motionProbeStrip
                    panelGrid
                }
                .padding(Instrument.Space.xl)
            }
        }
        .background(Instrument.Surface.panel)
        .environment(\.colorScheme, appearanceScheme)
        .motionPolicy(selectedMotionPolicy)
        .onAppear {
            driver.start()
        }
        .onDisappear {
            driver.stop()
        }
    }

    private var controlsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Instrument.Space.l) {
                Picker("Load", selection: $driver.loadMode) {
                    ForEach(InstrumentGalleryLoadMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 170)

                Toggle("+60 ms Jitter", isOn: $driver.lateJitterEnabled)
                    .toggleStyle(.checkbox)

                Button("15 s Sleep Gap") {
                    driver.injectSleepGap(seconds: 15.0)
                }
                .controlSize(.small)

                Divider()
                    .frame(height: 18)

                Picker("Appearance", selection: $appearanceScheme) {
                    Text("Light").tag(ColorScheme.light)
                    Text("Dark").tag(ColorScheme.dark)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)

                Picker("Motion", selection: $selectedMotionPolicy) {
                    Text("Full").tag(MotionPolicy.full)
                    Text("Reduced").tag(MotionPolicy.reduced)
                    Text("Frozen").tag(MotionPolicy.frozen)
                }
                .pickerStyle(.segmented)
                .frame(width: 195)
                .onChange(of: selectedMotionPolicy) { newPolicy in
                    driver.setFrozen(newPolicy == .frozen)
                }

                Picker("Tab", selection: $selectedTab) {
                    Text("Now").tag(PopoverTab.overview)
                    Text("Details").tag(PopoverTab.detail)
                    Text("History").tag(PopoverTab.history)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                Divider()
                    .frame(height: 18)

                Button(driver.isStreaming ? "Pause 1 Hz" : "Resume 1 Hz") {
                    if driver.isStreaming {
                        driver.stop()
                    } else {
                        driver.start()
                    }
                }
                .controlSize(.small)

                Text("Ticks: \(driver.tickCount)")
                    .font(Instrument.Typography.micro)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Instrument.Space.xl)
            .padding(.vertical, Instrument.Space.m)
        }
        .background(Instrument.Surface.module)
    }

    private var motionProbeStrip: some View {
        let netPoints = driver.coordinator.timedDualScalarHistory(
            primary: .networkInBytesPerSec,
            secondary: .networkOutBytesPerSec,
            duration: 60.0,
            referenceDate: driver.lastSampleDate
        )
        let cpuPoints = driver.coordinator.timedDualScalarHistory(
            primary: .cpuUser,
            secondary: .cpuSystem,
            duration: 60.0,
            referenceDate: driver.lastSampleDate
        )
        let latestNet = driver.coordinator.latestNetwork?.value.interfaces.first?.bytesInPerSec ?? 0
        let latestRPM = driver.coordinator.latestFan?.value.fans.first?.rpm ?? 1500

        return HStack(spacing: Instrument.Space.l) {
            VStack(alignment: .leading, spacing: Instrument.Space.xs) {
                Text("Motion Lab (\(selectedMotionPolicy.rawValue))")
                    .font(Instrument.Typography.sectionTitle)
                    .foregroundStyle(.secondary)
                HStack(spacing: Instrument.Space.l) {
                    LiveNumber(
                        value: latestNet / 1_048_576.0,
                        format: { String(format: "%.2f", $0) },
                        font: Instrument.Typography.displayCompact,
                        unit: "MiB/s"
                    )
                    TurbineView(
                        rpm: latestRPM,
                        minRPM: 1200,
                        maxRPM: 5800,
                        size: 28,
                        isPaused: selectedMotionPolicy == .frozen
                    )
                }
            }
            .frame(width: 210, alignment: .leading)

            LiveChart(
                category: .cpu,
                mode: .stacked(
                    points: cpuPoints,
                    primaryColor: CategoryPalette.tint(for: .cpu),
                    secondaryColor: CategoryPalette.Series.cpuSystem,
                    fixedMax: 100.0
                ),
                height: 56
            )
            .frame(maxWidth: .infinity)

            LiveChart(
                category: .network,
                mode: .mirrored(
                    points: netPoints,
                    topColor: CategoryPalette.tint(for: .network),
                    bottomColor: CategoryPalette.Series.networkUpload
                ),
                height: 56
            )
            .frame(maxWidth: .infinity)
        }
        .padding(Instrument.Space.l)
        .background(
            RoundedRectangle(cornerRadius: Instrument.Radius.module, style: .continuous)
                .fill(Instrument.Surface.module)
        )
    }

    private var panelGrid: some View {
        let columns = [
            GridItem(.adaptive(minimum: Instrument.Size.panelWidth, maximum: Instrument.Size.panelWidth), spacing: Instrument.Space.xl, alignment: .top)
        ]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: Instrument.Space.xl) {
            ForEach(MetricCategory.allCases, id: \.self) { category in
                PanelFactory.makeCategoryPanelView(
                    category: category,
                    initialTab: selectedTab,
                    rememberLastTab: false,
                    coordinator: driver.coordinator,
                    preferences: driver.preferences
                )
                .id("\(category.rawValue)-\(selectedTab.rawValue)")
                .frame(width: Instrument.Size.panelWidth)
                .background(
                    RoundedRectangle(cornerRadius: Instrument.Radius.panel, style: .continuous)
                        .fill(Instrument.Surface.panel)
                        .shadow(color: Color.black.opacity(appearanceScheme == .dark ? 0.35 : 0.12), radius: 10, x: 0, y: 4)
                )
                .clipShape(RoundedRectangle(cornerRadius: Instrument.Radius.panel, style: .continuous))
            }
        }
    }
}

struct InstrumentGalleryPreview_Previews: PreviewProvider {
    static var previews: some View {
        InstrumentGalleryPreview()
            .frame(width: 1480, height: 980)
            .previewDisplayName("Instrument Gallery — All 8 Panels")
    }
}
#endif
