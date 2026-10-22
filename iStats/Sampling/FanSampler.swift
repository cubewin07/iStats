import Foundation
import Darwin
import IOKit
import iStatsCore

// MARK: - Fan Info Provider Protocol

/// Abstract provider for reading physical fan telemetry and speed bounds from macOS hardware.
public protocol FanInfoProvider: Sendable {
    /// Returns the number of physical fans detected on the machine.
    func fanCount() throws -> Int

    /// Returns telemetry for each detected fan, including current RPM and min/max RPM bounds if exposed.
    func fans() throws -> [FanReading]
}

public extension FanInfoProvider {
    func fanCount() throws -> Int {
        try fans().count
    }
}

// MARK: - Host Fan Info Provider

/// Darwin AppleSMC implementation of `FanInfoProvider` (ADR 0003, Requirements 4.1, 4.2).
public struct HostFanInfoProvider: FanInfoProvider {

    public init() {}

    public func fanCount() throws -> Int {
        guard AppleSMCClient.shared.connection() != nil else {
            throw SamplerError.unsupported("AppleSMC service not available")
        }
        return readFanCount()
    }

    public func fans() throws -> [FanReading] {
        guard AppleSMCClient.shared.connection() != nil else {
            throw SamplerError.unsupported("AppleSMC service not available")
        }

        let count = readFanCount()
        guard count > 0 else {
            // Fanless systems (e.g. MacBook Air) report 0 fans cleanly (Requirement 4.4, ADR 0003)
            return []
        }

        var results: [FanReading] = []
        for i in 0..<count {
            let actualKey = "F\(i)Ac"
            let minKey = "F\(i)Mn"
            let maxKey = "F\(i)Mx"
            let idKey = "F\(i)ID"

            let actualRPM = AppleSMCClient.shared.readNumericKey(actualKey).map { Int(round($0)) } ?? 0
            let minRPM = AppleSMCClient.shared.readNumericKey(minKey).map { Int(round($0)) }
            let maxRPM = AppleSMCClient.shared.readNumericKey(maxKey).map { Int(round($0)) }
            let fanName = AppleSMCClient.shared.readStringKey(idKey) ?? defaultFanName(index: i, total: count)

            results.append(
                FanReading(
                    name: fanName,
                    rpm: max(0, actualRPM),
                    minRPM: minRPM.flatMap { $0 >= 0 ? $0 : nil },
                    maxRPM: maxRPM.flatMap { $0 >= 0 ? $0 : nil }
                )
            )
        }

        return results
    }

    // MARK: - SMC Key Readers

    private func readFanCount() -> Int {
        // Read FNum key
        if let countVal = AppleSMCClient.shared.readNumericKey("FNum") {
            let count = Int(countVal)
            if count >= 0 && count <= 16 {
                return count
            }
        }

        // Fallback: check if F0Ac exists
        if AppleSMCClient.shared.readNumericKey("F0Ac") != nil {
            if AppleSMCClient.shared.readNumericKey("F1Ac") != nil {
                return 2
            }
            return 1
        }

        return 0
    }

    private func defaultFanName(index: Int, total: Int) -> String {
        if total == 1 {
            return "Fan"
        } else if total == 2 {
            return index == 0 ? "Left Fan" : "Right Fan"
        } else {
            return "Fan \(index + 1)"
        }
    }
}

// MARK: - Concrete Fan Sampler

/// Concrete sampler for reading fan RPM and hardware speed bounds.
///
/// Conforms to `Sampler` (Requirements 4.1, 4.2, 11.3, ADR 0003, ADR 0004).
/// Strictly read-only; executes background work only via `SampleScheduler`.
public final class FanSampler: Sampler, @unchecked Sendable {
    public let category: MetricCategory = .fan

    private let provider: any FanInfoProvider

    public init(provider: any FanInfoProvider = HostFanInfoProvider()) {
        self.provider = provider
    }

    /// Samples fan speeds and RPM bounds. Runs off the main thread.
    public func sample() throws -> FanSample {
        let fans = try provider.fans()
        return Self.calculateSample(fans: fans)
    }

    /// Pure calculation helper constructing a validated `FanSample`.
    public static func calculateSample(fans: [FanReading]) -> FanSample {
        let validFans = fans.map { fan in
            FanReading(
                name: fan.name,
                rpm: max(0, fan.rpm),
                minRPM: fan.minRPM.flatMap { $0 >= 0 ? $0 : nil },
                maxRPM: fan.maxRPM.flatMap { $0 >= 0 ? $0 : nil }
            )
        }
        return FanSample(fans: validFans)
    }
}
