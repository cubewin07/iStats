import Foundation

/// A component that reads one category of metrics from the OS/hardware.
///
/// Concrete samplers live in the (hardware-touching) Sampling layer and are
/// created during Phases 2–5. `sample()` is expected to run **off the main
/// thread** (see ADR 0002) and may throw; the scheduler catches errors and
/// converts them to `.unavailable` readings so one failing sampler never stops
/// the others (Requirement 12.3).
public protocol Sampler: Sendable {
    associatedtype Output: Sendable

    /// The category this sampler produces.
    var category: MetricCategory { get }

    /// Read the current values. Runs off the main thread. May throw.
    func sample() throws -> Output
}

/// Errors a sampler can surface. These are turned into `.unavailable` readings.
public enum SamplerError: Error, Equatable, Sendable {
    /// The underlying API/sensor is not present on this hardware/OS.
    case unsupported(String)
    /// A system call failed (e.g., a non-zero kern_return_t).
    case systemCallFailed(String)
    /// The read exceeded its time budget and was skipped this cycle.
    case timedOut
}
