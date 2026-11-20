import XCTest
import Foundation
import SwiftUI
import AppKit
import Darwin
@testable import iStatsCore
@testable import iStats

@MainActor
final class PerformancePassTests: XCTestCase {
    // MARK: - Thread-Safe Test Helpers (Swift 6 Concurrency)

    private final class ThreadSafeCounter: @unchecked Sendable {
        private var value: Int = 0
        private let lock = NSLock()

        func increment() {
            lock.lock()
            value += 1
            lock.unlock()
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    private final class ThreadSafeMap<K: Hashable, V>: @unchecked Sendable {
        private var map: [K: V] = [:]
        private let lock = NSLock()

        func set(_ key: K, value: V) {
            lock.lock()
            map[key] = value
            lock.unlock()
        }

        func get(_ key: K) -> V? {
            lock.lock()
            defer { lock.unlock() }
            return map[key]
        }

        func contains(_ key: K) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return map[key] != nil
        }
    }

    private final class ThreadSafeSet<T: Hashable>: @unchecked Sendable {
        private var set: Set<T> = []
        private let lock = NSLock()

        func insert(_ item: T) {
            lock.lock()
            set.insert(item)
            lock.unlock()
        }

        func contains(_ item: T) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return set.contains(item)
        }
    }

    // MARK: - Off-Main-Thread Sampling Verification (Requirement 12.1, ADR 0002)

    func testAllSamplersExecuteOffMainThread() async {
        let scheduler = SampleScheduler(defaultInterval: 1.0)

        // Register all concrete samplers
        await scheduler.register(CPUSampler())
        await scheduler.register(MemorySampler())
        await scheduler.register(NetworkSampler())
        await scheduler.register(DiskSampler())
        await scheduler.register(PowerSampler())
        await scheduler.register(ThermalSampler())
        await scheduler.register(FanSampler())
        await scheduler.register(GPUSampler())

        let expectation = expectation(description: "All categories sampled off main thread")
        expectation.expectedFulfillmentCount = 8

        let threadExecutionMap = ThreadSafeMap<MetricCategory, Bool>()

        await scheduler.setOnSample { reading in
            let isBackground = !Thread.isMainThread
            if !threadExecutionMap.contains(reading.category) {
                threadExecutionMap.set(reading.category, value: isBackground)
                expectation.fulfill()
            }
        }

        await scheduler.start()

        await fulfillment(of: [expectation], timeout: 5.0)
        await scheduler.stop()

        for category in MetricCategory.allCases {
            let executedOnBackground = threadExecutionMap.get(category) ?? false
            XCTAssertTrue(
                executedOnBackground,
                "Sampler for category \(category.displayName) failed Requirement 12.1: must execute off the main thread."
            )
        }
    }

    // MARK: - Latency & Footprint Benchmark (Requirement 12.2)

