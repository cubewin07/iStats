import CoreGraphics

/// Pure rules for reading the menu bar order from on-screen frames.
public enum MenuBarOrdering {
    /// Left-to-right IDs read from on-screen status item frames, or nil when the layout can't be
    /// trusted. macOS stacks items it has no room for, so overlaps must not count as an order.
    public static func observedOrder(frames: [(id: String, frame: CGRect)]) -> [String]? {
        guard frames.count > 1, frames.allSatisfy({ $0.frame.width > 0 }) else { return nil }
        let sorted = frames.sorted { $0.frame.minX < $1.frame.minX }
        for (left, right) in zip(sorted, sorted.dropFirst()) {
            guard right.frame.minX >= left.frame.maxX - 1, right.frame.minY == left.frame.minY else {
                return nil
            }
        }
        return sorted.map(\.id)
    }
}
