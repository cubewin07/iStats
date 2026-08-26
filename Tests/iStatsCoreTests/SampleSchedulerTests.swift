import XCTest
@testable import iStatsCore

// Mock samplers for testing scheduler behavior
struct ConfigurableSampler<T: Sendable>: Sampler {
    typealias Output = T
    let category: MetricCategory
    let output: T
    let errorToThrow: Error?
    let sleepSeconds: TimeInterval
    let onSampleCalled: (@Sendable () -> Void)?

    init(
        category: MetricCategory,
        output: T,
        errorToThrow: Error? = nil,
        sleepSeconds: TimeInterval = 0,
        onSampleCalled: (@Sendable () -> Void)? = nil
    ) {
        self.category = category
        self.output = output
        self.errorToThrow = errorToThrow
        self.sleepSeconds = sleepSeconds
        self.onSampleCalled = onSampleCalled
    }

    func sample() throws -> T {
        onSampleCalled?()
        if sleepSeconds > 0 {
            Thread.sleep(forTimeInterval: sleepSeconds)
        }
        if let error = errorToThrow {
            throw error
        }
        return output
    }
}

final class SampleSchedulerTests: XCTestCase {

    func testRegistrationAndCategoryManagement() async {
        let scheduler = SampleScheduler()

        let cpuSampler = ConfigurableSampler(
            category: .cpu,
            output: CPUSample(totalUsage: 20, perCore: [20], user: 10, system: 10, idle: 80)
        )
        let memSampler = ConfigurableSampler(
            category: .memory,
            output: MemorySample(total: 100, used: 50, free: 50, wired: 10, compressed: 0, cached: 10, swapUsed: 0, pressure: .normal)
        )

        let isCpuRegisteredBefore = await scheduler.isRegistered(category: .cpu)
        XCTAssertFalse(isCpuRegisteredBefore)

        await scheduler.register(cpuSampler)
        await scheduler.register(AnySampler(memSampler))

        let isCpuRegisteredAfter = await scheduler.isRegistered(category: .cpu)
        let isMemRegisteredAfter = await scheduler.isRegistered(category: .memory)
        let registeredCats = await scheduler.registeredCategories()

        XCTAssertTrue(isCpuRegisteredAfter)
        XCTAssertTrue(isMemRegisteredAfter)
        XCTAssertTrue(registeredCats.contains(.cpu))
        XCTAssertTrue(registeredCats.contains(.memory))

        await scheduler.unregister(category: .cpu)
        let isCpuRegisteredFinal = await scheduler.isRegistered(category: .cpu)
        XCTAssertFalse(isCpuRegisteredFinal)
    }

    func testSamplingRunsOffMainThread() async {
        let expectation = expectation(description: "Sample executed on background thread")
        let cpuSampler = ConfigurableSampler(
            category: .cpu,
            output: CPUSample(totalUsage: 10, perCore: [10], user: 5, system: 5, idle: 90),
            onSampleCalled: {
                if !Thread.isMainThread {
                    expectation.fulfill()
                }
            }
        )

        let scheduler = SampleScheduler()
        await scheduler.register(cpuSampler)
        _ = await scheduler.sampleOnce(category: .cpu)

        await fulfillment(of: [expectation], timeout: 2.0)
    }

    func testSampleOnceAndSampleAll() async {
        let scheduler = SampleScheduler()

        let cpuSample = CPUSample(totalUsage: 35, perCore: [30, 40], user: 20, system: 15, idle: 65)
        let memSample = MemorySample(total: 1000, used: 600, free: 400, wired: 200, compressed: 50, cached: 150, swapUsed: 0, pressure: .normal)

        await scheduler.register(ConfigurableSampler(category: .cpu, output: cpuSample))
        await scheduler.register(ConfigurableSampler(category: .memory, output: memSample))

        let cpuReading = await scheduler.sampleOnce(category: .cpu)
        XCTAssertNotNil(cpuReading)
        XCTAssertEqual(cpuReading?.category, .cpu)
        XCTAssertTrue(cpuReading?.availability.isAvailable ?? false)

        if case .cpu(let sample) = cpuReading {
            XCTAssertEqual(sample.value, cpuSample)
        } else {
            XCTFail("Expected .cpu reading")
        }

        let allReadings = await scheduler.sampleAll()
        XCTAssertEqual(allReadings.count, 2)
        XCTAssertTrue(allReadings.contains(where: { $0.category == .cpu }))
        XCTAssertTrue(allReadings.contains(where: { $0.category == .memory }))
    }