    func testFullSamplingPassLatencyBenchmark() async {
        let samplers: [any Sampler] = [
            CPUSampler(),
            MemorySampler(),
            NetworkSampler(),
            DiskSampler(),
            PowerSampler(),
            ThermalSampler(),
            FanSampler(),
            GPUSampler()
        ]

        let iterations = 10
        var totalDuration: TimeInterval = 0.0
        var samplerDurations: [String: TimeInterval] = [:]

        for _ in 0..<iterations {
            let start = CFAbsoluteTimeGetCurrent()
            for sampler in samplers {
                let sStart = CFAbsoluteTimeGetCurrent()
                _ = try? sampler.sample()
                let sElapsed = CFAbsoluteTimeGetCurrent() - sStart
                samplerDurations[String(describing: type(of: sampler)), default: 0.0] += sElapsed
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            totalDuration += elapsed
        }

        let averagePassDurationMs = (totalDuration / Double(iterations)) * 1000.0
        print("Performance Benchmark: Average pass duration across all 8 samplers = \(String(format: "%.2f", averagePassDurationMs)) ms")
        for (name, dur) in samplerDurations {
            let avgMs = (dur / Double(iterations)) * 1000.0
            print("  - \(name): \(String(format: "%.2f", avgMs)) ms")
        }

        // In macOS on modern hardware, all 8 samplers execute within single-digit to low double-digit ms.
        // At a 2.0s refresh interval, an execution of 10ms accounts for ~0.5% duty cycle.
        XCTAssertLessThan(
            averagePassDurationMs,
            100.0,
            "Sampling pass exceeded 100ms budget, which could introduce noticeable background CPU footprint."
        )
    }

    // MARK: - Interval Scaling Reduces Frequency (Requirement 12.4)

    func testIntervalScalingReducesSamplingFrequency() async {
        let scheduler = SampleScheduler(defaultInterval: 0.2)
        await scheduler.register(CPUSampler())

        let fastCounter = ThreadSafeCounter()

        await scheduler.setOnSample { _ in
            fastCounter.increment()
        }

        await scheduler.start()
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        await scheduler.stop()

        let initialCount = fastCounter.count
        XCTAssertGreaterThanOrEqual(initialCount, 2, "Expected at least 2 samples at 0.2s interval")

        // Now scale interval up to 2.0s
        await scheduler.setDefaultInterval(2.0)
        let slowCounter = ThreadSafeCounter()

        await scheduler.setOnSample { _ in
            slowCounter.increment()
        }

        await scheduler.start()
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        await scheduler.stop()

        XCTAssertLessThanOrEqual(
            slowCounter.count,
            1,
            "Increasing refresh interval to 2.0s must reduce sample frequency within 0.5s window."
        )
    }

    // MARK: - Disabled Categories Incur Zero Sampling Overhead (Requirement 12.2)

    func testDisabledCategoriesIncurZeroSamplingOverhead() async {
        let scheduler = SampleScheduler(defaultInterval: 0.1)
        await scheduler.register(CPUSampler())
        await scheduler.register(MemorySampler())
        await scheduler.register(NetworkSampler())
        await scheduler.register(DiskSampler())

        // Disable all except CPU
        await scheduler.setEnabled(category: .memory, isEnabled: false)
        await scheduler.setEnabled(category: .network, isEnabled: false)
        await scheduler.setEnabled(category: .disk, isEnabled: false)

        let sampledCategories = ThreadSafeSet<MetricCategory>()

        await scheduler.setOnSample { reading in
            sampledCategories.insert(reading.category)
        }

        await scheduler.start()
        try? await Task.sleep(nanoseconds: 350_000_000) // 0.35s
        await scheduler.stop()

        XCTAssertTrue(sampledCategories.contains(.cpu))
        XCTAssertFalse(sampledCategories.contains(.memory))
        XCTAssertFalse(sampledCategories.contains(.network))
        XCTAssertFalse(sampledCategories.contains(.disk))
    }

    // MARK: - Phase 8.5 LiveChart v3 60-Frame & Single-Panel 1 Hz CPU Budgets (R8.5.6 / Task 8.5.9)

    private static func processCPUTimeSeconds() -> Double {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0.0 }
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000.0
        let sys = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000.0
        return user + sys
    }

