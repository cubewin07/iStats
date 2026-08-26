import Foundation
import Dispatch
import iStatsCore

/// Monitors kernel-level macOS memory pressure events via `DispatchSourceMemoryPressure`.
///
/// Runs strictly on background queues off the main thread (Invariant 1, Requirement 12.1).
public final class MemoryPressureMonitor: @unchecked Sendable {
    public static let shared = MemoryPressureMonitor()

    private let lock = NSLock()
    private var _currentPressure: MemoryPressure = .normal
    private var source: (any DispatchSourceMemoryPressure)?
    private let queue: DispatchQueue
    private var listeners: [@Sendable (MemoryPressure) -> Void] = []

    public var currentPressure: MemoryPressure {
        lock.lock()
        defer { lock.unlock() }
        return _currentPressure
    }

    public init(queue: DispatchQueue = DispatchQueue(label: "com.istats.memorypressure", qos: .utility), startImmediately: Bool = true) {
        self.queue = queue
        if startImmediately {
            start()
        }
    }

    deinit {
        stop()
    }

    /// Starts observing kernel memory pressure events.
    public func start() {
        lock.lock()
        defer { lock.unlock() }
        guard source == nil else { return }

        let src = DispatchSource.makeMemoryPressureSource(eventMask: .all, queue: queue)
        src.setEventHandler { [weak self, weak src] in
            guard let self, let src else { return }
            let event = src.data
            let mapped = Self.mapEvent(event)
            self.updatePressure(mapped)
        }

        src.setCancelHandler { [weak self] in
            // Clean up upon cancellation
            guard let _ = self else { return }
        }

        source = src
        src.resume()
    }

    /// Stops observing kernel memory pressure events.
    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        if let src = source {
            src.cancel()
            source = nil
        }
    }

    /// Registers a listener callback invoked when memory pressure changes.
    public func addListener(_ listener: @escaping @Sendable (MemoryPressure) -> Void) {
        lock.lock()
        listeners.append(listener)
        let current = _currentPressure
        lock.unlock()
        listener(current)
    }

    /// Updates internal pressure state and notifies registered listeners.
    public func updatePressure(_ pressure: MemoryPressure) {
        lock.lock()
        let changed = _currentPressure != pressure
        _currentPressure = pressure
        let currentListeners = listeners
        lock.unlock()

        if changed {
            for listener in currentListeners {
                listener(pressure)
            }
        }
    }

    /// Maps a `DispatchSource.MemoryPressureEvent` to `MemoryPressure`.
    public static func mapEvent(_ event: DispatchSource.MemoryPressureEvent) -> MemoryPressure {
        if event.contains(.critical) {
            return .critical
        } else if event.contains(.warning) {
            return .warning
        } else {
            return .normal
        }
    }
}