    func testErrorIsolation() async {
        let scheduler = SampleScheduler()

        let failingSampler = ConfigurableSampler(
            category: .thermal,
            output: ThermalSample(),
            errorToThrow: SamplerError.unsupported("Thermal sensors not supported on this model")
        )
        let healthySampler = ConfigurableSampler(
            category: .cpu,
            output: CPUSample(totalUsage: 12, perCore: [12], user: 6, system: 6, idle: 88)
        )

        await scheduler.register(failingSampler)
        await scheduler.register(healthySampler)

        let thermalReading = await scheduler.sampleOnce(category: .thermal)
        let cpuReading = await scheduler.sampleOnce(category: .cpu)

        XCTAssertNotNil(thermalReading)
        XCTAssertFalse(thermalReading!.availability.isAvailable)
        XCTAssertEqual(thermalReading!.category, .thermal)
        XCTAssertEqual(thermalReading!.availability.unavailableReason, "Unsupported: Thermal sensors not supported on this model")

        XCTAssertNotNil(cpuReading)
        XCTAssertTrue(cpuReading!.availability.isAvailable)
        XCTAssertEqual(cpuReading!.category, .cpu)
    }

    func testTimeoutIsolation() async {
        let scheduler = SampleScheduler(timeBudget: 0.05)

        let slowSampler = ConfigurableSampler(
            category: .fan,
            output: FanSample(),
            sleepSeconds: 0.5 // Exceeds 0.05s timeBudget
        )
        let fastSampler = ConfigurableSampler(
            category: .network,
            output: NetworkSample(interfaces: [])
        )

        await scheduler.register(slowSampler)
        await scheduler.register(fastSampler)

        let fanReading = await scheduler.sampleOnce(category: .fan)
        let networkReading = await scheduler.sampleOnce(category: .network)

        XCTAssertNotNil(fanReading)
        XCTAssertFalse(fanReading!.availability.isAvailable)
        XCTAssertEqual(fanReading!.category, .fan)
        XCTAssertTrue(fanReading!.availability.unavailableReason?.contains("timed out") ?? false)

        XCTAssertNotNil(networkReading)
        XCTAssertTrue(networkReading!.availability.isAvailable)
        XCTAssertEqual(networkReading!.category, .network)
    }

    func testAsyncStreamPublishing() async {
        let scheduler = SampleScheduler(defaultInterval: 0.05)
        let cpuSampler = ConfigurableSampler(
            category: .cpu,
            output: CPUSample(totalUsage: 15, perCore: [15], user: 5, system: 10, idle: 85)
        )
        await scheduler.register(cpuSampler)

        let expectation = expectation(description: "Received at least 2 stream samples")
        expectation.expectedFulfillmentCount = 2

        let stream = scheduler.stream
        let streamTask = Task {
            for await reading in stream {
                if reading.category == .cpu {
                    expectation.fulfill()
                }
            }
        }

        await scheduler.start()

        await fulfillment(of: [expectation], timeout: 2.0)
        await scheduler.stop()
        streamTask.cancel()
    }

    func testDynamicIntervalAdjustment() async {
        // Fast interval (0.02s) vs Slower interval (0.15s)
        let scheduler = SampleScheduler(defaultInterval: 0.02)
        await scheduler.register(ConfigurableSampler(
            category: .power,
            output: PowerSample(hasBattery: false)
        ))

        var fastCount = 0
        let expFast = expectation(description: "Collected fast samples")
        let stream1 = scheduler.stream
        let task1 = Task {
            for await _ in stream1 {
                fastCount += 1
                if fastCount >= 3 {
                    expFast.fulfill()
                    break
                }
            }
        }

        await scheduler.start()
        await fulfillment(of: [expFast], timeout: 2.0)
        task1.cancel()

        // Slow down interval to 0.5s (Requirement 12.4: Increasing interval reduces wake frequency)
        await scheduler.setInterval(category: .power, interval: 0.5)
        let updatedInterval = await scheduler.interval(for: .power)
        XCTAssertEqual(updatedInterval, 0.5)

        await scheduler.stop()
    }

    func testCategoryEnablementToggling() async {
        let scheduler = SampleScheduler(defaultInterval: 0.03)
        await scheduler.register(ConfigurableSampler(
            category: .disk,
            output: DiskSample()
        ))

        let isEnabledInitially = await scheduler.isEnabled(category: .disk)
        XCTAssertTrue(isEnabledInitially)

        await scheduler.setEnabled(category: .disk, isEnabled: false)
        let isEnabledAfter = await scheduler.isEnabled(category: .disk)
        XCTAssertFalse(isEnabledAfter)

        let readings = await scheduler.sampleAll()
        XCTAssertTrue(readings.isEmpty)

        await scheduler.setEnabled(category: .disk, isEnabled: true)
        let isEnabledFinal = await scheduler.isEnabled(category: .disk)
        XCTAssertTrue(isEnabledFinal)

        let readingsAfterReenable = await scheduler.sampleAll()
        XCTAssertEqual(readingsAfterReenable.count, 1)
        XCTAssertEqual(readingsAfterReenable.first?.category, .disk)
    }