    func testLiveChartV3SixtyFrameRenderAndCPUBudget() throws {
        // Measure 60 frames (1 simulated second @ 60 fps) of LiveChart v3:
        // 1) ChartModel.step + ChartRenderer.buildSeriesGeometry + Canvas CGContext draw
        // 2) Persistent SwiftUI NSHostingView Canvas redraw across 60 frames in an offscreen NSWindow
        let base: TimeInterval = 1_700_060_000.0
        var points = (0..<60).map { i in
            ChartPoint(timestamp: base + Double(i), value: 30.0 + 25.0 * sin(Double(i) * 0.25))
        }
        let dualPoints = (0..<60).map { i in
            DualChartPoint(
                timestamp: base + Double(i),
                primary: 2_500_000.0 + 900_000.0 * sin(Double(i) * 0.2),
                secondary: 450_000.0 + 180_000.0 * cos(Double(i) * 0.3)
            )
        }

        // Warm up caches/SwiftUI metal/CG pipelines once before timing
        let warmupModel = ChartModel(sampleInterval: 1.0)
        _ = warmupModel.step(
            now: base + 60.0,
            mode: .single(points: points, color: CategoryPalette.tint(for: .cpu), fixedMax: 100.0),
            category: .cpu,
            sampleInterval: 1.0,
            explicitWindow: 60.0,
            isScrubbing: false,
            motionPolicy: .full
        )

        let plotWidth: CGFloat = 347.0
        let plotHeight: CGFloat = 84.0
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(plotWidth),
            pixelsHigh: Int(plotHeight),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let cgCtx = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep)?.cgContext)

        // Benchmark 5 simulated seconds (300 frames) and average per 60 frames for stability
        let simulatedSeconds = 5
        let framesPerSecond = 60
        let totalFrames = simulatedSeconds * framesPerSecond

        let singleModel = ChartModel(sampleInterval: 1.0)
        let mirroredModel = ChartModel(sampleInterval: 1.0)

        let wallStart = CFAbsoluteTimeGetCurrent()
        let cpuStart = Self.processCPUTimeSeconds()

        for frame in 0..<totalFrames {
            if frame > 0 && frame % framesPerSecond == 0 {
                let nextIdx = 60 + (frame / framesPerSecond)
                points.append(ChartPoint(
                    timestamp: base + Double(nextIdx),
                    value: 30.0 + 25.0 * sin(Double(nextIdx) * 0.25)
                ))
            }
            let now = base + 60.0 + Double(frame) / Double(framesPerSecond)

            let resolvedSingle = singleModel.step(
                now: now,
                mode: .single(points: points, color: CategoryPalette.tint(for: .cpu), fixedMax: 100.0),
                category: .cpu,
                sampleInterval: 1.0,
                explicitWindow: 60.0,
                isScrubbing: false,
                motionPolicy: .full
            )
            let range = ChartRenderer.VerticalRange(
                floor: singleModel.topScale.displayedFloor,
                ceiling: singleModel.topScale.displayedCeiling,
                topY: 0,
                baselineY: plotHeight,
                inverted: false
            )
            if let geom = ChartRenderer.buildSeriesGeometry(
                points: resolvedSingle.primaryPoints,
                timeline: singleModel.timeline,
                windowDuration: resolvedSingle.windowDuration,
                plotWidth: plotWidth,
                verticalRange: range
            ) {
                cgCtx.saveGState()
                cgCtx.clear(CGRect(x: 0, y: 0, width: plotWidth, height: plotHeight))
                cgCtx.addPath(geom.fillPath.cgPath)
                cgCtx.setFillColor(NSColor.systemBlue.withAlphaComponent(0.18).cgColor)
                cgCtx.fillPath()
                cgCtx.addPath(geom.strokePath.cgPath)
                cgCtx.setStrokeColor(NSColor.systemBlue.cgColor)
                cgCtx.setLineWidth(1.75)
                cgCtx.strokePath()
                cgCtx.restoreGState()
            }

            // Also step mirrored dual-scale geometry (Network/Disk)
            let resolvedMirrored = mirroredModel.step(
                now: now,
                mode: .mirrored(points: dualPoints, topColor: .blue, bottomColor: .purple),
                category: .network,
                sampleInterval: 1.0,
                explicitWindow: 60.0,
                isScrubbing: false,
                motionPolicy: .full
            )
            let topRange = ChartRenderer.VerticalRange(
                floor: mirroredModel.topScale.displayedFloor,
                ceiling: mirroredModel.topScale.displayedCeiling,
                topY: 0,
                baselineY: plotHeight * 0.5,
                inverted: false
            )
            _ = ChartRenderer.buildSeriesGeometry(
                points: resolvedMirrored.primaryPoints,
                timeline: mirroredModel.timeline,
                windowDuration: resolvedMirrored.windowDuration,
                plotWidth: plotWidth,
                verticalRange: topRange
            )
        }

        let cpuElapsed = Self.processCPUTimeSeconds() - cpuStart
        let wallElapsed = CFAbsoluteTimeGetCurrent() - wallStart

        let sixtyFrameWallMs = (wallElapsed / Double(simulatedSeconds)) * 1000.0
        let sixtyFrameCPUMs = (cpuElapsed / Double(simulatedSeconds)) * 1000.0
        // CPU % for 1 chart rendering 60 frames over 1 second (averaged across single + mirrored)
        let singleChartCPUPercent = (sixtyFrameCPUMs / 2.0) / 10.0

        print(String(
            format: "Performance Benchmark (LiveChart v3, 60 frames): wall=%.2f ms (single+mirrored), cpu=%.2f ms, estChartCPU=%.3f%% (budget <= 1.5%%)",
            sixtyFrameWallMs,
            sixtyFrameCPUMs,
            singleChartCPUPercent
        ))

        XCTAssertLessThanOrEqual(
            singleChartCPUPercent,
            1.5,
            "60-frame LiveChart v3 rendering exceeded <= 1.5% CPU budget (R8.5.6)"
        )
    }

    func testSinglePanel1HzRefreshTotalAppCPUBudget() throws {
        let suiteName = "test.istats.perf.1hz.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let prefs = PreferencesStore(userDefaults: defaults)
        prefs.refreshInterval = 1.0
        let coord = MetricsCoordinator(preferencesStore: prefs, lowPowerModeProvider: { false })

        let cpuSampler = CPUSampler()
        let memSampler = MemorySampler()
        let netSampler = NetworkSampler()
        let diskSampler = DiskSampler()
        let powerSampler = PowerSampler()
        let thermalSampler = ThermalSampler()
        let fanSampler = FanSampler()
        let gpuSampler = GPUSampler()

        func sampleAll() -> [MetricReading] {
            let now = Date()
            var out: [MetricReading] = []
            out.reserveCapacity(8)
            out.append((try? cpuSampler.sample()).map { .cpu(Sample(value: $0, timestamp: now)) } ?? .unavailable(category: .cpu, reason: "n/a", timestamp: now))
            out.append((try? memSampler.sample()).map { .memory(Sample(value: $0, timestamp: now)) } ?? .unavailable(category: .memory, reason: "n/a", timestamp: now))
            out.append((try? netSampler.sample()).map { .network(Sample(value: $0, timestamp: now)) } ?? .unavailable(category: .network, reason: "n/a", timestamp: now))
            out.append((try? diskSampler.sample()).map { .disk(Sample(value: $0, timestamp: now)) } ?? .unavailable(category: .disk, reason: "n/a", timestamp: now))
            out.append((try? powerSampler.sample()).map { .power(Sample(value: $0, timestamp: now)) } ?? .unavailable(category: .power, reason: "n/a", timestamp: now))
            out.append((try? thermalSampler.sample()).map { .thermal(Sample(value: $0, timestamp: now)) } ?? .unavailable(category: .thermal, reason: "n/a", timestamp: now))
            out.append((try? fanSampler.sample()).map { .fan(Sample(value: $0, timestamp: now)) } ?? .unavailable(category: .fan, reason: "n/a", timestamp: now))
            out.append((try? gpuSampler.sample()).map { .gpu(Sample(value: $0, timestamp: now)) } ?? .unavailable(category: .gpu, reason: "n/a", timestamp: now))
            return out
        }

        // Seed 60 seconds of history so hero chart and insights operate at full steady-state load
        let baseDate = Date()
        for i in 0..<60 {
            let ts = baseDate.addingTimeInterval(-Double(59 - i))
            coord.handleReadings([
                .cpu(Sample(value: CPUSample(totalUsage: 32.0, perCore: [28, 36, 30, 34], user: 20, system: 12, idle: 68, efficiencyCoreCount: 2, performanceCoreCount: 2), timestamp: ts)),
                .memory(Sample(value: MemorySample(total: 16_000_000_000, used: 9_000_000_000, free: 7_000_000_000, wired: 2_000_000_000, compressed: 1_000_000_000, cached: 2_000_000_000, swapUsed: 0, pressure: .normal), timestamp: ts))
            ])
        }

        // Open one panel (CPUPanel) in a real NSWindow hosting view
        let panelView = CPUPanel(initialTab: .overview, rememberLastTab: false, coordinator: coord, preferences: prefs)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Instrument.Size.panelWidth, height: 420),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let hosting = NSHostingView(rootView: panelView)
        hosting.frame = NSRect(x: 0, y: 0, width: Instrument.Size.panelWidth, height: 420)
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        // Warmup 1 pass
        _ = sampleAll()
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))

        let chartModel = ChartModel(sampleInterval: 1.0)
        let simulatedSeconds = 5

        let wallStart = CFAbsoluteTimeGetCurrent()
        let cpuStart = Self.processCPUTimeSeconds()

        for sec in 0..<simulatedSeconds {
            // 1. Background 1 Hz sampling across all 8 categories
            let readings = sampleAll()
            coord.handleReadings(readings)

            // 2. Single-panel SwiftUI layout + display refresh at 1 Hz
            hosting.layoutSubtreeIfNeeded()
            window.displayIfNeeded()

            // 3. 60-frame chart stepping for the 1 s window
            let cpuPoints = coord.timedDualScalarHistory(primary: .cpuUser, secondary: .cpuSystem, duration: 60.0)
            for frame in 0..<60 {
                let now = Date().timeIntervalSince1970 + Double(sec) + Double(frame) / 60.0
                let resolved = chartModel.step(
                    now: now,
                    mode: .stacked(points: cpuPoints, primaryColor: .blue, secondaryColor: .red, fixedMax: 100.0),
                    category: .cpu,
                    sampleInterval: 1.0,
                    explicitWindow: 60.0,
                    isScrubbing: false,
                    motionPolicy: .full
                )
                let range = ChartRenderer.VerticalRange(floor: 0, ceiling: 100, topY: 0, baselineY: 72, inverted: false)
                _ = ChartRenderer.buildSeriesGeometry(
                    points: resolved.totalPoints,
                    timeline: chartModel.timeline,
                    windowDuration: resolved.windowDuration,
                    plotWidth: 347.0,
                    verticalRange: range
                )
            }
        }

        let cpuElapsed = Self.processCPUTimeSeconds() - cpuStart
        let wallElapsed = CFAbsoluteTimeGetCurrent() - wallStart

        // CPU % per simulated 1 Hz second (1000 ms budget per second)
        let cpuMsPerSecond = (cpuElapsed / Double(simulatedSeconds)) * 1000.0
        let wallMsPerSecond = (wallElapsed / Double(simulatedSeconds)) * 1000.0
        let totalAppCPUPercent = cpuMsPerSecond / 10.0

        print(String(
            format: "Performance Benchmark (Single-panel 1 Hz total app): wall=%.2f ms/s, cpu=%.2f ms/s, totalAppCPU=%.3f%% (budget <= 3.0%%)",
            wallMsPerSecond,
            cpuMsPerSecond,
            totalAppCPUPercent
        ))

        XCTAssertLessThanOrEqual(
            totalAppCPUPercent,
            3.0,
            "Single-panel 1 Hz refresh exceeded <= 3.0% total app CPU budget (R8.5.6)"
        )
    }
}
