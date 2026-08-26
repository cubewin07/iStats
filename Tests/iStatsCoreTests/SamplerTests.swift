import XCTest
@testable import iStatsCore

// Mock samplers for testing protocol conformance and error cases
struct MockCPUSampler: Sampler {
    typealias Output = CPUSample
    let category: MetricCategory = .cpu
    let shouldThrow: SamplerError?

    func sample() throws -> CPUSample {
        if let error = shouldThrow {
            throw error
        }
        return CPUSample(totalUsage: 25.5, perCore: [20.0, 31.0], user: 15.0, system: 10.5, idle: 74.5)
    }
}

final class SamplerTests: XCTestCase {

    func testSamplerSuccessfulSample() throws {
        let sampler = MockCPUSampler(shouldThrow: nil)
        XCTAssertEqual(sampler.category, .cpu)

        let result = try sampler.sample()
        XCTAssertEqual(result.totalUsage, 25.5)
        XCTAssertEqual(result.perCore, [20.0, 31.0])
        XCTAssertEqual(result.user, 15.0)
        XCTAssertEqual(result.system, 10.5)
        XCTAssertEqual(result.idle, 74.5)
    }

    func testSamplerThrowsUnsupported() {
        let sampler = MockCPUSampler(shouldThrow: .unsupported("No sensor available"))
        XCTAssertThrowsError(try sampler.sample()) { error in
            XCTAssertEqual(error as? SamplerError, SamplerError.unsupported("No sensor available"))
        }
    }

    func testSamplerThrowsSystemCallFailed() {
        let sampler = MockCPUSampler(shouldThrow: .systemCallFailed("kern_return_t: 5"))
        XCTAssertThrowsError(try sampler.sample()) { error in
            XCTAssertEqual(error as? SamplerError, SamplerError.systemCallFailed("kern_return_t: 5"))
        }
    }

    func testSamplerThrowsTimedOut() {
        let sampler = MockCPUSampler(shouldThrow: .timedOut)
        XCTAssertThrowsError(try sampler.sample()) { error in
            XCTAssertEqual(error as? SamplerError, SamplerError.timedOut)
        }
    }

    func testSamplerErrorEquality() {
        XCTAssertEqual(SamplerError.unsupported("A"), SamplerError.unsupported("A"))
        XCTAssertNotEqual(SamplerError.unsupported("A"), SamplerError.unsupported("B"))
        XCTAssertEqual(SamplerError.systemCallFailed("5"), SamplerError.systemCallFailed("5"))
        XCTAssertEqual(SamplerError.timedOut, SamplerError.timedOut)
        XCTAssertNotEqual(SamplerError.timedOut, SamplerError.unsupported("timedOut"))
    }
}