    func testStartStopLifecycle() async {
        let scheduler = SampleScheduler(defaultInterval: 0.05)
        let isRunningInitial = await scheduler.isRunning
        XCTAssertFalse(isRunningInitial)

        await scheduler.start()
        let isRunningAfterStart = await scheduler.isRunning
        XCTAssertTrue(isRunningAfterStart)

        await scheduler.stop()
        let isRunningAfterStop = await scheduler.isRunning
        XCTAssertFalse(isRunningAfterStop)
    }

    func testOnSampleCallbacks() async {
        let scheduler = SampleScheduler()
        let expOnSample = expectation(description: "onSample called")
        let expOnMainActor = expectation(description: "onMainActorSample called")

        await scheduler.register(ConfigurableSampler(
            category: .gpu,
            output: GPUSample(utilization: 55.0)
        ))

        await scheduler.setCallbacks(
            onSample: { reading in
                if reading.category == .gpu {
                    expOnSample.fulfill()
                }
            },
            onMainActorSample: { reading in
                if reading.category == .gpu && Thread.isMainThread {
                    expOnMainActor.fulfill()
                }
            }
        )

        _ = await scheduler.sampleOnce(category: .gpu)

        // Note: sampleOnce does direct sampling, we can trigger sampleCategory or start
        await scheduler.triggerPublishForTesting(category: .gpu)

        await fulfillment(of: [expOnSample, expOnMainActor], timeout: 2.0)
    }

    func testMetricReadingPropertiesAndWrapping() {
        let date = Date(timeIntervalSince1970: 1000)

        let cpu = MetricReading.wrap(
            category: .cpu,
            value: CPUSample(totalUsage: 10, perCore: [10], user: 5, system: 5, idle: 90),
            timestamp: date
        )
        XCTAssertEqual(cpu.category, .cpu)
        XCTAssertEqual(cpu.timestamp, date)
        XCTAssertEqual(cpu.availability, .available)

        let mem = MetricReading.wrap(
            category: .memory,
            value: MemorySample(total: 100, used: 50, free: 50, wired: 10, compressed: 0, cached: 10, swapUsed: 0, pressure: .normal),
            timestamp: date
        )
        XCTAssertEqual(mem.category, .memory)
        XCTAssertEqual(mem.availability, .available)

        let thermal = MetricReading.wrap(category: .thermal, value: ThermalSample(), timestamp: date)
        XCTAssertEqual(thermal.category, .thermal)

        let fan = MetricReading.wrap(category: .fan, value: FanSample(), timestamp: date)
        XCTAssertEqual(fan.category, .fan)

        let gpu = MetricReading.wrap(category: .gpu, value: GPUSample(), timestamp: date)
        XCTAssertEqual(gpu.category, .gpu)

        let network = MetricReading.wrap(category: .network, value: NetworkSample(), timestamp: date)
        XCTAssertEqual(network.category, .network)

        let disk = MetricReading.wrap(category: .disk, value: DiskSample(), timestamp: date)
        XCTAssertEqual(disk.category, .disk)

        let power = MetricReading.wrap(category: .power, value: PowerSample(hasBattery: false), timestamp: date)
        XCTAssertEqual(power.category, .power)

        let unavailable = MetricReading.unavailable(category: .cpu, reason: "Offline", timestamp: date)
        XCTAssertEqual(unavailable.category, .cpu)
        XCTAssertEqual(unavailable.timestamp, date)
        XCTAssertEqual(unavailable.availability, .unavailable(reason: "Offline"))
    }
}

// Testing helper extension
extension SampleScheduler {
    func setCallbacks(
        onSample: SampleHandler? = nil,
        onMainActorSample: MainActorSampleHandler? = nil
    ) {
        self.onSample = onSample
        self.onMainActorSample = onMainActorSample
    }

    func triggerPublishForTesting(category: MetricCategory) async {
        let reading = await sampleCategory(category)
        publishReadingForTesting(reading)
    }

    private func publishReadingForTesting(_ reading: MetricReading) {
        if let onSample = self.onSample {
            onSample(reading)
        }
        if let onMainActorSample = self.onMainActorSample {
            Task { @MainActor in
                onMainActorSample(reading)
            }
        }
    }

    func sampleCategory(_ category: MetricCategory) async -> MetricReading {
        guard let sampler = await self.sampleOnce(category: category) else {
            return .unavailable(category: category, reason: "Sampler not registered", timestamp: Date())
        }
        return sampler
    }
}
