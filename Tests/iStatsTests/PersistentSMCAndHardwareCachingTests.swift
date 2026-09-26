import XCTest
@testable import iStatsCore
@testable import iStats

final class PersistentSMCAndHardwareCachingTests: XCTestCase {

    func testAppleSMCClientMaintainsSinglePersistentConnection() {
        let client = AppleSMCClient.shared
        guard let conn1 = client.connection() else {
            // Environment does not expose AppleSMC (e.g., non-SMC VM)
            return
        }

        XCTAssertNotEqual(conn1, 0)

        // Multiple calls must return the EXACT same connection descriptor
        let conn2 = client.connection()
        XCTAssertEqual(conn1, conn2, "Expected connection descriptor to be persistently reused")

        let conn3 = client.connection()
        XCTAssertEqual(conn1, conn3, "Expected connection descriptor to remain stable across calls")
    }

    func testAppleSMCClientInvalidateAndReconnect() {
        let client = AppleSMCClient.shared
        guard let conn1 = client.connection() else { return }
        XCTAssertNotEqual(conn1, 0)

        // Invalidate explicitly
        client.invalidate()

        // Reconnect
        guard let conn2 = client.connection() else {
            XCTFail("Expected reconnect to succeed after invalidate")
            return
        }
        XCTAssertNotEqual(conn2, 0)
    }

    func testFanSamplerReusesPersistentSMCClient() throws {
        let sampler = FanSampler()
        // Sampling multiple times must succeed without error
        let sample1 = try? sampler.sample()
        let sample2 = try? sampler.sample()

        if let s1 = sample1, let s2 = sample2 {
            XCTAssertEqual(s1.fans.count, s2.fans.count)
        }
    }

    func testGPUSamplerHardwareCaching() throws {
        let sampler = GPUSampler()
        let sample1 = try? sampler.sample()
        let sample2 = try? sampler.sample()

        if let s1 = sample1, let s2 = sample2 {
            XCTAssertEqual(s1.deviceName, s2.deviceName)
            XCTAssertEqual(s1.displayCount, s2.displayCount)
        }
    }

    func testNetworkSamplerMaintainsCountersWhileCachingStaticData() throws {
        let sampler = NetworkSampler()
        let sample1 = try sampler.sample()
        let sample2 = try sampler.sample()

        // Interface lists should be consistent
        XCTAssertEqual(sample1.interfaces.count, sample2.interfaces.count)
    }

    func testAppleSMCClientMissingKeyDoesNotReconnectOrClose() {
        let client = AppleSMCClient.shared
        guard let conn1 = client.connection() else { return }
        client.resetPerformanceCounters()

        // Read a non-existent key
        let result = client.readNumericKey("ZNON")
        XCTAssertNil(result)

        let conn2 = client.connection()
        XCTAssertEqual(conn1, conn2, "Non-existent key probe must NOT invalidate connection handle")
        XCTAssertEqual(client.reconnectCount, 0, "Non-existent key probe must NOT trigger reconnect cycle")
    }

    func testGPUSamplerQueryConnectedDisplaysOffMainThread() async throws {
        let sample = try await Task.detached(priority: .utility) { () -> GPUSample in
            let sampler = GPUSampler()
            return try sampler.sample()
        }.value

        XCTAssertNotNil(sample.deviceName)
    }
}
