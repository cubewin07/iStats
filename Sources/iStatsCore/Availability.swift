import Foundation

/// Whether a metric reading is available on the current hardware/OS.
///
/// A core resilience principle (Requirements 1.5, 3.3, 12.3): when a sensor or
/// API can't be read, iStats marks the value `.unavailable` with a reason rather
/// than crashing or showing a misleading zero.
public enum Availability: Sendable, Equatable {
    case available
    case unavailable(reason: String)

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

/// One timestamped reading from a sampler.
public struct Sample<Value: Sendable>: Sendable {
    public let value: Value
    public let timestamp: Date
    public let availability: Availability

    public init(value: Value, timestamp: Date, availability: Availability = .available) {
        self.value = value
        self.timestamp = timestamp
        self.availability = availability
    }
}
