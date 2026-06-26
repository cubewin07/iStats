import Foundation

/// A fixed-capacity ring buffer. When full, appending overwrites the oldest
/// element. Backs the short-term in-memory history shown in the detail-view
/// graphs (Requirement 10.2). Telemetry is never persisted (ADR 0006).
public struct RingBuffer<Element>: Sendable where Element: Sendable {
    private var storage: [Element] = []
    private var head = 0
    public let capacity: Int

    public init(capacity: Int) {
        precondition(capacity > 0, "RingBuffer capacity must be > 0")
        self.capacity = capacity
        storage.reserveCapacity(capacity)
    }

    /// Number of elements currently stored (0...capacity).
    public var count: Int { storage.count }

    public var isEmpty: Bool { storage.isEmpty }

    public var isFull: Bool { storage.count == capacity }

    /// Append an element, evicting the oldest if at capacity.
    public mutating func append(_ element: Element) {
        if storage.count < capacity {
            storage.append(element)
        } else {
            storage[head] = element
            head = (head + 1) % capacity
        }
    }

    /// Elements in chronological order (oldest first, newest last).
    public var elements: [Element] {
        guard isFull else { return storage }
        // When full, `head` points at the oldest element.
        return Array(storage[head...] + storage[..<head])
    }

    /// The most recently appended element, if any.
    public var latest: Element? {
        guard !storage.isEmpty else { return nil }
        if !isFull { return storage.last }
        let lastIndex = (head - 1 + capacity) % capacity
        return storage[lastIndex]
    }
}
