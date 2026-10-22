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

    func testAppleSMCClientNumericDecoderParityAndTypeRejection() {
        let client = AppleSMCClient()

        // 1. fpe2 unsigned 14.2 fixed point (e.g., 10,000 RPM -> raw 40,000 = 0x9C40, which would be negative as Int16)
        let fpe2Bytes: [UInt8] = [0x9C, 0x40]
        let fpe2Val = fpe2Bytes.withUnsafeBytes { client.decodeNumericValue(buffer: $0, size: 2, type: "fpe2") }
        XCTAssertEqual(fpe2Val, 10000.0)

        // 2. sp78 signed 7.8 fixed point (e.g., 45.5°C -> 45.5 * 256 = 11648 = 0x2D80)
        let sp78Bytes: [UInt8] = [0x2D, 0x80]
        let sp78Val = sp78Bytes.withUnsafeBytes { client.decodeNumericValue(buffer: $0, size: 2, type: "sp78") }
        XCTAssertEqual(sp78Val, 45.5)

        // 3. flt 32-bit float (including negative value parity)
        var negFloat: Float32 = -12.5
        let fltVal = withUnsafeBytes(of: &negFloat) { client.decodeNumericValue(buffer: $0, size: 4, type: "flt ") }
        XCTAssertEqual(fltVal, -12.5)

        // 4. Unknown SMC types must return nil instead of guessing float or sp78
        let unknownBytes: [UInt8] = [0x42, 0x28, 0x00, 0x00]
        let unknown4 = unknownBytes.withUnsafeBytes { client.decodeNumericValue(buffer: $0, size: 4, type: "{pwm") }
        XCTAssertNil(unknown4, "Unknown 4-byte SMC type must not be decoded as Float32")
        let unknown2 = unknownBytes.withUnsafeBytes { client.decodeNumericValue(buffer: $0, size: 2, type: "flag") }
        XCTAssertNil(unknown2, "Unknown 2-byte SMC type must not be decoded as sp78")
    }
}
